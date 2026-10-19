package com.thinksql.jdbc;

import java.sql.*;

/**
 * ThinkSQL PreparedStatement.
 * Supports basic parameter substitution for parameterized queries.
 * Parameters are substituted as properly escaped string literals before
 * being sent to the native library.
 */
public class ThinkSQLPreparedStatement extends ThinkSQLStatement implements PreparedStatement {

    private final String sqlTemplate;
    private final Object[] parameters;
    private final int paramCount;

    ThinkSQLPreparedStatement(ThinkSQLConnection connection, String sql) {
        super(connection);
        this.sqlTemplate = sql;
        this.paramCount = countParameters(sql);
        this.parameters = new Object[paramCount];
    }

    private static int countParameters(String sql) {
        int count = 0;
        boolean inString = false;
        for (int i = 0; i < sql.length(); i++) {
            char c = sql.charAt(i);
            if (c == '\'') {
                inString = !inString;
            } else if (c == '?' && !inString) {
                count++;
            }
        }
        return count;
    }

    /**
     * Builds the final SQL by replacing ? placeholders with parameter values.
     */
    private String buildSql() throws SQLException {
        if (paramCount == 0) {
            return sqlTemplate;
        }

        StringBuilder sb = new StringBuilder();
        int paramIndex = 0;
        boolean inString = false;

        for (int i = 0; i < sqlTemplate.length(); i++) {
            char c = sqlTemplate.charAt(i);
            if (c == '\'') {
                inString = !inString;
                sb.append(c);
            } else if (c == '?' && !inString) {
                if (paramIndex >= paramCount) {
                    throw new SQLException("Too many parameter placeholders");
                }
                Object value = parameters[paramIndex++];
                if (value == null) {
                    sb.append("NULL");
                } else if (value instanceof Number) {
                    sb.append(value);
                } else if (value instanceof Boolean) {
                    sb.append((Boolean) value ? "1" : "0");
                } else {
                    // Escape single quotes for SQL string literals
                    String strVal = value.toString().replace("'", "''");
                    sb.append('\'').append(strVal).append('\'');
                }
            } else {
                sb.append(c);
            }
        }

        return sb.toString();
    }

    // ── PreparedStatement parameter setters ──────────────────────────

    private void checkIndex(int parameterIndex) throws SQLException {
        if (parameterIndex < 1 || parameterIndex > paramCount) {
            throw new SQLException("Parameter index " + parameterIndex + " out of range (1.." + paramCount + ")");
        }
    }

    @Override
    public void setNull(int parameterIndex, int sqlType) throws SQLException {
        checkIndex(parameterIndex);
        parameters[parameterIndex - 1] = null;
    }

    @Override
    public void setBoolean(int parameterIndex, boolean x) throws SQLException {
        checkIndex(parameterIndex);
        parameters[parameterIndex - 1] = x;
    }

    @Override
    public void setInt(int parameterIndex, int x) throws SQLException {
        checkIndex(parameterIndex);
        parameters[parameterIndex - 1] = x;
    }

    @Override
    public void setLong(int parameterIndex, long x) throws SQLException {
        checkIndex(parameterIndex);
        parameters[parameterIndex - 1] = x;
    }

    @Override
    public void setFloat(int parameterIndex, float x) throws SQLException {
        checkIndex(parameterIndex);
        parameters[parameterIndex - 1] = x;
    }

    @Override
    public void setDouble(int parameterIndex, double x) throws SQLException {
        checkIndex(parameterIndex);
        parameters[parameterIndex - 1] = x;
    }

    @Override
    public void setString(int parameterIndex, String x) throws SQLException {
        checkIndex(parameterIndex);
        parameters[parameterIndex - 1] = x;
    }

    @Override
    public void setObject(int parameterIndex, Object x) throws SQLException {
        checkIndex(parameterIndex);
        parameters[parameterIndex - 1] = x;
    }

    @Override
    public void setObject(int parameterIndex, Object x, int targetSqlType) throws SQLException {
        setObject(parameterIndex, x);
    }

    @Override
    public void setObject(int parameterIndex, Object x, int targetSqlType, int scaleOrLength) throws SQLException {
        setObject(parameterIndex, x);
    }

    @Override
    public void clearParameters() throws SQLException {
        java.util.Arrays.fill(parameters, null);
    }

    // ── Execution ────────────────────────────────────────────────────

    @Override
    public ResultSet executeQuery() throws SQLException {
        return executeQuery(buildSql());
    }

    @Override
    public int executeUpdate() throws SQLException {
        return executeUpdate(buildSql());
    }

    @Override
    public boolean execute() throws SQLException {
        return execute(buildSql());
    }

    // ── Metadata ─────────────────────────────────────────────────────

    @Override
    public ResultSetMetaData getMetaData() throws SQLException {
        return null;
    }

    @Override
    public ParameterMetaData getParameterMetaData() throws SQLException {
        throw new SQLFeatureNotSupportedException();
    }

    // ── Unsupported setters ──────────────────────────────────────────

    @Override
    public void setByte(int parameterIndex, byte x) throws SQLException {
        checkIndex(parameterIndex);
        parameters[parameterIndex - 1] = (int) x;
    }

    @Override
    public void setShort(int parameterIndex, short x) throws SQLException {
        checkIndex(parameterIndex);
        parameters[parameterIndex - 1] = (int) x;
    }

    @Override
    public void setBigDecimal(int parameterIndex, java.math.BigDecimal x) throws SQLException {
        checkIndex(parameterIndex);
        parameters[parameterIndex - 1] = x;
    }

    @Override
    public void setBytes(int parameterIndex, byte[] x) throws SQLException {
        throw new SQLFeatureNotSupportedException("setBytes not supported");
    }

