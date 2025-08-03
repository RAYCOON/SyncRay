# Unit Tests für komplexe Datenbank-Strukturen
# Testet hierarchische Beziehungen, Foreign Keys, Many-to-Many, Self-References

param([switch]$Verbose)

$ErrorActionPreference = "Stop"
if ($Verbose) { $VerbosePreference = "Continue" }

# Test-Framework laden
$testRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$sharedPath = Join-Path $testRoot "shared"
. (Join-Path $sharedPath "Test-Framework.ps1")
. (Join-Path $sharedPath "Database-TestHelpers.ps1")
. (Join-Path $sharedPath "Assertion-Helpers.ps1")
. (Join-Path $sharedPath "Complex-Database-Schema.ps1")

# Fixed Database Adapter laden
$srcRoot = Join-Path (Split-Path -Parent $testRoot) "src"
. (Join-Path $srcRoot "database-adapter-fixed.ps1")

# Test-Framework initialisieren
Initialize-TestFramework

# Test-Suite erstellen
$suite = New-TestSuite -Name "Complex-Database" -Category "unit" -Module "validation"

# Test 1: Komplexes Schema erstellen
$suite.AddTest("Complex-Schema-Creation", {
    param($context)
    
    try {
        # Test-Datenbank Pfad erstellen (OHNE automatisches Schema aus Database-TestHelpers)
        $testDataDir = Get-TestDataDirectory -Category "unit"
        $dbPath = Join-Path $testDataDir "complex_schema-$(Get-Random).db"
        $context.AddCleanup({ if ($dbPath -and (Test-Path $dbPath)) { Remove-Item $dbPath -Force -ErrorAction SilentlyContinue } })
        
        # Schema erstellen
        $schemaQueries = Get-ComplexDatabaseSchema -SchemaType "full"
        
        foreach ($query in $schemaQueries) {
            Write-Verbose "Executing schema query: $($query.Substring(0, [math]::Min(50, $query.Length)))..."
            $query | sqlite3 $dbPath
            
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to execute schema query"
            }
        }
        
        $connString = "Data Source=$dbPath"
        $adapter = New-DatabaseAdapter -ConnectionString $connString
        
        # Prüfen ob alle Tabellen erstellt wurden
        $expectedTables = @("Companies", "Departments", "Teams", "Users", "Roles", "UserRoles", "Projects", "Skills", "ProjectSkills", "UserSkills", "Tasks", "TaskAssignments", "Categories", "Budgets", "Expenses", "AuditLog")
        
        foreach ($table in $expectedTables) {
            $exists = $adapter.TableExists($table)
            Assert-True -Condition $exists -Message "Tabelle '$table' sollte erstellt werden"
        }
        
        # Prüfen ob Views erstellt wurden
        $views = $adapter.ExecuteQuery("SELECT name FROM sqlite_master WHERE type='view'", @{})
        Assert-True -Condition $views.Count -ge 3 -Message "Mindestens 3 Views sollten erstellt werden"
        
        return @{ Success = $true; Message = "Komplexes Schema erfolgreich erstellt ($($expectedTables.Count) Tabellen, $($views.Count) Views)" }
        
    } catch {
        return @{ Success = $false; Message = "Complex Schema Creation fehlgeschlagen: $_" }
    }
})

