package com.thinksql.jdbc;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import java.io.InputStream;
import java.io.Reader;
import java.math.BigDecimal;
import java.net.URL;
import java.sql.*;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.List;
import java.util.Map;

/**
 * ThinkSQL JDBC ResultSet.
 * Wraps JSON array results from the native ExecuteSql function.
 * The native library returns SELECT results as JSON: [{"Col1":"val1","Col2":123}, ...]
 */
public class ThinkSQLResultSet implements ResultSet {

    private final ThinkSQLStatement statement;
    private final List<String> columnNames;
    private final List<JsonObject> rows;
    private int currentRow = -1; // Before first row
    private boolean closed = false;
    private boolean wasNull = false;

    ThinkSQLResultSet(ThinkSQLStatement statement, String json) throws SQLException {
        this.statement = statement;

        try {
            JsonArray array = JsonParser.parseString(json).getAsJsonArray();
            this.rows = new ArrayList<>(array.size());
            this.columnNames = new ArrayList<>();

            // Extract column names from the first row
            if (array.size() > 0) {
                JsonObject firstRow = array.get(0).getAsJsonObject();
                for (String key : firstRow.keySet()) {
                    columnNames.add(key);
                }
            }

            // Store all rows
            for (JsonElement element : array) {
                rows.add(element.getAsJsonObject());
            }
        } catch (Exception e) {
            throw new SQLException("Failed to parse JSON result: " + e.getMessage(), e);
        }
    }

    private void checkOpen() throws SQLException {
        if (closed) {
            throw new SQLException("ResultSet is closed");
        }
    }

    private void checkRow() throws SQLException {
        checkOpen();
        if (currentRow < 0 || currentRow >= rows.size()) {
            throw new SQLException("Invalid cursor position");
        }
    }

    private JsonElement getElement(int columnIndex) throws SQLException {
        checkRow();
        if (columnIndex < 1 || columnIndex > columnNames.size()) {
            throw new SQLException("Column index " + columnIndex + " out of range (1.." + columnNames.size() + ")");
        }
        String columnName = columnNames.get(columnIndex - 1);
        JsonElement element = rows.get(currentRow).get(columnName);
        wasNull = (element == null || element.isJsonNull());
        return element;
    }

    private JsonElement getElement(String columnLabel) throws SQLException {
        checkRow();
        JsonElement element = rows.get(currentRow).get(columnLabel);
        if (element == null) {
            // Case-insensitive fallback
            for (String key : columnNames) {
                if (key.equalsIgnoreCase(columnLabel)) {
                    element = rows.get(currentRow).get(key);
                    break;
                }
            }
        }
        wasNull = (element == null || element.isJsonNull());
        return element;
    }

    // ── Navigation ───────────────────────────────────────────────────

    @Override
    public boolean next() throws SQLException {
        checkOpen();
        if (currentRow < rows.size() - 1) {
            currentRow++;
            return true;
        }
        currentRow = rows.size(); // Past last row
        return false;
    }

    @Override
    public void close() throws SQLException {
        closed = true;
    }

    @Override
    public boolean isClosed() {
        return closed;
    }

    @Override
    public boolean isBeforeFirst() throws SQLException {
        return currentRow == -1 && !rows.isEmpty();
    }

    @Override
    public boolean isAfterLast() throws SQLException {
        return currentRow >= rows.size();
    }

    @Override
    public boolean isFirst() throws SQLException {
        return currentRow == 0;
    }

    @Override
    public boolean isLast() throws SQLException {
        return currentRow == rows.size() - 1 && !rows.isEmpty();
    }

    @Override
    public int getRow() throws SQLException {
        if (currentRow >= 0 && currentRow < rows.size()) {
            return currentRow + 1;
        }
        return 0;
    }

    // ── Data access by column index ──────────────────────────────────

    @Override
    public String getString(int columnIndex) throws SQLException {
        JsonElement element = getElement(columnIndex);
        if (wasNull) return null;
        return element.getAsString();
    }

    @Override
    public boolean getBoolean(int columnIndex) throws SQLException {
        JsonElement element = getElement(columnIndex);
        if (wasNull) return false;
        if (element.getAsJsonPrimitive().isBoolean()) {
            return element.getAsBoolean();
        }
        // Handle numeric booleans (0/1)
        try {
            return element.getAsInt() != 0;
        } catch (Exception e) {
            return Boolean.parseBoolean(element.getAsString());
        }
    }

