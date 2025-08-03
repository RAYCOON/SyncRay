# Database Adapter for SQL Server, SQLite and PostgreSQL compatibility
# Provides abstraction layer for database operations

# Base adapter class
class DatabaseAdapter {
    [string]$Provider
    [string]$ConnectionString
    [object]$Connection
    
    # Factory method to create appropriate adapter
    static [DatabaseAdapter] Create([string]$connectionString) {
        # Detect SQLite by file extension or connection string pattern
        if ($connectionString -match '\.db$|\.db;|\.sqlite$|\.sqlite;|Data Source=.*\.(db|sqlite)') {
            return [SQLiteAdapter]::new($connectionString)
        }
        # Detect PostgreSQL by Host/Port pattern or postgresql:// scheme
        if ($connectionString -match 'Host=|Port=|postgresql://|postgres://') {
            return [PostgreSQLAdapter]::new($connectionString)
        }
        # Default to SQL Server
        return [SqlServerAdapter]::new($connectionString)
    }
    
    # Virtual methods to be overridden
    [void] Open() { throw "Must be implemented by derived class" }
    [void] Close() { throw "Must be implemented by derived class" }
    [object] CreateCommand() { throw "Must be implemented by derived class" }
    [string] TranslateQuery([string]$sql) { throw "Must be implemented by derived class" }
    [hashtable] GetConnectionInfo() { throw "Must be implemented by derived class" }
}

# SQL Server adapter (minimal changes to existing behavior)
class SqlServerAdapter : DatabaseAdapter {
    SqlServerAdapter([string]$connectionString) {
        $this.Provider = "SqlServer"
        $this.ConnectionString = $connectionString
        $this.Connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
    }
    
    [void] Open() {
        $this.Connection.Open()
    }
    
    [void] Close() {
        if ($this.Connection.State -ne 'Closed') {
            $this.Connection.Close()
        }
    }
    
    [object] CreateCommand() {
        return $this.Connection.CreateCommand()
    }
    
    [string] TranslateQuery([string]$sql) {
        # No translation needed for SQL Server
        return $sql
    }
    
    [hashtable] GetConnectionInfo() {
        $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder($this.ConnectionString)
        return @{
            Server = $builder.DataSource
            Database = $builder.InitialCatalog
            Auth = if ($builder.IntegratedSecurity) { "windows" } else { "sql" }
        }
    }
}

# SQLite adapter with SQL translation
class SQLiteAdapter : DatabaseAdapter {
    [hashtable]$TranslationCache = @{}
    
    SQLiteAdapter([string]$connectionString) {
        $this.Provider = "SQLite"
        $this.ConnectionString = $connectionString
        
        # Ensure PSSQLite module is loaded
        if (-not (Get-Module -Name PSSQLite)) {
            Import-Module PSSQLite -ErrorAction Stop
        }
        
        # Extract database path from connection string
        if ($connectionString -match 'Data Source=([^;]+)') {
            $dbPath = $matches[1]
        } else {
            $dbPath = $connectionString
        }
        
        $this.Connection = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$dbPath")
    }
    
    [void] Open() {
        $this.Connection.Open()
    }
    
    [void] Close() {
        if ($this.Connection.State -ne 'Closed') {
            $this.Connection.Close()
        }
    }
    
    [object] CreateCommand() {
        $cmd = $this.Connection.CreateCommand()
        # Wrap command to auto-translate SQL
        return [SQLiteCommand]::new($cmd, $this)
    }
    
