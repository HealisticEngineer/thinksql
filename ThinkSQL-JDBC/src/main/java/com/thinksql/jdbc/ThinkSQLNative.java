package com.thinksql.jdbc;

import com.sun.jna.Library;
import com.sun.jna.Native;
import com.sun.jna.Platform;
import com.sun.jna.Pointer;

/**
 * JNA interface to the ThinkSQL native library (ThinkSQL.dll / libThinkSQL.so).
 * Maps the four exported C functions: ConnectDb, DisconnectDb, ExecuteSql, FreeCString.
 */
public interface ThinkSQLNative extends Library {

    /** Singleton instance loaded from the platform-appropriate shared library. */
    ThinkSQLNative INSTANCE = loadLibrary();

    /**
     * Establishes a connection to SQL Server.
     *
     * @param connStr connection string, e.g. "server=localhost;user id=sa;password=pass;database=master"
     * @return Pointer to error message on failure, or null on success. Caller MUST call FreeCString on non-null.
     */
    Pointer ConnectDb(String connStr);

    /** Closes the active database connection. */
    void DisconnectDb();

    /**
     * Processes and executes a SQL statement.
     * SELECT queries return JSON results. Non-SELECT returns null on success.
     *
     * @param sql the SQL statement to execute
     * @return Pointer to result string (JSON for SELECT, error message on failure), or null for non-SELECT success.
     *         Caller MUST call FreeCString on non-null.
     */
    Pointer ExecuteSql(String sql);

    /**
     * Frees a C string previously returned by ConnectDb or ExecuteSql.
     *
     * @param str the pointer to free
     */
    void FreeCString(Pointer str);

    /**
     * Loads the ThinkSQL native library from the appropriate platform path.
     * Searches:
     *   1. System library path (java.library.path)
     *   2. Same directory as the JAR file
     */
    static ThinkSQLNative loadLibrary() {
        String libName;
        if (Platform.isWindows()) {
            libName = "ThinkSQL";
        } else {
            libName = "ThinkSQL";
        }

        // Allow override via system property
        String customPath = System.getProperty("thinksql.library.path");
        if (customPath != null && !customPath.isEmpty()) {
            System.setProperty("jna.library.path",
                    customPath + System.getProperty("path.separator", ";") +
                            System.getProperty("jna.library.path", ""));
        }

        return Native.load(libName, ThinkSQLNative.class);
    }
}
