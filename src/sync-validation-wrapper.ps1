# Wrapper for sync-validation.ps1 to support SQLite and PostgreSQL
# This file modifies the validation functions to work with SQL Server, SQLite and PostgreSQL

# Load the original validation functions
. (Join-Path $PSScriptRoot "sync-validation.ps1")

# Load database adapter if available
if (Test-Path (Join-Path $PSScriptRoot "database-adapter.ps1")) {
    . (Join-Path $PSScriptRoot "database-adapter.ps1")
}

# Override Test-DatabaseConnection to support SQLite and PostgreSQL
function Test-DatabaseConnection {
    param(
        [string]$ConnectionString,
        [switch]$ShowSQL
    )
    
    # Check if this is SQLite
    if ($ConnectionString -match '\.db$|\.db;|\.sqlite$|\.sqlite;|Data Source=.*\.(db|sqlite)') {
        # SQLite connection test
        try {
            if (-not (Get-Module -Name PSSQLite)) {
                Import-Module PSSQLite -ErrorAction Stop
            }
            
            # Extract database path
            if ($ConnectionString -match 'Data Source=([^;]+)') {
                $dbPath = $matches[1]
            } else {
                $dbPath = $ConnectionString
            }
            
            $connection = New-SQLiteConnection -DataSource $dbPath
            $connection.Open()
            
            # SQLite doesn't have permissions, so return all as true
            $permissions = @{
                CurrentDB = [System.IO.Path]::GetFileName($dbPath)
                CanSelect = $true
                CanInsert = $true
                CanUpdate = $true
                CanDelete = $true
            }
            
            $connection.Close()
            
            return @{
                Success = $true
                Message = "SQLite connection successful"
                Permissions = $permissions
            }
        }
        catch {
            return @{
                Success = $false
                Message = "SQLite connection failed: $($_.Exception.Message)"
                Permissions = @{}
            }
        }
    }
    # Check if this is PostgreSQL
    elseif ($ConnectionString -match 'Host=|Port=|postgresql://|postgres://') {
        # PostgreSQL connection test
        try {
            # Try to load Npgsql assembly
            try {
                Add-Type -Path "Npgsql.dll" -ErrorAction SilentlyContinue
            } catch {
                try {
                    [void][System.Reflection.Assembly]::LoadWithPartialName("Npgsql")
                } catch {
                    throw "Npgsql library not found. Please install: Install-Package Npgsql"
                }
            }
            
            $connection = New-Object Npgsql.NpgsqlConnection($ConnectionString)
            $connection.Open()
            
            # Test basic permissions
            $cmd = $connection.CreateCommand()
            $cmd.CommandText = "SELECT current_database()"
            $dbName = $cmd.ExecuteScalar()
            
            # PostgreSQL has a different permission system, simplified for now
            $permissions = @{
                CurrentDB = $dbName
                CanSelect = $true
                CanInsert = $true
                CanUpdate = $true
                CanDelete = $true
            }
            
            $connection.Close()
            
            return @{
                Success = $true
                Message = "PostgreSQL connection successful"
                Permissions = $permissions
            }
        }
        catch {
            return @{
                Success = $false
                Message = "PostgreSQL connection failed: $($_.Exception.Message)"
                Permissions = @{}
            }
        }
    }
    else {
        # Use original SQL Server function
        return Test-DatabaseConnectionOriginal -ConnectionString $ConnectionString -ShowSQL:$ShowSQL
    }
}

# Rename original function
Rename-Item -Path Function:\Test-DatabaseConnection -NewName Test-DatabaseConnectionOriginal -Force

# Create wrapper for connection creation
function New-DatabaseConnection {
    param(
        [string]$ConnectionString
    )
    
    if ($ConnectionString -match '\.db$|\.db;|\.sqlite$|\.sqlite;|Data Source=.*\.(db|sqlite)') {
        # SQLite
        if (-not (Get-Module -Name PSSQLite)) {
            Import-Module PSSQLite -ErrorAction Stop
        }
        
        if ($ConnectionString -match 'Data Source=([^;]+)') {
            $dbPath = $matches[1]
        } else {
            $dbPath = $ConnectionString
        }
        
        return New-SQLiteConnection -DataSource $dbPath
    }
    elseif ($ConnectionString -match 'Host=|Port=|postgresql://|postgres://') {
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
        
        return New-Object Npgsql.NpgsqlConnection($ConnectionString)
    }
    else {
        # SQL Server
        return New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
    }
}

# Create wrapper for command creation that translates SQL
function New-DatabaseCommand {
    param(
        [object]$Connection,
        [string]$CommandText
    )
    
    $cmd = $Connection.CreateCommand()
    
    # If SQLite, translate SQL
    if ($Connection.GetType().Name -eq 'SQLiteConnection') {
        $translated = $CommandText
        
        # Basic translations
        $translated = $translated -replace '\[([^\]]+)\]', '"$1"'
        $translated = $translated -replace 'GETDATE\(\)', "datetime('now')"
        $translated = $translated -replace '\bBIT\b', 'INTEGER'
        $translated = $translated -replace '\bNVARCHAR.*?\)', 'TEXT'
        
        # INFORMATION_SCHEMA translations
        if ($translated -match 'INFORMATION_SCHEMA\.TABLES') {
            $translated = $translated -replace 'SELECT COUNT\(\*\) FROM INFORMATION_SCHEMA\.TABLES WHERE TABLE_NAME = @TableName',
                "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name = @TableName"
        }
        
        if ($translated -match 'INFORMATION_SCHEMA\.COLUMNS') {
            $translated = "SELECT name as COLUMN_NAME, type as DATA_TYPE, `"notnull`" as IS_NULLABLE, pk as IS_IDENTITY FROM pragma_table_info(@TableName)"
        }
        
        # Primary key query
        if ($translated -match 'TABLE_CONSTRAINTS.*PRIMARY KEY') {
            $translated = "SELECT name as COLUMN_NAME FROM pragma_table_info(@TableName) WHERE pk > 0 ORDER BY pk"
        }
        
        # TOP to LIMIT
        if ($translated -match 'SELECT\s+TOP\s+(\d+)\s+(.+)') {
            $limit = $matches[1]
            $rest = $matches[2]
            $translated = "SELECT $rest LIMIT $limit"
        }
        
        # Permissions check - always return 1 for SQLite
        $translated = $translated -replace "HAS_PERMS_BY_NAME\([^)]+\)", '1'
        
        $cmd.CommandText = $translated
    }
    else {
        $cmd.CommandText = $CommandText
    }
    
    return $cmd
}

# Export wrapper functions
# Export-ModuleMember -Function Test-DatabaseConnection, New-DatabaseConnection, New-DatabaseCommand