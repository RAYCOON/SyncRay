# Debug Exact Primary Key Issue - Mimic failing test

$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

# Load the database adapter
$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$srcRoot = Join-Path (Split-Path -Parent $testRoot) "src"
. (Join-Path $srcRoot "database-adapter-fixed.ps1")

# Create exact same setup as failing test
$tempPath = Join-Path $testRoot "test-data" "temp"
if (-not (Test-Path $tempPath)) {
    New-Item -ItemType Directory -Path $tempPath -Force | Out-Null
}

$dbPath = Join-Path $tempPath "pk_test_debug.db"

# Exact same setup as failing test
$setupQueries = @(
    "CREATE TABLE single_pk (id INTEGER PRIMARY KEY, name TEXT);",
    "CREATE TABLE composite_pk (order_id INTEGER, product_id INTEGER, line_number INTEGER, quantity INTEGER, PRIMARY KEY (order_id, product_id, line_number));",
    "CREATE TABLE no_pk (name TEXT, value TEXT);"
)

foreach ($query in $setupQueries) {
    $query | sqlite3 $dbPath
}

$connString = "Data Source=$dbPath"

Write-Host "=== Testing Get-PrimaryKeyColumns Function ===" -ForegroundColor Yellow
Write-Host "Connection String: $connString"
Write-Host "Database Path: $dbPath"

# Test what the function actually returns
Write-Host "`n=== Testing Single PK ===" -ForegroundColor Cyan
$singlePK = Get-PrimaryKeyColumns -ConnectionString $connString -TableName "single_pk"

Write-Host "`n=== Testing Composite PK ===" -ForegroundColor Cyan
$compositePK = Get-PrimaryKeyColumns -ConnectionString $connString -TableName "composite_pk"

Write-Host "`n=== Testing Direct Adapter Method (single) ===" -ForegroundColor Cyan
$adapter = New-DatabaseAdapter -ConnectionString $connString
$directResult = $adapter.GetPrimaryKeyColumns("single_pk")

Write-Host "`n=== Testing Direct Adapter Method (composite) ===" -ForegroundColor Cyan
$directComposite = $adapter.GetPrimaryKeyColumns("composite_pk")

Write-Host "`nResult from Single PK:"
Write-Host "  Type: $($singlePK.GetType().Name)"
Write-Host "  Count: $($singlePK.Count)"
Write-Host "  Values: $($singlePK -join ', ')"

Write-Host "`nResult from Composite PK:"
Write-Host "  Type: $($compositePK.GetType().Name)"
Write-Host "  Count: $($compositePK.Count)"
Write-Host "  Values: $($compositePK -join ', ')"

Write-Host "`nResult from Direct Single PK:"
Write-Host "  Type: $($directResult.GetType().Name)"
Write-Host "  Count: $($directResult.Count)"
Write-Host "  Values: $($directResult -join ', ')"

Write-Host "`nResult from Direct Composite PK:"
Write-Host "  Type: $($directComposite.GetType().Name)"
Write-Host "  Count: $($directComposite.Count)"
Write-Host "  Values: $($directComposite -join ', ')"

# Test raw SQLite output directly
Write-Host "`n=== Raw SQLite Test (single_pk) ===" -ForegroundColor Yellow
$pragmaResult = "PRAGMA table_info(single_pk)" | sqlite3 -header -csv $dbPath
Write-Host "Raw PRAGMA result:"
Write-Host "'$pragmaResult'"

Write-Host "`n=== Raw SQLite Test (composite_pk) ===" -ForegroundColor Yellow
$compositePragma = "PRAGMA table_info(composite_pk)" | sqlite3 -header -csv $dbPath
Write-Host "Raw PRAGMA result:"
Write-Host "'$compositePragma'"

# Clean up
Remove-Item $dbPath -Force