# sync-export.ps1 - Export all configured tables from source database
param(
    [Parameter(Mandatory=$true)]
    [string]$From,
    
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile = "sync-config.json",
    
    [Parameter(Mandatory=$false)]
    [string]$Tables  # Comma-separated list of specific tables
)

# Load validation functions
. (Join-Path $PSScriptRoot "sync-validation.ps1")

# Load configuration
$configPath = Join-Path $PSScriptRoot $ConfigFile
if (-not (Test-Path $configPath)) {
    Write-Host "[ERROR] Config file not found: $configPath" -ForegroundColor Red
    exit 1
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json

# Validate source database
if (-not $config.databases.$From) {
    Write-Host "[ERROR] Database '$From' not found in config. Available: $($config.databases.PSObject.Properties.Name -join ', ')" -ForegroundColor Red
    exit 1
}

$sourceDb = $config.databases.$From

# Create export directory
$exportPath = Join-Path $PSScriptRoot $config.exportPath
if (-not (Test-Path $exportPath)) {
    New-Item -Path $exportPath -ItemType Directory | Out-Null
}

# Build connection string
if ($sourceDb.auth -eq "sql") {
    $connectionString = "Server=$($sourceDb.server);Database=$($sourceDb.database);User ID=$($sourceDb.user);Password=$($sourceDb.password);"
} else {
    $connectionString = "Server=$($sourceDb.server);Database=$($sourceDb.database);Integrated Security=True;"
}

Write-Host "`n=== SYNC EXPORT ===" -ForegroundColor Cyan
Write-Host "Source: $From ($($sourceDb.server))" -ForegroundColor White
Write-Host "Tables: $(if ($Tables) { $Tables } else { 'All configured' })" -ForegroundColor White

# Run validation before proceeding
$validation = Test-SyncConfiguration -Config $config -DatabaseKey $From -Mode "export"
if (-not $validation.Success) {
    Write-Host "`n[ABORTED] Configuration validation failed" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Determine which tables to export
if ($Tables) {
    $tablesToExport = $Tables -split "," | ForEach-Object { $_.Trim() }
} else {
    # Get unique source tables
    $tablesToExport = $config.syncTables | ForEach-Object { $_.sourceTable } | Sort-Object -Unique
}

$connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
$exportedCount = 0

try {
    $connection.Open()
    
    foreach ($tableName in $tablesToExport) {
        Write-Host "Exporting $tableName..." -ForegroundColor Yellow -NoNewline
        
        # Find table configs (can be multiple if source is mapped to different targets)
        $tableConfigs = $config.syncTables | Where-Object { $_.sourceTable -eq $tableName }
        if (-not $tableConfigs) {
            Write-Host " [SKIP] Not in config" -ForegroundColor DarkGray
            continue
        }
        
        # Use first config for export metadata (they should all have same source settings)
        $tableConfig = $tableConfigs[0]
        
        # If matchOn is not specified, get primary key
        if (-not $tableConfig.matchOn -or $tableConfig.matchOn.Count -eq 0) {
            Write-Host " (detecting primary key...)" -ForegroundColor DarkGray -NoNewline
            
            # Get primary key columns
            $pkCmd = $connection.CreateCommand()
            $pkCmd.CommandText = @"
SELECT ku.COLUMN_NAME
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE ku
    ON tc.CONSTRAINT_TYPE = 'PRIMARY KEY' 
    AND tc.CONSTRAINT_NAME = ku.CONSTRAINT_NAME
WHERE ku.TABLE_NAME = @TableName
ORDER BY ku.ORDINAL_POSITION
"@
            $pkCmd.Parameters.AddWithValue("@TableName", $tableName) | Out-Null
            
            $primaryKeys = @()
            $pkReader = $pkCmd.ExecuteReader()
            while ($pkReader.Read()) {
                $primaryKeys += $pkReader["COLUMN_NAME"]
            }
            $pkReader.Close()
            
            if ($primaryKeys.Count -gt 0) {
                # Filter out ignored columns
                $usableKeys = @()
                if ($tableConfig.ignoreColumns) {
                    $usableKeys = $primaryKeys | Where-Object { $_ -notin $tableConfig.ignoreColumns }
                } else {
                    $usableKeys = $primaryKeys
                }
                
                if ($usableKeys.Count -gt 0) {
                    $tableConfig | Add-Member -NotePropertyName "matchOn" -NotePropertyValue $usableKeys -Force
                    Write-Host " using PK: $($usableKeys -join ', ')" -ForegroundColor DarkGray -NoNewline
                } else {
                    Write-Host " [ERROR] Primary key columns are ignored" -ForegroundColor Red
                    continue
                }
            } else {
                Write-Host " [ERROR] No primary key found" -ForegroundColor Red
                continue
            }
        }
        
        # Get table schema
        $schemaCmd = $connection.CreateCommand()
        $schemaCmd.CommandText = @"
SELECT 
    c.COLUMN_NAME,
    c.DATA_TYPE,
    c.IS_NULLABLE,
    CASE 
        WHEN pk.COLUMN_NAME IS NOT NULL THEN 'YES'
        ELSE 'NO'
    END AS IS_PRIMARY_KEY
FROM INFORMATION_SCHEMA.COLUMNS c
LEFT JOIN (
    SELECT ku.COLUMN_NAME
    FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
    JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE ku
        ON tc.CONSTRAINT_TYPE = 'PRIMARY KEY' 
        AND tc.CONSTRAINT_NAME = ku.CONSTRAINT_NAME
    WHERE ku.TABLE_NAME = @Table
) pk ON c.COLUMN_NAME = pk.COLUMN_NAME
WHERE c.TABLE_NAME = @Table
ORDER BY c.ORDINAL_POSITION
"@
        $schemaCmd.Parameters.AddWithValue("@Table", $tableName) | Out-Null
        
        $columns = @()
        $primaryKeys = @()
        $reader = $schemaCmd.ExecuteReader()
        
        while ($reader.Read()) {
            $colInfo = @{
                name = $reader["COLUMN_NAME"]
                type = $reader["DATA_TYPE"]
                nullable = $reader["IS_NULLABLE"] -eq "YES"
            }
            $columns += $colInfo
            
            if ($reader["IS_PRIMARY_KEY"] -eq "YES") {
                $primaryKeys += $reader["COLUMN_NAME"]
            }
        }
        $reader.Close()
        
        # Export data with optional WHERE clause
        $dataCmd = $connection.CreateCommand()
        if ($tableConfig.exportWhere) {
            $dataCmd.CommandText = "SELECT * FROM [$tableName] WHERE $($tableConfig.exportWhere)"
            Write-Host " (filtered: $($tableConfig.exportWhere))" -ForegroundColor DarkGray -NoNewline
        } else {
            $dataCmd.CommandText = "SELECT * FROM [$tableName]"
        }
        $dataCmd.CommandTimeout = 300  # 5 minutes
        
        $reader = $dataCmd.ExecuteReader()
        $data = @()
        $rowCount = 0
        
        while ($reader.Read()) {
            $row = @{}
            for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                $fieldName = $reader.GetName($i)
                $value = if ($reader.IsDBNull($i)) { $null } else { $reader.GetValue($i) }
                
                # Handle special types
                if ($value -is [DateTime]) {
                    $value = $value.ToString("yyyy-MM-dd HH:mm:ss.fff")
                }
                elseif ($value -is [byte[]]) {
                    $value = [Convert]::ToBase64String($value)
                }
                
                $row[$fieldName] = $value
            }
            $data += $row
            $rowCount++
        }
        $reader.Close()
        
        # Create export object
        $export = @{
            metadata = @{
                tableName = $tableName
                exportDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                exportFrom = $From
                exportServer = $sourceDb.server
                exportDatabase = $sourceDb.database
                rowCount = $rowCount
                primaryKeys = $primaryKeys
                matchOn = $tableConfig.matchOn
                ignoreColumns = $tableConfig.ignoreColumns
                allowDeletes = $tableConfig.allowDeletes
            }
            columns = $columns
            data = $data
        }
        
        # Save to file
        $outputFile = Join-Path $exportPath "$tableName.json"
        $export | ConvertTo-Json -Depth 10 -Compress | Out-File -FilePath $outputFile -Encoding UTF8
        
        $fileSize = (Get-Item $outputFile).Length / 1KB
        Write-Host " [OK] $rowCount rows, $('{0:N0}' -f $fileSize) KB" -ForegroundColor Green
        $exportedCount++
    }
    
} catch {
    Write-Host "`n[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    if ($connection.State -eq 'Open') {
        $connection.Close()
    }
}

Write-Host "`n=== EXPORT COMPLETE ===" -ForegroundColor Cyan
Write-Host "Exported: $exportedCount tables" -ForegroundColor Green
Write-Host "Location: $exportPath" -ForegroundColor Gray
Write-Host ""