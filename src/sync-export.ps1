# sync-export.ps1 - Export all configured tables from source database
[CmdletBinding()]
param(
    # Core parameters
    [Parameter(Mandatory=$true)]
    [string]$From,
    
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile = "sync-config.json",
    
    [Parameter(Mandatory=$false)]
    [string]$Tables,  # Comma-separated list of specific tables
    
    # Actions (default: Export if none specified)
    [Parameter(Mandatory=$false)]
    [switch]$Preview,  # Preview mode - show what would be exported without prompts
    
    # Export options
    [Parameter(Mandatory=$false)]
    [switch]$SkipOnDuplicates,  # Skip tables with duplicates automatically
    
    [Parameter(Mandatory=$false)]
    [switch]$CreateReports,  # Create CSV reports for problems
    
    # General options
    [Parameter(Mandatory=$false)]
    [string]$ReportPath,  # Path for CSV reports (defaults based on mode)
    
    [Parameter(Mandatory=$false)]
    [string]$CsvDelimiter,  # CSV delimiter (defaults to culture-specific)
    
    [Parameter(Mandatory=$false)]
    [switch]$ShowSQL,  # Show SQL statements for debugging
    
    [Parameter(Mandatory=$false)]
    [switch]$Help  # Show help information
)

# Show help if requested
if ($Help) {
    Write-Host @"
`n=== SYNC-EXPORT HELP ===

DESCRIPTION:
    Exports data from a source database to JSON files for synchronization.
    Supports data quality analysis, validation, and CSV problem reports.

SYNTAX:
    sync-export.ps1 -From <database> [options]

PARAMETERS:
    -From <string> (required)
        Source database key from configuration file
        
    -ConfigFile <string>
        Path to configuration file (default: sync-config.json)
        
    -Tables <string>
        Comma-separated list of specific tables to process
        Example: -Tables "Users,Orders,Products"
        
        
    -SkipOnDuplicates
        Automatically skip tables with duplicate records
        Useful for automated/scheduled runs
        
    -CreateReports
        Create CSV reports for data quality problems during export
        Reports saved in reports/ directory
        
    -ReportPath <string>
        Custom path for CSV reports
        Default: ./reports/yyyyMMdd_HHmmss/ or ./analysis/yyyyMMdd_HHmmss/
        
    -CsvDelimiter <string>
        CSV delimiter character
        Default: Culture-specific (semicolon for DE, comma for US)
        Examples: -CsvDelimiter ";" or -CsvDelimiter ","
        
    -ShowSQL
        Show SQL statements and detailed debugging information
        
    -Help
        Show this help message

MODES OF OPERATION:
    1. Preview Mode (default)
       - Full data quality analysis
       - Duplicate detection with detailed records
       - Shows what would be exported
       - Optional reports with -CreateReports
       
    2. Export Mode (with -Execute from syncray.ps1)
       - Exports data to JSON files
       - Detailed execution report
       - Optional reports with -CreateReports

EXAMPLES:
    # Standard export
    sync-export.ps1 -From production
    
    # Export with problem reports
    sync-export.ps1 -From production -CreateReports
    
    # Preview data quality (use syncray.ps1)
    syncray.ps1 -From production
    
    # Export specific tables with SQL debug output
    sync-export.ps1 -From production -Tables "Users,Orders" -ShowSQL
    
    # Export with custom CSV delimiter
    sync-export.ps1 -From production -CreateReports -CsvDelimiter ";"
    
    # Preview with CSV reports
    sync-export.ps1 -From production -Preview -CreateReports

REPORT STRUCTURE:
    reports/yyyyMMdd_HHmmss/
    ├── analysis_report.md      # Analysis summary with recommendations
    ├── export_report.md        # Export execution results
    ├── duplicates/
    │   └── [Table]_duplicates.csv
    ├── skipped_tables.csv
    ├── export_summary.csv      # Table-by-table results
    └── export_log.json         # Detailed operation data

"@ -ForegroundColor Cyan
    exit 0
}

# No parameter validation needed anymore - simplified structure

# Load validation functions
. (Join-Path $PSScriptRoot "sync-validation.ps1")

# Load Get-PrimaryKeyColumns function
if (-not (Get-Command -Name Get-PrimaryKeyColumns -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] Required validation functions not loaded" -ForegroundColor Red
    exit 1
}

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

# Initialize problem tracking
$duplicateProblems = @()
$skippedTables = @()
$exportStartTime = Get-Date
$exportedTablesInfo = @()  # Track info for execution report

# Set report path if reports are requested
if ($CreateReports) {
    if (-not $ReportPath) {
        $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
        $ReportPath = Join-Path (Split-Path $exportPath) "reports/$timestamp"
    }
}

# Build connection string
if ($sourceDb.auth -eq "sql") {
    $connectionString = "Server=$($sourceDb.server);Database=$($sourceDb.database);User ID=$($sourceDb.user);Password=$($sourceDb.password);"
    if ($ShowSQL) {
        $maskedPassword = "*" * ($sourceDb.password.Length)
        Write-Host "[DEBUG] Connection: Server=$($sourceDb.server);Database=$($sourceDb.database);User ID=$($sourceDb.user);Password=$maskedPassword" -ForegroundColor DarkCyan
    }
} else {
    $connectionString = "Server=$($sourceDb.server);Database=$($sourceDb.database);Integrated Security=True;"
    if ($ShowSQL) {
        Write-Host "[DEBUG] Connection: Server=$($sourceDb.server);Database=$($sourceDb.database);Integrated Security=True" -ForegroundColor DarkCyan
    }
}

if ($Preview) {
    Write-Host "`n=== EXPORT PREVIEW ===" -ForegroundColor Cyan
    Write-Host "Analyzing data quality without exporting" -ForegroundColor Yellow
    if ($CreateReports) {
        Write-Host "CSV reports will be created" -ForegroundColor Yellow
    } else {
        Write-Host "Console output only (use -CreateReports for CSV)" -ForegroundColor Gray
    }
} else {
    Write-Host "`n=== SYNC EXPORT ===" -ForegroundColor Cyan
}
Write-Host "Source: $From ($($sourceDb.server))" -ForegroundColor White
Write-Host "Tables: $(if ($Tables) { $Tables } else { 'All configured' })" -ForegroundColor White

