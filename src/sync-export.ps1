# sync-export.ps1 - Export all configured tables from source database
[CmdletBinding(DefaultParameterSetName='Export')]
param(
    # Core parameters
    [Parameter(Mandatory=$true, ParameterSetName='Export')]
    [Parameter(Mandatory=$true, ParameterSetName='Analyze')]
    [Parameter(Mandatory=$true, ParameterSetName='Validate')]
    [string]$From,
    
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile = "sync-config.json",
    
    [Parameter(Mandatory=$false)]
    [string]$Tables,  # Comma-separated list of specific tables
    
    # Actions (default: Export if none specified)
    [Parameter(Mandatory=$false, ParameterSetName='Analyze')]
    [switch]$Analyze,  # Only analyze and create reports, don't export data
    
    [Parameter(Mandatory=$false, ParameterSetName='Validate')]
    [switch]$Validate,  # Only validate without reports or export
    
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
    
    [Parameter(Mandatory=$false, ParameterSetName='Help')]
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
        
    -Analyze
        Analyze data quality and create reports WITHOUT exporting data
        Automatically creates CSV reports in analysis/ directory
        
    -Validate
        Validate configuration and data WITHOUT exporting or reports
        Quick check for configuration issues
        
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
    1. Export Mode (default)
       Exports data from source database to JSON files
       
    2. Analyze Mode (-Analyze)
       Analyzes data quality without exporting
       Always creates CSV reports
       
    3. Validate Mode (-Validate)
       Quick validation without export or reports

EXAMPLES:
    # Standard export
    sync-export.ps1 -From production
    
    # Export with problem reports
    sync-export.ps1 -From production -CreateReports
    
    # Analyze data quality
    sync-export.ps1 -From production -Analyze
    
    # Export specific tables with SQL debug output
    sync-export.ps1 -From production -Tables "Users,Orders" -ShowSQL
    
    # Export with custom CSV delimiter
    sync-export.ps1 -From production -CreateReports -CsvDelimiter ";"
    
    # Quick validation
    sync-export.ps1 -From production -Validate

REPORT STRUCTURE:
    reports/ or analysis/
    └── yyyyMMdd_HHmmss/
        ├── duplicates/
        │   ├── Table1_duplicates.csv
        │   └── Table2_duplicates.csv
        └── skipped_tables.csv

"@ -ForegroundColor Cyan
    exit 0
}

# Validate parameter combinations
if ($Analyze -and $Validate) {
    Write-Host "[ERROR] Cannot use -Analyze and -Validate together" -ForegroundColor Red
    exit 1
}

if ($Validate -and $CreateReports) {
    Write-Host "[WARNING] -CreateReports ignored with -Validate" -ForegroundColor Yellow
    $CreateReports = $false
}

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

