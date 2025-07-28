# sync-validation.ps1 - Common validation functions for sync tools

function Test-DatabaseConnection {
    param(
        [string]$ConnectionString,
        [string]$DatabaseName
    )
    
    try {
        $connection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
        $connection.Open()
        
        # Test basic permissions
        $cmd = $connection.CreateCommand()
        $cmd.CommandText = "SELECT DB_NAME() as CurrentDB, HAS_PERMS_BY_NAME(null, null, 'SELECT') as CanSelect, HAS_PERMS_BY_NAME(null, null, 'INSERT') as CanInsert, HAS_PERMS_BY_NAME(null, null, 'UPDATE') as CanUpdate, HAS_PERMS_BY_NAME(null, null, 'DELETE') as CanDelete"
        $reader = $cmd.ExecuteReader()
        
        $permissions = @{}
        if ($reader.Read()) {
            $permissions = @{
                Database = $reader["CurrentDB"]
                CanSelect = $reader["CanSelect"]
                CanInsert = $reader["CanInsert"]
                CanUpdate = $reader["CanUpdate"]
                CanDelete = $reader["CanDelete"]
            }
        }
        $reader.Close()
        $connection.Close()
        
        return @{
            Success = $true
            Message = "Connection successful"
            Permissions = $permissions
        }
    }
    catch {
        return @{
            Success = $false
            Message = "Connection failed: $($_.Exception.Message)"
            Permissions = @{}
        }
    }
}

function Test-TableExists {
    param(
        [System.Data.SqlClient.SqlConnection]$Connection,
        [string]$TableName,
        [switch]$ShowSQL
    )
    
    $cmd = $Connection.CreateCommand()
    $query = "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = @TableName"
    $cmd.CommandText = $query
    $cmd.Parameters.AddWithValue("@TableName", $TableName) | Out-Null
    
    if ($ShowSQL) {
        Write-Host "[DEBUG] Checking table existence:" -ForegroundColor DarkCyan
        Write-Host $query -ForegroundColor DarkGray
        Write-Host "[DEBUG] Parameters: @TableName = '$TableName'" -ForegroundColor DarkCyan
    }
    
    $exists = $cmd.ExecuteScalar() -gt 0
    return $exists
}

function Get-TableColumns {
    param(
        [System.Data.SqlClient.SqlConnection]$Connection,
        [string]$TableName,
        [switch]$ShowSQL
    )
    
    $cmd = $Connection.CreateCommand()
    $query = @"
SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE,
       COLUMNPROPERTY(OBJECT_ID(TABLE_SCHEMA + '.' + TABLE_NAME), COLUMN_NAME, 'IsIdentity') as IS_IDENTITY
FROM INFORMATION_SCHEMA.COLUMNS 
WHERE TABLE_NAME = @TableName
ORDER BY ORDINAL_POSITION
"@
    $cmd.CommandText = $query
    $cmd.Parameters.AddWithValue("@TableName", $TableName) | Out-Null
    
    if ($ShowSQL) {
        Write-Host "[DEBUG] Getting table columns:" -ForegroundColor DarkCyan
        Write-Host $query -ForegroundColor DarkGray
        Write-Host "[DEBUG] Parameters: @TableName = '$TableName'" -ForegroundColor DarkCyan
    }
    
    $columns = @{}
    $reader = $cmd.ExecuteReader()
    while ($reader.Read()) {
        $columns[$reader["COLUMN_NAME"]] = @{
            DataType = $reader["DATA_TYPE"]
            IsNullable = $reader["IS_NULLABLE"] -eq "YES"
            IsIdentity = $reader["IS_IDENTITY"] -eq 1
        }
    }
    $reader.Close()
    
    return $columns
}

function Get-PrimaryKeyColumns {
    param(
        [System.Data.SqlClient.SqlConnection]$Connection,
        [string]$TableName,
        [switch]$ShowSQL
    )
    
    $cmd = $Connection.CreateCommand()
    $query = @"
SELECT ku.COLUMN_NAME
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE ku
    ON tc.CONSTRAINT_TYPE = 'PRIMARY KEY' 
    AND tc.CONSTRAINT_NAME = ku.CONSTRAINT_NAME
WHERE ku.TABLE_NAME = @TableName
ORDER BY ku.ORDINAL_POSITION
"@
    $cmd.CommandText = $query
    $cmd.Parameters.AddWithValue("@TableName", $TableName) | Out-Null
    
    if ($ShowSQL) {
        Write-Host "[DEBUG] Getting primary key columns:" -ForegroundColor DarkCyan
        Write-Host $query -ForegroundColor DarkGray
        Write-Host "[DEBUG] Parameters: @TableName = '$TableName'" -ForegroundColor DarkCyan
    }
    
    $primaryKeys = @()
    $reader = $cmd.ExecuteReader()
    while ($reader.Read()) {
        $primaryKeys += $reader["COLUMN_NAME"]
    }
    $reader.Close()
    
    return $primaryKeys
}

