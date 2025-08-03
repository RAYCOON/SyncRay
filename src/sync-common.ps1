# Common functions for multi-database support in SyncRay

# Detect if connection string is for SQLite
function Test-IsSQLite {
    param([string]$ConnectionString)
    
    return $ConnectionString -match '\.db$|\.db;|\.sqlite$|\.sqlite;|Data Source=.*\.(db|sqlite)'
}

# Detect if connection string is for PostgreSQL
function Test-IsPostgreSQL {
    param([string]$ConnectionString)
    
    return $ConnectionString -match 'Host=|Port=|postgresql://|postgres://'
}

# Create appropriate database connection
function New-SyncRayConnection {
    param([string]$ConnectionString)
    
    if (Test-IsSQLite $ConnectionString) {
        # SQLite
        if (-not (Get-Module -Name PSSQLite)) {
            Import-Module PSSQLite -ErrorAction Stop
        }
        
        if ($ConnectionString -match 'Data Source=([^;]+)') {
            $dbPath = $matches[1]
        } else {
            $dbPath = $ConnectionString
        }
        
        # Create wrapper object that looks like SqlConnection
        $sqliteConn = New-SQLiteConnection -DataSource $dbPath
        
        # Add compatibility properties/methods
        Add-Member -InputObject $sqliteConn -MemberType ScriptMethod -Name "CreateCommand" -Value {
            $cmd = $this.CreateCommand()
            # Return wrapped command that auto-translates SQL
            return New-SyncRayCommand -Command $cmd -IsSQLite $true
        } -Force
        
        return $sqliteConn
    }
    elseif (Test-IsPostgreSQL $ConnectionString) {
        # PostgreSQL
        try {
            Add-Type -Path "Npgsql.dll" -ErrorAction SilentlyContinue
        } catch {
            try {
                [void][System.Reflection.Assembly]::LoadWithPartialName("Npgsql")
            } catch {
                throw "Npgsql library not found. Please install: Install-Package Npgsql"
            }
        }
        
        $pgConn = New-Object Npgsql.NpgsqlConnection($ConnectionString)
        
        # Add compatibility method
        Add-Member -InputObject $pgConn -MemberType ScriptMethod -Name "CreateCommand" -Value {
            $cmd = $this.CreateCommand()
            # Return wrapped command that auto-translates SQL
            return New-SyncRayCommand -Command $cmd -IsPostgreSQL $true
        } -Force
        
        return $pgConn
    }
    else {
        # SQL Server
        return New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
    }
}

# Create wrapped command that translates SQL for different databases
function New-SyncRayCommand {
    param(
        [object]$Command,
        [bool]$IsSQLite = $false,
        [bool]$IsPostgreSQL = $false
    )
    
    if (-not $IsSQLite -and -not $IsPostgreSQL) {
        return $Command
    }
    
    # Create wrapper object
    $wrapper = [PSCustomObject]@{
        InnerCommand = $Command
        IsSQLite = $IsSQLite
        IsPostgreSQL = $IsPostgreSQL
    }
    
    # Add CommandText property with translation
    Add-Member -InputObject $wrapper -MemberType ScriptProperty -Name "CommandText" -Value {
        $this.InnerCommand.CommandText
    } -SecondValue {
        param($value)
        if ($this.IsSQLite) {
            $this.InnerCommand.CommandText = Convert-ToSQLiteQuery $value
        } elseif ($this.IsPostgreSQL) {
            $this.InnerCommand.CommandText = Convert-ToPostgreSQLQuery $value
        } else {
            $this.InnerCommand.CommandText = $value
        }
    }
    
    # Add other properties
    Add-Member -InputObject $wrapper -MemberType ScriptProperty -Name "Connection" -Value {
        $this.InnerCommand.Connection
    } -SecondValue {
        param($value)
        $this.InnerCommand.Connection = $value
    }
    
    Add-Member -InputObject $wrapper -MemberType ScriptProperty -Name "Transaction" -Value {
        $this.InnerCommand.Transaction
    } -SecondValue {
        param($value)
        $this.InnerCommand.Transaction = $value
    }
    
    Add-Member -InputObject $wrapper -MemberType ScriptProperty -Name "Parameters" -Value {
        $this.InnerCommand.Parameters
    }
    
    # Add methods
    Add-Member -InputObject $wrapper -MemberType ScriptMethod -Name "ExecuteReader" -Value {
        $this.InnerCommand.ExecuteReader()
    }
    
    Add-Member -InputObject $wrapper -MemberType ScriptMethod -Name "ExecuteScalar" -Value {
        $this.InnerCommand.ExecuteScalar()
    }
    
    Add-Member -InputObject $wrapper -MemberType ScriptMethod -Name "ExecuteNonQuery" -Value {
        $this.InnerCommand.ExecuteNonQuery()
    }
    
    Add-Member -InputObject $wrapper -MemberType ScriptMethod -Name "Dispose" -Value {
        $this.InnerCommand.Dispose()
    }
    
    return $wrapper
}