# Set report path based on mode
if ($Analyze -or $CreateReports) {
    if (-not $ReportPath) {
        $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
        if ($Analyze) {
            $ReportPath = Join-Path (Split-Path $exportPath) "analysis/$timestamp"
        } else {
            $ReportPath = Join-Path (Split-Path $exportPath) "reports/$timestamp"
        }
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

if ($Analyze) {
    Write-Host "`n=== ANALYZE MODE ===" -ForegroundColor Yellow
    Write-Host "This will analyze data quality and create reports WITHOUT exporting any data" -ForegroundColor Yellow
} elseif ($Validate) {
    Write-Host "`n=== VALIDATE MODE ===" -ForegroundColor Yellow
    Write-Host "This will validate configuration and data quality WITHOUT exporting" -ForegroundColor Yellow
} else {
    Write-Host "`n=== SYNC EXPORT ===" -ForegroundColor Cyan
}
Write-Host "Source: $From ($($sourceDb.server))" -ForegroundColor White
Write-Host "Tables: $(if ($Tables) { $Tables } else { 'All configured' })" -ForegroundColor White

# Run validation before proceeding
$validation = Test-SyncConfiguration -Config $config -DatabaseKey $From -Mode "export" -ShowSQL:$ShowSQL
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
            
            # Track duplicate problem for CSV export
            if (($Analyze -or $CreateReports) -and $uniquenessTest.DuplicateDetails) {
                $duplicateProblems += @{
                    TableName = $tableName
                    MatchOnFields = ($tableConfig.matchOn -join ",")
                    DuplicateGroups = $uniquenessTest.DuplicateGroups
                    TotalDuplicates = $uniquenessTest.TotalDuplicates
                    Details = $uniquenessTest.DuplicateDetails
                    Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                }
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
            if ($Analyze -or $Validate) {
                # In analyze/validate mode, just record the duplicates
                Write-Host "    [ANALYZED] Found duplicates" -ForegroundColor Yellow
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
        
        # Skip actual export if in analyze or validate mode
        if ($Analyze -or $Validate) {
            if ($Analyze) {
                Write-Host "Analyzing $tableName..." -ForegroundColor Yellow -NoNewline
            } else {
                Write-Host "Validating $tableName..." -ForegroundColor Yellow -NoNewline
            }
            Write-Host " [OK]" -ForegroundColor Green
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
        
        # Export data with optional WHERE clause
        $dataCmd = $connection.CreateCommand()
        if ($tableConfig.exportWhere) {
            $dataCmd.CommandText = "SELECT * FROM [$tableName] WHERE $($tableConfig.exportWhere)"
            Write-Host " (filtered: $($tableConfig.exportWhere))" -ForegroundColor DarkGray -NoNewline
            if ($ShowSQL) {
                Write-Host "`n[DEBUG] Executing data export query:" -ForegroundColor DarkCyan
                Write-Host $dataCmd.CommandText -ForegroundColor DarkGray
            }
        } else {
            $dataCmd.CommandText = "SELECT * FROM [$tableName]"
            if ($ShowSQL) {
                Write-Host "`n[DEBUG] Executing data export query:" -ForegroundColor DarkCyan
                Write-Host $dataCmd.CommandText -ForegroundColor DarkGray
            }
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

if ($Analyze) {
    Write-Host "`n=== ANALYSIS COMPLETE ===" -ForegroundColor Cyan
    Write-Host "Analyzed: $($tablesToExport.Count) tables" -ForegroundColor Green
    Write-Host "No data was exported (analyze mode)" -ForegroundColor Yellow
} elseif ($Validate) {
    Write-Host "`n=== VALIDATION COMPLETE ===" -ForegroundColor Cyan
    Write-Host "Validated: $($tablesToExport.Count) tables" -ForegroundColor Green
    Write-Host "No data was exported (validate mode)" -ForegroundColor Yellow
} else {
    Write-Host "`n=== EXPORT COMPLETE ===" -ForegroundColor Cyan
    Write-Host "Exported: $exportedCount tables" -ForegroundColor Green
    Write-Host "Location: $exportPath" -ForegroundColor Gray
}

# Export problems to CSV if requested
if (($Analyze -or $CreateReports) -and (($duplicateProblems.Count -gt 0) -or ($skippedTables.Count -gt 0))) {
    if ($Analyze) {
        Write-Host "`nCreating analysis reports..." -ForegroundColor Yellow
    } else {
        Write-Host "`nCreating problem reports..." -ForegroundColor Yellow
    }
    
    # Export duplicates CSV - one file per table
    if ($duplicateProblems.Count -gt 0) {
        # Create duplicates subdirectory
        $duplicatesDir = Join-Path $ReportPath "duplicates"
        if (-not (Test-Path $duplicatesDir)) {
            New-Item -Path $duplicatesDir -ItemType Directory -Force | Out-Null
        }
        
        # Export each table's duplicates to its own file
        foreach ($tableProblem in $duplicateProblems) {
            $tableCsvPath = Join-Path $duplicatesDir "$($tableProblem.TableName)_duplicates.csv"
            if ($CsvDelimiter) {
                Export-DuplicatesToCSV -DuplicateProblems @($tableProblem) -OutputPath $tableCsvPath -Delimiter $CsvDelimiter
            } else {
                Export-DuplicatesToCSV -DuplicateProblems @($tableProblem) -OutputPath $tableCsvPath
            }
            Write-Host "  $($tableProblem.TableName): $tableCsvPath" -ForegroundColor Gray
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
}

# Show summary statistics for analyze mode
if ($Analyze) {
    Write-Host "`n=== ANALYSIS SUMMARY ===" -ForegroundColor Cyan
    Write-Host "Total tables analyzed: $($tablesToExport.Count)" -ForegroundColor White
    Write-Host "Tables with duplicates: $($duplicateProblems.Count)" -ForegroundColor $(if ($duplicateProblems.Count -gt 0) { "Yellow" } else { "Green" })
    Write-Host "Tables skipped: $($skippedTables.Count)" -ForegroundColor $(if ($skippedTables.Count -gt 0) { "Yellow" } else { "Green" })
    
    if ($duplicateProblems.Count -gt 0) {
        $totalDuplicateRecords = ($duplicateProblems | Measure-Object -Property TotalDuplicates -Sum).Sum
        $totalDuplicateGroups = ($duplicateProblems | Measure-Object -Property DuplicateGroups -Sum).Sum
        Write-Host "`nDuplicate statistics:" -ForegroundColor Yellow
        Write-Host "  Total duplicate records: $totalDuplicateRecords" -ForegroundColor Gray
        Write-Host "  Total duplicate groups: $totalDuplicateGroups" -ForegroundColor Gray
    }
    
    Write-Host "`nAnalysis reports saved to: $ReportPath" -ForegroundColor Gray
    Write-Host "To export data, run without -Analyze parameter" -ForegroundColor Cyan
}

Write-Host ""

# Exit successfully
exit 0