# Determine which tables to export
if ($Tables) {
    $tablesToExport = $Tables -split "," | ForEach-Object { $_.Trim() }
} else {
    # Get unique source tables
    $tablesToExport = $config.syncTables | ForEach-Object { $_.sourceTable } | Sort-Object -Unique
}

# Run validation before proceeding (only for tables we're going to export)
$validation = Test-SyncConfiguration -Config $config -DatabaseKey $From -Mode "export" -TablesToValidate $tablesToExport -ShowSQL:$ShowSQL
if (-not $validation.Success) {
    # Check if validation failed due to duplicates
    $duplicateProblems = @()
    foreach ($error in $validation.Errors) {
        if ($error -match "Duplicate records found in table '([^']+)'") {
            $tableName = $matches[1]
            $duplicateProblems += $tableName
        }
    }
    
    if ($duplicateProblems.Count -gt 0) {
        Write-Host "`n[WARNING] Validation failed due to duplicate records in the following tables:" -ForegroundColor Yellow
        foreach ($table in $duplicateProblems) {
            Write-Host "  - $table" -ForegroundColor Yellow
        }
        
        # Show detailed duplicate information
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        try {
            $connection.Open()
            foreach ($tableName in $duplicateProblems) {
                $tableConfig = $config.syncTables | Where-Object { $_.sourceTable -eq $tableName } | Select-Object -First 1
                
                if ($tableConfig) {
                    $matchFields = $tableConfig.matchOn
                    if (-not $matchFields -or $matchFields.Count -eq 0) {
                        # Get primary key as matchOn
                        $primaryKeys = Get-PrimaryKeyColumns -Connection $connection -TableName $tableName -ShowSQL:$ShowSQL
                        if ($primaryKeys -and $primaryKeys.Count -gt 0) {
                            $matchFields = $primaryKeys
                        } else {
                            Write-Host "`nTable: $tableName - Unable to show duplicates (no matchOn fields or primary key)" -ForegroundColor Yellow
                            continue
                        }
                    }
                    
                    Write-Host "`n=== Duplicate Records in $tableName ===" -ForegroundColor Cyan
                    $whereClause = if ($tableConfig.exportWhere) { $tableConfig.exportWhere } else { "" }
                    $uniquenessTest = Test-UniquenessConstraint -Connection $connection -TableName $tableName -MatchFields $matchFields -WhereClause $whereClause -ShowSQL:$ShowSQL
                    if ($uniquenessTest.DetailedDuplicates) {
                        Write-Host $uniquenessTest.DetailedDuplicates
                    }
                }
            }
        }
        finally {
            if ($connection.State -eq 'Open') { $connection.Close() }
        }
        
        if (-not $SkipOnDuplicates) {
            Write-Host "`nTo export tables with duplicates, use -SkipOnDuplicates parameter" -ForegroundColor Yellow
            Write-Host "This will export duplicate records (keeping all duplicates)" -ForegroundColor Yellow
        }
    }
    
    Write-Host "`n[ABORTED] Configuration validation failed" -ForegroundColor Red
    exit 1
}
Write-Host ""

$connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
$exportedCount = 0

try {
    $connection.Open()
    
    foreach ($tableName in $tablesToExport) {
        Write-Host "Processing $tableName..." -ForegroundColor Yellow -NoNewline
        
        # Find table configs (can be multiple if source is mapped to different targets)
        $tableConfigs = $config.syncTables | Where-Object { $_.sourceTable -eq $tableName }
        if (-not $tableConfigs) {
            Write-Host " [SKIP] Not in config" -ForegroundColor DarkGray
            $skippedTables += @{
                TableName = $tableName
                Reason = "Not found in configuration"
                DuplicateGroups = 0
                TotalDuplicates = 0
                Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
            continue
        }
        
        # Use first config for export metadata (they should all have same source settings)
        $tableConfig = $tableConfigs[0]
        
        # Get primary key columns for the table (needed for duplicate check)
        $primaryKeys = Get-PrimaryKeyColumns -Connection $connection -TableName $tableName -ShowSQL:$ShowSQL
        
        # If matchOn is not specified, get primary key
        if (-not $tableConfig.matchOn -or $tableConfig.matchOn.Count -eq 0) {
            Write-Host " (detecting primary key...)" -ForegroundColor DarkGray -NoNewline
            
            # Get primary key columns
            $pkCmd = $connection.CreateCommand()
            $pkQuery = @"
SELECT ku.COLUMN_NAME
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE ku
    ON tc.CONSTRAINT_TYPE = 'PRIMARY KEY' 
    AND tc.CONSTRAINT_NAME = ku.CONSTRAINT_NAME
WHERE ku.TABLE_NAME = @TableName
ORDER BY ku.ORDINAL_POSITION
"@
            $pkCmd.CommandText = $pkQuery
            $pkCmd.Parameters.AddWithValue("@TableName", $tableName) | Out-Null
            
            if ($ShowSQL) {
                Write-Host "[DEBUG] Executing primary key query:" -ForegroundColor DarkCyan
                Write-Host $pkQuery -ForegroundColor DarkGray
                Write-Host "[DEBUG] Parameters: @TableName = '$tableName'" -ForegroundColor DarkCyan
            }
            
            # Read primary keys from query (for matchOn detection)
            $matchOnKeys = @()
            $pkReader = $pkCmd.ExecuteReader()
            while ($pkReader.Read()) {
                $matchOnKeys += $pkReader["COLUMN_NAME"]
            }
            $pkReader.Close()
            
            if ($matchOnKeys.Count -gt 0) {
                # Filter out ignored columns
                $usableKeys = @()
                if ($tableConfig.ignoreColumns) {
                    $usableKeys = $matchOnKeys | Where-Object { $_ -notin $tableConfig.ignoreColumns }
                } else {
                    $usableKeys = $matchOnKeys
                }
                
                if ($usableKeys.Count -gt 0) {
                    $tableConfig | Add-Member -NotePropertyName "matchOn" -NotePropertyValue $usableKeys -Force
                    Write-Host " using PK: $($usableKeys -join ', ')" -ForegroundColor DarkGray -NoNewline
                } else {
                    Write-Host " [ERROR] Primary key columns are ignored" -ForegroundColor Red
                    $skippedTables += @{
                        TableName = $tableName
                        Reason = "Primary key columns are all ignored"
                        DuplicateGroups = 0
                        TotalDuplicates = 0
                        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                    }
                    continue
                }
            } else {
                Write-Host " [ERROR] No primary key found" -ForegroundColor Red
                $skippedTables += @{
                    TableName = $tableName
                    Reason = "No primary key found and no matchOn specified"
                    DuplicateGroups = 0
                    TotalDuplicates = 0
                    Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                }
                continue
            }
        }
        
        # Check for duplicates based on matchOn fields
        Write-Host " checking duplicates..." -ForegroundColor DarkGray -NoNewline
        $whereClause = if ($tableConfig.exportWhere) { $tableConfig.exportWhere } else { "" }
        $uniquenessTest = Test-MatchFieldsUniqueness -Connection $connection -TableName $tableName -MatchFields $tableConfig.matchOn -WhereClause $whereClause -ShowSQL:$ShowSQL -PrimaryKeys $primaryKeys
        
        if ($uniquenessTest.HasDuplicates) {
            Write-Host " [DUPLICATES FOUND]" -ForegroundColor Red
            Write-Host "    Found $($uniquenessTest.TotalDuplicates) duplicate records in $($uniquenessTest.DuplicateGroups) groups" -ForegroundColor Yellow
            
            # Always track duplicate problems for summary
            $duplicateProblems += @{
                TableName = $tableName
                MatchOnFields = ($tableConfig.matchOn -join ",")
                DuplicateGroups = $uniquenessTest.DuplicateGroups
                TotalDuplicates = $uniquenessTest.TotalDuplicates
                Details = if ($CreateReports -and $uniquenessTest.DuplicateDetails) { $uniquenessTest.DuplicateDetails } else { @() }
                PrimaryKeys = $primaryKeys  # Pass primary key info
                Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
            
            # Show examples
            if ($uniquenessTest.Examples) {
                Write-Host "    Example duplicates:" -ForegroundColor Yellow
                foreach ($example in $uniquenessTest.Examples | Select-Object -First 3) {
                    $valueDisplay = ($example.Values.GetEnumerator() | ForEach-Object { "$($_.Key)='$($_.Value)'" }) -join ", "
                    Write-Host "    - $valueDisplay ($($example.Count) occurrences)" -ForegroundColor Yellow
                }
            }
            
            # Show detailed duplicate table if available
            if ($uniquenessTest.DetailedDuplicates) {
                Write-Host "`n    Detailed duplicate records (max 200 rows):" -ForegroundColor Yellow
                Write-Host $uniquenessTest.DetailedDuplicates -ForegroundColor Gray
            }
            
            # Prompt user or skip based on mode
            if ($Preview) {
                # In preview mode, show detailed analysis
                Write-Host "    [PREVIEW] Found duplicates - export would prompt for action" -ForegroundColor Yellow
                $skippedTables += @{
                    TableName = $tableName
                    Reason = "Has duplicates (would prompt in execute mode)"
                    DuplicateGroups = $uniquenessTest.DuplicateGroups
                    TotalDuplicates = $uniquenessTest.TotalDuplicates
                    Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                }
                continue
            } elseif ($SkipOnDuplicates) {
                Write-Host "    [SKIP] Skipping table due to duplicates (SkipOnDuplicates)" -ForegroundColor Red
                $skippedTables += @{
                    TableName = $tableName
                    Reason = "Duplicates found"
                    DuplicateGroups = $uniquenessTest.DuplicateGroups
                    TotalDuplicates = $uniquenessTest.TotalDuplicates
                    Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                }
                continue
            } else {
                Write-Host "`n    Duplicates will be grouped by matchOn fields during export." -ForegroundColor Cyan
                Write-Host "    Only one record per unique combination will be exported." -ForegroundColor Cyan
                $response = Read-Host "`n    Continue with export? (y=yes, n=no/skip, a=abort all)"
                
                if ($response -eq 'a' -or $response -eq 'A') {
                    Write-Host "`n[ABORTED] Export cancelled by user" -ForegroundColor Red
                    if ($connection.State -eq 'Open') {
                        $connection.Close()
                    }
                    exit 0
                }
                elseif ($response -ne 'y' -and $response -ne 'Y') {
                    Write-Host "    [SKIP] Skipping table at user request" -ForegroundColor Yellow
                    $skippedTables += @{
                        TableName = $tableName
                        Reason = "User skipped due to duplicates"
                        DuplicateGroups = $uniquenessTest.DuplicateGroups
                        TotalDuplicates = $uniquenessTest.TotalDuplicates
                        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                    }
                    continue
                }
                Write-Host "    Continuing with export..." -ForegroundColor Green
            }
        } else {
            Write-Host " [OK]" -ForegroundColor Green
        }
        
        # Skip actual export if in preview mode
        if ($Preview) {
            Write-Host "Would export $tableName..." -ForegroundColor Yellow -NoNewline
            
            # Quick count query to show what would be exported
            $countCmd = $connection.CreateCommand()
            if ($tableConfig.exportWhere) {
                $countCmd.CommandText = "SELECT COUNT(*) FROM [$tableName] WHERE $($tableConfig.exportWhere)"
                Write-Host " (filtered: $($tableConfig.exportWhere))" -ForegroundColor DarkGray -NoNewline
            } else {
                $countCmd.CommandText = "SELECT COUNT(*) FROM [$tableName]"
            }
            
            try {
                $count = $countCmd.ExecuteScalar()
                Write-Host " [PREVIEW] $count rows" -ForegroundColor Green
                $exportedCount++
            } catch {
                Write-Host " [ERROR] $($_.Exception.Message)" -ForegroundColor Red
            }
            continue
        }
        
        # Now actually export the table
        Write-Host "Exporting $tableName..." -ForegroundColor Yellow -NoNewline
        
        # Get table schema
        $schemaCmd = $connection.CreateCommand()
        $schemaQuery = @"
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
        $schemaCmd.CommandText = $schemaQuery
        $schemaCmd.Parameters.AddWithValue("@Table", $tableName) | Out-Null
        
        if ($ShowSQL) {
            Write-Host "[DEBUG] Executing schema query:" -ForegroundColor DarkCyan
            Write-Host $schemaQuery -ForegroundColor DarkGray
            Write-Host "[DEBUG] Parameters: @Table = '$tableName'" -ForegroundColor DarkCyan
        }
        
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
        
        # Build column list excluding ignored columns
        $exportColumns = @()
        foreach ($col in $columns) {
            if ($col.name -notin $tableConfig.ignoreColumns) {
                $exportColumns += "[$($col.name)]"
            }
        }
        $columnList = if ($exportColumns.Count -gt 0) { $exportColumns -join ", " } else { "*" }
        
        if ($ShowSQL -and $tableConfig.ignoreColumns.Count -gt 0) {
            Write-Host "`n[DEBUG] Excluding ignored columns: $($tableConfig.ignoreColumns -join ', ')" -ForegroundColor DarkCyan
        }
        
        # Export data with duplicate handling
        $dataCmd = $connection.CreateCommand()
        
        # If we have duplicates, use ROW_NUMBER to get only one row per matchOn group
        if ($uniquenessTest -and $uniquenessTest.HasDuplicates) {
            # Build partition columns for ROW_NUMBER
            $matchColumns = $tableConfig.matchOn | ForEach-Object { "[$_]" }
            $partitionBy = $matchColumns -join ", "
            
            # Order by primary key to get consistent results
            $orderBy = if ($primaryKeys.Count -gt 0) {
                ($primaryKeys | ForEach-Object { "[$_]" }) -join ", "
            } else {
                "1"  # Fallback if no primary key
            }
            
            $whereClause = if ($tableConfig.exportWhere) { "WHERE $($tableConfig.exportWhere)" } else { "" }
            
            $dataCmd.CommandText = @"
WITH RankedData AS (
    SELECT $columnList,
           ROW_NUMBER() OVER (PARTITION BY $partitionBy ORDER BY $orderBy) as rn
    FROM [$tableName]
    $whereClause
)
SELECT $($exportColumns -join ", ")
FROM RankedData
WHERE rn = 1
"@
            Write-Host " (grouped by matchOn)" -ForegroundColor DarkGray -NoNewline
            if ($tableConfig.exportWhere) {
                Write-Host " (filtered: $($tableConfig.exportWhere))" -ForegroundColor DarkGray -NoNewline
            }
        } else {
            # No duplicates, use simple query
            if ($tableConfig.exportWhere) {
                $dataCmd.CommandText = "SELECT $columnList FROM [$tableName] WHERE $($tableConfig.exportWhere)"
                Write-Host " (filtered: $($tableConfig.exportWhere))" -ForegroundColor DarkGray -NoNewline
            } else {
                $dataCmd.CommandText = "SELECT $columnList FROM [$tableName]"
            }
        }
        
        if ($ShowSQL) {
            Write-Host "`n[DEBUG] Executing data export query:" -ForegroundColor DarkCyan
            Write-Host $dataCmd.CommandText -ForegroundColor DarkGray
        }
        $dataCmd.CommandTimeout = 300  # 5 minutes
        
        if ($ShowSQL) {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        }
        
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
            
            if ($ShowSQL -and ($rowCount % 100 -eq 0)) {
                Write-Host "[DEBUG] Exported $rowCount rows..." -ForegroundColor DarkCyan
            }
        }
        $reader.Close()
        
        if ($ShowSQL) {
            $stopwatch.Stop()
            Write-Host "[DEBUG] Query execution time: $($stopwatch.ElapsedMilliseconds)ms" -ForegroundColor DarkCyan
            Write-Host "[DEBUG] Total rows exported: $rowCount" -ForegroundColor DarkCyan
        }
        
        # Filter columns to only include exported ones
        $exportedColumnInfo = @()
        foreach ($col in $columns) {
            if ($col.name -notin $tableConfig.ignoreColumns) {
                $exportedColumnInfo += $col
            }
        }
        
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
            columns = $exportedColumnInfo
            data = $data
        }
        
        # Save to file
        $outputFile = Join-Path $exportPath "$tableName.json"
        $export | ConvertTo-Json -Depth 10 -Compress | Out-File -FilePath $outputFile -Encoding UTF8
        
        $fileSize = (Get-Item $outputFile).Length
        if ($uniquenessTest -and $uniquenessTest.HasDuplicates) {
            $originalRows = $rowCount + $uniquenessTest.TotalDuplicates
            Write-Host " [OK] $rowCount rows (from $originalRows with duplicates), $('{0:N0}' -f ($fileSize / 1KB)) KB" -ForegroundColor Green
        } else {
            Write-Host " [OK] $rowCount rows, $('{0:N0}' -f ($fileSize / 1KB)) KB" -ForegroundColor Green
        }
        $exportedCount++
        
        # Track exported table info for report
        $exportedTablesInfo += @{
            TableName = $tableName
            RowCount = $rowCount
            FileSize = $fileSize
        }
    }
    
} catch {
    Write-Host "`n[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    if ($connection.State -eq 'Open') {
        $connection.Close()
    }
}

