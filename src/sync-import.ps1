# sync-import.ps1 - Import/sync tables to target database
[CmdletBinding(DefaultParameterSetName='Import')]
param(
    [Parameter(Mandatory=$true, ParameterSetName='Import')]
    [string]$To,
    
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile = "sync-config.json",
    
    [Parameter(Mandatory=$false)]
    [string]$Tables,  # Comma-separated list of specific tables
    
    [Parameter(Mandatory=$false)]
    [switch]$Execute,  # Actually perform the sync (default is dry-run)
    
    [Parameter(Mandatory=$false)]
    [switch]$ShowSQL,  # Show SQL statements for debugging
    
    [Parameter(Mandatory=$false, ParameterSetName='Help')]
    [switch]$Help  # Show help information
)

# Show help if requested
if ($Help) {
    Write-Host @"
`n=== SYNC-IMPORT HELP ===

DESCRIPTION:
    Imports data from JSON files to target database for synchronization.
    Supports dry-run preview and transactional execution.

SYNTAX:
    sync-import.ps1 -To <database> [options]

PARAMETERS:
    -To <string> (required)
        Target database key from configuration file
        
    -ConfigFile <string>
        Path to configuration file (default: sync-config.json)
        
    -Tables <string>
        Comma-separated list of specific tables to import
        Example: -Tables "Users,Orders,Products"
        
    -Execute
        Apply changes to database (default is dry-run preview)
        Requires explicit confirmation before execution
        
    -ShowSQL
        Show SQL statements and detailed debugging information
        
    -Help
        Show this help message

OPERATION MODES:
    1. Dry-Run Mode (default)
       Preview all changes without modifying database
       Shows INSERT, UPDATE, DELETE counts per table
       
    2. Execute Mode (-Execute)
       Apply changes to database with confirmation
       All changes wrapped in transaction
       Automatic rollback on any error

SAFETY FEATURES:
    - Validation before any operation
    - Dry-run by default
    - Explicit confirmation required for execution
    - Transaction rollback on errors
    - Detailed change preview

EXAMPLES:
    # Preview changes (dry-run)
    sync-import.ps1 -To development
    
    # Apply changes with confirmation
    sync-import.ps1 -To development -Execute
    
    # Import specific tables with SQL debug
    sync-import.ps1 -To development -Tables "Users,Orders" -ShowSQL
    
    # Import from custom config
    sync-import.ps1 -To staging -ConfigFile staging-config.json

DATA FLOW:
    1. Reads JSON files from sync-data/ directory
    2. Validates data against target database schema
    3. Calculates required changes (INSERT/UPDATE/DELETE)
    4. Shows preview or executes changes

"@ -ForegroundColor Cyan
    exit 0
}

# Load validation functions
. (Join-Path $PSScriptRoot "sync-validation.ps1")

# Load configuration
$configPath = Join-Path $PSScriptRoot $ConfigFile
if (-not (Test-Path $configPath)) {
    Write-Host "[ERROR] Config file not found: $configPath" -ForegroundColor Red
    exit 1
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json

# Validate target database
if (-not $config.databases.$To) {
    Write-Host "[ERROR] Database '$To' not found in config. Available: $($config.databases.PSObject.Properties.Name -join ', ')" -ForegroundColor Red
    exit 1
}

$targetDb = $config.databases.$To
$exportPath = Join-Path $PSScriptRoot $config.exportPath

# Build connection string
if ($targetDb.auth -eq "sql") {
    $connectionString = "Server=$($targetDb.server);Database=$($targetDb.database);User ID=$($targetDb.user);Password=$($targetDb.password);"
    if ($ShowSQL) {
        $maskedPassword = "*" * ($targetDb.password.Length)
        Write-Host "[DEBUG] Connection: Server=$($targetDb.server);Database=$($targetDb.database);User ID=$($targetDb.user);Password=$maskedPassword" -ForegroundColor DarkCyan
    }
} else {
    $connectionString = "Server=$($targetDb.server);Database=$($targetDb.database);Integrated Security=True;"
    if ($ShowSQL) {
        Write-Host "[DEBUG] Connection: Server=$($targetDb.server);Database=$($targetDb.database);Integrated Security=True" -ForegroundColor DarkCyan
    }
}

Write-Host "`n=== SYNC IMPORT ===" -ForegroundColor Cyan
Write-Host "Target: $To ($($targetDb.server))" -ForegroundColor White
Write-Host "Mode: $(if ($Execute) { 'EXECUTE' } else { 'DRY-RUN' })" -ForegroundColor $(if ($Execute) { 'Yellow' } else { 'Green' })

# Run validation before proceeding
$validation = Test-SyncConfiguration -Config $config -DatabaseKey $To -Mode "import" -ShowSQL:$ShowSQL
if (-not $validation.Success) {
    Write-Host "`n[ABORTED] Configuration validation failed" -ForegroundColor Red
    exit 1
}

# Determine which sync configs to process
if ($Tables) {
    # Filter configs by specified tables
    $tableNames = $Tables -split "," | ForEach-Object { $_.Trim() }
    $syncConfigs = $config.syncTables | Where-Object { $_.targetTable -in $tableNames }
} else {
    # Use all sync configs
    $syncConfigs = $config.syncTables
}

$connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
$totalChanges = @{ inserts = 0; updates = 0; deletes = 0 }
$allChanges = @()  # Store all changes for potential execution
$tableResults = @()  # Store results per table for summary

try {
    $connection.Open()
    $transaction = $null
    
    foreach ($syncConfig in $syncConfigs) {
        $sourceTable = $syncConfig.sourceTable
        $targetTable = if ([string]::IsNullOrWhiteSpace($syncConfig.targetTable)) { $sourceTable } else { $syncConfig.targetTable }
        $jsonFile = Join-Path $exportPath "$sourceTable.json"
        
        if (-not (Test-Path $jsonFile)) {
            Write-Host "$sourceTable -> $targetTable... [SKIP] No export file found" -ForegroundColor DarkGray
            $tableResult = @{
                table = $displayName
                inserts = 0
                updates = 0
                deletes = 0
                insertsDisabled = $false
                updatesDisabled = $false
                deletesDisabled = 0
                skipped = $true
                skipReason = "Export file not found: $($sourceTable).json"
            }
            $tableResults += $tableResult
            continue
        }
        
        $displayName = if ($sourceTable -eq $targetTable) { $targetTable } else { "$sourceTable -> $targetTable" }
        Write-Host "`nAnalyzing $displayName..." -ForegroundColor Gray
        
        # Load export data
        $export = Get-Content $jsonFile -Raw | ConvertFrom-Json
        
        # Use config from sync-config, not from export metadata
        $matchOn = $syncConfig.matchOn
        $ignoreColumns = $syncConfig.ignoreColumns
        $allowInserts = if ($null -ne $syncConfig.allowInserts) { $syncConfig.allowInserts } else { $true }
        $allowUpdates = if ($null -ne $syncConfig.allowUpdates) { $syncConfig.allowUpdates } else { $true }
        $allowDeletes = if ($null -ne $syncConfig.allowDeletes) { $syncConfig.allowDeletes } else { $false }
        
        # If matchOn is not specified, get primary key from export metadata
        if (-not $matchOn -or $matchOn.Count -eq 0) {
            if ($export.metadata.primaryKeys -and $export.metadata.primaryKeys.Count -gt 0) {
                # Filter out ignored columns
                $usableKeys = @()
                if ($ignoreColumns) {
                    $usableKeys = $export.metadata.primaryKeys | Where-Object { $_ -notin $ignoreColumns }
                } else {
                    $usableKeys = $export.metadata.primaryKeys
                }
                
                if ($usableKeys.Count -gt 0) {
                    $matchOn = $usableKeys
                    Write-Host "Using primary key: $($matchOn -join ', ')" -ForegroundColor Gray
                } else {
                    Write-Host "$sourceTable -> $targetTable... [ERROR] Primary key columns are ignored" -ForegroundColor Red
                    continue
                }
            } else {
                Write-Host "$sourceTable -> $targetTable... [ERROR] No matchOn fields and no primary key in export" -ForegroundColor Red
                continue
            }
        }
        
        
        # Load target data
        $targetData = @{}
        $cmd = $connection.CreateCommand()
        $cmd.CommandText = "SELECT * FROM [$targetTable]"
        
        if ($ShowSQL) {
            Write-Host "[DEBUG] Loading target data:" -ForegroundColor DarkCyan
            Write-Host $cmd.CommandText -ForegroundColor DarkGray
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        }
        
        $reader = $cmd.ExecuteReader()
        
        $columnNames = @()
        for ($i = 0; $i -lt $reader.FieldCount; $i++) {
            $columnNames += $reader.GetName($i)
        }
        
        $targetRowCount = 0
        while ($reader.Read()) {
            $row = @{}
            for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                $colName = $reader.GetName($i)
                if ($reader.IsDBNull($i)) {
                    $row[$colName] = $null
                } else {
                    # Get the actual value
                    $value = $reader.GetValue($i)
                    # Ensure booleans are properly typed
                    if ($reader.GetFieldType($i) -eq [System.Boolean]) {
                        $row[$colName] = [bool]$value
                    } else {
                        $row[$colName] = $value
                    }
                }
            }
            
            # Create composite key for matching
            $keyValues = @()
            foreach ($keyField in $matchOn) {
                $keyValues += $row[$keyField]
            }
            $compositeKey = $keyValues -join "|"
            
            
            $targetData[$compositeKey] = $row
            $targetRowCount++
        }
        $reader.Close()
        
        if ($ShowSQL) {
            $stopwatch.Stop()
            Write-Host "[DEBUG] Loaded $targetRowCount target rows in $($stopwatch.ElapsedMilliseconds)ms" -ForegroundColor DarkCyan
        }
        
        # Analyze changes
        $changes = @{ inserts = @(); updates = @(); deletes = @() }
        
        # Check for inserts and updates
        foreach ($sourceRow in $export.data) {
            # Create composite key
            $keyValues = @()
            foreach ($keyField in $matchOn) {
                $keyValues += $sourceRow.$keyField
            }
            $compositeKey = $keyValues -join "|"
            
            if ($targetData.ContainsKey($compositeKey)) {
                # Check for updates
                $targetRow = $targetData[$compositeKey]
                $isDifferent = $false
                $changedFields = @()
                
                foreach ($col in $columnNames) {
                    if ($col -notin $matchOn -and $col -notin $ignoreColumns) {
                        $sourceVal = $sourceRow.$col
                        $targetVal = $targetRow[$col]
                        
                        # Convert types for proper comparison
                        if ($sourceVal -is [string]) {
                            if ($sourceVal -match '^\d{4}-\d{2}-\d{2}') {
                                $sourceVal = [DateTime]::Parse($sourceVal)
                            }
                            elseif ($sourceVal -eq "True" -or $sourceVal -eq "true") {
                                $sourceVal = $true
                            }
                            elseif ($sourceVal -eq "False" -or $sourceVal -eq "false") {
                                $sourceVal = $false
                            }
                        }
                        
                        # Compare values (handle boolean vs bit comparison)
                        $areEqual = $false
                        if ($null -eq $sourceVal -and $null -eq $targetVal) {
                            $areEqual = $true
                        }
                        elseif ($null -eq $sourceVal -or $null -eq $targetVal) {
                            $areEqual = $false
                        }
                        elseif ($sourceVal -is [bool] -or $targetVal -is [bool]) {
                            # Boolean comparison (handle bit/boolean mismatch)
                            $sourceBool = [bool]$sourceVal
                            $targetBool = [bool]$targetVal
                            $areEqual = $sourceBool -eq $targetBool
                        }
                        else {
                            $areEqual = $sourceVal -eq $targetVal
                        }
                        
                        if (-not $areEqual) {
                            $isDifferent = $true
                            $changedFields += @{
                                field = $col
                                oldValue = $targetVal
                                newValue = $sourceVal
                            }
                        }
                    }
                }
                
                if ($isDifferent) {
                    # Update (only if allowed)
                    if ($allowUpdates) {
                        $changes.updates += @{
                            compositeKey = $compositeKey
                            matchFields = $matchOn
                            matchValues = $keyValues
                            changes = $changedFields
                            data = $sourceRow
                        }
                    }
                }
                
                # Remove from targetData to track deletes
                $targetData.Remove($compositeKey)
            }
            else {
                # Insert (only if allowed)
                if ($allowInserts) {
                    $changes.inserts += @{
                        compositeKey = $compositeKey
                        data = $sourceRow
                    }
                }
            }
        }
        
        # Remaining items in targetData are deletes
        if ($allowDeletes) {
            foreach ($key in $targetData.Keys) {
                $changes.deletes += @{
                    compositeKey = $key
                    data = $targetData[$key]
                }
            }
        }
        
        # Count changes and store table results
        $tableResult = @{
            table = $displayName
            inserts = $changes.inserts.Count
            updates = $changes.updates.Count
            deletes = if ($allowDeletes) { $changes.deletes.Count } else { 0 }
            insertsDisabled = if (-not $allowInserts) { $true } else { $false }
            updatesDisabled = if (-not $allowUpdates) { $true } else { $false }
            deletesDisabled = if (-not $allowDeletes -and $changes.deletes.Count -gt 0) { $changes.deletes.Count } else { 0 }
        }
        $tableResults += $tableResult
        
        if ($changes.inserts.Count -gt 0) {
            $totalChanges.inserts += $changes.inserts.Count
        }
        if ($changes.updates.Count -gt 0) {
            $totalChanges.updates += $changes.updates.Count
        }
        if ($changes.deletes.Count -gt 0 -and $allowDeletes) {
            $totalChanges.deletes += $changes.deletes.Count
        }
        
        # Store changes for later execution
        if ($changes.inserts.Count -gt 0 -or $changes.updates.Count -gt 0 -or ($allowDeletes -and $changes.deletes.Count -gt 0)) {
            $allChanges += @{
                syncConfig = $syncConfig
                targetTable = $targetTable
                changes = $changes
                preserveIdentity = if ($syncConfig.preserveIdentity) { $true } else { $false }
            }
        }
    }
    
} catch {
    Write-Host "`n[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Check if we have any changes
$hasChanges = $totalChanges.inserts -gt 0 -or $totalChanges.updates -gt 0 -or $totalChanges.deletes -gt 0

if (-not $hasChanges) {
    # No changes needed
    Write-Host "`n✓ All tables are in sync - no changes needed" -ForegroundColor Green
    Write-Host ""
    exit 0
}

# Show what was found in table format
Write-Host "`n=== CHANGES DETECTED ===" -ForegroundColor Yellow
Write-Host ""

# Calculate column widths
$maxTableWidth = ($tableResults | ForEach-Object { $_.table.Length } | Measure-Object -Maximum).Maximum
$maxTableWidth = [Math]::Max($maxTableWidth, 15)

# Print header
$header = "Table".PadRight($maxTableWidth) + " | " + "Insert".PadLeft(7) + " | " + "Update".PadLeft(7) + " | " + "Delete".PadLeft(7)
Write-Host $header -ForegroundColor Cyan
Write-Host ("-" * $header.Length) -ForegroundColor DarkGray

# Print table data
foreach ($result in $tableResults) {
    $row = $result.table.PadRight($maxTableWidth) + " | "
    
    # Check if table was skipped
    if ($result.ContainsKey('skipped') -and $result.skipped) {
        $row += "SKIPPED: $($result.skipReason)".PadLeft($header.Length - $maxTableWidth - 3)
        Write-Host $row -ForegroundColor DarkGray
        continue
    }
    
    # Inserts column
    if ($result.insertsDisabled) {
        $row += "OFF".PadLeft(7)
    } else {
        $row += $result.inserts.ToString().PadLeft(7)
    }
    $row += " | "
    
    # Updates column
    if ($result.updatesDisabled) {
        $row += "OFF".PadLeft(7)
    } else {
        $row += $result.updates.ToString().PadLeft(7)
    }
    $row += " | "
    
    # Deletes column
    if ($result.deletesDisabled -gt 0) {
        $row += "($($result.deletesDisabled))".PadLeft(7)
    } else {
        $row += $result.deletes.ToString().PadLeft(7)
    }
    
    Write-Host $row
}

# Print totals
Write-Host ("-" * $header.Length) -ForegroundColor DarkGray
$totalRow = "TOTAL".PadRight($maxTableWidth) + " | "
$totalRow += $totalChanges.inserts.ToString().PadLeft(7) + " | "
$totalRow += $totalChanges.updates.ToString().PadLeft(7) + " | "
$totalRow += $totalChanges.deletes.ToString().PadLeft(7)
Write-Host $totalRow -ForegroundColor White
Write-Host ""

# Show summary line
if ($totalChanges.inserts -gt 0) { 
    Write-Host "  → $($totalChanges.inserts) new rows to insert" -ForegroundColor Green 
}
if ($totalChanges.updates -gt 0) { 
    Write-Host "  → $($totalChanges.updates) rows to update" -ForegroundColor Yellow 
}
if ($totalChanges.deletes -gt 0) { 
    Write-Host "  → $($totalChanges.deletes) rows to delete" -ForegroundColor Red 
}

# Safety confirmation for execute mode
if ($Execute) {
    Write-Host "`n⚠️  WARNING: You are about to modify the database!" -ForegroundColor Yellow
    Write-Host ""    
    $confirmation = Read-Host "Do you want to execute these changes? (yes/no)"
    
    if ($confirmation -ne "yes") {
        Write-Host "`n✗ Aborted - no changes were made" -ForegroundColor Red
        Write-Host ""
        exit 0
    }
    
    # Execute all stored changes
    Write-Host "`n=== EXECUTING CHANGES ===" -ForegroundColor Cyan
    
    $executionSuccess = $true
    $executionStats = @{ inserts = 0; updates = 0; deletes = 0 }
    
    # Re-open connection for execution phase
    if ($connection.State -ne 'Open') {
        $connection.Open()
    }
    
    foreach ($changeSet in $allChanges) {
        $syncConfig = $changeSet.syncConfig
        $targetTable = $changeSet.targetTable
        $changes = $changeSet.changes
        $preserveIdentity = $changeSet.preserveIdentity
        $sourceTable = $syncConfig.sourceTable
        $displayName = if ($sourceTable -eq $targetTable) { $targetTable } else { "$sourceTable -> $targetTable" }
        
        Write-Host "`n→ $displayName" -ForegroundColor White
        
        # Start transaction for this table
        $transaction = $connection.BeginTransaction()
        $successCount = @{ inserts = 0; updates = 0; deletes = 0 }
        $hasError = $false
        
        try {
            # Check if we need IDENTITY_INSERT
            if ($preserveIdentity) {
                $identityCmd = $connection.CreateCommand()
                $identityCmd.Transaction = $transaction
                $identityCmd.CommandText = "SET IDENTITY_INSERT [$targetTable] ON"
                $identityCmd.ExecuteNonQuery() | Out-Null
            }
            
            # Execute INSERTs
            if ($changes.inserts.Count -gt 0) {
                Write-Host "  Inserting $($changes.inserts.Count) rows..." -ForegroundColor Green -NoNewline
                
                foreach ($insert in $changes.inserts) {
                    # Build column and value lists
                    $columns = @()
                    $values = @()
                    $parameters = @()
                    
                    foreach ($key in $insert.data.PSObject.Properties.Name) {
                        # Skip ignored columns (like identity columns)
                        if ($key -in $syncConfig.ignoreColumns) {
                            continue
                        }
                        
                        $value = $insert.data.$key
                        $columns += "[$key]"
                        $paramName = "@p$($parameters.Count)"
                        $values += $paramName
                        $parameters += @{ name = $paramName; value = $value }
                    }
                    
                    $insertSql = "INSERT INTO [$targetTable] ($($columns -join ', ')) VALUES ($($values -join ', '))"
                    
                    if ($ShowSQL) {
                        Write-Host "[DEBUG] INSERT SQL:" -ForegroundColor DarkCyan
                        Write-Host $insertSql -ForegroundColor DarkGray
                    }
                    
                    $insertCmd = $connection.CreateCommand()
                    $insertCmd.Transaction = $transaction
                    $insertCmd.CommandText = $insertSql
                    
                    # Add parameters
                    foreach ($param in $parameters) {
                        if ($null -eq $param.value) {
                            $insertCmd.Parameters.AddWithValue($param.name, [DBNull]::Value) | Out-Null
                            if ($ShowSQL) {
                                Write-Host "[DEBUG] Parameter $($param.name) = NULL" -ForegroundColor DarkCyan
                            }
                        } else {
                            # Handle different data types
                            if ($param.value -is [string]) {
                                # Handle DateTime strings
                                if ($param.value -match '^\d{4}-\d{2}-\d{2}') {
                                    $dateValue = [DateTime]::Parse($param.value)
                                    $insertCmd.Parameters.AddWithValue($param.name, $dateValue) | Out-Null
                                    if ($ShowSQL) {
                                        Write-Host "[DEBUG] Parameter $($param.name) = '$dateValue' (DateTime)" -ForegroundColor DarkCyan
                                    }
                                }
                                # Handle Boolean strings from JSON
                                elseif ($param.value -eq "True" -or $param.value -eq "true") {
                                    $insertCmd.Parameters.AddWithValue($param.name, $true) | Out-Null
                                    if ($ShowSQL) {
                                        Write-Host "[DEBUG] Parameter $($param.name) = True (Boolean)" -ForegroundColor DarkCyan
                                    }
                                }
                                elseif ($param.value -eq "False" -or $param.value -eq "false") {
                                    $insertCmd.Parameters.AddWithValue($param.name, $false) | Out-Null
                                    if ($ShowSQL) {
                                        Write-Host "[DEBUG] Parameter $($param.name) = False (Boolean)" -ForegroundColor DarkCyan
                                    }
                                }
                                else {
                                    $insertCmd.Parameters.AddWithValue($param.name, $param.value) | Out-Null
                                    if ($ShowSQL) {
                                        Write-Host "[DEBUG] Parameter $($param.name) = '$($param.value)' (String)" -ForegroundColor DarkCyan
                                    }
                                }
                            }
                            elseif ($param.value -is [bool]) {
                                # Direct boolean value
                                $insertCmd.Parameters.AddWithValue($param.name, $param.value) | Out-Null
                                if ($ShowSQL) {
                                    Write-Host "[DEBUG] Parameter $($param.name) = $($param.value) (Boolean)" -ForegroundColor DarkCyan
                                }
                            }
                            else {
                                $insertCmd.Parameters.AddWithValue($param.name, $param.value) | Out-Null
                                if ($ShowSQL) {
                                    Write-Host "[DEBUG] Parameter $($param.name) = '$($param.value)' ($($param.value.GetType().Name))" -ForegroundColor DarkCyan
                                }
                            }
                        }
                    }
                    
                    $insertCmd.ExecuteNonQuery() | Out-Null
                    $successCount.inserts++
                    $executionStats.inserts++
                }
                
                Write-Host " [OK]" -ForegroundColor Green
            }
            
            # Execute UPDATEs
            if ($changes.updates.Count -gt 0) {
                Write-Host "  Updating $($changes.updates.Count) rows..." -ForegroundColor Yellow -NoNewline
                
                foreach ($update in $changes.updates) {
                    # Build SET clause
                    $setClauses = @()
                    $parameters = @()
                    $whereParameters = @()
                    
                    # Add changed fields to SET clause
                    foreach ($change in $update.changes) {
                        $paramName = "@p$($parameters.Count)"
                        $setClauses += "[$($change.field)] = $paramName"
                        $parameters += @{ name = $paramName; value = $change.newValue }
                    }
                    
                    # Build WHERE clause from match fields
                    $whereClauses = @()
                    for ($i = 0; $i -lt $update.matchFields.Count; $i++) {
                        $paramName = "@w$i"
                        $whereClauses += "[$($update.matchFields[$i])] = $paramName"
                        $whereParameters += @{ name = $paramName; value = $update.matchValues[$i] }
                    }
                    
                    $updateSql = "UPDATE [$targetTable] SET $($setClauses -join ', ') WHERE $($whereClauses -join ' AND ')"
                    
                    if ($ShowSQL) {
                        Write-Host "[DEBUG] UPDATE SQL:" -ForegroundColor DarkCyan
                        Write-Host $updateSql -ForegroundColor DarkGray
                    }
                    
                    $updateCmd = $connection.CreateCommand()
                    $updateCmd.Transaction = $transaction
                    $updateCmd.CommandText = $updateSql
                    
                    # Add SET parameters
                    foreach ($param in $parameters) {
                        if ($null -eq $param.value) {
                            $updateCmd.Parameters.AddWithValue($param.name, [DBNull]::Value) | Out-Null
                            if ($ShowSQL) {
                                Write-Host "[DEBUG] SET Parameter $($param.name) = NULL" -ForegroundColor DarkCyan
                            }
                        } else {
                            # Handle different data types
                            if ($param.value -is [string]) {
                                # Handle DateTime strings
                                if ($param.value -match '^\d{4}-\d{2}-\d{2}') {
                                    $dateValue = [DateTime]::Parse($param.value)
                                    $updateCmd.Parameters.AddWithValue($param.name, $dateValue) | Out-Null
                                    if ($ShowSQL) {
                                        Write-Host "[DEBUG] SET Parameter $($param.name) = '$dateValue' (DateTime)" -ForegroundColor DarkCyan
                                    }
                                }
                                # Handle Boolean strings from JSON
                                elseif ($param.value -eq "True" -or $param.value -eq "true") {
                                    $updateCmd.Parameters.AddWithValue($param.name, $true) | Out-Null
                                    if ($ShowSQL) {
                                        Write-Host "[DEBUG] SET Parameter $($param.name) = True (Boolean)" -ForegroundColor DarkCyan
                                    }
                                }
                                elseif ($param.value -eq "False" -or $param.value -eq "false") {
                                    $updateCmd.Parameters.AddWithValue($param.name, $false) | Out-Null
                                    if ($ShowSQL) {
                                        Write-Host "[DEBUG] SET Parameter $($param.name) = False (Boolean)" -ForegroundColor DarkCyan
                                    }
                                }
                                else {
                                    $updateCmd.Parameters.AddWithValue($param.name, $param.value) | Out-Null
                                    if ($ShowSQL) {
                                        Write-Host "[DEBUG] SET Parameter $($param.name) = '$($param.value)' (String)" -ForegroundColor DarkCyan
                                    }
                                }
                            }
                            elseif ($param.value -is [bool]) {
                                # Direct boolean value
                                $updateCmd.Parameters.AddWithValue($param.name, $param.value) | Out-Null
                                if ($ShowSQL) {
                                    Write-Host "[DEBUG] SET Parameter $($param.name) = $($param.value) (Boolean)" -ForegroundColor DarkCyan
                                }
                            }
                            else {
                                $updateCmd.Parameters.AddWithValue($param.name, $param.value) | Out-Null
                                if ($ShowSQL) {
                                    Write-Host "[DEBUG] SET Parameter $($param.name) = '$($param.value)' ($($param.value.GetType().Name))" -ForegroundColor DarkCyan
                                }
                            }
                        }
                    }
                    
                    # Add WHERE parameters
                    foreach ($param in $whereParameters) {
                        if ($null -eq $param.value) {
                            $updateCmd.Parameters.AddWithValue($param.name, [DBNull]::Value) | Out-Null
                            if ($ShowSQL) {
                                Write-Host "[DEBUG] WHERE Parameter $($param.name) = NULL" -ForegroundColor DarkCyan
                            }
                        } else {
                            $updateCmd.Parameters.AddWithValue($param.name, $param.value) | Out-Null
                            if ($ShowSQL) {
                                Write-Host "[DEBUG] WHERE Parameter $($param.name) = '$($param.value)'" -ForegroundColor DarkCyan
                            }
                        }
                    }
                    
                    $updateCmd.ExecuteNonQuery() | Out-Null
                    $successCount.updates++
                    $executionStats.updates++
                }
                
                Write-Host " [OK]" -ForegroundColor Yellow
            }
            
            # Execute DELETEs
            if ($syncConfig.allowDeletes -and $changes.deletes.Count -gt 0) {
                Write-Host "  Deleting $($changes.deletes.Count) rows..." -ForegroundColor Red -NoNewline
                
                foreach ($delete in $changes.deletes) {
                    # Build WHERE clause from match fields
                    $whereClauses = @()
                    $parameters = @()
                    
                    # Get match field values from the delete data
                    foreach ($matchField in $syncConfig.matchOn) {
                        $paramName = "@p$($parameters.Count)"
                        $whereClauses += "[$matchField] = $paramName"
                        $parameters += @{ name = $paramName; value = $delete.data[$matchField] }
                    }
                    
                    $deleteSql = "DELETE FROM [$targetTable] WHERE $($whereClauses -join ' AND ')"
                    
                    if ($ShowSQL) {
                        Write-Host "[DEBUG] DELETE SQL:" -ForegroundColor DarkCyan
                        Write-Host $deleteSql -ForegroundColor DarkGray
                    }
                    
                    $deleteCmd = $connection.CreateCommand()
                    $deleteCmd.Transaction = $transaction
                    $deleteCmd.CommandText = $deleteSql
                    
                    # Add parameters
                    foreach ($param in $parameters) {
                        if ($null -eq $param.value) {
                            $deleteCmd.Parameters.AddWithValue($param.name, [DBNull]::Value) | Out-Null
                            if ($ShowSQL) {
                                Write-Host "[DEBUG] Parameter $($param.name) = NULL" -ForegroundColor DarkCyan
                            }
                        } else {
                            $deleteCmd.Parameters.AddWithValue($param.name, $param.value) | Out-Null
                            if ($ShowSQL) {
                                Write-Host "[DEBUG] Parameter $($param.name) = '$($param.value)'" -ForegroundColor DarkCyan
                            }
                        }
                    }
                    
                    $deleteCmd.ExecuteNonQuery() | Out-Null
                    $successCount.deletes++
                    $executionStats.deletes++
                }
                
                Write-Host " [OK]" -ForegroundColor Red
            }
            
            # Turn off IDENTITY_INSERT if it was on
            if ($preserveIdentity) {
                $identityCmd = $connection.CreateCommand()
                $identityCmd.Transaction = $transaction
                $identityCmd.CommandText = "SET IDENTITY_INSERT [$targetTable] OFF"
                $identityCmd.ExecuteNonQuery() | Out-Null
            }
            
            # Commit transaction
            if ($ShowSQL) {
                Write-Host "[DEBUG] Committing transaction..." -ForegroundColor DarkCyan
            }
            $transaction.Commit()
            Write-Host "  ✓ Transaction committed" -ForegroundColor Green
        }
        catch {
            # Rollback on error
            $executionSuccess = $false
            Write-Host ""
            Write-Host "  ✗ ERROR: $_" -ForegroundColor Red
            
            if ($null -ne $transaction) {
                Write-Host "  Rolling back transaction..." -ForegroundColor Yellow
                try {
                    $transaction.Rollback()
                    Write-Host "  Transaction rolled back" -ForegroundColor Yellow
                }
                catch {
                    Write-Host "  ERROR during rollback: $_" -ForegroundColor Red
                }
            }
            
            # Stop processing further tables on error
            break
        }
    }
    # Close connection after execution
    if ($connection.State -eq 'Open') {
        $connection.Close()
    }
    
    if ($executionSuccess) {
        Write-Host "`n✓ All changes executed successfully" -ForegroundColor Green
    
        # Show execution statistics in table format
        Write-Host "`n=== EXECUTION STATISTICS ===" -ForegroundColor Cyan
        Write-Host ""
        
        # Print header (same format as changes table)
        Write-Host $header -ForegroundColor Cyan
        Write-Host ("-" * $header.Length) -ForegroundColor DarkGray
        
        # Print execution results per table
        foreach ($changeSet in $allChanges) {
            $displayName = if ($changeSet.syncConfig.sourceTable -eq $changeSet.targetTable) { 
                $changeSet.targetTable 
            } else { 
                "$($changeSet.syncConfig.sourceTable) -> $($changeSet.targetTable)" 
            }
            
            $row = $displayName.PadRight($maxTableWidth) + " | "
            
            # Get actual counts from successCount (stored in changeSet during execution)
            if ($changeSet.ContainsKey('successCount')) {
                $row += $changeSet.successCount.inserts.ToString().PadLeft(7) + " | "
                $row += $changeSet.successCount.updates.ToString().PadLeft(7) + " | "
                $row += $changeSet.successCount.deletes.ToString().PadLeft(7)
            } else {
                # Fallback to original counts if execution tracking failed
                $row += $changeSet.changes.inserts.Count.ToString().PadLeft(7) + " | "
                $row += $changeSet.changes.updates.Count.ToString().PadLeft(7) + " | "
                $row += $changeSet.changes.deletes.Count.ToString().PadLeft(7)
            }
            
            Write-Host $row -ForegroundColor Green
        }
        
        # Print totals
        Write-Host ("-" * $header.Length) -ForegroundColor DarkGray
        $totalRow = "TOTAL".PadRight($maxTableWidth) + " | "
        $totalRow += $executionStats.inserts.ToString().PadLeft(7) + " | "
        $totalRow += $executionStats.updates.ToString().PadLeft(7) + " | "
        $totalRow += $executionStats.deletes.ToString().PadLeft(7)
        Write-Host $totalRow -ForegroundColor White
    } else {
        Write-Host "`n✗ Execution failed - some changes may not have been applied" -ForegroundColor Red
        exit 1
    }
} else {
    # Dry-run mode
    Write-Host "`n[DRY-RUN] No changes were made" -ForegroundColor Cyan
    Write-Host "Run with -Execute to apply these changes" -ForegroundColor Gray
}

# Always close connection
if ($connection.State -eq 'Open') {
    $connection.Close()
}

Write-Host ""