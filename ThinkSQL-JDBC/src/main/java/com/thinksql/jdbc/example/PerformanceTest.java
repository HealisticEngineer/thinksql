package com.thinksql.jdbc.example;

import java.sql.*;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Performance comparison: ThinkSQL JDBC vs Microsoft JDBC Driver.
 *
 * Usage:
 *   java --enable-native-access=ALL-UNNAMED -Dthinksql.library.path=. -cp thinksql-jdbc-1.0.0.jar \
 *        com.thinksql.jdbc.example.PerformanceTest [password] [iterations] [runs]
 */
public class PerformanceTest {

    private static final String CYAN = "\u001B[36m";
    private static final String GREEN = "\u001B[32m";
    private static final String YELLOW = "\u001B[33m";
    private static final String GRAY = "\u001B[90m";
    private static final String RED = "\u001B[31m";
    private static final String RESET = "\u001B[0m";
    private static final String BOLD = "\u001B[1m";

    private static final Map<String, Map<String, double[]>> results = new LinkedHashMap<>();

    private static int iterations = 100;
    private static int runs = 10;

    public static void main(String[] args) throws Exception {
        String server = env("THINKSQL_SERVER", "localhost");
        String database = env("THINKSQL_DATABASE", "master");
        String user = env("THINKSQL_USER", "SA");
        String password = env("THINKSQL_PASSWORD", "");

        if (args.length > 0) password = args[0];
        if (args.length > 1) iterations = Integer.parseInt(args[1]);
        if (args.length > 2) runs = Integer.parseInt(args[2]);

        if (password.isEmpty()) {
            System.err.println("Usage: PerformanceTest <password> [iterations] [runs]");
            System.exit(1);
        }

        String thinkUrl = "jdbc:thinksql:" + String.format(
                "server=%s;user id=%s;password=%s;database=%s;encrypt=disable;TrustServerCertificate=true",
                server, user, password, database);

        String msUrl = String.format(
                "jdbc:sqlserver://%s;databaseName=%s;user=%s;password=%s;encrypt=false;trustServerCertificate=true",
                server, database, user, password);

        System.out.println(CYAN + "============================================================");
        System.out.println("  ThinkSQL JDBC  vs  Microsoft JDBC  Performance Comparison");
        System.out.println("============================================================" + RESET);
        System.out.println();
        System.out.printf(YELLOW + "Configuration:" + RESET + "%n");
        System.out.printf(GRAY + "  Server:     %s%n  Database:   %s%n  Iterations: %d per run%n  Runs:       %d%n  Total:      %d operations per test%n" + RESET + "%n",
                server, database, iterations, runs, iterations * runs);

        runSuite("ThinkSQL JDBC", thinkUrl, "TS");
        runSuite("Microsoft JDBC", msUrl, "MS");
        printComparison();
        testConcurrency(thinkUrl, msUrl);
    }