function Test-WhereClause {
    param(
        [System.Data.SqlClient.SqlConnection]$Connection,
        [string]$TableName,
        [string]$WhereClause,
        [switch]$ShowSQL
    )
    
    try {
        $cmd = $Connection.CreateCommand()
        # Use TOP 0 to test syntax without returning data
        $sqlStatement = "SELECT TOP 0 * FROM [$TableName] WHERE $WhereClause"
        $cmd.CommandText = $sqlStatement
        
        if ($ShowSQL) {
            Write-Host "[DEBUG] Testing WHERE clause:" -ForegroundColor DarkCyan
            Write-Host $sqlStatement -ForegroundColor DarkGray
        }
        
        $cmd.ExecuteReader().Close()
        
        return @{
            Success = $true
            Message = "WHERE clause syntax is valid"
        }
    }
    catch {
        $sqlStatement = "SELECT TOP 0 * FROM [$TableName] WHERE $WhereClause"
        $message = "Invalid WHERE clause: $($_.Exception.Message)"
        if ($ShowSQL) {
            $message += "`nSQL: $sqlStatement"
        }
        return @{
            Success = $false
            Message = $message
        }
    }
}

function Test-SyncConfiguration {
    param(
        [PSCustomObject]$Config,
        [string]$DatabaseKey,
        [string]$Mode,  # "export" or "import"
        [string[]]$TablesToValidate = @(),  # Optional: specific tables to validate
        [switch]$ShowSQL  # Show SQL statements for debugging
    )
    
    Write-Host "`n=== CONFIGURATION VALIDATION ===" -ForegroundColor Cyan
    
    $errors = @()
    $warnings = @()
    
    # Get database config
    $dbConfig = $Config.databases.$DatabaseKey
    if (-not $dbConfig) {
        Write-Host "[X] Database '$DatabaseKey' not found in configuration" -ForegroundColor Red
        return @{ Success = $false; Errors = @("Database '$DatabaseKey' not found"); Warnings = @() }
    }
    
    # Build connection string
    if ($dbConfig.auth -eq "sql") {
        $connectionString = "Server=$($dbConfig.server);Database=$($dbConfig.database);User ID=$($dbConfig.user);Password=$($dbConfig.password);"
    } else {
        $connectionString = "Server=$($dbConfig.server);Database=$($dbConfig.database);Integrated Security=True;"
    }
    
    # Test database connection
    Write-Host "Checking database connection..." -ForegroundColor Gray -NoNewline
    $connTest = Test-DatabaseConnection -ConnectionString $connectionString -DatabaseName $dbConfig.database
    if ($connTest.Success) {
        Write-Host " [OK]" -ForegroundColor Green
        
        # Check permissions
        $perms = $connTest.Permissions
        if ($Mode -eq "export" -and -not $perms.CanSelect) {
            $errors += "Missing SELECT permission on database"
        }
        if ($Mode -eq "import") {
            if (-not $perms.CanSelect) { $errors += "Missing SELECT permission on database" }
            if (-not $perms.CanInsert) { $warnings += "Missing INSERT permission - inserts will fail" }
            if (-not $perms.CanUpdate) { $warnings += "Missing UPDATE permission - updates will fail" }
            if (-not $perms.CanDelete) { $warnings += "Missing DELETE permission - deletes will fail" }
        }
    } else {
        Write-Host " [X]" -ForegroundColor Red
        $errors += $connTest.Message
        Write-Host "[X] $($connTest.Message)" -ForegroundColor Red
        return @{ Success = $false; Errors = $errors; Warnings = $warnings }
    }
    
    # Open connection for table validation
    $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
    try {
        $connection.Open()
        
        # Validate each sync table configuration
        foreach ($syncTable in $Config.syncTables) {
            $tableName = if ($Mode -eq "export") { $syncTable.sourceTable } else { 
                if ([string]::IsNullOrWhiteSpace($syncTable.targetTable)) { $syncTable.sourceTable } else { $syncTable.targetTable }
            }
            
            # Skip validation if specific tables requested and this isn't one of them
            if ($TablesToValidate.Count -gt 0 -and $tableName -notin $TablesToValidate) {
                continue
            }
            
            Write-Host "`nValidating table: $tableName" -ForegroundColor Yellow
            
            # Check if table exists
            Write-Host "  Checking table existence..." -ForegroundColor Gray -NoNewline
            if (Test-TableExists -Connection $connection -TableName $tableName -ShowSQL:$ShowSQL) {
                Write-Host " [OK]" -ForegroundColor Green
                
                # Get table columns
                $columns = Get-TableColumns -Connection $connection -TableName $tableName -ShowSQL:$ShowSQL
                
                # Get primary keys first (needed for detailed duplicate output)
                $primaryKeys = Get-PrimaryKeyColumns -Connection $connection -TableName $tableName -ShowSQL:$ShowSQL
                
                # Skip matchOn validation for replaceMode
                if ($syncTable.replaceMode -eq $true) {
                    Write-Host "  Skipping match field validation (replace mode)..." -ForegroundColor Gray
                    Write-Host " [OK]" -ForegroundColor Green
                } else {
                    # Handle empty matchOn - try to use primary key
                    if (-not $syncTable.matchOn -or $syncTable.matchOn.Count -eq 0) {
                        Write-Host "  No matchOn specified, checking primary key..." -ForegroundColor Gray -NoNewline
                        
                        # Filter out ignored columns
                        $usableKeys = @()
                        if ($syncTable.ignoreColumns) {
                            $usableKeys = $primaryKeys | Where-Object { $_ -notin $syncTable.ignoreColumns }
                        } else {
                            $usableKeys = $primaryKeys
                        }
                        
                        if ($usableKeys.Count -gt 0) {
                            Write-Host " [OK] Using: $($usableKeys -join ', ')" -ForegroundColor Green
                            $syncTable | Add-Member -NotePropertyName "matchOn" -NotePropertyValue $usableKeys -Force
                        } else {
                            Write-Host " [X]" -ForegroundColor Red
                            $pkInfo = if ($primaryKeys.Count -gt 0) { " (Primary key: $($primaryKeys -join ', '))" } else { "" }
                            $errors += "Table '$tableName': No matchOn fields specified and primary key columns are ignored$pkInfo"
                            continue
                        }
                    }
                    
                    # Validate matchOn fields exist
                    Write-Host "  Checking match fields..." -ForegroundColor Gray -NoNewline
                    $missingMatchFields = @()
                    foreach ($field in $syncTable.matchOn) {
                        if (-not $columns.ContainsKey($field)) {
                            $missingMatchFields += $field
                        }
                    }
                    
                    if ($missingMatchFields.Count -eq 0) {
                        Write-Host " [OK]" -ForegroundColor Green
                        
                        # Check uniqueness of matchOn fields
                        Write-Host "  Checking matchOn uniqueness..." -ForegroundColor Gray -NoNewline
                        $whereClause = if ($Mode -eq "export" -and $syncTable.exportWhere) { $syncTable.exportWhere } else { "" }
                        $uniquenessTest = Test-MatchFieldsUniqueness -Connection $connection -TableName $tableName -MatchFields $syncTable.matchOn -WhereClause $whereClause -ShowSQL:$ShowSQL -PrimaryKeys $primaryKeys
                        
                        if ($uniquenessTest.HasDuplicates) {
                            # During export, duplicates are warnings not errors (will be handled table-by-table)
                        if ($Mode -eq "export") {
                            Write-Host " [!]" -ForegroundColor Yellow
                            $pkInfo = if ($primaryKeys.Count -gt 0) { " (Primary key: $($primaryKeys -join ', '))" } else { "" }
                            $warnings += "Table '$tableName': matchOn fields [$($syncTable.matchOn -join ', ')] produce $($uniquenessTest.TotalDuplicates) duplicate(s)$pkInfo - will prompt during export"
                        } else {
                            Write-Host " [X]" -ForegroundColor Red
                            $primaryKeys = Get-PrimaryKeyColumns -Connection $connection -TableName $tableName -ShowSQL:$ShowSQL
                            $pkInfo = if ($primaryKeys.Count -gt 0) { " (Primary key: $($primaryKeys -join ', '))" } else { "" }
                            $sqlInfo = if ($ShowSQL -and $uniquenessTest.SqlStatement) { "`nSQL: $($uniquenessTest.SqlStatement)" } else { "" }
                            $errors += "Table '$tableName': matchOn fields [$($syncTable.matchOn -join ', ')] produce $($uniquenessTest.TotalDuplicates) duplicate(s)$pkInfo$sqlInfo"
                        }
                        
                        # Show examples
                        if ($uniquenessTest.Examples) {
                            $exampleColor = if ($Mode -eq "export") { "Yellow" } else { "Red" }
                            $duplicateLabel = if ($uniquenessTest.Examples.Count -le 3) {
                                "Duplicate groups found:"
                            } else {
                                "Example duplicates (showing first 3):"
                            }
                            Write-Host "    $duplicateLabel" -ForegroundColor $exampleColor
                            foreach ($example in $uniquenessTest.Examples | Select-Object -First 3) {
                                $valueDisplay = ($example.Values.GetEnumerator() | ForEach-Object { "$($_.Key)='$($_.Value)'" }) -join ", "
                                Write-Host "    - $valueDisplay ($($example.Count) occurrences)" -ForegroundColor $exampleColor
                            }
                        }
                        
                        # Show detailed duplicate table if available
                        if ($uniquenessTest.DetailedDuplicates) {
                            Write-Host "`n    Detailed duplicate records (max 200 rows):" -ForegroundColor Yellow
                            Write-Host $uniquenessTest.DetailedDuplicates -ForegroundColor Gray
                        }
                        
                        # Offer cleanup option for import mode
                        if ($Mode -eq "import" -and $uniquenessTest.HasDuplicates) {
                            Write-Host "`n    [!] Found $($uniquenessTest.TotalDuplicates) duplicate record(s) in $($uniquenessTest.DuplicateGroups) group(s)" -ForegroundColor Yellow
                            Write-Host "    Would you like to automatically remove duplicates, keeping only one record per group?" -ForegroundColor Yellow
                            Write-Host "    (The record with the lowest $($primaryKeys[0]) will be kept)" -ForegroundColor Gray
                            $cleanup = Read-Host "    Clean up duplicates? (yes/no)"
                            
                            if ($cleanup -eq "yes") {
                                Write-Host "`n    Cleaning duplicates..." -ForegroundColor Yellow -NoNewline
                                
                                # First show preview
                                $previewResult = Remove-DuplicateRecords -Connection $connection -TableName $tableName -MatchFields $syncTable.matchOn -PrimaryKeys $primaryKeys -WhereClause $whereClause -ShowSQL:$ShowSQL -Preview
                                
                                if ($previewResult.Success -and $previewResult.PreviewCount -gt 0) {
                                    Write-Host "`n    Confirm deletion of $($previewResult.PreviewCount) duplicate record(s)?" -ForegroundColor Yellow
                                    $confirm = Read-Host "    Proceed with deletion? (yes/no)"
                                    
                                    if ($confirm -eq "yes") {
                                        $deleteResult = Remove-DuplicateRecords -Connection $connection -TableName $tableName -MatchFields $syncTable.matchOn -PrimaryKeys $primaryKeys -WhereClause $whereClause -ShowSQL:$ShowSQL
                                        
                                        if ($deleteResult.Success) {
                                            Write-Host " [OK]" -ForegroundColor Green
                                            Write-Host "    $($deleteResult.Message)" -ForegroundColor Green
                                            
                                            # Re-run uniqueness test to verify
                                            Write-Host "    Re-checking uniqueness..." -ForegroundColor Gray -NoNewline
                                            $uniquenessTest = Test-MatchFieldsUniqueness -Connection $connection -TableName $tableName -MatchFields $syncTable.matchOn -WhereClause $whereClause -ShowSQL:$ShowSQL -PrimaryKeys $primaryKeys
                                            
                                            if (-not $uniquenessTest.HasDuplicates) {
                                                Write-Host " [OK]" -ForegroundColor Green
                                                # Remove error since duplicates are now cleaned
                                                $errors = $errors | Where-Object { $_ -notlike "*Table '$tableName': matchOn fields*" }
                                            } else {
                                                Write-Host " [X]" -ForegroundColor Red
                                                Write-Host "    Warning: Some duplicates remain" -ForegroundColor Yellow
                                            }
                                        } else {
                                            Write-Host " [X]" -ForegroundColor Red
                                            Write-Host "    $($deleteResult.Message)" -ForegroundColor Red
                                        }
                                    } else {
                                        Write-Host "    Skipped duplicate cleanup" -ForegroundColor Gray
                                    }
                                } else {
                                    Write-Host " [OK]" -ForegroundColor Green
                                    Write-Host "    $($previewResult.Message)" -ForegroundColor Gray
                                }
                            } else {
                                Write-Host "    Skipped duplicate cleanup" -ForegroundColor Gray
                            }
                        }
                    } elseif ($uniquenessTest.Error) {
                        Write-Host " [!]" -ForegroundColor Yellow
                        $warnings += "Table '$tableName': Could not check uniqueness - $($uniquenessTest.Error)"
                        } else {
                            Write-Host " [OK]" -ForegroundColor Green
                        }
                    } else {
                        Write-Host " [X]" -ForegroundColor Red
                        $primaryKeys = Get-PrimaryKeyColumns -Connection $connection -TableName $tableName -ShowSQL:$ShowSQL
                        $pkInfo = if ($primaryKeys.Count -gt 0) { " (Primary key: $($primaryKeys -join ', '))" } else { "" }
                        $errors += "Table '$tableName': Match fields not found: $($missingMatchFields -join ', ')$pkInfo"
                    }
                } # End of else block for replaceMode check
                
                # Validate ignoreColumns if specified
                if ($syncTable.ignoreColumns -and $syncTable.ignoreColumns.Count -gt 0) {
                    Write-Host "  Checking ignore columns..." -ForegroundColor Gray -NoNewline
                    $missingIgnoreFields = @()
                    foreach ($field in $syncTable.ignoreColumns) {
                        if (-not $columns.ContainsKey($field)) {
                            $missingIgnoreFields += $field
                        }
                    }
                    
                    if ($missingIgnoreFields.Count -eq 0) {
                        Write-Host " [OK]" -ForegroundColor Green
                    } else {
                        Write-Host " [X]" -ForegroundColor Red
                        $warnings += "Table '$tableName': Ignore columns not found: $($missingIgnoreFields -join ', ')"
                    }
                }
                
                # Validate exportWhere clause if in export mode
                if ($Mode -eq "export" -and $syncTable.exportWhere) {
                    Write-Host "  Checking WHERE clause..." -ForegroundColor Gray -NoNewline
                    $whereTest = Test-WhereClause -Connection $connection -TableName $tableName -WhereClause $syncTable.exportWhere -ShowSQL:$ShowSQL
                    if ($whereTest.Success) {
                        Write-Host " [OK]" -ForegroundColor Green
                    } else {
                        Write-Host " [X]" -ForegroundColor Red
                        $errors += "Table '$tableName': $($whereTest.Message)"
                    }
                }
                
                # Check for identity columns if preserveIdentity is true
                if ($syncTable.preserveIdentity) {
                    $identityColumns = $columns.GetEnumerator() | Where-Object { $_.Value.IsIdentity } | ForEach-Object { $_.Key }
                    if ($identityColumns.Count -gt 0) {
                        Write-Host "  Identity columns found: $($identityColumns -join ', ')" -ForegroundColor Gray
                    }
                }
                
            } else {
                Write-Host " [X]" -ForegroundColor Red
                $sqlStatement = "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = '$tableName'"
                $errorMsg = "Table '$tableName' not found in database"
                if ($ShowSQL) {
                    $errorMsg += "`nSQL: $sqlStatement"
                }
                $errors += $errorMsg
            }
        }
        
    } catch {
        $errors += "Validation error: $($_.Exception.Message)"
    } finally {
        if ($connection.State -eq 'Open') {
            $connection.Close()
        }
    }
    
    # Summary
    Write-Host "`n=== VALIDATION SUMMARY ===" -ForegroundColor Cyan
    if ($errors.Count -eq 0) {
        Write-Host "[OK] All validations passed" -ForegroundColor Green
    } else {
        Write-Host "[X] Found $($errors.Count) error(s):" -ForegroundColor Red
        foreach ($error in $errors) {
            Write-Host "  - $error" -ForegroundColor Red
        }
    }
    
    if ($warnings.Count -gt 0) {
        Write-Host "[!] Found $($warnings.Count) warning(s):" -ForegroundColor Yellow
        foreach ($warning in $warnings) {
            Write-Host "  - $warning" -ForegroundColor Yellow
        }
    }
    
    return @{
        Success = $errors.Count -eq 0
        Errors = $errors
        Warnings = $warnings
    }
}