    [string] TranslateQuery([string]$sql) {
        # Check cache first
        if ($this.TranslationCache.ContainsKey($sql)) {
            return $this.TranslationCache[$sql]
        }
        
        $translated = $sql
        
        # Basic translations
        # Replace [brackets] with "quotes"
        $translated = $translated -replace '\[([^\]]+)\]', '"`$1"'
        
        # SQL Server to SQLite function mappings
        $translated = $translated -replace 'GETDATE\(\)', "datetime('now')"
        $translated = $translated -replace 'DATEADD\((\w+),\s*([^,]+),\s*([^)]+)\)', "datetime(`$3, '`$2 `$1')"
        $translated = $translated -replace 'DATEDIFF\((\w+),\s*([^,]+),\s*([^)]+)\)', "julianday(`$3) - julianday(`$2)"
        
        # Data type conversions
        $translated = $translated -replace '\bBIT\b', 'INTEGER'
        $translated = $translated -replace '\bNVARCHAR\s*\(\s*\d+\s*\)', 'TEXT'
        $translated = $translated -replace '\bNVARCHAR\s*\(MAX\)', 'TEXT'
        $translated = $translated -replace '\bVARCHAR\s*\(\s*\d+\s*\)', 'TEXT'
        $translated = $translated -replace '\bDATETIME\b', 'TEXT'
        $translated = $translated -replace '\bDECIMAL\s*\(\s*\d+\s*,\s*\d+\s*\)', 'REAL'
        
        # TOP to LIMIT
        if ($translated -match 'SELECT\s+TOP\s+(\d+)\s+(.+)') {
            $limit = $matches[1]
            $rest = $matches[2]
            $translated = "SELECT $rest LIMIT $limit"
        }
        
        # INFORMATION_SCHEMA translations
        if ($translated -match 'INFORMATION_SCHEMA\.TABLES') {
            $translated = $translated -replace 'SELECT COUNT\(\*\) FROM INFORMATION_SCHEMA\.TABLES WHERE TABLE_NAME = @TableName',
                "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name = @TableName"
        }
        
        if ($translated -match 'INFORMATION_SCHEMA\.COLUMNS') {
            # Convert to pragma_table_info
            if ($translated -match 'WHERE\s+TABLE_NAME\s*=\s*@TableName') {
                $translated = "SELECT name as COLUMN_NAME, type as DATA_TYPE, `"notnull`" as IS_NULLABLE, pk as IS_IDENTITY FROM pragma_table_info(@TableName)"
            }
        }
        
        # Primary key query translation
        if ($translated -match 'TABLE_CONSTRAINTS.*PRIMARY KEY') {
            $translated = "SELECT name as COLUMN_NAME FROM pragma_table_info(@TableName) WHERE pk > 0 ORDER BY pk"
        }
        
        # COLUMNPROPERTY for identity
        $translated = $translated -replace "COLUMNPROPERTY\([^,]+,\s*'IsIdentity'\)", 'pk'
        
        # HAS_PERMS_BY_NAME - SQLite doesn't have permissions, always return 1
        $translated = $translated -replace "HAS_PERMS_BY_NAME\([^)]+\)", '1'
        
        # Cache the translation
        $this.TranslationCache[$sql] = $translated
        
        return $translated
    }
    
    [hashtable] GetConnectionInfo() {
        if ($this.ConnectionString -match 'Data Source=([^;]+)') {
            $dbPath = $matches[1]
        } else {
            $dbPath = $this.ConnectionString
        }
        
        return @{
            Server = "localhost"
            Database = $dbPath
            Auth = "sqlite"
        }
    }
}

# Wrapper for SQLite commands to auto-translate SQL
class SQLiteCommand {
    [object]$InnerCommand
    [SQLiteAdapter]$Adapter
    
    SQLiteCommand([object]$command, [SQLiteAdapter]$adapter) {
        $this.InnerCommand = $command
        $this.Adapter = $adapter
    }
    
    # Property getters/setters
    [string] get_CommandText() {
        return $this.InnerCommand.CommandText
    }
    
    [void] set_CommandText([string]$value) {
        # Translate SQL before setting
        $this.InnerCommand.CommandText = $this.Adapter.TranslateQuery($value)
    }
    
    [object] get_Connection() {
        return $this.InnerCommand.Connection
    }
    
    [void] set_Connection([object]$value) {
        $this.InnerCommand.Connection = $value
    }
    
    [object] get_Transaction() {
        return $this.InnerCommand.Transaction
    }
    
    [void] set_Transaction([object]$value) {
        $this.InnerCommand.Transaction = $value
    }
    
    [object] get_Parameters() {
        return $this.InnerCommand.Parameters
    }
    
    # Method delegations
    [object] ExecuteReader() {
        return $this.InnerCommand.ExecuteReader()
    }
    
    [object] ExecuteScalar() {
        return $this.InnerCommand.ExecuteScalar()
    }
    
    [int] ExecuteNonQuery() {
        return $this.InnerCommand.ExecuteNonQuery()
    }
    
    [void] Dispose() {
        $this.InnerCommand.Dispose()
    }
}

# PostgreSQL adapter with SQL translation
class PostgreSQLAdapter : DatabaseAdapter {
    [hashtable]$TranslationCache = @{}
    
    PostgreSQLAdapter([string]$connectionString) {
        $this.Provider = "PostgreSQL"
        $this.ConnectionString = $connectionString
        
        # Try to load Npgsql assembly
        try {
            Add-Type -Path "Npgsql.dll" -ErrorAction SilentlyContinue
        } catch {
            # If not found locally, try GAC or NuGet package
            try {
                [void][System.Reflection.Assembly]::LoadWithPartialName("Npgsql")
            } catch {
                throw "Npgsql library not found. Please install: Install-Package Npgsql"
            }
        }
        
        $this.Connection = New-Object Npgsql.NpgsqlConnection($connectionString)
    }
    
    [void] Open() {
        $this.Connection.Open()
    }
    
    [void] Close() {
        if ($this.Connection.State -ne 'Closed') {
            $this.Connection.Close()
        }
    }
    
    [object] CreateCommand() {
        $cmd = $this.Connection.CreateCommand()
        # Wrap command to auto-translate SQL
        return [PostgreSQLCommand]::new($cmd, $this)
    }
    
    [string] TranslateQuery([string]$sql) {
        # Check cache first
        if ($this.TranslationCache.ContainsKey($sql)) {
            return $this.TranslationCache[$sql]
        }
        
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
        if ($translated -match 'SELECT\s+TOP\s+(\d+)\s+(.+)') {
            $limit = $matches[1]
            $rest = $matches[2]
            $translated = "SELECT $rest LIMIT $limit"
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
        # For simplicity, always return true (1)
        $translated = $translated -replace "HAS_PERMS_BY_NAME\([^)]+\)", '1'
        
        # Parameter style - PostgreSQL uses $ instead of @
        $translated = $translated -replace '@(\w+)', '$$$1'
        
        # Cache the translation
        $this.TranslationCache[$sql] = $translated
        
        return $translated
    }
    
    [hashtable] GetConnectionInfo() {
        $builder = New-Object Npgsql.NpgsqlConnectionStringBuilder($this.ConnectionString)
        return @{
            Server = $builder.Host
            Database = $builder.Database
            Auth = if ($builder.Username) { "password" } else { "integrated" }
            Port = $builder.Port
        }
    }
}

# Wrapper for PostgreSQL commands to auto-translate SQL
class PostgreSQLCommand {
    [object]$InnerCommand
    [PostgreSQLAdapter]$Adapter
    
    PostgreSQLCommand([object]$command, [PostgreSQLAdapter]$adapter) {
        $this.InnerCommand = $command
        $this.Adapter = $adapter
    }
    
    # Property getters/setters
    [string] get_CommandText() {
        return $this.InnerCommand.CommandText
    }
    
    [void] set_CommandText([string]$value) {
        # Translate SQL before setting
        $this.InnerCommand.CommandText = $this.Adapter.TranslateQuery($value)
    }
    
    [object] get_Connection() {
        return $this.InnerCommand.Connection
    }
    
    [void] set_Connection([object]$value) {
        $this.InnerCommand.Connection = $value
    }
    
    [object] get_Transaction() {
        return $this.InnerCommand.Transaction
    }
    
    [void] set_Transaction([object]$value) {
        $this.InnerCommand.Transaction = $value
    }
    
    [object] get_Parameters() {
        return $this.InnerCommand.Parameters
    }
    
    # Method delegations
    [object] ExecuteReader() {
        return $this.InnerCommand.ExecuteReader()
    }
    
    [object] ExecuteScalar() {
        return $this.InnerCommand.ExecuteScalar()
    }
    
    [int] ExecuteNonQuery() {
        return $this.InnerCommand.ExecuteNonQuery()
    }
    
    [void] Dispose() {
        $this.InnerCommand.Dispose()
    }
}

# Helper function to create database adapter
function New-DatabaseAdapter {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ConnectionString
    )
    
    return [DatabaseAdapter]::Create($ConnectionString)
}

# Export functions and classes
# Export-ModuleMember -Function New-DatabaseAdapter