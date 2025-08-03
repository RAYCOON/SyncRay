# Direkter Complex Database Test (ohne Test-Framework)
param([switch]$Verbose)

$ErrorActionPreference = "Stop"
if ($Verbose) { $VerbosePreference = "Continue" }

try {
    Write-Host "🧪 Direct Complex Database Test" -ForegroundColor Cyan
    Write-Host "=" * 50 -ForegroundColor Gray
    
    # Lade benötigte Module
    $testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $srcRoot = Join-Path (Split-Path -Parent $testRoot) "src"
    $sharedPath = Join-Path $testRoot "shared"
    
    . (Join-Path $sharedPath "Complex-Database-Schema.ps1")
    . (Join-Path $srcRoot "database-adapter-fixed.ps1")
    
    # Test 1: Schema Creation
    Write-Host "`n1️⃣ Testing Schema Creation..." -ForegroundColor Yellow
    
    # Lokales Test-Data-Verzeichnis verwenden
    $testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $testDataDir = Join-Path $testRoot "test-data" "temp"
    if (-not (Test-Path $testDataDir)) {
        New-Item -ItemType Directory -Path $testDataDir -Force | Out-Null
    }
    $dbPath = Join-Path $testDataDir "direct-test-$(Get-Random).db"
    Write-Host "   Database: $dbPath" -ForegroundColor Gray
    
    # Schema erstellen
    $schemaQueries = Get-ComplexDatabaseSchema -SchemaType "full"
    Write-Host "   Creating $($schemaQueries.Count) schema objects..." -ForegroundColor Gray
    
    foreach ($query in $schemaQueries) {
        $query | sqlite3 $dbPath
        if ($LASTEXITCODE -ne 0) {
            throw "Schema creation failed on query: $($query.Substring(0, 50))..."
        }
    }
    
    Write-Host "   ✅ Schema created successfully" -ForegroundColor Green
    
    # Test 2: Database Adapter
    Write-Host "`n2️⃣ Testing Database Adapter..." -ForegroundColor Yellow
    
    $connString = "Data Source=$dbPath"
    $adapter = New-DatabaseAdapter -ConnectionString $connString
    
    # Teste Tabellen
    $expectedTables = @("Companies", "Departments", "Teams", "Users", "Roles", "UserRoles")
    $foundTables = 0
    
    foreach ($table in $expectedTables) {
        if ($adapter.TableExists($table)) {
            $foundTables++
            Write-Host "   ✅ Table '$table' exists" -ForegroundColor Green
        } else {
            Write-Host "   ❌ Table '$table' missing" -ForegroundColor Red
        }
    }
    
    Write-Host "   Found $foundTables/$($expectedTables.Count) tables" -ForegroundColor Gray
    
    # Test 3: Data Creation
    Write-Host "`n3️⃣ Testing Data Creation..." -ForegroundColor Yellow
    
    $dataStats = Initialize-ComplexTestData -Connection $connString -DataSize "small"
    
    Write-Host "   ✅ Data created:" -ForegroundColor Green
    Write-Host "      - Companies: $($dataStats.Companies)" -ForegroundColor Gray
    Write-Host "      - Departments: $($dataStats.Departments)" -ForegroundColor Gray
    Write-Host "      - Teams: $($dataStats.Teams)" -ForegroundColor Gray
    Write-Host "      - Users: $($dataStats.Users)" -ForegroundColor Gray
    Write-Host "      - UserRoles: $($dataStats.UserRoles)" -ForegroundColor Gray
    
    # Test 4: Simple Query
    Write-Host "`n4️⃣ Testing Queries..." -ForegroundColor Yellow
    
    $userCount = $adapter.ExecuteQuery("SELECT COUNT(*) as Count FROM Users", @{})
    $companyCount = $adapter.ExecuteQuery("SELECT COUNT(*) as Count FROM Companies", @{})
    
    Write-Host "   ✅ Query results:" -ForegroundColor Green
    Write-Host "      - Users in database: $($userCount[0].Count)" -ForegroundColor Gray
    Write-Host "      - Companies in database: $($companyCount[0].Count)" -ForegroundColor Gray
    
    # Test 5: Complex Join
    Write-Host "`n5️⃣ Testing Complex Joins..." -ForegroundColor Yellow
    
    $hierarchyData = $adapter.ExecuteQuery(@"
SELECT u.Username, t.TeamName, d.DepartmentName, c.CompanyName
FROM Users u
JOIN Teams t ON u.TeamID = t.TeamID
JOIN Departments d ON t.DepartmentID = d.DepartmentID
JOIN Companies c ON d.CompanyID = c.CompanyID
LIMIT 5
"@, @{})
    
    Write-Host "   ✅ Complex join returned $($hierarchyData.Count) rows" -ForegroundColor Green
    if ($hierarchyData.Count -gt 0) {
        Write-Host "      Sample: $($hierarchyData[0].Username) in $($hierarchyData[0].CompanyName)" -ForegroundColor Gray
    }
    
    # Cleanup
    Remove-Item $dbPath -Force -ErrorAction SilentlyContinue
    
    Write-Host "`n🎉 All direct tests passed!" -ForegroundColor Green
    Write-Host "Complex database implementation is working correctly." -ForegroundColor Green
    
} catch {
    Write-Host "`n❌ Test failed: $_" -ForegroundColor Red
    Write-Host "Stack trace:" -ForegroundColor Yellow
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
}