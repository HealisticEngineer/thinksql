package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"database/sql"
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

	fmt.Println("INFO: Database connection established successfully.")
	return nil // Success
}

// DisconnectDb closes the database connection.
//
//export DisconnectDb
func DisconnectDb() {
	if db != nil {
		db.Close()
		db = nil
		fmt.Println("INFO: Database connection closed.")
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
	fmt.Println("INFO: Added default PRIMARY KEY to CREATE TABLE statement.")
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
	fmt.Println("INFO: Prepended SET TRANSACTION ISOLATION LEVEL SNAPSHOT to SELECT statement.")
	return processedSQL
}

// ExecuteSql processes and executes a SQL statement.
// It takes a C string as input, processes it, executes it on the connected DB,
// and returns a C string with an error message if it fails.
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

	if strings.HasPrefix(trimmedUpperSql, "CREATE TABLE") {
		processedSql = processCreateTable(goSql)
	} else if strings.HasPrefix(trimmedUpperSql, "SELECT") {
		// Note: The driver will execute the SET and SELECT as separate statements in a batch.
		// For queries that return data, a more complex function would be needed to handle row results.
		// For this example, we assume Exec is sufficient (e.g., SELECT INTO).
		processedSql = processSelect(goSql)
	} else {
		// For any other SQL command, leave it unaltered
		processedSql = goSql
	}

	// Execute the final SQL statement.
	// Exec is suitable for commands that don't return rows (CREATE, INSERT, etc.)
	_, err := db.Exec(processedSql)
	if err != nil {
		return C.CString(fmt.Sprintf("ERROR: SQL execution failed: %v", err))
	}

	fmt.Printf("INFO: Successfully executed SQL: %s\n", processedSql)
	return nil // Success
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