    @Override
    public int getInt(int columnIndex) throws SQLException {
        JsonElement element = getElement(columnIndex);
        if (wasNull) return 0;
        return element.getAsInt();
    }

    @Override
    public long getLong(int columnIndex) throws SQLException {
        JsonElement element = getElement(columnIndex);
        if (wasNull) return 0;
        return element.getAsLong();
    }

    @Override
    public float getFloat(int columnIndex) throws SQLException {
        JsonElement element = getElement(columnIndex);
        if (wasNull) return 0;
        return element.getAsFloat();
    }

    @Override
    public double getDouble(int columnIndex) throws SQLException {
        JsonElement element = getElement(columnIndex);
        if (wasNull) return 0;
        return element.getAsDouble();
    }

    @Override
    public BigDecimal getBigDecimal(int columnIndex) throws SQLException {
        JsonElement element = getElement(columnIndex);
        if (wasNull) return null;
        return element.getAsBigDecimal();
    }

    @Override
    public Object getObject(int columnIndex) throws SQLException {
        JsonElement element = getElement(columnIndex);
        if (wasNull) return null;
        if (element.getAsJsonPrimitive().isNumber()) {
            return element.getAsNumber();
        } else if (element.getAsJsonPrimitive().isBoolean()) {
            return element.getAsBoolean();
        }
        return element.getAsString();
    }

    // ── Data access by column label ──────────────────────────────────

    @Override
    public String getString(String columnLabel) throws SQLException {
        JsonElement element = getElement(columnLabel);
        if (wasNull) return null;
        return element.getAsString();
    }

    @Override
    public boolean getBoolean(String columnLabel) throws SQLException {
        JsonElement element = getElement(columnLabel);
        if (wasNull) return false;
        if (element.getAsJsonPrimitive().isBoolean()) {
            return element.getAsBoolean();
        }
        try {
            return element.getAsInt() != 0;
        } catch (Exception e) {
            return Boolean.parseBoolean(element.getAsString());
        }
    }

    @Override
    public int getInt(String columnLabel) throws SQLException {
        JsonElement element = getElement(columnLabel);
        if (wasNull) return 0;
        return element.getAsInt();
    }

    @Override
    public long getLong(String columnLabel) throws SQLException {
        JsonElement element = getElement(columnLabel);
        if (wasNull) return 0;
        return element.getAsLong();
    }

    @Override
    public float getFloat(String columnLabel) throws SQLException {
        JsonElement element = getElement(columnLabel);
        if (wasNull) return 0;
        return element.getAsFloat();
    }

    @Override
    public double getDouble(String columnLabel) throws SQLException {
        JsonElement element = getElement(columnLabel);
        if (wasNull) return 0;
        return element.getAsDouble();
    }

    @Override
    public BigDecimal getBigDecimal(String columnLabel) throws SQLException {
        JsonElement element = getElement(columnLabel);
        if (wasNull) return null;
        return element.getAsBigDecimal();
    }

    @Override
    public Object getObject(String columnLabel) throws SQLException {
        JsonElement element = getElement(columnLabel);
        if (wasNull) return null;
        if (element.getAsJsonPrimitive().isNumber()) {
            return element.getAsNumber();
        } else if (element.getAsJsonPrimitive().isBoolean()) {
            return element.getAsBoolean();
        }
        return element.getAsString();
    }

    // ── Metadata ─────────────────────────────────────────────────────

    @Override
    public ResultSetMetaData getMetaData() throws SQLException {
        return new ThinkSQLResultSetMetaData(columnNames);
    }

    @Override
    public int findColumn(String columnLabel) throws SQLException {
        for (int i = 0; i < columnNames.size(); i++) {
            if (columnNames.get(i).equalsIgnoreCase(columnLabel)) {
                return i + 1;
            }
        }
        throw new SQLException("Column not found: " + columnLabel);
    }

    @Override
    public boolean wasNull() throws SQLException {
        return wasNull;
    }

    @Override
    public Statement getStatement() throws SQLException {
        return statement;
    }

    // ── Cursor type info ─────────────────────────────────────────────

    @Override
    public int getType() throws SQLException {
        return ResultSet.TYPE_FORWARD_ONLY;
    }

    @Override
    public int getConcurrency() throws SQLException {
        return ResultSet.CONCUR_READ_ONLY;
    }

    @Override
    public int getFetchDirection() throws SQLException {
        return ResultSet.FETCH_FORWARD;
    }

    @Override
    public void setFetchDirection(int direction) throws SQLException {
    }