if ($Preview) {
    Write-Host "`n=== PREVIEW COMPLETE ===" -ForegroundColor Cyan
    Write-Host "Total tables analyzed: $($tablesToExport.Count)" -ForegroundColor White
    Write-Host "Would export: $exportedCount tables" -ForegroundColor Green
    if ($skippedTables.Count -gt 0) {
        Write-Host "Would skip: $($skippedTables.Count) tables (duplicates)" -ForegroundColor Yellow
    }
    
    # Show duplicate statistics like Analyze did
    if ($duplicateProblems.Count -gt 0) {
        $totalDuplicateRecords = ($duplicateProblems | ForEach-Object { $_.TotalDuplicates } | Measure-Object -Sum).Sum
        $totalDuplicateGroups = ($duplicateProblems | ForEach-Object { $_.DuplicateGroups } | Measure-Object -Sum).Sum
        Write-Host "`nDuplicate statistics:" -ForegroundColor Yellow
        Write-Host "  Tables with duplicates: $($duplicateProblems.Count)" -ForegroundColor Gray
        Write-Host "  Total duplicate records: $totalDuplicateRecords" -ForegroundColor Gray
        Write-Host "  Total duplicate groups: $totalDuplicateGroups" -ForegroundColor Gray
    }
    
    Write-Host "`nNo data exported (preview mode)" -ForegroundColor Gray
    Write-Host "Run with -Execute flag in syncray.ps1 to perform export" -ForegroundColor Cyan
} else {
    # Calculate duration
    $exportEndTime = Get-Date
    $duration = $exportEndTime - $exportStartTime
    
    Write-Host "`n=== EXPORT EXECUTION REPORT ===" -ForegroundColor Cyan
    Write-Host "Start time: $($exportStartTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray
    Write-Host "End time: $($exportEndTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray
    Write-Host "Duration: $($duration.TotalSeconds) seconds" -ForegroundColor Gray
    
    Write-Host "`nEXPORTED TABLES:" -ForegroundColor White
    foreach ($tableInfo in $exportedTablesInfo) {
        Write-Host "[OK] $($tableInfo.TableName)" -ForegroundColor Green -NoNewline
        Write-Host " - $($tableInfo.RowCount) rows ($('{0:N0}' -f ($tableInfo.FileSize / 1KB)) KB)" -ForegroundColor Gray
    }
    
    if ($skippedTables.Count -gt 0) {
        Write-Host "`nSKIPPED TABLES:" -ForegroundColor Yellow
        foreach ($skipped in $skippedTables) {
            Write-Host "[X] $($skipped.TableName)" -ForegroundColor Red -NoNewline
            Write-Host " - $($skipped.Reason)" -ForegroundColor Gray
        }
    }
    
    Write-Host "`nSUMMARY:" -ForegroundColor White
    Write-Host "- Total tables processed: $($tablesToExport.Count)" -ForegroundColor Gray
    Write-Host "- Successfully exported: $exportedCount" -ForegroundColor $(if ($exportedCount -eq $tablesToExport.Count) { "Green" } else { "Yellow" })
    Write-Host "- Skipped: $($skippedTables.Count)" -ForegroundColor $(if ($skippedTables.Count -gt 0) { "Yellow" } else { "Green" })
    
    if ($exportedTablesInfo.Count -gt 0) {
        $totalRows = ($exportedTablesInfo | Measure-Object -Property RowCount -Sum).Sum
        $totalSize = ($exportedTablesInfo | Measure-Object -Property FileSize -Sum).Sum
        Write-Host "- Total rows exported: $('{0:N0}' -f $totalRows)" -ForegroundColor Gray
        Write-Host "- Total size: $('{0:N0}' -f ($totalSize / 1KB)) KB" -ForegroundColor Gray
    }
    
    if ($duplicateProblems.Count -gt 0) {
        Write-Host "`nISSUES:" -ForegroundColor Yellow
        foreach ($problem in $duplicateProblems) {
            Write-Host "- $($problem.TableName): $($problem.TotalDuplicates) duplicate records in $($problem.DuplicateGroups) groups" -ForegroundColor Yellow
        }
    }
    
    Write-Host "`nExport location: $exportPath" -ForegroundColor Gray
    
    # Generate operation documentation if requested (for actual export operations)
    if ($CreateReports) {
        Write-Host "`nCreating export documentation..." -ForegroundColor Yellow
        
        # Create operation report directory
        if (-not (Test-Path $ReportPath)) {
            New-Item -Path $ReportPath -ItemType Directory -Force | Out-Null
        }
        
        # Generate export operation documentation
        $operationDoc = @{
            timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            operation = "export"
            mode = "execute"
            database = @{
                key = $From
                server = $sourceDb.server
                database = $sourceDb.database
            }
            exportStatistics = @{
                totalTables = $tablesToExport.Count
                exportedTables = $exportedCount
                skippedTables = $skippedTables.Count
                tablesWithDuplicates = $duplicateProblems.Count
            }
            exportResults = $tablesToExport | ForEach-Object {
                $tableName = $_
                $wasExported = $exportedCount -gt 0  # This is a simplified check
                $duplicateProblem = $duplicateProblems | Where-Object { $_.TableName -eq $tableName }
                $skippedProblem = $skippedTables | Where-Object { $_.TableName -eq $tableName }
                
                @{
                    tableName = $tableName
                    exported = $wasExported -and (-not $skippedProblem)
                    hasDuplicates = $duplicateProblem -ne $null
                    duplicateGroups = if ($duplicateProblem) { $duplicateProblem.DuplicateGroups } else { 0 }
                    totalDuplicates = if ($duplicateProblem) { $duplicateProblem.TotalDuplicates } else { 0 }
                    skipReason = if ($skippedProblem) { $skippedProblem.Reason } else { $null }
                }
            }
            summary = @{
                success = $exportedCount -gt 0
                exportPath = $exportPath
                totalProblems = $duplicateProblems.Count + $skippedTables.Count
            }
        }
        
        # Save JSON operation documentation
        $jsonDocPath = Join-Path $ReportPath "export_log.json"
        $operationDoc | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonDocPath -Encoding UTF8
        
        # Save CSV summary
        $csvDocPath = Join-Path $ReportPath "export_summary.csv"
        $operationDoc.exportResults | ForEach-Object {
            [PSCustomObject][ordered]@{
                Timestamp = $operationDoc.timestamp
                Database = $From
                TableName = $_.tableName
                Exported = $_.exported
                HasDuplicates = $_.hasDuplicates
                DuplicateGroups = $_.duplicateGroups
                TotalDuplicates = $_.totalDuplicates
                SkipReason = $_.skipReason
            }
        } | Export-Csv -Path $csvDocPath -NoTypeInformation -Encoding UTF8
        
        Write-Host "  Export log: $jsonDocPath" -ForegroundColor Gray
        Write-Host "  Export summary: $csvDocPath" -ForegroundColor Gray
        
        # Generate Markdown report
        $markdownPath = Join-Path $ReportPath "export_report.md"
        $markdown = @"
# Export Report

**Date**: $($operationDoc.timestamp)  
**Operation**: Export  
**Mode**: Execute  
**Database**: $From ($($sourceDb.server)/$($sourceDb.database))

## Summary

- **Total tables**: $($operationDoc.exportStatistics.totalTables)
- **Successfully exported**: $($operationDoc.exportStatistics.exportedTables)
- **Skipped**: $($operationDoc.exportStatistics.skippedTables)
- **Tables with duplicates**: $($operationDoc.exportStatistics.tablesWithDuplicates)

## Exported Tables

| Table | Rows | Size (KB) |
|-------|------|----------|
"@
        foreach ($tableInfo in $exportedTablesInfo) {
            $markdown += "`n| $($tableInfo.TableName) | $('{0:N0}' -f $tableInfo.RowCount) | $('{0:N0}' -f ($tableInfo.FileSize / 1KB)) |"
        }
        
        if ($skippedTables.Count -gt 0) {
            $markdown += @"

## Skipped Tables

| Table | Reason | Duplicate Groups | Total Duplicates |
|-------|--------|------------------|------------------|
"@
            foreach ($skipped in $skippedTables) {
                $markdown += "`n| $($skipped.TableName) | $($skipped.Reason) | $($skipped.DuplicateGroups) | $($skipped.TotalDuplicates) |"
            }
        }
        
        $markdown += @"

## Export Location

``$exportPath``
"@
        
        $markdown | Out-File -FilePath $markdownPath -Encoding UTF8
        Write-Host "  Export report: $markdownPath" -ForegroundColor Gray
    }
}