    private static void runSuite(String driverName, String url, String tablePrefix) throws Exception {
        Map<String, double[]> suite = new LinkedHashMap<>();
        results.put(driverName, suite);

        System.out.println();
        System.out.println(CYAN + "========================================");
        System.out.printf("  %s%n", driverName);
        System.out.println("========================================" + RESET);

        try {
            Connection test = DriverManager.getConnection(url);
            test.close();
        } catch (Exception e) {
            System.out.printf(RED + "  FAILED to connect: %s%n" + RESET, e.getMessage());
            return;
        }

        // 1. Connection
        section("1. Connection Time (" + driverName + ")");
        double[] connectAvgs = bench(() -> {
            Connection c = DriverManager.getConnection(url);
            c.close();
        });
        suite.put("Connection", connectAvgs);
        printRunSummary(connectAvgs);

        Connection conn = DriverManager.getConnection(url);

        // 2. SELECT Queries
        section("2. SELECT Queries (" + driverName + ")");
        String[][] queries = {
                {"Simple SELECT", "SELECT @@VERSION AS Version"},
                {"System Query", "SELECT name, database_id, create_date FROM sys.databases"},
                {"Aggregate Query", "SELECT COUNT(*) AS TableCount FROM sys.tables"},
                {"Large Aggregate", "SELECT COUNT(*) AS ObjectCount FROM sys.all_objects"},
        };
        for (String[] q : queries) {
            System.out.printf(YELLOW + "  %s" + RESET + "%n", q[0]);
            double[] avgs = bench(() -> {
                try (Statement stmt = conn.createStatement();
                     ResultSet rs = stmt.executeQuery(q[1])) {
                    while (rs.next()) rs.getString(1);
                }
            });
            suite.put(q[0], avgs);
            printRunSummary(avgs);
        }

        // 3. Batch Operations (5 queries)
        section("3. Batch Operations - 5 queries (" + driverName + ")");
        String[] batchQueries = {
                "SELECT COUNT(*) AS TableCount FROM sys.tables",
                "SELECT COUNT(*) AS DatabaseCount FROM sys.databases",
                "SELECT @@VERSION AS Version",
                "SELECT GETDATE() AS CurrentTime",
                "SELECT COUNT(*) AS ObjectCount FROM sys.objects",
        };
        double[] batchAvgs = bench(() -> {
            for (String bq : batchQueries) {
                try (Statement stmt = conn.createStatement();
                     ResultSet rs = stmt.executeQuery(bq)) {
                    while (rs.next()) rs.getString(1);
                }
            }
        });
        suite.put("Batch (5 queries)", batchAvgs);
        printRunSummary(batchAvgs);

        // 4. CREATE TABLE
        section("4. CREATE TABLE (" + driverName + ")");
        double[] createAvgs = new double[runs];
        for (int run = 0; run < runs; run++) {
            double[] times = new double[iterations];
            for (int i = 0; i < iterations; i++) {
                String tbl = tablePrefix + "_Create_" + run + "_" + i;
                long start = System.nanoTime();
                try (Statement stmt = conn.createStatement()) {
                    stmt.executeUpdate("CREATE TABLE " + tbl + " (Name VARCHAR(100), Value INT)");
                }
                times[i] = (System.nanoTime() - start) / 1_000_000.0;
                try (Statement stmt = conn.createStatement()) {
                    stmt.executeUpdate("DROP TABLE " + tbl);
                }
            }
            createAvgs[run] = avg(times);
        }
        suite.put("CREATE TABLE", createAvgs);
        printRunSummary(createAvgs);

        // 5. Bulk INSERT (100 rows)
        section("5. Bulk INSERT - 100 rows (" + driverName + ")");
        String insertTable = tablePrefix + "_PerfInsert";
        try (Statement stmt = conn.createStatement()) {
            stmt.executeUpdate("IF OBJECT_ID('" + insertTable + "','U') IS NOT NULL DROP TABLE " + insertTable);
            stmt.executeUpdate("CREATE TABLE " + insertTable
                    + " (ID INT PRIMARY KEY IDENTITY(1,1), TestValue VARCHAR(100), CreatedAt DATETIME DEFAULT GETDATE())");
        }
        double[] insertAvgs = new double[runs];
        for (int run = 0; run < runs; run++) {
            double[] times = new double[iterations];
            for (int i = 0; i < iterations; i++) {
                StringBuilder sb = new StringBuilder("INSERT INTO " + insertTable + " (TestValue) VALUES ");
                for (int row = 0; row < 100; row++) {
                    if (row > 0) sb.append(",");
                    sb.append("('").append(tablePrefix).append("_").append(i).append("_").append(row).append("')");
                }
                long start = System.nanoTime();
                try (Statement stmt = conn.createStatement()) {
                    stmt.executeUpdate(sb.toString());
                }
                times[i] = (System.nanoTime() - start) / 1_000_000.0;
            }
            insertAvgs[run] = avg(times);
            if (run < runs - 1) {
                try (Statement stmt = conn.createStatement()) {
                    stmt.executeUpdate("TRUNCATE TABLE " + insertTable);
                }
            }
        }
        suite.put("Bulk INSERT (100 rows)", insertAvgs);
        printRunSummary(insertAvgs);

        // 6. PreparedStatement INSERT
        section("6. PreparedStatement INSERT (" + driverName + ")");
        try (Statement stmt = conn.createStatement()) {
            stmt.executeUpdate("TRUNCATE TABLE " + insertTable);
        }
        double[] pstmtAvgs = bench(() -> {
            try (PreparedStatement ps = conn.prepareStatement(
                    "INSERT INTO " + insertTable + " (TestValue) VALUES (?)")) {
                ps.setString(1, tablePrefix + "_ps_test");
                ps.executeUpdate();
            }
        });
        suite.put("PreparedStatement INSERT", pstmtAvgs);
        printRunSummary(pstmtAvgs);

        // 7. SELECT read-back
        section("7. SELECT read-back (" + driverName + ")");
        int rowCount;
        try (Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery("SELECT COUNT(*) FROM " + insertTable)) {
            rs.next();
            rowCount = rs.getInt(1);
        }
        System.out.printf(GRAY + "  Table has %d rows%n" + RESET, rowCount);
        double[] readAvgs = bench(() -> {
            try (Statement stmt = conn.createStatement();
                 ResultSet rs = stmt.executeQuery("SELECT ID, TestValue FROM " + insertTable)) {
                while (rs.next()) {
                    rs.getInt("ID");
                    rs.getString("TestValue");
                }
            }
        });
        suite.put("SELECT read-back", readAvgs);
        printRunSummary(readAvgs);

        // Cleanup
        try (Statement stmt = conn.createStatement()) {
            stmt.executeUpdate("DROP TABLE " + insertTable);
        }
        conn.close();
    }

