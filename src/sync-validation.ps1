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
        [switch]$ShowSQL  # Show SQL statements for debugging
    )
    
    Write-Host "`n=== CONFIGURATION VALIDATION ===" -ForegroundColor Cyan
    
    $errors = @()
    $warnings = @()
    
    # Get database config
    $dbConfig = $Config.databases.$DatabaseKey
    if (-not $dbConfig) {
        Write-Host "✗ Database '$DatabaseKey' not found in configuration" -ForegroundColor Red
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
        Write-Host " ✓" -ForegroundColor Green
        
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
        Write-Host " ✗" -ForegroundColor Red
        $errors += $connTest.Message
        Write-Host "✗ $($connTest.Message)" -ForegroundColor Red
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
            
            Write-Host "`nValidating table: $tableName" -ForegroundColor Yellow
            
            # Check if table exists
            Write-Host "  Checking table existence..." -ForegroundColor Gray -NoNewline
            if (Test-TableExists -Connection $connection -TableName $tableName -ShowSQL:$ShowSQL) {
                Write-Host " ✓" -ForegroundColor Green
                
                # Get table columns
                $columns = Get-TableColumns -Connection $connection -TableName $tableName -ShowSQL:$ShowSQL
                
                # Get primary keys first (needed for detailed duplicate output)
                $primaryKeys = Get-PrimaryKeyColumns -Connection $connection -TableName $tableName -ShowSQL:$ShowSQL
                
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
                        Write-Host " ✓ Using: $($usableKeys -join ', ')" -ForegroundColor Green
                        $syncTable | Add-Member -NotePropertyName "matchOn" -NotePropertyValue $usableKeys -Force
                    } else {
                        Write-Host " ✗" -ForegroundColor Red
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
                    Write-Host " ✓" -ForegroundColor Green
                    
                    # Check uniqueness of matchOn fields
                    Write-Host "  Checking matchOn uniqueness..." -ForegroundColor Gray -NoNewline
                    $whereClause = if ($Mode -eq "export" -and $syncTable.exportWhere) { $syncTable.exportWhere } else { "" }
                    $uniquenessTest = Test-MatchFieldsUniqueness -Connection $connection -TableName $tableName -MatchFields $syncTable.matchOn -WhereClause $whereClause -ShowSQL:$ShowSQL -PrimaryKeys $primaryKeys
                    
                    if ($uniquenessTest.HasDuplicates) {
                        # During export, duplicates are warnings not errors (will be handled table-by-table)
                        if ($Mode -eq "export") {
                            Write-Host " ⚠" -ForegroundColor Yellow
                            $pkInfo = if ($primaryKeys.Count -gt 0) { " (Primary key: $($primaryKeys -join ', '))" } else { "" }
                            $warnings += "Table '$tableName': matchOn fields [$($syncTable.matchOn -join ', ')] produce $($uniquenessTest.TotalDuplicates) duplicate(s)$pkInfo - will prompt during export"
                        } else {
                            Write-Host " ✗" -ForegroundColor Red
                            $primaryKeys = Get-PrimaryKeyColumns -Connection $connection -TableName $tableName -ShowSQL:$ShowSQL
                            $pkInfo = if ($primaryKeys.Count -gt 0) { " (Primary key: $($primaryKeys -join ', '))" } else { "" }
                            $sqlInfo = if ($ShowSQL -and $uniquenessTest.SqlStatement) { "`nSQL: $($uniquenessTest.SqlStatement)" } else { "" }
                            $errors += "Table '$tableName': matchOn fields [$($syncTable.matchOn -join ', ')] produce $($uniquenessTest.TotalDuplicates) duplicate(s)$pkInfo$sqlInfo"
                        }
                        
                        # Show examples
                        if ($uniquenessTest.Examples) {
                            $exampleColor = if ($Mode -eq "export") { "Yellow" } else { "Red" }
                            Write-Host "    Example duplicates:" -ForegroundColor $exampleColor
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
                    } elseif ($uniquenessTest.Error) {
                        Write-Host " ⚠" -ForegroundColor Yellow
                        $warnings += "Table '$tableName': Could not check uniqueness - $($uniquenessTest.Error)"
                    } else {
                        Write-Host " ✓" -ForegroundColor Green
                    }
                } else {
                    Write-Host " ✗" -ForegroundColor Red
                    $primaryKeys = Get-PrimaryKeyColumns -Connection $connection -TableName $tableName -ShowSQL:$ShowSQL
                    $pkInfo = if ($primaryKeys.Count -gt 0) { " (Primary key: $($primaryKeys -join ', '))" } else { "" }
                    $errors += "Table '$tableName': Match fields not found: $($missingMatchFields -join ', ')$pkInfo"
                }
                
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
                        Write-Host " ✓" -ForegroundColor Green
                    } else {
                        Write-Host " ✗" -ForegroundColor Red
                        $warnings += "Table '$tableName': Ignore columns not found: $($missingIgnoreFields -join ', ')"
                    }
                }
                
                # Validate exportWhere clause if in export mode
                if ($Mode -eq "export" -and $syncTable.exportWhere) {
                    Write-Host "  Checking WHERE clause..." -ForegroundColor Gray -NoNewline
                    $whereTest = Test-WhereClause -Connection $connection -TableName $tableName -WhereClause $syncTable.exportWhere -ShowSQL:$ShowSQL
                    if ($whereTest.Success) {
                        Write-Host " ✓" -ForegroundColor Green
                    } else {
                        Write-Host " ✗" -ForegroundColor Red
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
                Write-Host " ✗" -ForegroundColor Red
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
        Write-Host "✓ All validations passed" -ForegroundColor Green
    } else {
        Write-Host "✗ Found $($errors.Count) error(s):" -ForegroundColor Red
        foreach ($error in $errors) {
            Write-Host "  - $error" -ForegroundColor Red
        }
    }
    
    if ($warnings.Count -gt 0) {
        Write-Host "⚠ Found $($warnings.Count) warning(s):" -ForegroundColor Yellow
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
            # Expand duplicate details into individual rows
            foreach ($detail in $problem.Details) {
                $row = [PSCustomObject]@{
                    TableName = $problem.TableName
                    MatchOnFields = $problem.MatchOnFields
                    DuplicateGroup = $detail.DuplicateGroup
                    DuplicateGroups = $problem.DuplicateGroups
                    TotalDuplicates = $problem.TotalDuplicates
                    Timestamp = $problem.Timestamp
                }
                
                # Add primary key columns
                foreach ($pk in $detail.PSObject.Properties) {
                    if ($pk.Name -notin @('DuplicateGroup')) {
                        $row | Add-Member -NotePropertyName $pk.Name -NotePropertyValue $pk.Value
                    }
                }
                
                $csvData += $row
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
        
        # Convert to CSV-friendly format
        $csvData = $SkippedTables | ForEach-Object {
            [PSCustomObject]@{
                TableName = $_.TableName
                Reason = $_.Reason
                DuplicateGroups = $_.DuplicateGroups
                TotalDuplicates = $_.TotalDuplicates
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