# Test 2: Hierarchische Datenstrukturen testen
$suite.AddTest("Hierarchical-Data-Structures", {
    param($context)
    
    try {
        # Test-Datenbank Pfad erstellen (OHNE automatisches Schema aus Database-TestHelpers)
        $testDataDir = Get-TestDataDirectory -Category "unit"
        $dbPath = Join-Path $testDataDir "hierarchical_test-$(Get-Random).db"
        $context.AddCleanup({ if ($dbPath -and (Test-Path $dbPath)) { Remove-Item $dbPath -Force -ErrorAction SilentlyContinue } })
        
        # Schema erstellen
        $schemaQueries = Get-ComplexDatabaseSchema -SchemaType "full"
        foreach ($query in $schemaQueries) {
            $query | sqlite3 $dbPath | Out-Null
        }
        
        $connString = "Data Source=$dbPath"
        
        # Test-Daten einfügen
        $dataStats = Initialize-ComplexTestData -Connection $connString -DataSize "small"
        
        Assert-True -Condition $dataStats.Companies -gt 0 -Message "Companies sollten erstellt werden"
        Assert-True -Condition $dataStats.Departments -gt 0 -Message "Departments sollten erstellt werden"
        Assert-True -Condition $dataStats.Teams -gt 0 -Message "Teams sollten erstellt werden"
        Assert-True -Condition $dataStats.Users -gt 0 -Message "Users sollten erstellt werden"
        Assert-True -Condition $dataStats.Roles -gt 0 -Message "Roles sollten erstellt werden"
        Assert-True -Condition $dataStats.UserRoles -gt 0 -Message "UserRoles sollten erstellt werden"
        
        # Hierarchie-Integrität testen
        $integrityTest = Test-HierarchicalIntegrity -Connection $connString
        Assert-True -Condition $integrityTest.IsValid -Message "Hierarchische Integrität sollte gültig sein. Issues: $($integrityTest.Issues -join ', ')"
        
        return @{ Success = $true; Message = "Hierarchische Strukturen erfolgreich getestet (Companies: $($dataStats.Companies), Users: $($dataStats.Users))" }
        
    } catch {
        return @{ Success = $false; Message = "Hierarchical Data Structures Test fehlgeschlagen: $_" }
    }
})

# Test 3: Foreign Key Beziehungen testen
$suite.AddTest("Foreign-Key-Relationships", {
    param($context)
    
    try {
        # Test-Datenbank Pfad erstellen (OHNE automatisches Schema aus Database-TestHelpers)
        $testDataDir = Get-TestDataDirectory -Category "unit"
        $dbPath = Join-Path $testDataDir "fk_test-$(Get-Random).db"
        $context.AddCleanup({ if ($dbPath -and (Test-Path $dbPath)) { Remove-Item $dbPath -Force -ErrorAction SilentlyContinue } })
        
        # Schema erstellen
        $schemaQueries = Get-ComplexDatabaseSchema -SchemaType "full"
        foreach ($query in $schemaQueries) {
            $query | sqlite3 $dbPath | Out-Null
        }
        
        $connString = "Data Source=$dbPath"
        
        # Test-Daten einfügen
        Initialize-ComplexTestData -Connection $connString -DataSize "small"
        
        # Referentielle Integrität testen
        $refIntegrityTest = Test-ReferentialIntegrity -Connection $connString
        Assert-True -Condition $refIntegrityTest.IsValid -Message "Referentielle Integrität sollte gültig sein. Issues: $($refIntegrityTest.Issues -join ', ')"
        
        $adapter = New-DatabaseAdapter -ConnectionString $connString
        
        # Spezifische FK-Tests
        # Test 1: Users -> Teams FK
        $usersWithValidTeams = $adapter.ExecuteQuery("SELECT COUNT(*) as Count FROM Users u JOIN Teams t ON u.TeamID = t.TeamID", @{})
        $totalUsers = $adapter.ExecuteQuery("SELECT COUNT(*) as Count FROM Users WHERE TeamID IS NOT NULL", @{})
        Assert-Equal -Expected $totalUsers[0].Count -Actual $usersWithValidTeams[0].Count -Message "Alle Users sollten gültige Teams haben"
        
        # Test 2: Departments -> Companies FK
        $deptsWithValidCompanies = $adapter.ExecuteQuery("SELECT COUNT(*) as Count FROM Departments d JOIN Companies c ON d.CompanyID = c.CompanyID", @{})
        $totalDepts = $adapter.ExecuteQuery("SELECT COUNT(*) as Count FROM Departments", @{})
        Assert-Equal -Expected $totalDepts[0].Count -Actual $deptsWithValidCompanies[0].Count -Message "Alle Departments sollten gültige Companies haben"
        
        # Test 3: UserRoles Many-to-Many
        $userRolesValid = $adapter.ExecuteQuery("SELECT COUNT(*) as Count FROM UserRoles ur JOIN Users u ON ur.UserID = u.UserID JOIN Roles r ON ur.RoleID = r.RoleID", @{})
        $totalUserRoles = $adapter.ExecuteQuery("SELECT COUNT(*) as Count FROM UserRoles", @{})
        Assert-Equal -Expected $totalUserRoles[0].Count -Actual $userRolesValid[0].Count -Message "Alle UserRoles sollten gültige Users und Roles haben"
        
        return @{ Success = $true; Message = "Foreign Key Relationships erfolgreich getestet" }
        
    } catch {
        return @{ Success = $false; Message = "Foreign Key Relationships Test fehlgeschlagen: $_" }
    }
})

