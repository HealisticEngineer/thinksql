package com.thinksql.jdbc;

import com.sun.jna.Pointer;

import java.sql.*;
import java.util.Properties;
import java.util.logging.Logger;

/**
 * ThinkSQL JDBC Driver.
 * <p>
 * Accepts URLs of the form:
 * <pre>jdbc:thinksql:server=host;user id=user;password=pass;database=db</pre>
 * <p>
 * The portion after "jdbc:thinksql:" is passed directly as the connection string
 * to the ThinkSQL native library.
 */
public class ThinkSQLDriver implements Driver {

    /** URL prefix for this driver. */
    public static final String URL_PREFIX = "jdbc:thinksql:";

    static {
        try {
            DriverManager.registerDriver(new ThinkSQLDriver());
        } catch (SQLException e) {
            throw new ExceptionInInitializerError(e);
        }
    }

    @Override
    public Connection connect(String url, Properties info) throws SQLException {
        if (!acceptsURL(url)) {
            return null;
        }

        String connStr = url.substring(URL_PREFIX.length());

        // Merge properties into connection string if present
        if (info != null) {
            String server = info.getProperty("server");
            String user = info.getProperty("user");
            String password = info.getProperty("password");
            String database = info.getProperty("database");

            if (server != null && !connStr.toLowerCase().contains("server=")) {
                connStr += ";server=" + server;
            }
            if (user != null && !connStr.toLowerCase().contains("user id=")) {
                connStr += ";user id=" + user;
            }
            if (password != null && !connStr.toLowerCase().contains("password=")) {
                connStr += ";password=" + password;
            }
            if (database != null && !connStr.toLowerCase().contains("database=")) {
                connStr += ";database=" + database;
            }
        }

        // Call native ConnectDb
        Pointer result = ThinkSQLNative.INSTANCE.ConnectDb(connStr);
        if (result != null) {
            String error = result.getString(0);
            ThinkSQLNative.INSTANCE.FreeCString(result);
            throw new SQLException("ThinkSQL connection failed: " + error);
        }

        return new ThinkSQLConnection(url);
    }

    @Override
    public boolean acceptsURL(String url) {
        return url != null && url.startsWith(URL_PREFIX);
    }

    @Override
    public DriverPropertyInfo[] getPropertyInfo(String url, Properties info) {
        return new DriverPropertyInfo[0];
    }

    @Override
    public int getMajorVersion() {
        return 1;
    }

    @Override
    public int getMinorVersion() {
        return 0;
    }

    @Override
    public boolean jdbcCompliant() {
        return false; // Not a full JDBC implementation
    }

    @Override
    public Logger getParentLogger() throws SQLFeatureNotSupportedException {
        throw new SQLFeatureNotSupportedException("java.util.logging not supported");
    }
}