# Export problems to CSV if requested
if ($CreateReports -and (($duplicateProblems.Count -gt 0) -or ($skippedTables.Count -gt 0))) {
    Write-Host "`nCreating problem reports..." -ForegroundColor Yellow
    
    # Export duplicates CSV - one file per table
    if ($duplicateProblems.Count -gt 0) {
        # Create duplicates subdirectory
        $duplicatesDir = Join-Path $ReportPath "duplicates"
        if (-not (Test-Path $duplicatesDir)) {
            New-Item -Path $duplicatesDir -ItemType Directory -Force | Out-Null
        }
        
        # First create a summary info file
        $duplicatesSummaryPath = Join-Path $duplicatesDir "duplicates_info.csv"
        $duplicateProblems | ForEach-Object {
            [PSCustomObject][ordered]@{
                TableName = $_.TableName
                MatchOnFields = $_.MatchOnFields
                DuplicateGroups = $_.DuplicateGroups
                TotalDuplicates = $_.TotalDuplicates
                DetailFile = "$($_.TableName)_duplicates.csv"
            }
        } | Export-Csv -Path $duplicatesSummaryPath -NoTypeInformation -Encoding UTF8 -UseCulture
        Write-Host "  Duplicates summary: $duplicatesSummaryPath" -ForegroundColor Gray
        
        # Export each table's duplicates to its own file
        foreach ($tableProblem in $duplicateProblems) {
            $tableCsvPath = Join-Path $duplicatesDir "$($tableProblem.TableName)_duplicates.csv"
            if ($CsvDelimiter) {
                Export-DuplicatesToCSV -DuplicateProblems @($tableProblem) -OutputPath $tableCsvPath -Delimiter $CsvDelimiter
            } else {
                Export-DuplicatesToCSV -DuplicateProblems @($tableProblem) -OutputPath $tableCsvPath
            }
            Write-Host "  $($tableProblem.TableName) details: $tableCsvPath" -ForegroundColor Gray
        }
        
    }
    
    # Export skipped tables CSV
    if ($skippedTables.Count -gt 0) {
        $skippedCsvPath = Join-Path $ReportPath "skipped_tables.csv"
        if ($CsvDelimiter) {
            Export-SkippedTablesToCSV -SkippedTables $skippedTables -OutputPath $skippedCsvPath -Delimiter $CsvDelimiter
        } else {
            Export-SkippedTablesToCSV -SkippedTables $skippedTables -OutputPath $skippedCsvPath
        }
        Write-Host "  Skipped tables report: $skippedCsvPath" -ForegroundColor Gray
    }
    
    # Generate Markdown analysis report
    $markdownPath = Join-Path $ReportPath "analysis_report.md"
    $markdown = @"
# Export Analysis Report

**Date**: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")  
**Operation**: Export Analysis  
**Mode**: Preview  
**Database**: $From ($($sourceDb.server)/$($sourceDb.database))

## Summary

- **Total tables analyzed**: $($tablesToExport.Count)
- **Tables ready for export**: $exportedCount
- **Tables with issues**: $($skippedTables.Count)
- **Tables with duplicates**: $($duplicateProblems.Count)
"@
    
    if ($duplicateProblems.Count -gt 0) {
        $totalDuplicateRecords = ($duplicateProblems | ForEach-Object { $_.TotalDuplicates } | Measure-Object -Sum).Sum
        $totalDuplicateGroups = ($duplicateProblems | ForEach-Object { $_.DuplicateGroups } | Measure-Object -Sum).Sum
        
        $markdown += @"

## Duplicate Analysis

**Total duplicate records**: $totalDuplicateRecords  
**Total duplicate groups**: $totalDuplicateGroups

| Table | Match Fields | Duplicate Groups | Total Duplicates |
|-------|--------------|------------------|------------------|
"@
        foreach ($problem in $duplicateProblems) {
            $markdown += "`n| $($problem.TableName) | $($problem.MatchOnFields) | $($problem.DuplicateGroups) | $($problem.TotalDuplicates) |"
        }
    }
    
    if ($skippedTables.Count -gt 0) {
        $markdown += @"

## Tables to Skip

| Table | Reason |
|-------|--------|
"@
        foreach ($skipped in $skippedTables) {
            $markdown += "`n| $($skipped.TableName) | $($skipped.Reason) |"
        }
    }
    
    $markdown += @"

## Recommendations

"@
    if ($duplicateProblems.Count -gt 0) {
        $markdown += @"
- Review and resolve duplicate records before export
- Consider updating matchOn fields to ensure uniqueness
- Or use -SkipOnDuplicates to skip tables with duplicates
"@
    }
    
    $markdown | Out-File -FilePath $markdownPath -Encoding UTF8
    Write-Host "  Analysis report: $markdownPath" -ForegroundColor Gray
}

# Summary statistics are now shown in Preview mode above

Write-Host ""

# Exit successfully
exit 0