function Test-MatchFieldsUniqueness {
    param(
        [System.Data.SqlClient.SqlConnection]$Connection,
        [string]$TableName,
        [string[]]$MatchFields,
        [string]$WhereClause = "",
        [switch]$ShowSQL,
        [string[]]$PrimaryKeys = @()  # Primary key columns for detailed output
    )
    
    try {
        # Build concatenation of match fields for uniqueness check
        $concatFields = @()
        foreach ($field in $MatchFields) {
            $concatFields += "ISNULL(CAST([$field] AS NVARCHAR(MAX)), 'NULL')"
        }
        $concatExpression = $concatFields -join " + '|' + "
        
        # Build query to check uniqueness
        $whereFilter = if ($WhereClause) { "WHERE $WhereClause" } else { "" }
        
        $cmd = $Connection.CreateCommand()
        $sqlStatement = @"
WITH DuplicateCheck AS (
    SELECT $concatExpression as MatchKey,
           COUNT(*) as OccurrenceCount
    FROM [$TableName]
    $whereFilter
    GROUP BY $concatExpression
    HAVING COUNT(*) > 1
)
SELECT COUNT(*) as DuplicateGroups,
       SUM(OccurrenceCount - 1) as TotalDuplicates
FROM DuplicateCheck
"@
        $cmd.CommandText = $sqlStatement
        
        if ($ShowSQL) {
            Write-Host "[DEBUG] Checking uniqueness:" -ForegroundColor DarkCyan
            Write-Host $sqlStatement -ForegroundColor DarkGray
        }
        
        $reader = $cmd.ExecuteReader()
        $hasDuplicates = $false
        $duplicateInfo = @{
            HasDuplicates = $false
            DuplicateGroups = 0
            TotalDuplicates = 0
        }
        
        if ($reader.Read()) {
            $duplicateInfo.DuplicateGroups = $reader["DuplicateGroups"]
            $duplicateInfo.TotalDuplicates = $reader["TotalDuplicates"]
            $duplicateInfo.HasDuplicates = $duplicateInfo.DuplicateGroups -gt 0
        }
        $reader.Close()
        
        # If duplicates found, get examples
        if ($duplicateInfo.HasDuplicates) {
            $cmd = $Connection.CreateCommand()
            $selectFields = ($MatchFields | ForEach-Object { "[$_]" }) -join ", "
            $exampleQuery = @"
WITH DuplicateExamples AS (
    SELECT TOP 5 $selectFields, 
           COUNT(*) as OccurrenceCount
    FROM [$TableName]
    $whereFilter
    GROUP BY $selectFields
    HAVING COUNT(*) > 1
    ORDER BY COUNT(*) DESC
)
SELECT * FROM DuplicateExamples
"@
            $cmd.CommandText = $exampleQuery
            
            if ($ShowSQL) {
                Write-Host "[DEBUG] Getting duplicate examples:" -ForegroundColor DarkCyan
                Write-Host $exampleQuery -ForegroundColor DarkGray
            }
            
            $examples = @()
            $reader = $cmd.ExecuteReader()
            while ($reader.Read()) {
                $example = @{
                    Values = @{}
                    Count = $reader["OccurrenceCount"]
                }
                foreach ($field in $MatchFields) {
                    $example.Values[$field] = $reader[$field]
                }
                $examples += $example
            }
            $reader.Close()
            
            $duplicateInfo.Examples = $examples
            
            # Get detailed duplicate records with primary keys
            if ($PrimaryKeys.Count -gt 0) {
                $detailedDuplicates = Get-DetailedDuplicateRecords -Connection $Connection -TableName $TableName -MatchFields $MatchFields -PrimaryKeys $PrimaryKeys -WhereClause $WhereClause -ShowSQL:$ShowSQL
                if ($detailedDuplicates) {
                    $duplicateInfo.DetailedDuplicates = $detailedDuplicates.FormattedOutput
                    # Also store structured data for CSV export
                    $duplicateInfo.DuplicateDetails = $detailedDuplicates.Details
                }
            }
        }
        
        if ($ShowSQL) {
            $duplicateInfo.SqlStatement = $sqlStatement
        }
        return $duplicateInfo
    }
    catch {
        $result = @{
            HasDuplicates = $false
            Error = $_.Exception.Message
        }
        if ($ShowSQL) {
            $result.SqlStatement = $sqlStatement
        }
        return $result
    }
}

