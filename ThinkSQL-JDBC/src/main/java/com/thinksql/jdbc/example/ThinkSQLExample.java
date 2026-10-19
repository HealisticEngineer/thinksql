package com.thinksql.jdbc.example;

import java.sql.*;

/**
 * Example usage of the ThinkSQL JDBC driver.
 * Run with: java -Dthinksql.library.path=. -cp thinksql-jdbc-1.0.0.jar com.thinksql.jdbc.example.ThinkSQLExample
 */
public class ThinkSQLExample {

    public static void main(String[] args) throws Exception {
        // Connection parameters - override with command line args or environment
        String server = System.getenv("THINKSQL_SERVER") != null ? System.getenv("THINKSQL_SERVER") : "localhost";
        String database = System.getenv("THINKSQL_DATABASE") != null ? System.getenv("THINKSQL_DATABASE") : "master";
        String user = System.getenv("THINKSQL_USER") != null ? System.getenv("THINKSQL_USER") : "sa";
        String password = System.getenv("THINKSQL_PASSWORD") != null ? System.getenv("THINKSQL_PASSWORD") : "";

        if (password.isEmpty() && args.length > 0) {
            password = args[0];
        }

        if (password.isEmpty()) {
            System.err.println("Usage: ThinkSQLExample <password>");
            System.err.println("  Or set THINKSQL_PASSWORD environment variable");
            System.exit(1);
        }

        String url = String.format("jdbc:thinksql:server=%s;user id=%s;password=%s;database=%s;encrypt=disable;TrustServerCertificate=true",
                server, user, password, database);

        System.out.println("========================================");
        System.out.println("ThinkSQL JDBC Driver Example");
        System.out.println("========================================");
        System.out.println();

        // 1. Connect
        System.out.println("Connecting to " + server + "/" + database + "...");
        try (Connection conn = DriverManager.getConnection(url)) {
            System.out.println("✓ Connected successfully");
            System.out.println();

            // 2. Query system databases
            System.out.println("Querying sys.databases...");
            try (Statement stmt = conn.createStatement();
                 ResultSet rs = stmt.executeQuery("SELECT name, database_id, create_date FROM sys.databases")) {

                ResultSetMetaData meta = rs.getMetaData();
                int cols = meta.getColumnCount();

                // Print header
                for (int i = 1; i <= cols; i++) {
                    System.out.printf("%-30s", meta.getColumnName(i));
                }
                System.out.println();
                System.out.println("-".repeat(30 * cols));

                // Print rows
                while (rs.next()) {
                    for (int i = 1; i <= cols; i++) {
                        System.out.printf("%-30s", rs.getString(i));
                    }
                    System.out.println();
                }
            }
            System.out.println();

            // 3. Demonstrate CREATE TABLE with auto primary key
            System.out.println("Creating table JDBCTestTable...");
            try (Statement stmt = conn.createStatement()) {
                stmt.executeUpdate("IF OBJECT_ID('JDBCTestTable', 'U') IS NOT NULL DROP TABLE JDBCTestTable");
                stmt.executeUpdate("CREATE TABLE JDBCTestTable (Name VARCHAR(100), Value INT)");
                System.out.println("✓ Table created (primary key auto-injected by ThinkSQL)");
            }

            // 4. Insert data with PreparedStatement
            System.out.println("Inserting test data...");
            try (PreparedStatement pstmt = conn.prepareStatement(
                    "INSERT INTO JDBCTestTable (Name, Value) VALUES (?, ?)")) {
                pstmt.setString(1, "Alpha");
                pstmt.setInt(2, 100);
                pstmt.executeUpdate();

                pstmt.setString(1, "Beta");
                pstmt.setInt(2, 200);
                pstmt.executeUpdate();

                pstmt.setString(1, "Gamma");
                pstmt.setInt(2, 300);
                pstmt.executeUpdate();
            }
            System.out.println("✓ Inserted 3 rows");

            // 5. Query the table
            System.out.println();
            System.out.println("Querying JDBCTestTable...");
            try (Statement stmt = conn.createStatement();
                 ResultSet rs = stmt.executeQuery("SELECT * FROM JDBCTestTable")) {

                while (rs.next()) {
                    System.out.printf("  ID=%d, Name=%s, Value=%d%n",
                            rs.getInt("ID"),
                            rs.getString("Name"),
                            rs.getInt("Value"));
                }
            }

            // 6. Clean up
            System.out.println();
            System.out.println("Cleaning up...");
            try (Statement stmt = conn.createStatement()) {
                stmt.executeUpdate("DROP TABLE JDBCTestTable");
            }
            System.out.println("✓ Test table dropped");

            System.out.println();
            System.out.println("========================================");
            System.out.println("✓ All tests passed!");
            System.out.println("========================================");
        }
    }
}