    // ── Comparison ───────────────────────────────────────────────────

    private static void printComparison() {
        if (results.size() < 2) {
            System.out.println(RED + "\nCannot compare - one driver failed to connect." + RESET);
            return;
        }
        Map<String, double[]> r1 = results.get("ThinkSQL JDBC");
        Map<String, double[]> r2 = results.get("Microsoft JDBC");

        System.out.println();
        System.out.println(CYAN + BOLD + "============================================================");
        System.out.println("  PERFORMANCE COMPARISON");
        System.out.println("============================================================" + RESET);
        System.out.println();
        System.out.printf("%-25s %12s %12s %12s %10s%n",
                "Test", "ThinkSQL", "Microsoft", "Difference", "Winner");
        System.out.println("-".repeat(73));

        int thinkWins = 0, msWins = 0, ties = 0;
        for (String test : r1.keySet()) {
            double[] a1 = r1.get(test);
            double[] a2 = r2 != null ? r2.get(test) : null;
            if (a1 == null || a2 == null) continue;

            double avg1 = avg(a1), avg2 = avg(a2);
            double pct = (avg2 != 0) ? ((avg1 - avg2) / avg2) * 100 : 0;

            String winner; String winColor;
            if (Math.abs(pct) < 5) { winner = "~tie"; winColor = GRAY; ties++; }
            else if (avg1 < avg2)  { winner = "ThinkSQL"; winColor = GREEN; thinkWins++; }
            else                   { winner = "Microsoft"; winColor = YELLOW; msWins++; }

            System.out.printf("%-25s %10.2f ms %10.2f ms %+9.1f%% %s  %s" + RESET + "%n",
                    test, avg1, avg2, pct, winColor, winner);
        }
        System.out.println("-".repeat(73));
        System.out.println();

        System.out.printf(CYAN + "Score: " + RESET);
        System.out.printf(GREEN + "ThinkSQL %d" + RESET + " | ", thinkWins);
        System.out.printf(YELLOW + "Microsoft %d" + RESET + " | ", msWins);
        System.out.printf(GRAY + "Ties %d" + RESET + "%n%n", ties);

        System.out.println(CYAN + "Detailed Statistics:" + RESET);
        System.out.printf("%-25s  %8s %8s %8s  |  %8s %8s %8s%n",
                "", "TS Avg", "TS Min", "TS Max", "MS Avg", "MS Min", "MS Max");
        System.out.println("-".repeat(85));
        for (String test : r1.keySet()) {
            double[] a1 = r1.get(test);
            double[] a2 = r2 != null ? r2.get(test) : null;
            if (a1 == null || a2 == null) continue;
            System.out.printf("%-25s  %6.2f ms %6.2f ms %6.2f ms  |  %6.2f ms %6.2f ms %6.2f ms%n",
                    test, avg(a1), min(a1), max(a1), avg(a2), min(a2), max(a2));
        }
        System.out.println();
        System.out.printf(GRAY + "(%d iterations x %d runs = %d total operations per test per driver)%n" + RESET,
                iterations, runs, iterations * runs);
        System.out.println(CYAN + "============================================================" + RESET);
    }