function Get-DetailedDuplicateRecords {
    param(
        [System.Data.SqlClient.SqlConnection]$Connection,
        [string]$TableName,
        [string[]]$MatchFields,
        [string[]]$PrimaryKeys,
        [string]$WhereClause = "",
        [switch]$ShowSQL
    )
    
    try {
        # Build column lists
        $matchColumns = $MatchFields | ForEach-Object { "[$_]" }
        $primaryColumns = $PrimaryKeys | ForEach-Object { "[$_]" }
        $allColumns = @()
        foreach ($col in $primaryColumns) {
            $allColumns += $col
        }
        foreach ($col in $matchColumns) {
            if ($col -notin $primaryColumns) {
                $allColumns += $col
            }
        }
        
        # Build NULL-safe join conditions
        $joinConditions = @()
        foreach ($field in $MatchFields) {
            $joinConditions += "(st.[$field] = dg.[$field] OR (st.[$field] IS NULL AND dg.[$field] IS NULL))"
        }
        $joinClause = $joinConditions -join "`n                        AND "
        
        # Build the query
        $whereFilter = if ($WhereClause) { "WHERE $WhereClause" } else { "" }
        $detailQuery = @"
WITH DuplicateGroups AS (
    SELECT 
        $($matchColumns -join ",`n        "),
        ROW_NUMBER() OVER (ORDER BY $($matchColumns -join ", ")) as GroupNumber
    FROM [$TableName]
    $whereFilter
    GROUP BY
        $($matchColumns -join ",`n        ")
    HAVING COUNT(*) > 1
)
SELECT TOP 200
    st.$($allColumns -join ",`n    st."),
    dg.GroupNumber as DuplicateGroup
FROM [$TableName] st
    INNER JOIN DuplicateGroups dg
        ON $joinClause
ORDER BY
    dg.GroupNumber,
    $($primaryColumns -join ", ")
"@
        
        if ($ShowSQL) {
            Write-Host "[DEBUG] Getting detailed duplicate records:" -ForegroundColor DarkCyan
            Write-Host $detailQuery -ForegroundColor DarkGray
        }
        
        $cmd = $Connection.CreateCommand()
        $cmd.CommandText = $detailQuery
        $cmd.CommandTimeout = 60
        
        $reader = $cmd.ExecuteReader()
        $results = @()
        
        # Get column names in desired order
        $columnNames = @()
        # Add primary key columns first
        foreach ($pk in $PrimaryKeys) {
            $columnNames += $pk
        }
        # Add match fields that aren't already in primary keys
        foreach ($mf in $MatchFields) {
            if ($mf -notin $PrimaryKeys) {
                $columnNames += $mf
            }
        }
        # Add DuplicateGroup column
        $columnNames += "DuplicateGroup"
        
        # Read data
        while ($reader.Read()) {
            $row = New-Object PSObject
            foreach ($colName in $columnNames) {
                $value = if ($reader[$colName] -eq [DBNull]::Value) { "NULL" } else { $reader[$colName] }
                $row | Add-Member -NotePropertyName $colName -NotePropertyValue $value
            }
            $results += $row
        }
        $reader.Close()
        
        if ($results.Count -eq 0) {
            return $null
        }
        
        # Format as table with proper column layout
        $tableOutput = $results | Format-Table -Property * -AutoSize -Wrap | Out-String -Width 300
        
        # Return both the formatted output and structured data
        return @{
            FormattedOutput = $tableOutput
            Details = $results
        }
        
    }
    catch {
        if ($ShowSQL) {
            Write-Host "[DEBUG] Error getting detailed duplicates: $_" -ForegroundColor Red
        }
        return $null
    }
}

