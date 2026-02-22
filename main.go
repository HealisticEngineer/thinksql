package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
	"time"
	"unsafe"

	_ "github.com/microsoft/go-mssqldb" // SQL Server driver
)

// Pre-compiled regex for SNAPSHOT hint detection (avoids recompilation on every query)
var snapshotHintRegex = regexp.MustCompile(`(?i)\bWITH\s*\(\s*SNAPSHOT\s*\)`)

// Pre-compiled regex to detect a standalone SELECT statement inside a DECLARE batch
var selectInBatchRegex = regexp.MustCompile(`(?i)(?:^|[;\s])SELECT\b`)

// Global variable to hold the database connection pool.
var db *sql.DB

// Track the current connection string to enable fast reconnect
var currentConnStr string

// Cached pool kept alive across disconnect/reconnect cycles (like .NET connection pooling)
var cachedDb *sql.DB
var cachedConnStr string

// connected tracks whether the user considers the connection "open"
var connected bool

// main is required for the build, but it does not run in a shared library.
func main() {}

// ConnectDb establishes a connection to the SQL Server database.
// It takes a connection string and returns a C string with an error message if it fails.
// Returns nil on success. The caller is responsible for freeing the error string.
// example connStr: "server=localhost;user id=sa;password=your_password;database=your_db"
// example usage as dll: ConnectDb(C.CString("server=localhost;user id=sa;password=your_password;database=your_db"))

//export ConnectDb
func ConnectDb(connStr *C.char) *C.char {
	goConnStr := C.GoString(connStr)

	// Fast path: already connected with same connection string
	if db != nil && connected && currentConnStr == goConnStr {
		if err := db.Ping(); err == nil {
			return nil // Existing connection is still good
		}
		// Connection is stale, fall through to reconnect
		db.Close()
		db = nil
		currentConnStr = ""
		cachedDb = nil
		cachedConnStr = ""
	}

	// Pool reuse path: reuse cached pool from a prior disconnect (like .NET connection pooling)
	if cachedDb != nil && cachedConnStr == goConnStr {
		if err := cachedDb.Ping(); err == nil {
			db = cachedDb
			currentConnStr = goConnStr
			connected = true
			return nil
		}
		// Cached pool is dead, discard it
		cachedDb.Close()
		cachedDb = nil
		cachedConnStr = ""
	}

	// Close any existing connection/pool with a different connection string
	if db != nil {
		db.Close()
		db = nil
		currentConnStr = ""
	}
	if cachedDb != nil {
		cachedDb.Close()
		cachedDb = nil
		cachedConnStr = ""
	}

	var err error

	// Open a new connection pool
	db, err = sql.Open("sqlserver", goConnStr)
	if err != nil {
		return C.CString(fmt.Sprintf("ERROR: Failed to open connection: %v", err))
	}

	// Configure connection pool for performance
	db.SetMaxOpenConns(10)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)
	db.SetConnMaxIdleTime(2 * time.Minute)

	// Ping the database to verify the connection is alive
	err = db.Ping()
	if err != nil {
		db.Close()
		db = nil
		return C.CString(fmt.Sprintf("ERROR: Failed to connect to database: %v", err))
	}

	currentConnStr = goConnStr
	connected = true
	return nil // Success
}

// DisconnectDb closes the database connection.
//
//export DisconnectDb
func DisconnectDb() {
	if db != nil {
		// Cache the pool for fast reconnect instead of destroying it
		cachedDb = db
		cachedConnStr = currentConnStr
		db = nil
	}
	currentConnStr = ""
	connected = false
}

// processCreateTable checks a CREATE TABLE statement for a PRIMARY KEY.
// If one is not found, it injects a default identity-based primary key.
func processCreateTable(sql string) string {
	// Use case-insensitive matching to find "PRIMARY KEY"
	upperSQL := strings.ToUpper(sql)
	if strings.Contains(upperSQL, "PRIMARY KEY") {
		// Primary key already exists, return the original query
		return sql
	}

	// Find the first opening parenthesis to inject the new column definition
	firstParenIndex := strings.Index(sql, "(")
	if firstParenIndex == -1 {
		// Malformed CREATE TABLE statement, return as-is
		return sql
	}

	// Define the primary key column to add for SQL Server (T-SQL).
	primaryKeyColumn := "ID INT PRIMARY KEY IDENTITY(1,1), "

	// Inject the primary key column definition right after the opening parenthesis
	processedSQL := sql[:firstParenIndex+1] + primaryKeyColumn + sql[firstParenIndex+1:]
	return processedSQL
}

// processSelect checks a SELECT statement for the WITH (SNAPSHOT) hint.
// Returns the SQL unchanged and whether SNAPSHOT isolation needs to be set.
// Uses pre-compiled regex for performance.
func processSelect(sqlStr string) (string, bool) {
	if snapshotHintRegex.MatchString(sqlStr) {
		return sqlStr, false
	}
	return sqlStr, true // needs snapshot isolation
}