# Test 4: Self-References testen
$suite.AddTest("Self-References", {
    param($context)
    
    try {
        # Test-Datenbank Pfad erstellen (OHNE automatisches Schema aus Database-TestHelpers)
        $testDataDir = Get-TestDataDirectory -Category "unit"
        $dbPath = Join-Path $testDataDir "self_ref_test-$(Get-Random).db"
        $context.AddCleanup({ if ($dbPath -and (Test-Path $dbPath)) { Remove-Item $dbPath -Force -ErrorAction SilentlyContinue } })
        
        # Schema erstellen
        $schemaQueries = Get-ComplexDatabaseSchema -SchemaType "full"
        foreach ($query in $schemaQueries) {
            $query | sqlite3 $dbPath | Out-Null
        }
        
        $connString = "Data Source=$dbPath"
        
        # Test-Daten einfügen
        Initialize-ComplexTestData -Connection $connString -DataSize "small"
        
        $adapter = New-DatabaseAdapter -ConnectionString $connString
        
        # Test 1: User Manager Self-Reference
        $usersWithManagers = $adapter.ExecuteQuery("SELECT u.UserID, u.Username, m.Username as ManagerName FROM Users u LEFT JOIN Users m ON u.ManagerUserID = m.UserID WHERE u.ManagerUserID IS NOT NULL", @{})
        Assert-True -Condition $usersWithManagers.Count -gt 0 -Message "Einige Users sollten Manager haben"
        
        # Test 2: Department Parent Self-Reference
        $departmentsWithParents = $adapter.ExecuteQuery("SELECT d.DepartmentID, d.DepartmentName, p.DepartmentName as ParentDepartment FROM Departments d LEFT JOIN Departments p ON d.ParentDepartmentID = p.DepartmentID WHERE d.ParentDepartmentID IS NOT NULL", @{})
        # Es können Departments ohne Parent geben, das ist OK
        
        # Test 3: Keine zirkulären Referenzen
        $circularUsers = $adapter.ExecuteQuery("SELECT u1.UserID FROM Users u1 JOIN Users u2 ON u1.ManagerUserID = u2.UserID WHERE u2.ManagerUserID = u1.UserID", @{})
        Assert-Equal -Expected 0 -Actual $circularUsers.Count -Message "Keine zirkulären Manager-Referenzen sollten existieren"
        
        # Test 4: Manager-Hierarchie Tiefe
        $managerHierarchy = $adapter.ExecuteQuery(@"
WITH RECURSIVE manager_hierarchy AS (
    SELECT UserID, ManagerUserID, Username, 0 as level 
    FROM Users 
    WHERE ManagerUserID IS NULL
    UNION ALL
    SELECT u.UserID, u.ManagerUserID, u.Username, mh.level + 1
    FROM Users u
    JOIN manager_hierarchy mh ON u.ManagerUserID = mh.UserID
    WHERE mh.level < 5
)
SELECT MAX(level) as MaxLevel FROM manager_hierarchy
"@, @{})
        
        $maxLevel = if ($managerHierarchy[0].MaxLevel) { [int]$managerHierarchy[0].MaxLevel } else { 0 }
        Assert-True -Condition $maxLevel -le 4 -Message "Manager-Hierarchie sollte nicht zu tief sein (Max 4 Ebenen)"
        
        return @{ Success = $true; Message = "Self-References erfolgreich getestet (Manager-Hierarchie: $maxLevel Ebenen)" }
        
    } catch {
        return @{ Success = $false; Message = "Self-References Test fehlgeschlagen: $_" }
    }
})

# Test 5: Many-to-Many Beziehungen
$suite.AddTest("Many-to-Many-Relationships", {
    param($context)
    
    try {
        # Test-Datenbank Pfad erstellen (OHNE automatisches Schema aus Database-TestHelpers)
        $testDataDir = Get-TestDataDirectory -Category "unit"
        $dbPath = Join-Path $testDataDir "m2m_test-$(Get-Random).db"
        $context.AddCleanup({ if ($dbPath -and (Test-Path $dbPath)) { Remove-Item $dbPath -Force -ErrorAction SilentlyContinue } })
        
        # Schema erstellen
        $schemaQueries = Get-ComplexDatabaseSchema -SchemaType "full"
        foreach ($query in $schemaQueries) {
            $query | sqlite3 $dbPath | Out-Null
        }
        
        $connString = "Data Source=$dbPath"
        $adapter = New-DatabaseAdapter -ConnectionString $connString
        
        # Test-Daten einfügen (UserRoles wird automatisch erstellt)
        Initialize-ComplexTestData -Connection $connString -DataSize "small"
        
        # Zusätzliche Skills und UserSkills erstellen
        $skills = @(
            @{ SkillID = 1; SkillName = "JavaScript"; SkillCategory = "Programming" },
            @{ SkillID = 2; SkillName = "Python"; SkillCategory = "Programming" },
            @{ SkillID = 3; SkillName = "SQL"; SkillCategory = "Database" },
            @{ SkillID = 4; SkillName = "Project Management"; SkillCategory = "Management" },
            @{ SkillID = 5; SkillName = "Communication"; SkillCategory = "Soft Skills" }
        )
        
        foreach ($skill in $skills) {
            $query = "INSERT INTO Skills (SkillID, SkillName, SkillCategory) VALUES (@SkillID, @SkillName, @SkillCategory)"
            $adapter.ExecuteNonQuery($query, $skill) | Out-Null
        }
        
        # UserSkills erstellen (Many-to-Many zwischen Users und Skills)
        $users = $adapter.ExecuteQuery("SELECT UserID FROM Users LIMIT 10", @{})
        $userSkillId = 1
        
        foreach ($user in $users) {
            # Jeder User bekommt 2-4 zufällige Skills
            $skillCount = Get-Random -Minimum 2 -Maximum 5
            $assignedSkills = @()
            
            for ($s = 1; $s -le $skillCount; $s++) {
                $skillId = Get-Random -Minimum 1 -Maximum $skills.Count + 1
                if ($assignedSkills -notcontains $skillId) {
                    $assignedSkills += $skillId
                    
                    $userSkill = @{
                        UserSkillID = $userSkillId
                        UserID = $user.UserID
                        SkillID = $skillId
                        SkillLevel = Get-Random -Minimum 1 -Maximum 6
                        YearsExperience = (Get-Random -Maximum 10) + (Get-Random -Maximum 100) / 100.0
                        LastAssessedDate = (Get-Date).AddDays(-(Get-Random -Maximum 365)).ToString("yyyy-MM-dd")
                    }
                    $userSkillId++
                    
                    $query = "INSERT INTO UserSkills (UserSkillID, UserID, SkillID, SkillLevel, YearsExperience, LastAssessedDate) VALUES (@UserSkillID, @UserID, @SkillID, @SkillLevel, @YearsExperience, @LastAssessedDate)"
                    $adapter.ExecuteNonQuery($query, $userSkill) | Out-Null
                }
            }
        }
        
        # Tests für Many-to-Many Beziehungen
        
        # Test 1: UserRoles (automatisch erstellt)
        $userRoleStats = $adapter.ExecuteQuery("SELECT COUNT(*) as TotalAssignments, COUNT(DISTINCT UserID) as UniqueUsers, COUNT(DISTINCT RoleID) as UniqueRoles FROM UserRoles", @{})
        Assert-True -Condition [int]$userRoleStats[0].TotalAssignments -gt 0 -Message "UserRoles sollten existieren"
        Assert-True -Condition [int]$userRoleStats[0].UniqueUsers -gt 0 -Message "Mehrere Users sollten Rollen haben"
        Assert-True -Condition [int]$userRoleStats[0].UniqueRoles -gt 0 -Message "Mehrere Rollen sollten zugewiesen sein"
        
        # Test 2: UserSkills 
        $userSkillStats = $adapter.ExecuteQuery("SELECT COUNT(*) as TotalAssignments, COUNT(DISTINCT UserID) as UniqueUsers, COUNT(DISTINCT SkillID) as UniqueSkills FROM UserSkills", @{})
        Assert-True -Condition [int]$userSkillStats[0].TotalAssignments -gt 0 -Message "UserSkills sollten existieren"
        Assert-True -Condition [int]$userSkillStats[0].UniqueUsers -gt 0 -Message "Mehrere Users sollten Skills haben"
        Assert-True -Condition [int]$userSkillStats[0].UniqueSkills -gt 0 -Message "Mehrere Skills sollten zugewiesen sein"
        
        # Test 3: Keine Duplikate in Many-to-Many Tabellen
        $duplicateUserRoles = $adapter.ExecuteQuery("SELECT UserID, RoleID, COUNT(*) as Count FROM UserRoles GROUP BY UserID, RoleID HAVING COUNT(*) > 1", @{})
        Assert-Equal -Expected 0 -Actual $duplicateUserRoles.Count -Message "Keine Duplikate in UserRoles sollten existieren"
        
        $duplicateUserSkills = $adapter.ExecuteQuery("SELECT UserID, SkillID, COUNT(*) as Count FROM UserSkills GROUP BY UserID, SkillID HAVING COUNT(*) > 1", @{})
        Assert-Equal -Expected 0 -Actual $duplicateUserSkills.Count -Message "Keine Duplikate in UserSkills sollten existieren"
        
        # Test 4: Complex Join über Many-to-Many
        $userSkillsJoin = $adapter.ExecuteQuery(@"
SELECT u.Username, s.SkillName, us.SkillLevel, us.YearsExperience
FROM Users u
JOIN UserSkills us ON u.UserID = us.UserID
JOIN Skills s ON us.SkillID = s.SkillID
ORDER BY u.Username, s.SkillName
LIMIT 5
"@, @{})
        Assert-True -Condition $userSkillsJoin.Count -gt 0 -Message "Complex Many-to-Many Join sollte Ergebnisse liefern"
        
        return @{ Success = $true; Message = "Many-to-Many Relationships erfolgreich getestet (UserRoles: $($userRoleStats[0].TotalAssignments), UserSkills: $($userSkillStats[0].TotalAssignments))" }
        
    } catch {
        return @{ Success = $false; Message = "Many-to-Many Relationships Test fehlgeschlagen: $_" }
    }
})

# Test 6: Views und komplexe Queries
$suite.AddTest("Views-and-Complex-Queries", {
    param($context)
    
    try {
        # Test-Datenbank Pfad erstellen (OHNE automatisches Schema aus Database-TestHelpers)
        $testDataDir = Get-TestDataDirectory -Category "unit"
        $dbPath = Join-Path $testDataDir "views_test-$(Get-Random).db"
        $context.AddCleanup({ if ($dbPath -and (Test-Path $dbPath)) { Remove-Item $dbPath -Force -ErrorAction SilentlyContinue } })
        
        # Schema erstellen
        $schemaQueries = Get-ComplexDatabaseSchema -SchemaType "full"
        foreach ($query in $schemaQueries) {
            $query | sqlite3 $dbPath | Out-Null
        }
        
        $connString = "Data Source=$dbPath"
        $adapter = New-DatabaseAdapter -ConnectionString $connString
        
        # Test-Daten einfügen
        Initialize-ComplexTestData -Connection $connString -DataSize "small"
        
        # Test 1: UserHierarchy View
        $userHierarchy = $adapter.ExecuteQuery("SELECT * FROM UserHierarchy WHERE ManagerName IS NOT NULL LIMIT 5", @{})
        Assert-True -Condition $userHierarchy.Count -gt 0 -Message "UserHierarchy View sollte Daten liefern"
        
        # Prüfen ob alle erwarteten Spalten vorhanden sind
        $expectedColumns = @("UserID", "Username", "FullName", "JobTitle", "TeamName", "DepartmentName", "CompanyName", "ManagerName")
        foreach ($col in $expectedColumns) {
            Assert-HasProperty -Object $userHierarchy[0] -PropertyName $col -Message "UserHierarchy sollte Spalte '$col' haben"
        }
        
        # Test 2: Komplexe Query - Mitarbeiter pro Department
        $deptStats = $adapter.ExecuteQuery(@"
SELECT 
    d.DepartmentName,
    c.CompanyName,
    COUNT(u.UserID) as EmployeeCount,
    AVG(u.Salary) as AvgSalary,
    MAX(u.Salary) as MaxSalary,
    MIN(u.Salary) as MinSalary
FROM Departments d
JOIN Companies c ON d.CompanyID = c.CompanyID
LEFT JOIN Teams t ON d.DepartmentID = t.DepartmentID
LEFT JOIN Users u ON t.TeamID = u.TeamID
GROUP BY d.DepartmentID, d.DepartmentName, c.CompanyName
HAVING COUNT(u.UserID) > 0
ORDER BY EmployeeCount DESC
"@, @{})
        
        Assert-True -Condition $deptStats.Count -gt 0 -Message "Department Statistics Query sollte Ergebnisse liefern"
        
        foreach ($stat in $deptStats) {
            Assert-True -Condition [int]$stat.EmployeeCount -gt 0 -Message "Jedes Department sollte mindestens einen Mitarbeiter haben"
            Assert-True -Condition [double]$stat.AvgSalary -gt 0 -Message "Durchschnittsgehalt sollte positiv sein"
        }
        
        # Test 3: Hierarchie-Query - Manager mit ihren Mitarbeitern
        $managerTeams = $adapter.ExecuteQuery(@"
SELECT 
    m.Username as ManagerName,
    m.JobTitle as ManagerTitle,
    COUNT(u.UserID) as TeamSize,
    AVG(u.Salary) as AvgTeamSalary
FROM Users m
JOIN Users u ON m.UserID = u.ManagerUserID
GROUP BY m.UserID, m.Username, m.JobTitle
ORDER BY TeamSize DESC
"@, @{})
        
        if ($managerTeams.Count -gt 0) {
            Assert-True -Condition [int]$managerTeams[0].TeamSize -gt 0 -Message "Top Manager sollte mindestens einen Mitarbeiter haben"
        }
        
        # Test 4: Role Distribution Query
        $roleDistribution = $adapter.ExecuteQuery(@"
SELECT 
    r.RoleName,
    COUNT(ur.UserID) as UserCount,
    ROUND(COUNT(ur.UserID) * 100.0 / (SELECT COUNT(*) FROM UserRoles), 2) as Percentage
FROM Roles r
LEFT JOIN UserRoles ur ON r.RoleID = ur.RoleID
GROUP BY r.RoleID, r.RoleName
ORDER BY UserCount DESC
"@, @{})
        
        Assert-True -Condition $roleDistribution.Count -gt 0 -Message "Role Distribution Query sollte Ergebnisse liefern"
        
        $totalPercentage = ($roleDistribution | ForEach-Object { [double]$_.Percentage } | Measure-Object -Sum).Sum
        Assert-True -Condition $totalPercentage -gt 90 -Message "Gesamtprozentsatz sollte nahe 100% sein"
        
        return @{ Success = $true; Message = "Views and Complex Queries erfolgreich getestet (UserHierarchy: $($userHierarchy.Count), DeptStats: $($deptStats.Count), Roles: $($roleDistribution.Count))" }
        
    } catch {
        return @{ Success = $false; Message = "Views and Complex Queries Test fehlgeschlagen: $_" }
    }
})

# Test 7: Performance mit komplexen Daten
$suite.AddTest("Complex-Database-Performance", {
    param($context)
    
    try {
        # Test-Datenbank Pfad erstellen (OHNE automatisches Schema aus Database-TestHelpers)
        $testDataDir = Get-TestDataDirectory -Category "performance"
        $dbPath = Join-Path $testDataDir "performance_test-$(Get-Random).db"
        $context.AddCleanup({ if ($dbPath -and (Test-Path $dbPath)) { Remove-Item $dbPath -Force -ErrorAction SilentlyContinue } })
        
        # Schema erstellen
        $schemaQueries = Get-ComplexDatabaseSchema -SchemaType "full"
        foreach ($query in $schemaQueries) {
            $query | sqlite3 $dbPath | Out-Null
        }
        
        $connString = "Data Source=$dbPath"
        
        # Performance messen - Schema Setup
        $setupMeasurement = Measure-DatabaseOperation -OperationName "Complex-Data-Setup" -Operation {
            Initialize-ComplexTestData -Connection $connString -DataSize "medium"
        }
        
        Assert-True -Condition $setupMeasurement.Success -Message "Complex Data Setup sollte erfolgreich sein"
        Assert-True -Condition $setupMeasurement.Duration.TotalSeconds -lt 30 -Message "Data Setup sollte unter 30 Sekunden dauern"
        
        # Performance messen - Complex Query
        $queryMeasurement = Measure-DatabaseOperation -OperationName "Complex-Query" -Operation {
            $adapter = New-DatabaseAdapter -ConnectionString $connString
            $adapter.ExecuteQuery(@"
SELECT 
    c.CompanyName,
    d.DepartmentName,
    COUNT(DISTINCT u.UserID) as EmployeeCount,
    COUNT(DISTINCT ur.RoleID) as UniqueRoles,
    AVG(u.Salary) as AvgSalary,
    COUNT(DISTINCT t.TeamID) as TeamCount
FROM Companies c
JOIN Departments d ON c.CompanyID = d.CompanyID
JOIN Teams t ON d.DepartmentID = t.DepartmentID
JOIN Users u ON t.TeamID = u.TeamID
LEFT JOIN UserRoles ur ON u.UserID = ur.UserID
GROUP BY c.CompanyID, c.CompanyName, d.DepartmentID, d.DepartmentName
ORDER BY EmployeeCount DESC, AvgSalary DESC
"@, @{})
        }
        
        Assert-True -Condition $queryMeasurement.Success -Message "Complex Query sollte erfolgreich sein"
        Assert-True -Condition $queryMeasurement.Duration.TotalSeconds -lt 5 -Message "Complex Query sollte unter 5 Sekunden dauern"
        
        $result = $queryMeasurement.Result
        Assert-True -Condition $result.Count -gt 0 -Message "Complex Query sollte Ergebnisse liefern"
        
        return @{ Success = $true; Message = "Complex Database Performance erfolgreich getestet (Setup: $(($setupMeasurement.Duration.TotalMilliseconds).ToString('F0'))ms, Query: $(($queryMeasurement.Duration.TotalMilliseconds).ToString('F0'))ms, Results: $($result.Count))" }
        
    } catch {
        return @{ Success = $false; Message = "Complex Database Performance Test fehlgeschlagen: $_" }
    }
})

# Test-Suite ausführen
try {
    Write-Host "`n🧪 Unit Tests: Complex Database" -ForegroundColor Cyan
    Write-Host "=" * 60 -ForegroundColor Gray
    
    $results = $suite.Run()
    
    # Ergebnisse anzeigen
    Write-Host "`nErgebnisse:" -ForegroundColor White
    Write-Host "  Gesamt: $($results.Total) Tests" -ForegroundColor Gray
    Write-Host "  ✅ Bestanden: $($results.Passed)" -ForegroundColor Green
    Write-Host "  ❌ Fehlgeschlagen: $($results.Failed)" -ForegroundColor Red
    Write-Host "  ⏱️ Dauer: $($results.Duration.ToString('mm\:ss\.fff'))" -ForegroundColor Gray
    
    # Detaillierte Ergebnisse
    foreach ($result in $results.Results) {
        $icon = if ($result.Success) { "✅" } else { "❌" }
        $color = if ($result.Success) { "Green" } else { "Red" }
        Write-Host "  $icon $($result.TestName)" -ForegroundColor $color
        
        if (-not $result.Success) {
            Write-Host "    Error: $($result.ErrorMessage)" -ForegroundColor Yellow
        }
    }
    
    $success = $results.Failed -eq 0
    
    if ($success) {
        Write-Host "`n🎉 Alle Complex Database Tests bestanden!" -ForegroundColor Green
    } else {
        Write-Host "`n⚠️ $($results.Failed) Test(s) fehlgeschlagen" -ForegroundColor Yellow
    }
    
    return @{
        Success = $success
        Message = "Complex Database: $($results.Passed)/$($results.Total) Tests bestanden"
        Results = $results
    }
    
} catch {
    Write-Host "`n❌ Kritischer Fehler in Complex Database Tests: $_" -ForegroundColor Red
    return @{
        Success = $false
        Message = "Kritischer Fehler: $_"
    }
} finally {
    # Cleanup
    Clear-AllMocks
    Clear-TestData
}