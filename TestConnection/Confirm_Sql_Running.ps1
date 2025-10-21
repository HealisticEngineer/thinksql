
$SqlQuery = "SELECT * FROM master.sys.databases;"

$SqlUser = "SA"
$SqlPass = "NeverSafe2Day!"
$ConnectionString = "Server=localhost;Database=Master;User ID=$SqlUser;Password=$SqlPass;"
# --- 2. Connection and Execution Logic ---

# Initialize variables to hold the .NET objects
$SqlConnection = $null
$SqlCommand = $null
$SqlDataReader = $null

try {
    # 1. Create Connection Object
    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $SqlConnection.ConnectionString = $ConnectionString

    # 2. Open Connection
    Write-Host "Attempting to open connection..."
    $SqlConnection.Open()
    Write-Host "Connection successful (State: $($SqlConnection.State))"

    # 3. Create Command Object
    $SqlCommand = New-Object System.Data.SqlClient.SqlCommand
    $SqlCommand.Connection = $SqlConnection
    $SqlCommand.CommandText = $SqlQuery

    # 4. Execute Reader
    Write-Host "Executing query..."
    $SqlDataReader = $SqlCommand.ExecuteReader()

    # 5. Read and Display Results
    if ($SqlDataReader.HasRows) {
        Write-Host "--- Query Results ---"

        # Display column names (header)
        $Headers = @()
        for ($i = 0; $i -lt $SqlDataReader.FieldCount; $i++) {
            $Headers += $SqlDataReader.GetName($i)
        }
        Write-Host ($Headers -join "`t|`t")
        Write-Host ("-" * ($Headers -join "`t|`t").Length)

        # Display rows
        while ($SqlDataReader.Read()) {
            $RowValues = @()
            for ($i = 0; $i -lt $SqlDataReader.FieldCount; $i++) {
                # Format the value for display
                $Value = $SqlDataReader.GetValue($i)
                $RowValues += if ($Value -eq $null) { "NULL" } else { "$Value" }
            }
            Write-Host ($RowValues -join "`t|`t")
        }
        Write-Host "--- End Results ---`n"
    } else {
        Write-Warning "Query executed successfully, but returned no rows."
    }

} catch {
    Write-Error "An error occurred during SQL operation:"
    Write-Error $_.Exception.Message
    Write-Error "Check the Server name, Database name, and Connection String."
} finally {
    # 6. Clean up resources
    Write-Host "Cleaning up resources..."

    if ($SqlDataReader -ne $null) {
        $SqlDataReader.Close()
        $SqlDataReader.Dispose()
        Write-Host "SqlDataReader closed and disposed."
    }

    if ($SqlConnection -ne $null -and $SqlConnection.State -ne [System.Data.ConnectionState]::Closed) {
        $SqlConnection.Close()
        $SqlConnection.Dispose()
        Write-Host "SqlConnection closed and disposed."
    } elseif ($SqlConnection -ne $null) {
        $SqlConnection.Dispose()
    }
    Write-Host "--- Test Complete ---"
}