function Export-DuplicatesToCSV {
    param(
        [array]$DuplicateProblems,
        [string]$OutputPath,
        [string]$Delimiter = $null
    )
    
    try {
        # Ensure directory exists
        $outputDir = Split-Path -Parent $OutputPath
        if (-not (Test-Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }
        
        # Create CSV data array
        $csvData = @()
        
        foreach ($problem in $DuplicateProblems) {
            # First, collect all unique column names from the details to ensure consistent structure
            $allColumns = @()
            $standardColumns = @('TableName', 'DuplicateGroup', 'MatchOnFields')
            
            # Get all unique column names from details (these are the actual data columns)
            if ($problem.Details -and $problem.Details.Count -gt 0) {
                $firstDetail = $problem.Details[0]
                foreach ($prop in $firstDetail.PSObject.Properties) {
                    if ($prop.Name -ne 'DuplicateGroup') {
                        $allColumns += $prop.Name
                    }
                }
            }
            
            # Get primary key columns from the problem metadata
            $primaryKeyColumns = @()
            if ($problem.PrimaryKeys -and $problem.PrimaryKeys.Count -gt 0) {
                $primaryKeyColumns = $problem.PrimaryKeys
            } else {
                # Fallback: try to detect primary key columns by name pattern
                foreach ($colName in $allColumns) {
                    if ($colName -match '_RSN$|_ID$|ID$|_Key$|Key$') {
                        $primaryKeyColumns += $colName
                    }
                }
            }
            
            # Reorder columns: primary keys first, then other columns, DuplicateGroup last
            $orderedColumns = @()
            # Add primary keys that exist in our data
            foreach ($pk in $primaryKeyColumns) {
                if ($pk -in $allColumns) {
                    $orderedColumns += $pk
                }
            }
            # Add remaining columns (excluding those already added)
            $orderedColumns += $allColumns | Where-Object { $_ -notin $orderedColumns }
            
            # Expand duplicate details into individual rows
            foreach ($detail in $problem.Details) {
                # Create ordered hashtable with data columns
                $orderedRow = [ordered]@{}
                
                # Add data columns in the reordered sequence
                foreach ($colName in $orderedColumns) {
                    $value = $null
                    if ($detail.PSObject.Properties.Name -contains $colName) {
                        $value = $detail.$colName
                    }
                    $orderedRow[$colName] = $value
                }
                
                # Add DuplicateGroup at the end
                $orderedRow['DuplicateGroup'] = $detail.DuplicateGroup
                
                # Convert to PSCustomObject to maintain order
                $csvData += [PSCustomObject]$orderedRow
            }
        }
        
        # Export to CSV
        if ($Delimiter) {
            $csvData | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8 -Delimiter $Delimiter
        } else {
            $csvData | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8 -UseCulture
        }
        
        return @{
            Success = $true
            RowCount = $csvData.Count
            Path = $OutputPath
        }
    }
    catch {
        Write-Host "[ERROR] Failed to export duplicates to CSV: $($_.Exception.Message)" -ForegroundColor Red
        return @{
            Success = $false
            Message = $_.Exception.Message
        }
    }
}

function Export-SkippedTablesToCSV {
    param(
        [array]$SkippedTables,
        [string]$OutputPath,
        [string]$Delimiter = $null
    )
    
    try {
        # Ensure directory exists
        $outputDir = Split-Path -Parent $OutputPath
        if (-not (Test-Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }
        
        # Convert to CSV-friendly format with ordered columns
        $csvData = $SkippedTables | ForEach-Object {
            [PSCustomObject][ordered]@{
                Timestamp = $_.Timestamp
                TableName = $_.TableName
                Reason = $_.Reason
                DuplicateGroups = if ($null -ne $_.DuplicateGroups) { $_.DuplicateGroups } else { 0 }
                TotalDuplicates = if ($null -ne $_.TotalDuplicates) { $_.TotalDuplicates } else { 0 }
            }
        }
        
        # Export to CSV
        if ($Delimiter) {
            $csvData | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8 -Delimiter $Delimiter
        } else {
            $csvData | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8 -UseCulture
        }
        
        return @{
            Success = $true
            RowCount = $csvData.Count
            Path = $OutputPath
        }
    }
    catch {
        Write-Host "[ERROR] Failed to export skipped tables to CSV: $($_.Exception.Message)" -ForegroundColor Red
        return @{
            Success = $false
            Message = $_.Exception.Message
        }
    }
}

function Export-ValidationProblemsToCSV {
    param(
        [array]$ValidationProblems,
        [string]$OutputPath,
        [string]$Delimiter = $null
    )
    
    try {
        # Ensure directory exists
        $outputDir = Split-Path -Parent $OutputPath
        if (-not (Test-Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }
        
        # Convert validation problems to CSV format
        $csvData = $ValidationProblems | ForEach-Object {
            [PSCustomObject]@{
                TableName = $_.TableName
                ProblemType = $_.Type
                Message = $_.Message
                Details = $_.Details
                Severity = $_.Severity
                Timestamp = $_.Timestamp
            }
        }
        
        # Export to CSV
        if ($Delimiter) {
            $csvData | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8 -Delimiter $Delimiter
        } else {
            $csvData | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8 -UseCulture
        }
        
        return @{
            Success = $true
            RowCount = $csvData.Count
            Path = $OutputPath
        }
    }
    catch {
        Write-Host "[ERROR] Failed to export validation problems to CSV: $($_.Exception.Message)" -ForegroundColor Red
        return @{
            Success = $false
            Message = $_.Exception.Message
        }
    }
}

function Remove-DuplicateRecords {
    param(
        [System.Data.SqlClient.SqlConnection]$Connection,
        [string]$TableName,
        [string[]]$MatchFields,
        [string[]]$PrimaryKeys,
        [string]$WhereClause = "",
        [switch]$ShowSQL,
        [switch]$Preview
    )
    
    try {
        if ($PrimaryKeys.Count -eq 0) {
            return @{
                Success = $false
                Message = "No primary key found for table '$TableName'"
            }
        }
        
        # Use first primary key for ordering
        $primaryKey = $PrimaryKeys[0]
        
        # Build partition columns
        $partitionColumns = $MatchFields | ForEach-Object { "[$_]" }
        $partitionBy = $partitionColumns -join ", "
        
        # First, get count of duplicates that would be deleted
        $whereFilter = if ($WhereClause) { "WHERE $WhereClause" } else { "" }
        
        $countQuery = @"
WITH DuplicatesToDelete AS (
    SELECT [$primaryKey],
           ROW_NUMBER() OVER (
               PARTITION BY $partitionBy
               ORDER BY [$primaryKey]
           ) as rn
    FROM [$TableName]
    $whereFilter
)
SELECT COUNT(*) as DuplicateCount
FROM DuplicatesToDelete
WHERE rn > 1
"@
        
        if ($ShowSQL) {
            Write-Host "`n[DEBUG] Counting duplicates to delete:" -ForegroundColor DarkCyan
            Write-Host $countQuery -ForegroundColor DarkGray
        }
        
        $cmd = $Connection.CreateCommand()
        $cmd.CommandText = $countQuery
        $deleteCount = $cmd.ExecuteScalar()
        
        if ($deleteCount -eq 0) {
            return @{
                Success = $true
                Message = "No duplicates to delete"
                DeletedCount = 0
            }
        }
        
        if ($Preview) {
            # Show preview of records to be deleted
            $previewQuery = @"
WITH DuplicatesToDelete AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY $partitionBy
               ORDER BY [$primaryKey]
           ) as rn
    FROM [$TableName]
    $whereFilter
)
SELECT TOP 20 *
FROM DuplicatesToDelete
WHERE rn > 1
ORDER BY $partitionBy, [$primaryKey]
"@
            
            if ($ShowSQL) {
                Write-Host "`n[DEBUG] Preview of records to delete:" -ForegroundColor DarkCyan
                Write-Host $previewQuery -ForegroundColor DarkGray
            }
            
            $cmd.CommandText = $previewQuery
            $reader = $cmd.ExecuteReader()
            
            Write-Host "`n    Records to be deleted (showing max 20):" -ForegroundColor Yellow
            $previewData = @()
            while ($reader.Read()) {
                $row = New-Object PSObject
                for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                    $colName = $reader.GetName($i)
                    if ($colName -ne "rn") {
                        $value = if ($reader.IsDBNull($i)) { "NULL" } else { $reader.GetValue($i) }
                        $row | Add-Member -NotePropertyName $colName -NotePropertyValue $value
                    }
                }
                $previewData += $row
            }
            $reader.Close()
            
            if ($previewData.Count -gt 0) {
                $previewData | Format-Table -AutoSize | Out-String | Write-Host -ForegroundColor Gray
            }
            
            return @{
                Success = $true
                Message = "Would delete $deleteCount duplicate record(s)"
                DeletedCount = 0
                PreviewCount = $deleteCount
            }
        }
        
        # Execute deletion
        $deleteQuery = @"
WITH DuplicatesToDelete AS (
    SELECT [$primaryKey],
           ROW_NUMBER() OVER (
               PARTITION BY $partitionBy
               ORDER BY [$primaryKey]
           ) as rn
    FROM [$TableName]
    $whereFilter
)
DELETE FROM [$TableName]
WHERE [$primaryKey] IN (
    SELECT [$primaryKey]
    FROM DuplicatesToDelete
    WHERE rn > 1
)
"@
        
        if ($ShowSQL) {
            Write-Host "`n[DEBUG] Executing delete query:" -ForegroundColor DarkCyan
            Write-Host $deleteQuery -ForegroundColor DarkGray
        }
        
        $transaction = $Connection.BeginTransaction()
        try {
            $cmd = $Connection.CreateCommand()
            $cmd.Transaction = $transaction
            $cmd.CommandText = $deleteQuery
            $deletedRows = $cmd.ExecuteNonQuery()
            
            $transaction.Commit()
            
            return @{
                Success = $true
                Message = "Successfully deleted $deletedRows duplicate record(s)"
                DeletedCount = $deletedRows
            }
        }
        catch {
            $transaction.Rollback()
            throw
        }
    }
    catch {
        return @{
            Success = $false
            Message = "Failed to remove duplicates: $($_.Exception.Message)"
            DeletedCount = 0
        }
    }
}