    // ── Concurrency Tests ─────────────────────────────────────────────

    private static void testConcurrency(String thinkUrl, String msUrl) throws Exception {
        System.out.println();
        System.out.println(CYAN + BOLD + "============================================================");
        System.out.println("  CONCURRENCY TESTS: Blocking Sessions & Deadlocks");
        System.out.println("============================================================" + RESET);

        // Setup
        Connection setup = DriverManager.getConnection(msUrl);
        try (Statement stmt = setup.createStatement()) {
            stmt.executeUpdate("IF OBJECT_ID('ConcurrencyTest','U') IS NOT NULL DROP TABLE ConcurrencyTest");
            stmt.executeUpdate("CREATE TABLE ConcurrencyTest (ID INT PRIMARY KEY, Value VARCHAR(100))");
            stmt.executeUpdate("INSERT INTO ConcurrencyTest VALUES (1, 'Original'), (2, 'Original')");
        }

        // ── 8. Blocking Read ─────────────────────────────────────────
        section("8. Blocking Read: SNAPSHOT vs READ COMMITTED");
        System.out.println(GRAY + "  Setup: MS JDBC holds exclusive lock via uncommitted UPDATE" + RESET);

        Connection blocker = DriverManager.getConnection(msUrl);
        blocker.setAutoCommit(false);
        try (Statement stmt = blocker.createStatement()) {
            stmt.executeUpdate("UPDATE ConcurrencyTest SET Value = 'Locked' WHERE ID = 1");
        }

        // ThinkSQL SELECT (SNAPSHOT - should NOT block)
        {
            Connection tsConn = DriverManager.getConnection(thinkUrl);
            long start = System.nanoTime();
            try (Statement stmt = tsConn.createStatement();
                 ResultSet rs = stmt.executeQuery("SELECT * FROM ConcurrencyTest WHERE ID = 1")) {
                if (rs.next()) {
                    double ms = (System.nanoTime() - start) / 1_000_000.0;
                    System.out.printf(GREEN + "  ThinkSQL  READ: %.2f ms " + RESET + "(SNAPSHOT - no block, value='%s')%n", ms, rs.getString("Value"));
                }
            } catch (Exception e) {
                double ms = (System.nanoTime() - start) / 1_000_000.0;
                System.out.printf(RED + "  ThinkSQL  READ: %.2f ms - ERROR: %s%n" + RESET, ms, shortError(e));
            }
            tsConn.close();
        }

        // MS JDBC SELECT (READ COMMITTED - SHOULD block)
        {
            Connection msConn = DriverManager.getConnection(msUrl);
            try (Statement stmt = msConn.createStatement()) {
                stmt.execute("SET LOCK_TIMEOUT 3000");
            }
            long start = System.nanoTime();
            try (Statement stmt = msConn.createStatement();
                 ResultSet rs = stmt.executeQuery("SELECT * FROM ConcurrencyTest WHERE ID = 1")) {
                if (rs.next()) {
                    double ms = (System.nanoTime() - start) / 1_000_000.0;
                    System.out.printf(YELLOW + "  Microsoft READ: %.2f ms " + RESET + "(READ COMMITTED - succeeded, value='%s')%n", ms, rs.getString("Value"));
                }
            } catch (Exception e) {
                double ms = (System.nanoTime() - start) / 1_000_000.0;
                System.out.printf(YELLOW + "  Microsoft READ: %.2f ms " + RESET + "(READ COMMITTED - blocked then timed out)%n", ms);
            }
            msConn.close();
        }

        blocker.rollback();
        blocker.close();

        // ── 9. Blocking Write ────────────────────────────────────────
        section("9. Blocking Write: Lock Timeout Handling");
        System.out.println(GRAY + "  Setup: MS JDBC holds exclusive lock via uncommitted UPDATE" + RESET);

        blocker = DriverManager.getConnection(msUrl);
        blocker.setAutoCommit(false);
        try (Statement stmt = blocker.createStatement()) {
            stmt.executeUpdate("UPDATE ConcurrencyTest SET Value = 'Locked' WHERE ID = 1");
        }

        // ThinkSQL UPDATE attempt (combine SET LOCK_TIMEOUT in same batch so it applies on same pool conn)
        {
            Connection tsConn = DriverManager.getConnection(thinkUrl);
            long start = System.nanoTime();
            try (Statement stmt = tsConn.createStatement()) {
                stmt.executeUpdate("SET LOCK_TIMEOUT 3000; UPDATE ConcurrencyTest SET Value = 'TS_Write' WHERE ID = 1");
                double ms = (System.nanoTime() - start) / 1_000_000.0;
                System.out.printf(GREEN + "  ThinkSQL  WRITE: %.2f ms " + RESET + "(succeeded)%n", ms);
            } catch (Exception e) {
                double ms = (System.nanoTime() - start) / 1_000_000.0;
                System.out.printf(YELLOW + "  ThinkSQL  WRITE: %.2f ms " + RESET + "(blocked then timed out - correct)%n", ms);
            }
            tsConn.close();
        }

        // MS JDBC UPDATE attempt
        {
            Connection msConn = DriverManager.getConnection(msUrl);
            try (Statement stmt = msConn.createStatement()) {
                stmt.execute("SET LOCK_TIMEOUT 3000");
            }
            long start = System.nanoTime();
            try (Statement stmt = msConn.createStatement()) {
                stmt.executeUpdate("UPDATE ConcurrencyTest SET Value = 'MS_Write' WHERE ID = 1");
                double ms = (System.nanoTime() - start) / 1_000_000.0;
                System.out.printf(GREEN + "  Microsoft WRITE: %.2f ms " + RESET + "(succeeded)%n", ms);
            } catch (Exception e) {
                double ms = (System.nanoTime() - start) / 1_000_000.0;
                System.out.printf(YELLOW + "  Microsoft WRITE: %.2f ms " + RESET + "(blocked then timed out - correct)%n", ms);
            }
            msConn.close();
        }

        blocker.rollback();
        blocker.close();

        // ── 10. Deadlock Detection ───────────────────────────────────
        section("10. Deadlock Detection & Recovery");

        try (Statement stmt = setup.createStatement()) {
            stmt.executeUpdate("IF OBJECT_ID('DeadlockA','U') IS NOT NULL DROP TABLE DeadlockA");
            stmt.executeUpdate("IF OBJECT_ID('DeadlockB','U') IS NOT NULL DROP TABLE DeadlockB");
            stmt.executeUpdate("CREATE TABLE DeadlockA (ID INT PRIMARY KEY, Value VARCHAR(100))");
            stmt.executeUpdate("CREATE TABLE DeadlockB (ID INT PRIMARY KEY, Value VARCHAR(100))");
            stmt.executeUpdate("INSERT INTO DeadlockA VALUES (1, 'A')");
            stmt.executeUpdate("INSERT INTO DeadlockB VALUES (1, 'B')");
        }

        System.out.println(GRAY + "  Creating classic deadlock: two connections lock resources in opposite order" + RESET);

        Connection dl1 = DriverManager.getConnection(msUrl);
        Connection dl2 = DriverManager.getConnection(msUrl);
        dl1.setAutoCommit(false);
        dl2.setAutoCommit(false);

        // Each connection locks one table
        try (Statement stmt = dl1.createStatement()) {
            stmt.executeUpdate("UPDATE DeadlockA SET Value = 'DL1' WHERE ID = 1");
        }
        try (Statement stmt = dl2.createStatement()) {
            stmt.executeUpdate("UPDATE DeadlockB SET Value = 'DL2' WHERE ID = 1");
        }

        // Cross-lock to trigger deadlock
        AtomicBoolean dl1Victim = new AtomicBoolean(false);
        AtomicBoolean dl2Victim = new AtomicBoolean(false);
        AtomicReference<String> dl1Error = new AtomicReference<>();
        AtomicReference<String> dl2Error = new AtomicReference<>();
        long[] dlElapsed = new long[2];
        CountDownLatch latch = new CountDownLatch(2);

        Thread t1 = new Thread(() -> {
            long start = System.nanoTime();
            try (Statement stmt = dl1.createStatement()) {
                stmt.executeUpdate("UPDATE DeadlockB SET Value = 'DL1_cross' WHERE ID = 1");
            } catch (Exception e) {
                String msg = e.getMessage();
                dl1Victim.set(msg != null && (msg.contains("1205") || msg.toLowerCase().contains("deadlock")));
                dl1Error.set(msg);
            }
            dlElapsed[0] = System.nanoTime() - start;
            latch.countDown();
        });

        Thread t2 = new Thread(() -> {
            long start = System.nanoTime();
            try (Statement stmt = dl2.createStatement()) {
                stmt.executeUpdate("UPDATE DeadlockA SET Value = 'DL2_cross' WHERE ID = 1");
            } catch (Exception e) {
                String msg = e.getMessage();
                dl2Victim.set(msg != null && (msg.contains("1205") || msg.toLowerCase().contains("deadlock")));
                dl2Error.set(msg);
            }
            dlElapsed[1] = System.nanoTime() - start;
            latch.countDown();
        });

        t1.start();
        t2.start();
        latch.await();

        boolean anyDeadlock = dl1Victim.get() || dl2Victim.get();
        if (anyDeadlock) {
            for (int i = 0; i < 2; i++) {
                boolean victim = (i == 0) ? dl1Victim.get() : dl2Victim.get();
                if (victim) {
                    System.out.printf(YELLOW + "  Connection %d: Deadlock VICTIM in %.2f ms" + RESET + "%n",
                            i + 1, dlElapsed[i] / 1_000_000.0);
                } else {
                    System.out.printf(GREEN + "  Connection %d: Deadlock WINNER in %.2f ms" + RESET + "%n",
                            i + 1, dlElapsed[i] / 1_000_000.0);
                }
            }
            System.out.printf(GREEN + "  PASS: SQL Server deadlock detection working correctly%n" + RESET);
        } else {
            System.out.printf(RED + "  UNEXPECTED: No deadlock detected%n" + RESET);
            if (dl1Error.get() != null) System.out.printf(RED + "    Conn 1: %s%n" + RESET, dl1Error.get());
            if (dl2Error.get() != null) System.out.printf(RED + "    Conn 2: %s%n" + RESET, dl2Error.get());
        }

        try { dl1.rollback(); } catch (Exception ignored) {}
        try { dl2.rollback(); } catch (Exception ignored) {}
        dl1.close();
        dl2.close();

        // ThinkSQL SNAPSHOT read during active write lock
        System.out.println();
        System.out.println(GRAY + "  Testing ThinkSQL SNAPSHOT read during concurrent write lock..." + RESET);
        Connection writer = DriverManager.getConnection(msUrl);
        writer.setAutoCommit(false);
        try (Statement stmt = writer.createStatement()) {
            stmt.executeUpdate("UPDATE DeadlockA SET Value = 'WriterHoldsLock' WHERE ID = 1");
        }
        {
            Connection tsConn = DriverManager.getConnection(thinkUrl);
            long start = System.nanoTime();
            try (Statement stmt = tsConn.createStatement();
                 ResultSet rs = stmt.executeQuery("SELECT * FROM DeadlockA WHERE ID = 1")) {
                if (rs.next()) {
                    double ms = (System.nanoTime() - start) / 1_000_000.0;
                    System.out.printf(GREEN + "  ThinkSQL SNAPSHOT read: %.2f ms" + RESET + " (no block, sees pre-lock value='%s')%n",
                            ms, rs.getString("Value"));
                }
            } catch (Exception e) {
                double ms = (System.nanoTime() - start) / 1_000_000.0;
                System.out.printf(RED + "  ThinkSQL SNAPSHOT read: %.2f ms - ERROR: %s%n" + RESET, ms, shortError(e));
            }
            tsConn.close();
        }
        writer.rollback();
        writer.close();

        // Cleanup
        try (Statement stmt = setup.createStatement()) {
            stmt.executeUpdate("DROP TABLE ConcurrencyTest");
            stmt.executeUpdate("DROP TABLE DeadlockA");
            stmt.executeUpdate("DROP TABLE DeadlockB");
        }
        setup.close();

        System.out.println();
        System.out.println(CYAN + "============================================================");
        System.out.println("  Concurrency Tests Complete");
        System.out.println("============================================================" + RESET);
    }