// formatJSONValue writes a Go value as JSON into a bytes.Buffer without json.Marshal reflection overhead.
// Handles the common types returned by database/sql scanning.
func formatJSONValue(buf *bytes.Buffer, val interface{}) {
	if val == nil {
		buf.WriteString("null")
		return
	}
	switch v := val.(type) {
	case int64:
		fmt.Fprintf(buf, "%d", v)
	case float64:
		fmt.Fprintf(buf, "%g", v)
	case bool:
		if v {
			buf.WriteString("true")
		} else {
			buf.WriteString("false")
		}
	case string:
		escaped, _ := json.Marshal(v)
		buf.Write(escaped)
	case []byte:
		escaped, _ := json.Marshal(string(v))
		buf.Write(escaped)
	case time.Time:
		escaped, _ := json.Marshal(v.Format(time.RFC3339Nano))
		buf.Write(escaped)
	default:
		escaped, err := json.Marshal(v)
		if err != nil {
			buf.WriteString("null")
		} else {
			buf.Write(escaped)
		}
	}
}

// declareBatchContainsSelect checks whether a DECLARE-based SQL batch
// contains a SELECT statement that would return result rows.
// It looks for a standalone SELECT keyword (not inside a sub-expression).
func declareBatchContainsSelect(sql string) bool {
	upper := strings.ToUpper(sql)
	// Look for SELECT that appears as a statement (preceded by newline, semicolon, or start-of-batch
	// after the DECLARE section). A simple heuristic: any standalone SELECT keyword in the batch.
	return selectInBatchRegex.MatchString(upper)
}

// ExecuteSql processes and executes a SQL statement.
// It takes a C string as input, processes it, executes it on the connected DB,
// and returns a C string with the results (JSON for SELECT) or error message.
// The caller is RESPONSIBLE for freeing the returned C string using FreeCString.
//
//export ExecuteSql
func ExecuteSql(inputSql *C.char) *C.char {
	if db == nil {
		return C.CString("ERROR: Database not connected. Call ConnectDb first.")
	}

	goSql := C.GoString(inputSql)
	trimmedSql := strings.TrimSpace(goSql)

	// Check prefix case-insensitively without allocating a full uppercase copy
	var processedSql string
	isSelect := false

	if len(trimmedSql) >= 12 && strings.EqualFold(trimmedSql[:12], "CREATE TABLE") {
		processedSql = processCreateTable(goSql)
	} else if len(trimmedSql) >= 6 && strings.EqualFold(trimmedSql[:6], "SELECT") {
		isSelect = true
		processedSql = goSql
	} else if len(trimmedSql) >= 4 && strings.EqualFold(trimmedSql[:4], "WITH") {
		// WITH (CTE) — treat as a SELECT query that returns results
		isSelect = true
		processedSql = goSql
	} else if len(trimmedSql) >= 7 && strings.EqualFold(trimmedSql[:7], "DECLARE") {
		// DECLARE blocks that contain a SELECT should return JSON results
		if declareBatchContainsSelect(trimmedSql) {
			isSelect = true
		}
		processedSql = goSql
	} else {
		// For any other SQL command, leave it unaltered
		processedSql = goSql
	}

	if isSelect {
		// Check if we need snapshot isolation
		_, needsSnapshot := processSelect(processedSql)

		if needsSnapshot {
			// Combine SET + SELECT into a single batch to avoid an extra server roundtrip
			processedSql = "SET TRANSACTION ISOLATION LEVEL SNAPSHOT;\n" + processedSql
		}

		// Execute SELECT query (with optional SET prefix as a single batch)
		rows, err := db.Query(processedSql)
		if err != nil {
			return C.CString(fmt.Sprintf("ERROR: Query execution failed: %v", err))
		}
		defer rows.Close()

		// Get column names
		columns, err := rows.Columns()
		if err != nil {
			return C.CString(fmt.Sprintf("ERROR: Failed to get columns: %v", err))
		}

		// Reuse scan buffers across rows
		columnValues := make([]interface{}, len(columns))
		columnPointers := make([]interface{}, len(columns))
		for i := range columnValues {
			columnPointers[i] = &columnValues[i]
		}

		// Pre-quote column names for JSON output (avoids re-marshaling on every row)
		quotedColumns := make([][]byte, len(columns))
		for i, col := range columns {
			quoted, _ := json.Marshal(col)
			quotedColumns[i] = quoted
		}

		// Build JSON directly into a buffer instead of building []map[string]interface{}
		// then marshaling. This avoids map allocations and reflection-based marshaling.
		var buf bytes.Buffer
		buf.Grow(4096) // Pre-allocate buffer space
		buf.WriteByte('[')

		rowCount := 0
		for rows.Next() {
			if err := rows.Scan(columnPointers...); err != nil {
				return C.CString(fmt.Sprintf("ERROR: Failed to scan row: %v", err))
			}

			if rowCount > 0 {
				buf.WriteByte(',')
			}
			buf.WriteByte('{')

			for i := range columns {
				if i > 0 {
					buf.WriteByte(',')
				}
				buf.Write(quotedColumns[i])
				buf.WriteByte(':')
				formatJSONValue(&buf, columnValues[i])
			}

			buf.WriteByte('}')
			rowCount++
		}

		if err = rows.Err(); err != nil {
			return C.CString(fmt.Sprintf("ERROR: Row iteration error: %v", err))
		}

		buf.WriteByte(']')

		return C.CString(buf.String())
	} else {
		// Execute non-SELECT statement
		_, err := db.Exec(processedSql)
		if err != nil {
			return C.CString(fmt.Sprintf("ERROR: SQL execution failed: %v", err))
		}

		return nil // Success
	}
}

// FreeCString frees the memory for a C string allocated by Go.
// This MUST be called by the client code for any returned error strings.
//
//export FreeCString
func FreeCString(s *C.char) {
	if s != nil {
		C.free(unsafe.Pointer(s))
	}
}