# Convert SQL Server query to SQLite
function Convert-ToSQLiteQuery {
    param([string]$sql)
    
    $translated = $sql
    
    # Basic translations
    $translated = $translated -replace '\[([^\]]+)\]', '"$1"'
    $translated = $translated -replace 'GETDATE\(\)', "datetime('now')"
    $translated = $translated -replace 'DATEADD\((\w+),\s*([^,]+),\s*([^)]+)\)', "datetime($3, '$2 $1')"
    
    # Data types
    $translated = $translated -replace '\bBIT\b', 'INTEGER'
    $translated = $translated -replace '\bNVARCHAR\s*\([^)]+\)', 'TEXT'
    $translated = $translated -replace '\bVARCHAR\s*\([^)]+\)', 'TEXT'
    $translated = $translated -replace '\bDATETIME\b', 'TEXT'
    $translated = $translated -replace '\bDECIMAL\s*\([^)]+\)', 'REAL'
    
    # TOP to LIMIT
    if ($translated -match '^(.*SELECT)\s+TOP\s+(\d+)\s+(.+)$') {
        $prefix = $matches[1]
        $limit = $matches[2]
        $rest = $matches[3]
        $translated = "$prefix $rest LIMIT $limit"
    }
    
    # INFORMATION_SCHEMA
    if ($translated -match 'INFORMATION_SCHEMA\.TABLES') {
        $translated = $translated -replace 'SELECT COUNT\(\*\) FROM INFORMATION_SCHEMA\.TABLES WHERE TABLE_NAME = @TableName',
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name = @TableName"
    }
    
    if ($translated -match 'INFORMATION_SCHEMA\.COLUMNS') {
        $translated = "SELECT name as COLUMN_NAME, type as DATA_TYPE, `"notnull`" = 0 as IS_NULLABLE, pk as IS_IDENTITY FROM pragma_table_info(@TableName)"
    }
    
    # Primary keys
    if ($translated -match 'TABLE_CONSTRAINTS.*PRIMARY KEY') {
        $translated = "SELECT name as COLUMN_NAME FROM pragma_table_info(@TableName) WHERE pk > 0 ORDER BY pk"
    }
    
    # Permissions - always true for SQLite
    $translated = $translated -replace "HAS_PERMS_BY_NAME\([^)]+\)", '1'
    
    # COLUMNPROPERTY
    $translated = $translated -replace "COLUMNPROPERTY\([^)]+\)", 'pk'
    
    # DB_NAME()
    $translated = $translated -replace "DB_NAME\(\)", "'sqlite'"
    
    # SET IDENTITY_INSERT - ignore for SQLite
    $translated = $translated -replace "SET IDENTITY_INSERT.*?(ON|OFF)", "-- IDENTITY_INSERT not needed in SQLite"
    
    return $translated
}

# Convert SQL Server query to PostgreSQL
function Convert-ToPostgreSQLQuery {
    param([string]$sql)
    
    $translated = $sql
    
    # Basic translations from SQL Server to PostgreSQL
    # Replace [brackets] with "quotes"
    $translated = $translated -replace '\[([^\]]+)\]', '"$1"'
    
    # SQL Server to PostgreSQL function mappings
    $translated = $translated -replace 'GETDATE\(\)', 'NOW()'
    $translated = $translated -replace 'DATEADD\((\w+),\s*([^,]+),\s*([^)]+)\)', "($3 + INTERVAL '$2 $1')"
    $translated = $translated -replace 'DATEDIFF\((\w+),\s*([^,]+),\s*([^)]+)\)', "EXTRACT($1 FROM ($3 - $2))"
    
    # Data type conversions
    $translated = $translated -replace '\bBIT\b', 'BOOLEAN'
    $translated = $translated -replace '\bNVARCHAR\s*\(\s*\d+\s*\)', 'VARCHAR'
    $translated = $translated -replace '\bNVARCHAR\s*\(MAX\)', 'TEXT'
    $translated = $translated -replace '\bVARCHAR\s*\(\s*\d+\s*\)', 'VARCHAR'
    $translated = $translated -replace '\bDATETIME\b', 'TIMESTAMP'
    $translated = $translated -replace '\bDECIMAL\s*\(\s*\d+\s*,\s*\d+\s*\)', 'NUMERIC'
    
    # TOP to LIMIT
    if ($translated -match '^(.*SELECT)\s+TOP\s+(\d+)\s+(.+)$') {
        $prefix = $matches[1]
        $limit = $matches[2]
        $rest = $matches[3]
        $translated = "$prefix $rest LIMIT $limit"
    }
    
    # INFORMATION_SCHEMA translations
    if ($translated -match 'INFORMATION_SCHEMA\.TABLES') {
        $translated = $translated -replace 'SELECT COUNT\(\*\) FROM INFORMATION_SCHEMA\.TABLES WHERE TABLE_NAME = @TableName',
            "SELECT COUNT(*) FROM information_schema.tables WHERE table_name = @TableName AND table_schema = 'public'"
    }
    
    if ($translated -match 'INFORMATION_SCHEMA\.COLUMNS') {
        # PostgreSQL has proper INFORMATION_SCHEMA support
        $translated = $translated -replace 'WHERE\s+TABLE_NAME\s*=\s*@TableName',
            "WHERE table_name = @TableName AND table_schema = 'public'"
    }
    
    # Primary key query translation
    if ($translated -match 'TABLE_CONSTRAINTS.*PRIMARY KEY') {
        $translated = @"
SELECT kcu.column_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
WHERE tc.table_name = @TableName AND tc.constraint_type = 'PRIMARY KEY' AND tc.table_schema = 'public'
ORDER BY kcu.ordinal_position
"@
    }
    
    # COLUMNPROPERTY for identity - PostgreSQL uses sequences
    $translated = $translated -replace "COLUMNPROPERTY\([^,]+,\s*'IsIdentity'\)", 
        "CASE WHEN column_default LIKE 'nextval%' THEN 1 ELSE 0 END"
    
    # HAS_PERMS_BY_NAME - PostgreSQL has different permission system
    $translated = $translated -replace "HAS_PERMS_BY_NAME\([^)]+\)", '1'
    
    # DB_NAME()
    $translated = $translated -replace "DB_NAME\(\)", "current_database()"
    
    # SET IDENTITY_INSERT - PostgreSQL doesn't use this
    $translated = $translated -replace "SET IDENTITY_INSERT.*?(ON|OFF)", "-- IDENTITY_INSERT not needed in PostgreSQL"
    
    # Parameter style - PostgreSQL uses $ instead of @
    $translated = $translated -replace '@(\w+)', '$$$1'
    
    return $translated
}

# Build connection string based on config
function Get-ConnectionString {
    param($dbConfig)
    
    if ($dbConfig.auth -eq "sqlite" -or $dbConfig.database -match '\.(db|sqlite)$') {
        # SQLite connection string
        return $dbConfig.database
    }
    elseif ($dbConfig.auth -eq "postgresql" -or $dbConfig.server -match 'Host=|Port=|postgresql://|postgres://') {
        # PostgreSQL connection string
        if ($dbConfig.server -match '^postgresql://|^postgres://') {
            # Already a full PostgreSQL URI
            return $dbConfig.server
        } else {
            # Build PostgreSQL connection string
            $connStr = "Host=$($dbConfig.server);Database=$($dbConfig.database);"
            if ($dbConfig.port) {
                $connStr += "Port=$($dbConfig.port);"
            }
            if ($dbConfig.user -and $dbConfig.password) {
                $connStr += "Username=$($dbConfig.user);Password=$($dbConfig.password);"
            }
            return $connStr
        }
    }
    else {
        # SQL Server connection string (original logic)
        $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
        $builder["Data Source"] = $dbConfig.server
        $builder["Initial Catalog"] = $dbConfig.database
        
        if ($dbConfig.auth -eq "windows") {
            $builder["Integrated Security"] = $true
        } else {
            $builder["User ID"] = $dbConfig.user
            $builder["Password"] = $dbConfig.password
        }
        
        return $builder.ConnectionString
    }
}

# Export functions
# Export-ModuleMember -Function Test-IsSQLite, Test-IsPostgreSQL, New-SyncRayConnection, New-SyncRayCommand, Convert-ToSQLiteQuery, Convert-ToPostgreSQLQuery, Get-ConnectionString