    @Override
    public int getFetchSize() throws SQLException {
        return 0;
    }

    @Override
    public void setFetchSize(int rows) throws SQLException {
    }

    @Override
    public int getHoldability() throws SQLException {
        return ResultSet.HOLD_CURSORS_OVER_COMMIT;
    }

    @Override
    public String getCursorName() throws SQLException {
        throw new SQLFeatureNotSupportedException();
    }

    // ── Unsupported / deprecated methods ─────────────────────────────

    @Override
    @SuppressWarnings("deprecation")
    public BigDecimal getBigDecimal(int columnIndex, int scale) throws SQLException {
        BigDecimal bd = getBigDecimal(columnIndex);
        return bd != null ? bd.setScale(scale) : null;
    }

    @Override
    @SuppressWarnings("deprecation")
    public BigDecimal getBigDecimal(String columnLabel, int scale) throws SQLException {
        BigDecimal bd = getBigDecimal(columnLabel);
        return bd != null ? bd.setScale(scale) : null;
    }

    @Override
    public byte getByte(int columnIndex) throws SQLException {
        return (byte) getInt(columnIndex);
    }

    @Override
    public short getShort(int columnIndex) throws SQLException {
        return (short) getInt(columnIndex);
    }

    @Override
    public byte[] getBytes(int columnIndex) throws SQLException {
        String s = getString(columnIndex);
        return s != null ? s.getBytes() : null;
    }

    @Override
    public Date getDate(int columnIndex) throws SQLException {
        String s = getString(columnIndex);
        if (s == null) return null;
        try { return Date.valueOf(s.substring(0, 10)); } catch (Exception e) { throw new SQLException("Cannot parse date: " + s); }
    }

    @Override
    public Time getTime(int columnIndex) throws SQLException {
        String s = getString(columnIndex);
        if (s == null) return null;
        try { return Time.valueOf(s); } catch (Exception e) { throw new SQLException("Cannot parse time: " + s); }
    }

    @Override
    public Timestamp getTimestamp(int columnIndex) throws SQLException {
        String s = getString(columnIndex);
        if (s == null) return null;
        try { return Timestamp.valueOf(s.replace("T", " ").replaceAll("Z$", "")); } catch (Exception e) { throw new SQLException("Cannot parse timestamp: " + s); }
    }

    @Override
    public byte getByte(String columnLabel) throws SQLException {
        return (byte) getInt(columnLabel);
    }

    @Override
    public short getShort(String columnLabel) throws SQLException {
        return (short) getInt(columnLabel);
    }

    @Override
    public byte[] getBytes(String columnLabel) throws SQLException {
        String s = getString(columnLabel);
        return s != null ? s.getBytes() : null;
    }

    @Override
    public Date getDate(String columnLabel) throws SQLException {
        String s = getString(columnLabel);
        if (s == null) return null;
        try { return Date.valueOf(s.substring(0, 10)); } catch (Exception e) { throw new SQLException("Cannot parse date: " + s); }
    }

    @Override
    public Time getTime(String columnLabel) throws SQLException {
        String s = getString(columnLabel);
        if (s == null) return null;
        try { return Time.valueOf(s); } catch (Exception e) { throw new SQLException("Cannot parse time: " + s); }
    }

    @Override
    public Timestamp getTimestamp(String columnLabel) throws SQLException {
        String s = getString(columnLabel);
        if (s == null) return null;
        try { return Timestamp.valueOf(s.replace("T", " ").replaceAll("Z$", "")); } catch (Exception e) { throw new SQLException("Cannot parse timestamp: " + s); }
    }

    @Override
    public InputStream getAsciiStream(int columnIndex) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    @SuppressWarnings("deprecation")
    public InputStream getUnicodeStream(int columnIndex) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public InputStream getBinaryStream(int columnIndex) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public InputStream getAsciiStream(String columnLabel) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    @SuppressWarnings("deprecation")
    public InputStream getUnicodeStream(String columnLabel) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public InputStream getBinaryStream(String columnLabel) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public SQLWarning getWarnings() throws SQLException { return null; }
    @Override
    public void clearWarnings() throws SQLException { }
    @Override
    public Reader getCharacterStream(int columnIndex) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public Reader getCharacterStream(String columnLabel) throws SQLException { throw new SQLFeatureNotSupportedException(); }

    // ── Positioning (not supported for FORWARD_ONLY) ─────────────────