    private static String shortError(Exception e) {
        String msg = e.getMessage();
        if (msg == null) return e.getClass().getSimpleName();
        return msg.length() > 120 ? msg.substring(0, 120) + "..." : msg;
    }

    // ── Bench helper ─────────────────────────────────────────────────

    @FunctionalInterface
    interface ThrowingRunnable { void run() throws Exception; }

    private static double[] bench(ThrowingRunnable task) throws Exception {
        double[] runAvgs = new double[runs];
        for (int run = 0; run < runs; run++) {
            double[] times = new double[iterations];
            for (int i = 0; i < iterations; i++) {
                long start = System.nanoTime();
                task.run();
                times[i] = (System.nanoTime() - start) / 1_000_000.0;
            }
            runAvgs[run] = avg(times);
        }
        return runAvgs;
    }

    // ── Helpers ──────────────────────────────────────────────────────

    private static String env(String key, String def) {
        String val = System.getenv(key);
        return (val != null && !val.isEmpty()) ? val : def;
    }

    private static void section(String title) {
        System.out.println();
        System.out.println(CYAN + "--- " + title + " ---" + RESET);
    }

    private static void printRunSummary(double[] runAvgs) {
        System.out.printf(GRAY + "  Avg: %.2f ms  (±%.2f)  Range: %.2f - %.2f ms%n" + RESET,
                avg(runAvgs), stdDev(runAvgs), min(runAvgs), max(runAvgs));
    }

    private static double avg(double[] v) {
        double s = 0; for (double x : v) s += x; return s / v.length;
    }
    private static double min(double[] v) {
        double m = v[0]; for (double x : v) if (x < m) m = x; return m;
    }
    private static double max(double[] v) {
        double m = v[0]; for (double x : v) if (x > m) m = x; return m;
    }
    private static double stdDev(double[] v) {
        double mean = avg(v), sq = 0;
        for (double x : v) sq += (x - mean) * (x - mean);
        return Math.sqrt(sq / v.length);
    }
}
