# Native SQLite wrapper for SyncRay
param(
    [string]$Database,
    [string]$Query
)

# Execute query
$Query | sqlite3 $Database

# Return exit code
exit $LASTEXITCODE