    @Override
    public void beforeFirst() throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void afterLast() throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public boolean first() throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public boolean last() throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public boolean absolute(int row) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public boolean relative(int rows) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public boolean previous() throws SQLException { throw new SQLFeatureNotSupportedException(); }

    // ── Update operations (read-only) ────────────────────────────────

    @Override
    public boolean rowUpdated() throws SQLException { return false; }
    @Override
    public boolean rowInserted() throws SQLException { return false; }
    @Override
    public boolean rowDeleted() throws SQLException { return false; }

    @Override
    public void updateNull(int columnIndex) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateBoolean(int columnIndex, boolean x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateByte(int columnIndex, byte x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateShort(int columnIndex, short x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateInt(int columnIndex, int x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateLong(int columnIndex, long x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateFloat(int columnIndex, float x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateDouble(int columnIndex, double x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateBigDecimal(int columnIndex, BigDecimal x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateString(int columnIndex, String x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateBytes(int columnIndex, byte[] x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateDate(int columnIndex, Date x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateTime(int columnIndex, Time x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateTimestamp(int columnIndex, Timestamp x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateAsciiStream(int columnIndex, InputStream x, int length) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateBinaryStream(int columnIndex, InputStream x, int length) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateCharacterStream(int columnIndex, Reader x, int length) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateObject(int columnIndex, Object x, int scaleOrLength) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateObject(int columnIndex, Object x) throws SQLException { throw new SQLFeatureNotSupportedException(); }

    @Override
    public void updateNull(String columnLabel) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateBoolean(String columnLabel, boolean x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateByte(String columnLabel, byte x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateShort(String columnLabel, short x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateInt(String columnLabel, int x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateLong(String columnLabel, long x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateFloat(String columnLabel, float x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateDouble(String columnLabel, double x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateBigDecimal(String columnLabel, BigDecimal x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateString(String columnLabel, String x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateBytes(String columnLabel, byte[] x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateDate(String columnLabel, Date x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateTime(String columnLabel, Time x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateTimestamp(String columnLabel, Timestamp x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateAsciiStream(String columnLabel, InputStream x, int length) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateBinaryStream(String columnLabel, InputStream x, int length) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateCharacterStream(String columnLabel, Reader x, int length) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateObject(String columnLabel, Object x, int scaleOrLength) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateObject(String columnLabel, Object x) throws SQLException { throw new SQLFeatureNotSupportedException(); }

    @Override
    public void insertRow() throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateRow() throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void deleteRow() throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void refreshRow() throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void cancelRowUpdates() throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void moveToInsertRow() throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void moveToCurrentRow() throws SQLException { throw new SQLFeatureNotSupportedException(); }

    @Override
    public Object getObject(int columnIndex, Map<String, Class<?>> map) throws SQLException { return getObject(columnIndex); }
    @Override
    public Ref getRef(int columnIndex) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public Blob getBlob(int columnIndex) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public Clob getClob(int columnIndex) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public Array getArray(int columnIndex) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public Object getObject(String columnLabel, Map<String, Class<?>> map) throws SQLException { return getObject(columnLabel); }
    @Override
    public Ref getRef(String columnLabel) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public Blob getBlob(String columnLabel) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public Clob getClob(String columnLabel) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public Array getArray(String columnLabel) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public Date getDate(int columnIndex, Calendar cal) throws SQLException { return getDate(columnIndex); }
    @Override
    public Date getDate(String columnLabel, Calendar cal) throws SQLException { return getDate(columnLabel); }
    @Override
    public Time getTime(int columnIndex, Calendar cal) throws SQLException { return getTime(columnIndex); }
    @Override
    public Time getTime(String columnLabel, Calendar cal) throws SQLException { return getTime(columnLabel); }
    @Override
    public Timestamp getTimestamp(int columnIndex, Calendar cal) throws SQLException { return getTimestamp(columnIndex); }
    @Override
    public Timestamp getTimestamp(String columnLabel, Calendar cal) throws SQLException { return getTimestamp(columnLabel); }
    @Override
    public URL getURL(int columnIndex) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public URL getURL(String columnLabel) throws SQLException { throw new SQLFeatureNotSupportedException(); }

    @Override
    public void updateRef(int columnIndex, Ref x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateRef(String columnLabel, Ref x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateBlob(int columnIndex, Blob x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateBlob(String columnLabel, Blob x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateClob(int columnIndex, Clob x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateClob(String columnLabel, Clob x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateArray(int columnIndex, Array x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateArray(String columnLabel, Array x) throws SQLException { throw new SQLFeatureNotSupportedException(); }

    @Override
    public RowId getRowId(int columnIndex) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public RowId getRowId(String columnLabel) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateRowId(int columnIndex, RowId x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateRowId(String columnLabel, RowId x) throws SQLException { throw new SQLFeatureNotSupportedException(); }

    @Override
    public void updateNString(int columnIndex, String nString) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateNString(String columnLabel, String nString) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateNClob(int columnIndex, NClob nClob) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateNClob(String columnLabel, NClob nClob) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public NClob getNClob(int columnIndex) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public NClob getNClob(String columnLabel) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public SQLXML getSQLXML(int columnIndex) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public SQLXML getSQLXML(String columnLabel) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateSQLXML(int columnIndex, SQLXML xmlObject) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateSQLXML(String columnLabel, SQLXML xmlObject) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public String getNString(int columnIndex) throws SQLException { return getString(columnIndex); }
    @Override
    public String getNString(String columnLabel) throws SQLException { return getString(columnLabel); }
    @Override
    public Reader getNCharacterStream(int columnIndex) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public Reader getNCharacterStream(String columnLabel) throws SQLException { throw new SQLFeatureNotSupportedException(); }

    @Override
    public void updateAsciiStream(int columnIndex, InputStream x, long length) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateBinaryStream(int columnIndex, InputStream x, long length) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateCharacterStream(int columnIndex, Reader x, long length) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateAsciiStream(String columnLabel, InputStream x, long length) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateBinaryStream(String columnLabel, InputStream x, long length) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateCharacterStream(String columnLabel, Reader x, long length) throws SQLException { throw new SQLFeatureNotSupportedException(); }

    @Override
    public void updateBlob(int columnIndex, InputStream inputStream, long length) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateBlob(String columnLabel, InputStream inputStream, long length) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateClob(int columnIndex, Reader reader, long length) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateClob(String columnLabel, Reader reader, long length) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateNClob(int columnIndex, Reader reader, long length) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateNClob(String columnLabel, Reader reader, long length) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateNCharacterStream(int columnIndex, Reader x, long length) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateNCharacterStream(String columnLabel, Reader x, long length) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateNCharacterStream(int columnIndex, Reader x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateNCharacterStream(String columnLabel, Reader x) throws SQLException { throw new SQLFeatureNotSupportedException(); }

    @Override
    public void updateAsciiStream(int columnIndex, InputStream x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateBinaryStream(int columnIndex, InputStream x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateCharacterStream(int columnIndex, Reader x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateAsciiStream(String columnLabel, InputStream x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateBinaryStream(String columnLabel, InputStream x) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateCharacterStream(String columnLabel, Reader x) throws SQLException { throw new SQLFeatureNotSupportedException(); }

    @Override
    public void updateBlob(int columnIndex, InputStream inputStream) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateBlob(String columnLabel, InputStream inputStream) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateClob(int columnIndex, Reader reader) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateClob(String columnLabel, Reader reader) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateNClob(int columnIndex, Reader reader) throws SQLException { throw new SQLFeatureNotSupportedException(); }
    @Override
    public void updateNClob(String columnLabel, Reader reader) throws SQLException { throw new SQLFeatureNotSupportedException(); }

    @Override
    public <T> T getObject(int columnIndex, Class<T> type) throws SQLException {
        Object val = getObject(columnIndex);
        if (val == null) return null;
        if (type.isInstance(val)) return type.cast(val);
        if (type == String.class) return type.cast(val.toString());
        throw new SQLException("Cannot convert to " + type.getName());
    }

    @Override
    public <T> T getObject(String columnLabel, Class<T> type) throws SQLException {
        Object val = getObject(columnLabel);
        if (val == null) return null;
        if (type.isInstance(val)) return type.cast(val);
        if (type == String.class) return type.cast(val.toString());
        throw new SQLException("Cannot convert to " + type.getName());
    }

    @Override
    public <T> T unwrap(Class<T> iface) throws SQLException {
        if (iface.isInstance(this)) return iface.cast(this);
        throw new SQLException("Cannot unwrap to " + iface.getName());
    }

    @Override
    public boolean isWrapperFor(Class<?> iface) {
        return iface.isInstance(this);
    }
}
