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
        [string]$TableName
    )
    
    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = @TableName"
    $cmd.Parameters.AddWithValue("@TableName", $TableName) | Out-Null
    
    $exists = $cmd.ExecuteScalar() -gt 0
    return $exists
}

function Get-TableColumns {
    param(
        [System.Data.SqlClient.SqlConnection]$Connection,
        [string]$TableName
    )
    
    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = @"
SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE,
       COLUMNPROPERTY(OBJECT_ID(TABLE_SCHEMA + '.' + TABLE_NAME), COLUMN_NAME, 'IsIdentity') as IS_IDENTITY
FROM INFORMATION_SCHEMA.COLUMNS 
WHERE TABLE_NAME = @TableName
ORDER BY ORDINAL_POSITION
"@
    $cmd.Parameters.AddWithValue("@TableName", $TableName) | Out-Null
    
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
        [string]$TableName
    )
    
    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = @"
SELECT ku.COLUMN_NAME
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE ku
    ON tc.CONSTRAINT_TYPE = 'PRIMARY KEY' 
    AND tc.CONSTRAINT_NAME = ku.CONSTRAINT_NAME
WHERE ku.TABLE_NAME = @TableName
ORDER BY ku.ORDINAL_POSITION
"@
    $cmd.Parameters.AddWithValue("@TableName", $TableName) | Out-Null
    
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
        [string]$WhereClause
    )
    
    try {
        $cmd = $Connection.CreateCommand()
        # Use TOP 0 to test syntax without returning data
        $cmd.CommandText = "SELECT TOP 0 * FROM [$TableName] WHERE $WhereClause"
        $cmd.ExecuteReader().Close()
        
        return @{
            Success = $true
            Message = "WHERE clause syntax is valid"
        }
    }
    catch {
        return @{
            Success = $false
            Message = "Invalid WHERE clause: $($_.Exception.Message)"
        }
    }
}

function Test-SyncConfiguration {
    param(
        [PSCustomObject]$Config,
        [string]$DatabaseKey,
        [string]$Mode  # "export" or "import"
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
            if (Test-TableExists -Connection $connection -TableName $tableName) {
                Write-Host " ✓" -ForegroundColor Green
                
                # Get table columns
                $columns = Get-TableColumns -Connection $connection -TableName $tableName
                
                # Handle empty matchOn - try to use primary key
                if (-not $syncTable.matchOn -or $syncTable.matchOn.Count -eq 0) {
                    Write-Host "  No matchOn specified, checking primary key..." -ForegroundColor Gray -NoNewline
                    $primaryKeys = Get-PrimaryKeyColumns -Connection $connection -TableName $tableName
                    
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
                        $errors += "Table '$tableName': No matchOn fields specified and primary key columns are ignored"
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
                    $uniquenessTest = Test-MatchFieldsUniqueness -Connection $connection -TableName $tableName -MatchFields $syncTable.matchOn -WhereClause $whereClause
                    
                    if ($uniquenessTest.HasDuplicates) {
                        Write-Host " ✗" -ForegroundColor Red
                        $errors += "Table '$tableName': matchOn fields [$($syncTable.matchOn -join ', ')] produce $($uniquenessTest.TotalDuplicates) duplicate(s)"
                        
                        # Show examples
                        if ($uniquenessTest.Examples) {
                            Write-Host "    Example duplicates:" -ForegroundColor Red
                            foreach ($example in $uniquenessTest.Examples | Select-Object -First 3) {
                                $valueDisplay = ($example.Values.GetEnumerator() | ForEach-Object { "$($_.Key)='$($_.Value)'" }) -join ", "
                                Write-Host "    - $valueDisplay ($($example.Count) occurrences)" -ForegroundColor Red
                            }
                        }
                    } elseif ($uniquenessTest.Error) {
                        Write-Host " ⚠" -ForegroundColor Yellow
                        $warnings += "Table '$tableName': Could not check uniqueness - $($uniquenessTest.Error)"
                    } else {
                        Write-Host " ✓" -ForegroundColor Green
                    }
                } else {
                    Write-Host " ✗" -ForegroundColor Red
                    $errors += "Table '$tableName': Match fields not found: $($missingMatchFields -join ', ')"
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
                    $whereTest = Test-WhereClause -Connection $connection -TableName $tableName -WhereClause $syncTable.exportWhere
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
                $errors += "Table '$tableName' not found in database"
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
        [string]$WhereClause = ""
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
        $cmd.CommandText = @"
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
            $cmd.CommandText = @"
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
        }
        
        return $duplicateInfo
    }
    catch {
        return @{
            HasDuplicates = $false
            Error = $_.Exception.Message
        }
    }
}