package com.thinksql.jdbc;

import com.sun.jna.Pointer;

import java.sql.*;

/**
 * ThinkSQL JDBC Statement.
 * Delegates SQL execution to the ThinkSQL native library.
 * SELECT results are returned as JSON from the native layer and parsed into a ThinkSQLResultSet.
 */
public class ThinkSQLStatement implements Statement {

    protected final ThinkSQLConnection connection;
    private ThinkSQLResultSet currentResultSet;
    private int updateCount = -1;
    private boolean closed = false;

    ThinkSQLStatement(ThinkSQLConnection connection) {
        this.connection = connection;
    }

    private void checkOpen() throws SQLException {
        if (closed) {
            throw new SQLException("Statement is closed");
        }
    }

    /**
     * Determines whether the SQL is a SELECT-type query that returns results.
     */
    private boolean isQuery(String sql) {
        String trimmed = sql.trim().toUpperCase();
        return trimmed.startsWith("SELECT")
                || trimmed.startsWith("WITH")
                || (trimmed.startsWith("DECLARE") && trimmed.contains("SELECT"));
    }

    /**
     * Executes the SQL via the native library and returns the raw result string.
     *
     * @return null for successful non-SELECT, JSON string for SELECT, or throws on error
     */
    protected String executeNative(String sql) throws SQLException {
        checkOpen();

        Pointer result = ThinkSQLNative.INSTANCE.ExecuteSql(sql);

        if (result == null) {
            // Non-SELECT succeeded
            return null;
        }

        String resultStr = result.getString(0);
        ThinkSQLNative.INSTANCE.FreeCString(result);

        if (resultStr.startsWith("ERROR:")) {
            throw new SQLException(resultStr);
        }

        return resultStr;
    }

    // ── Core execution methods ───────────────────────────────────────

    @Override
    public ResultSet executeQuery(String sql) throws SQLException {
        String json = executeNative(sql);
        if (json == null) {
            // Return empty result set for non-SELECT queries
            json = "[]";
        }
        currentResultSet = new ThinkSQLResultSet(this, json);
        return currentResultSet;
    }

    @Override
    public int executeUpdate(String sql) throws SQLException {
        String result = executeNative(sql);
        updateCount = (result == null) ? 0 : -1;
        return updateCount;
    }

    @Override
    public boolean execute(String sql) throws SQLException {
        String result = executeNative(sql);

        if (result != null && isQuery(sql)) {
            currentResultSet = new ThinkSQLResultSet(this, result);
            updateCount = -1;
            return true; // has ResultSet
        } else {
            currentResultSet = null;
            updateCount = (result == null) ? 0 : -1;
            return false; // no ResultSet
        }
    }

    @Override
    public ResultSet getResultSet() throws SQLException {
        return currentResultSet;
    }

    @Override
    public int getUpdateCount() throws SQLException {
        return updateCount;
    }

    @Override
    public boolean getMoreResults() throws SQLException {
        currentResultSet = null;
        updateCount = -1;
        return false;
    }

    @Override
    public boolean getMoreResults(int current) throws SQLException {
        return getMoreResults();
    }

    @Override
    public void close() throws SQLException {
        if (!closed) {
            if (currentResultSet != null) {
                currentResultSet.close();
                currentResultSet = null;
            }
            closed = true;
        }
    }

    @Override
    public boolean isClosed() {
        return closed;
    }

    @Override
    public Connection getConnection() throws SQLException {
        return connection;
    }

    // ── Batch operations ─────────────────────────────────────────────

    @Override
    public void addBatch(String sql) throws SQLException {
        throw new SQLFeatureNotSupportedException("Batch operations not supported");
    }

    @Override
    public void clearBatch() throws SQLException {
    }

    @Override
    public int[] executeBatch() throws SQLException {
        throw new SQLFeatureNotSupportedException("Batch operations not supported");
    }

    // ── Properties ───────────────────────────────────────────────────

    @Override
    public int getMaxFieldSize() throws SQLException {
        return 0;
    }

    @Override
    public void setMaxFieldSize(int max) throws SQLException {
    }

    @Override
    public int getMaxRows() throws SQLException {
        return 0;
    }

    @Override
    public void setMaxRows(int max) throws SQLException {
    }

    @Override
    public void setEscapeProcessing(boolean enable) throws SQLException {
    }

    @Override
    public int getQueryTimeout() throws SQLException {
        return 0;
    }

    @Override
    public void setQueryTimeout(int seconds) throws SQLException {
    }

    @Override
    public void cancel() throws SQLException {
    }

    @Override
    public SQLWarning getWarnings() throws SQLException {
        return null;
    }

    @Override
    public void clearWarnings() throws SQLException {
    }

    @Override
    public void setCursorName(String name) throws SQLException {
    }

    @Override
    public void setFetchDirection(int direction) throws SQLException {
    }

    @Override
    public int getFetchDirection() throws SQLException {
        return ResultSet.FETCH_FORWARD;
    }

    @Override
    public void setFetchSize(int rows) throws SQLException {
    }

    @Override
    public int getFetchSize() throws SQLException {
        return 0;
    }

    @Override
    public int getResultSetConcurrency() throws SQLException {
        return ResultSet.CONCUR_READ_ONLY;
    }

    @Override
    public int getResultSetType() throws SQLException {
        return ResultSet.TYPE_FORWARD_ONLY;
    }

    @Override
    public int getResultSetHoldability() throws SQLException {
        return ResultSet.HOLD_CURSORS_OVER_COMMIT;
    }

    @Override
    public ResultSet getGeneratedKeys() throws SQLException {
        throw new SQLFeatureNotSupportedException();
    }

    @Override
    public int executeUpdate(String sql, int autoGeneratedKeys) throws SQLException {
        return executeUpdate(sql);
    }

    @Override
    public int executeUpdate(String sql, int[] columnIndexes) throws SQLException {
        return executeUpdate(sql);
    }

    @Override
    public int executeUpdate(String sql, String[] columnNames) throws SQLException {
        return executeUpdate(sql);
    }

    @Override
    public boolean execute(String sql, int autoGeneratedKeys) throws SQLException {
        return execute(sql);
    }

    @Override
    public boolean execute(String sql, int[] columnIndexes) throws SQLException {
        return execute(sql);
    }

    @Override
    public boolean execute(String sql, String[] columnNames) throws SQLException {
        return execute(sql);
    }

    @Override
    public void setPoolable(boolean poolable) throws SQLException {
    }

    @Override
    public boolean isPoolable() throws SQLException {
        return false;
    }

    @Override
    public void closeOnCompletion() throws SQLException {
    }

    @Override
    public boolean isCloseOnCompletion() throws SQLException {
        return false;
    }

    @Override
    public <T> T unwrap(Class<T> iface) throws SQLException {
        if (iface.isInstance(this)) {
            return iface.cast(this);
        }
        throw new SQLException("Cannot unwrap to " + iface.getName());
    }

    @Override
    public boolean isWrapperFor(Class<?> iface) {
        return iface.isInstance(this);
    }
}
