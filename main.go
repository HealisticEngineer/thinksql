package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
	"unsafe"

	_ "github.com/denisenkom/go-mssqldb" // SQL Server driver
)

// Global variable to hold the database connection pool.
var db *sql.DB

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
	var err error

	// Open a connection to the database
	db, err = sql.Open("sqlserver", goConnStr)
	if err != nil {
		return C.CString(fmt.Sprintf("ERROR: Failed to open connection: %v", err))
	}

	// Ping the database to verify the connection is alive
	err = db.Ping()
	if err != nil {
		db.Close() // Close the connection if ping fails
		return C.CString(fmt.Sprintf("ERROR: Failed to connect to database: %v", err))
	}

	return nil // Success
}

// DisconnectDb closes the database connection.
//
//export DisconnectDb
func DisconnectDb() {
	if db != nil {
		db.Close()
		db = nil
	}
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

// processSelect checks a SELECT statement and prepends the snapshot isolation level
// command if it's not already hinted at.
func processSelect(sql string) string {
	// Use a regex to check for the presence of the WITH (SNAPSHOT) hint.
	re := regexp.MustCompile(`(?i)\bWITH\s*\(\s*SNAPSHOT\s*\)`)
	if re.MatchString(sql) {
		return sql
	}

	// Prepend the SET statement.
	processedSQL := "SET TRANSACTION ISOLATION LEVEL SNAPSHOT;\n" + sql
	return processedSQL
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
	trimmedUpperSql := strings.TrimSpace(strings.ToUpper(goSql))

	var processedSql string
	isSelect := false

	if strings.HasPrefix(trimmedUpperSql, "CREATE TABLE") {
		processedSql = processCreateTable(goSql)
	} else if strings.HasPrefix(trimmedUpperSql, "SELECT") {
		processedSql = processSelect(goSql)
		isSelect = true
	} else {
		// For any other SQL command, leave it unaltered
		processedSql = goSql
	}

	if isSelect {
		// If the processed SQL has a SET statement, execute it first
		if strings.Contains(processedSql, "SET TRANSACTION ISOLATION LEVEL SNAPSHOT") {
			// Execute the SET statement first
			_, err := db.Exec("SET TRANSACTION ISOLATION LEVEL SNAPSHOT")
			if err != nil {
				return C.CString(fmt.Sprintf("ERROR: Failed to set isolation level: %v", err))
			}
			// Extract just the SELECT portion
			parts := strings.SplitN(processedSql, "\n", 2)
			if len(parts) > 1 {
				processedSql = strings.TrimSpace(parts[1])
			}
		}

		// Execute SELECT query and return JSON results
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

		// Build result set
		var results []map[string]interface{}
		for rows.Next() {
			// Create a slice of interface{} to hold each column value
			columnValues := make([]interface{}, len(columns))
			columnPointers := make([]interface{}, len(columns))
			for i := range columnValues {
				columnPointers[i] = &columnValues[i]
			}

			// Scan the row into the column pointers
			if err := rows.Scan(columnPointers...); err != nil {
				return C.CString(fmt.Sprintf("ERROR: Failed to scan row: %v", err))
			}

			// Create a map for this row
			row := make(map[string]interface{})
			for i, colName := range columns {
				val := columnValues[i]
				// Convert byte arrays to strings for better JSON representation
				if b, ok := val.([]byte); ok {
					row[colName] = string(b)
				} else {
					row[colName] = val
				}
			}
			results = append(results, row)
		}

		if err = rows.Err(); err != nil {
			return C.CString(fmt.Sprintf("ERROR: Row iteration error: %v", err))
		}

		// Marshal results to JSON
		jsonData, err := json.Marshal(results)
		if err != nil {
			return C.CString(fmt.Sprintf("ERROR: Failed to marshal JSON: %v", err))
		}

		return C.CString(string(jsonData))
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