    @Override
    public void setDate(int parameterIndex, Date x) throws SQLException {
        checkIndex(parameterIndex);
        parameters[parameterIndex - 1] = x != null ? x.toString() : null;
    }

    @Override
    public void setTime(int parameterIndex, Time x) throws SQLException {
        checkIndex(parameterIndex);
        parameters[parameterIndex - 1] = x != null ? x.toString() : null;
    }

    @Override
    public void setTimestamp(int parameterIndex, Timestamp x) throws SQLException {
        checkIndex(parameterIndex);
        parameters[parameterIndex - 1] = x != null ? x.toString() : null;
    }

    @Override
    public void setAsciiStream(int parameterIndex, java.io.InputStream x, int length) throws SQLException {
        throw new SQLFeatureNotSupportedException();
    }

    @Override
    @SuppressWarnings("deprecation")
    public void setUnicodeStream(int parameterIndex, java.io.InputStream x, int length) throws SQLException {
        throw new SQLFeatureNotSupportedException();
    }

    @Override
    public void setBinaryStream(int parameterIndex, java.io.InputStream x, int length) throws SQLException {
        throw new SQLFeatureNotSupportedException();
    }

    @Override
    public void addBatch() throws SQLException {
        throw new SQLFeatureNotSupportedException("Batch not supported");
    }

    @Override
    public void setCharacterStream(int parameterIndex, java.io.Reader reader, int length) throws SQLException {
        throw new SQLFeatureNotSupportedException();
    }

    @Override
    public void setRef(int parameterIndex, Ref x) throws SQLException {
        throw new SQLFeatureNotSupportedException();
    }

    @Override
    public void setBlob(int parameterIndex, Blob x) throws SQLException {
        throw new SQLFeatureNotSupportedException();
    }

    @Override
    public void setClob(int parameterIndex, Clob x) throws SQLException {
        throw new SQLFeatureNotSupportedException();
    }

    @Override
    public void setArray(int parameterIndex, Array x) throws SQLException {
        throw new SQLFeatureNotSupportedException();
    }

    @Override
    public void setDate(int parameterIndex, Date x, java.util.Calendar cal) throws SQLException {
        setDate(parameterIndex, x);
    }

    @Override
    public void setTime(int parameterIndex, Time x, java.util.Calendar cal) throws SQLException {
        setTime(parameterIndex, x);
    }

    @Override
    public void setTimestamp(int parameterIndex, Timestamp x, java.util.Calendar cal) throws SQLException {
        setTimestamp(parameterIndex, x);
    }

    @Override
    public void setNull(int parameterIndex, int sqlType, String typeName) throws SQLException {
        setNull(parameterIndex, sqlType);
    }

    @Override
    public void setURL(int parameterIndex, java.net.URL x) throws SQLException {
        checkIndex(parameterIndex);
        parameters[parameterIndex - 1] = x != null ? x.toString() : null;
    }

    @Override
    public void setRowId(int parameterIndex, RowId x) throws SQLException {
        throw new SQLFeatureNotSupportedException();
    }

    @Override
    public void setNString(int parameterIndex, String value) throws SQLException {
        setString(parameterIndex, value);
    }

    @Override
    public void setNCharacterStream(int parameterIndex, java.io.Reader value, long length) throws SQLException {
        throw new SQLFeatureNotSupportedException();
    }

    @Override
    public void setNClob(int parameterIndex, NClob value) throws SQLException {
        throw new SQLFeatureNotSupportedException();
    }

    @Override
    public void setClob(int parameterIndex, java.io.Reader reader, long length) throws SQLException {
        throw new SQLFeatureNotSupportedException();
    }

    @Override
    public void setBlob(int parameterIndex, java.io.InputStream inputStream, long length) throws SQLException {
        throw new SQLFeatureNotSupportedException();
    }

    @Override
    public void setNClob(int parameterIndex, java.io.Reader reader, long length) throws SQLException {
        throw new SQLFeatureNotSupportedException();
    }

    @Override
    public void setSQLXML(int parameterIndex, SQLXML xmlObject) throws SQLException {
        throw new SQLFeatureNotSupportedException();
    }

    @Override
    public void setAsciiStream(int parameterIndex, java.io.InputStream x, long length) throws SQLException {
        throw new SQLFeatureNotSupportedException();
    }

    @Override
    public void setBinaryStream(int parameterIndex, java.io.InputStream x, long length) throws SQLException {
        throw new SQLFeatureNotSupportedException();
    }

    @Override
    public void setCharacterStream(int parameterIndex, java.io.Reader reader, long length) throws SQLException {
        throw new SQLFeatureNotSupportedException();
    }

    @Override
    public void setAsciiStream(int parameterIndex, java.io.InputStream x) throws SQLException {
        throw new SQLFeatureNotSupportedException();
    }

    @Override
    public void setBinaryStream(int parameterIndex, java.io.InputStream x) throws SQLException {
        throw new SQLFeatureNotSupportedException();
    }

    @Override
    public void setCharacterStream(int parameterIndex, java.io.Reader reader) throws SQLException {
        throw new SQLFeatureNotSupportedException();
    }

    @Override
    public void setNCharacterStream(int parameterIndex, java.io.Reader value) throws SQLException {
        throw new SQLFeatureNotSupportedException();
    }

    @Override
    public void setClob(int parameterIndex, java.io.Reader reader) throws SQLException {
        throw new SQLFeatureNotSupportedException();
    }

    @Override
    public void setBlob(int parameterIndex, java.io.InputStream inputStream) throws SQLException {
        throw new SQLFeatureNotSupportedException();
    }

    @Override
    public void setNClob(int parameterIndex, java.io.Reader reader) throws SQLException {
        throw new SQLFeatureNotSupportedException();
    }
}
