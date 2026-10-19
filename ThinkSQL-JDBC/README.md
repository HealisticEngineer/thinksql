# ThinkSQL JDBC Driver

A JDBC driver for SQL Server that wraps the ThinkSQL native library, providing automatic SQL processing features including SNAPSHOT isolation for SELECT queries and automatic primary key injection for CREATE TABLE statements.

## Prerequisites

- **JDK 11+** — [Adoptium](https://adoptium.net/) or any OpenJDK distribution
- **Maven 3.6+** — [Apache Maven](https://maven.apache.org/download.cgi)
- **ThinkSQL native library** — `ThinkSQL.dll` (Windows) or `libThinkSQL.so` (Linux) must be built first

## Building

From the project root:

```powershell
.\Build-JDBC.ps1
```

This produces `ThinkSQL-JDBC/target/thinksql-jdbc-1.0.0.jar` (a fat JAR with all dependencies included).

Or build manually with Maven:

```bash
cd ThinkSQL-JDBC
mvn clean package
```

## Quick Start

```java
import java.sql.*;

public class Example {
    public static void main(String[] args) throws Exception {
        String url = "jdbc:thinksql:server=localhost;user id=sa;password=YourPassword;database=master;encrypt=disable;TrustServerCertificate=true";

        try (Connection conn = DriverManager.getConnection(url)) {
            // SELECT queries automatically use SNAPSHOT isolation
            try (Statement stmt = conn.createStatement();
                 ResultSet rs = stmt.executeQuery("SELECT name FROM sys.databases")) {
                while (rs.next()) {
                    System.out.println(rs.getString("name"));
                }
            }

            // CREATE TABLE automatically gets a primary key
            try (Statement stmt = conn.createStatement()) {
                stmt.executeUpdate("CREATE TABLE Users (Name VARCHAR(100), Email VARCHAR(100))");
            }

            // PreparedStatement with parameters
            try (PreparedStatement pstmt = conn.prepareStatement(
                    "INSERT INTO Users (Name, Email) VALUES (?, ?)")) {
                pstmt.setString(1, "John Doe");
                pstmt.setString(2, "john@example.com");
                pstmt.executeUpdate();
            }
        }
    }
}
```

## JDBC URL Format

```
jdbc:thinksql:<connection-string>
```

The portion after `jdbc:thinksql:` is passed directly to the ThinkSQL native library as the connection string.

**Examples:**

```
jdbc:thinksql:server=localhost;user id=sa;password=MyPass;database=master
jdbc:thinksql:server=10.0.0.5;user id=app_user;password=secret;database=mydb;encrypt=disable;TrustServerCertificate=true
```

You can also pass connection properties via the `Properties` object:

```java
Properties props = new Properties();
props.setProperty("user", "sa");
props.setProperty("password", "MyPass");
Connection conn = DriverManager.getConnection("jdbc:thinksql:server=localhost;database=master", props);
```

## Running the Example

```powershell
# Make sure ThinkSQL.dll is in the current directory or java.library.path
java -Dthinksql.library.path=. -cp thinksql-jdbc-1.0.0.jar com.thinksql.jdbc.example.ThinkSQLExample YourPassword
```

Or using environment variables:

```powershell
$env:THINKSQL_SERVER = "localhost"
$env:THINKSQL_DATABASE = "master"
$env:THINKSQL_USER = "sa"
$env:THINKSQL_PASSWORD = "YourPassword"
java -Dthinksql.library.path=. -cp thinksql-jdbc-1.0.0.jar com.thinksql.jdbc.example.ThinkSQLExample
```

## Native Library Location

The driver uses JNA to load the ThinkSQL native library. It searches in this order:

1. Path specified by `-Dthinksql.library.path=<dir>`
2. `java.library.path` system property
3. Default OS library search paths

On Windows, the simplest approach is to place `ThinkSQL.dll` in the same directory as your application. On Linux, place `libThinkSQL.so` in `/usr/local/lib` or set `LD_LIBRARY_PATH`.

## Supported JDBC Features

| Feature | Supported |
|---------|-----------|
| `Connection` | Connect, disconnect, auto-commit |
| `Statement` | executeQuery, executeUpdate, execute |
| `PreparedStatement` | Parameter binding (String, int, long, float, double, boolean, BigDecimal, Date, Time, Timestamp) |
| `ResultSet` | Forward-only, read-only; getString, getInt, getLong, getFloat, getDouble, getBoolean, getBigDecimal, getObject, getDate, getTime, getTimestamp |
| `ResultSetMetaData` | Column names and count |
| `DatabaseMetaData` | getTables, getColumns, getSchemas, getCatalogs, getPrimaryKeys |
| JDBC SPI auto-discovery | Yes (META-INF/services) |

## Architecture

```
┌──────────────────────┐
│   Your Java App      │
│  (JDBC API calls)    │
└──────────┬───────────┘
           │
┌──────────▼───────────┐
│  ThinkSQL JDBC       │
│  Driver (JNA bridge) │
│  thinksql-jdbc.jar   │
└──────────┬───────────┘
           │ JNA FFI
┌──────────▼───────────┐
│  ThinkSQL Native     │
│  .dll / .so          │
│  (Go → C shared lib) │
└──────────┬───────────┘
           │
┌──────────▼───────────┐
│  SQL Server          │
└──────────────────────┘
```

## Important Notes

- **Global connection**: ThinkSQL uses a single global connection, so only one `Connection` object should be active at a time
- **Memory management**: The JDBC driver handles all native memory cleanup (FreeCString) automatically
- **SQL processing**: All SQL goes through ThinkSQL's automatic processing pipeline (SNAPSHOT isolation, auto-PK injection)
