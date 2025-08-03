# SyncRay Test Framework - Gemeinsame Test-Utilities und Assertion-Funktionen
# Bietet umfassende Test-Infrastruktur für Unit-, Integration-, Performance- und Security-Tests

# Test-Framework Konfiguration
$Global:TestFramework = @{
    Version = "1.0.0"
    DefaultTimeout = 30
    VerboseOutput = $false
    StrictMode = $true
    TestDataDirectory = $null
    TempDirectory = $null
    Configuration = $null
}

# Test-Kontext für jeden Test
class TestContext {
    [string]$TestName
    [string]$Category  
    [string]$Module
    [hashtable]$Data
    [System.Collections.ArrayList]$Cleanup
    [datetime]$StartTime
    [timespan]$Duration
    [bool]$Success
    [string]$ErrorMessage
    [hashtable]$Metadata
    
    TestContext([string]$name, [string]$category, [string]$module) {
        $this.TestName = $name
        $this.Category = $category
        $this.Module = $module
        $this.Data = @{}
        $this.Cleanup = [System.Collections.ArrayList]::new()
        $this.StartTime = Get-Date
        $this.Success = $false
        $this.Metadata = @{}
    }
    
    [void]AddCleanup([scriptblock]$action) {
        $this.Cleanup.Add($action) | Out-Null
    }
    
    [void]RunCleanup() {
        foreach ($action in $this.Cleanup) {
            try {
                & $action
            } catch {
                Write-Warning "Cleanup-Fehler in $($this.TestName): $_"
            }
        }
    }
    
    [void]Complete([bool]$success, [string]$message = "") {
        $this.Success = $success
        $this.ErrorMessage = $message
        $this.Duration = (Get-Date) - $this.StartTime
    }
}

# Test-Suite Klasse
class TestSuite {
    [string]$Name
    [string]$Category
    [string]$Module
    [System.Collections.ArrayList]$Tests
    [hashtable]$Configuration
    [hashtable]$SharedData
    
    TestSuite([string]$name, [string]$category, [string]$module) {
        $this.Name = $name
        $this.Category = $category
        $this.Module = $module
        $this.Tests = [System.Collections.ArrayList]::new()
        $this.Configuration = @{}
        $this.SharedData = @{}
    }
    
    [TestContext]AddTest([string]$testName, [scriptblock]$testAction) {
        $context = [TestContext]::new($testName, $this.Category, $this.Module)
        $this.Tests.Add(@{
            Context = $context
            Action = $testAction
        }) | Out-Null
        return $context
    }
    
    [hashtable]Run() {
        $results = @{
            SuiteName = $this.Name
            Category = $this.Category
            Module = $this.Module
            Total = $this.Tests.Count
            Passed = 0
            Failed = 0
            Skipped = 0
            Results = @()
            Duration = [timespan]::Zero
        }
        
        $suiteStart = Get-Date
        
        foreach ($test in $this.Tests) {
            $context = $test.Context
            $action = $test.Action
            
            try {
                Write-Verbose "Ausführung: $($context.TestName)"
                
                # Test ausführen
                $testResult = & $action $context
                
                if ($testResult -is [bool]) {
                    $context.Complete($testResult)
                } elseif ($testResult -is [hashtable]) {
                    $context.Complete($testResult.Success, $testResult.Message)
                } else {
                    $context.Complete($true, "Test abgeschlossen")
                }
                
                if ($context.Success) {
                    $results.Passed++
                } else {
                    $results.Failed++
                }
                
            } catch {
                $context.Complete($false, $_.Exception.Message)
                $results.Failed++
                Write-Verbose "Test-Fehler: $_"
            } finally {
                $context.RunCleanup()
            }
            
            $results.Results += $context
        }
        
        $results.Duration = (Get-Date) - $suiteStart
        return $results
    }
}

# Assertion-Funktionen
function Assert-True {
    param([bool]$Condition, [string]$Message = "Assertion fehlgeschlagen")
    
    if (-not $Condition) {
        throw "Assert-True: $Message"
    }
}

function Assert-False {
    param([bool]$Condition, [string]$Message = "Assertion fehlgeschlagen")
    
    if ($Condition) {
        throw "Assert-False: $Message"
    }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message = "Werte sind nicht gleich")
    
    if ($Expected -ne $Actual) {
        throw "Assert-Equal: $Message. Erwartet: '$Expected', Tatsächlich: '$Actual'"
    }
}

function Assert-NotEqual {
    param($Expected, $Actual, [string]$Message = "Werte sind gleich")
    
    if ($Expected -eq $Actual) {
        throw "Assert-NotEqual: $Message. Beide Werte: '$Expected'"
    }
}

function Assert-Null {
    param($Value, [string]$Message = "Wert ist nicht null")
    
    if ($null -ne $Value) {
        throw "Assert-Null: $Message. Wert: '$Value'"
    }
}

function Assert-NotNull {
    param($Value, [string]$Message = "Wert ist null")
    
    if ($null -eq $Value) {
        throw "Assert-NotNull: $Message"
    }
}

function Assert-Contains {
    param($Collection, $Item, [string]$Message = "Element nicht in Collection gefunden")
    
    if ($Collection -notcontains $Item) {
        throw "Assert-Contains: $Message. Item: '$Item'"
    }
}

function Assert-NotContains {
    param($Collection, $Item, [string]$Message = "Element in Collection gefunden")
    
    if ($Collection -contains $Item) {
        throw "Assert-NotContains: $Message. Item: '$Item'"
    }
}

function Assert-Match {
    param([string]$String, [string]$Pattern, [string]$Message = "String entspricht nicht dem Pattern")
    
    if ($String -notmatch $Pattern) {
        throw "Assert-Match: $Message. String: '$String', Pattern: '$Pattern'"
    }
}

function Assert-NotMatch {
    param([string]$String, [string]$Pattern, [string]$Message = "String entspricht dem Pattern")
    
    if ($String -match $Pattern) {
        throw "Assert-NotMatch: $Message. String: '$String', Pattern: '$Pattern'"
    }
}

function Assert-FileExists {
    param([string]$Path, [string]$Message = "Datei existiert nicht")
    
    if (-not (Test-Path $Path -PathType Leaf)) {
        throw "Assert-FileExists: $Message. Pfad: '$Path'"
    }
}

function Assert-DirectoryExists {
    param([string]$Path, [string]$Message = "Verzeichnis existiert nicht")
    
    if (-not (Test-Path $Path -PathType Container)) {
        throw "Assert-DirectoryExists: $Message. Pfad: '$Path'"
    }
}

function Assert-Throws {
    param([scriptblock]$ScriptBlock, [string]$ExpectedMessage = "", [string]$Message = "Erwartete Exception wurde nicht geworfen")
    
    $threwException = $false
    $actualMessage = ""
    
    try {
        & $ScriptBlock
    } catch {
        $threwException = $true
        $actualMessage = $_.Exception.Message
    }
    
    if (-not $threwException) {
        throw "Assert-Throws: $Message"
    }
    
    if ($ExpectedMessage -and $actualMessage -notlike "*$ExpectedMessage*") {
        throw "Assert-Throws: Exception-Message entspricht nicht der Erwartung. Erwartet: '$ExpectedMessage', Tatsächlich: '$actualMessage'"
    }
}

function Assert-DoesNotThrow {
    param([scriptblock]$ScriptBlock, [string]$Message = "Unerwartete Exception geworfen")
    
    try {
        & $ScriptBlock
    } catch {
        throw "Assert-DoesNotThrow: $Message. Exception: $($_.Exception.Message)"
    }
}

function Assert-Performance {
    param([scriptblock]$ScriptBlock, [timespan]$MaxDuration, [string]$Message = "Performance-Anforderung nicht erfüllt")
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        & $ScriptBlock
    } finally {
        $stopwatch.Stop()
    }
    
    if ($stopwatch.Elapsed -gt $MaxDuration) {
        throw "Assert-Performance: $Message. Dauer: $($stopwatch.Elapsed), Maximum: $MaxDuration"
    }
}

function Assert-MemoryUsage {
    param([scriptblock]$ScriptBlock, [long]$MaxMemoryMB, [string]$Message = "Speicher-Anforderung nicht erfüllt")
    
    $initialMemory = [System.GC]::GetTotalMemory($false)
    
    try {
        & $ScriptBlock
    } finally {
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        [System.GC]::Collect()
    }
    
    $finalMemory = [System.GC]::GetTotalMemory($false)
    $usedMemoryMB = [math]::Round(($finalMemory - $initialMemory) / 1MB, 2)
    
    if ($usedMemoryMB -gt $MaxMemoryMB) {
        throw "Assert-MemoryUsage: $Message. Verwendet: ${usedMemoryMB}MB, Maximum: ${MaxMemoryMB}MB"
    }
}

# SQL-spezifische Assertions
function Assert-SqlResult {
    param($Connection, [string]$Query, $ExpectedResult, [string]$Message = "SQL-Ergebnis entspricht nicht der Erwartung")
    
    try {
        $result = Invoke-SqlQuery -Connection $Connection -Query $Query
        Assert-Equal -Expected $ExpectedResult -Actual $result -Message $Message
    } catch {
        throw "Assert-SqlResult: Fehler bei SQL-Ausführung: $_"
    }
}

function Assert-TableExists {
    param($Connection, [string]$TableName, [string]$Message = "Tabelle existiert nicht")
    
    $query = if (Test-IsSQLite -Connection $Connection) {
        "SELECT name FROM sqlite_master WHERE type='table' AND name='$TableName'"
    } else {
        "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = '$TableName'"
    }
    
    $result = Invoke-SqlQuery -Connection $Connection -Query $query
    
    if (-not $result) {
        throw "Assert-TableExists: $Message. Tabelle: '$TableName'"
    }
}

function Assert-ColumnExists {
    param($Connection, [string]$TableName, [string]$ColumnName, [string]$Message = "Spalte existiert nicht")
    
    $query = if (Test-IsSQLite -Connection $Connection) {
        "PRAGMA table_info($TableName)"
    } else {
        "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = '$TableName' AND COLUMN_NAME = '$ColumnName'"
    }
    
    $result = Invoke-SqlQuery -Connection $Connection -Query $query
    
    $columnExists = if (Test-IsSQLite -Connection $Connection) {
        $result | Where-Object { $_.name -eq $ColumnName }
    } else {
        $result
    }
    
    if (-not $columnExists) {
        throw "Assert-ColumnExists: $Message. Tabelle: '$TableName', Spalte: '$ColumnName'"
    }
}

function Assert-RecordCount {
    param($Connection, [string]$TableName, [int]$ExpectedCount, [string]$WhereClause = "", [string]$Message = "Datensatz-Anzahl entspricht nicht der Erwartung")
    
    $query = "SELECT COUNT(*) as RecordCount FROM $TableName"
    if ($WhereClause) {
        $query += " WHERE $WhereClause"
    }
    
    $result = Invoke-SqlQuery -Connection $Connection -Query $query
    $actualCount = $result.RecordCount
    
    Assert-Equal -Expected $ExpectedCount -Actual $actualCount -Message "$Message. Tabelle: '$TableName'"
}

# Hilfsfunktionen für Test-Setup
function New-TestSuite {
    param([string]$Name, [string]$Category, [string]$Module)
    
    return [TestSuite]::new($Name, $Category, $Module)
}

function Initialize-TestFramework {
    param([string]$ConfigPath, [string]$TempDirectory = $null)
    
    if ($ConfigPath -and (Test-Path $ConfigPath)) {
        $Global:TestFramework.Configuration = Get-Content $ConfigPath | ConvertFrom-Json
    }
    
    # Finde Test-Root-Verzeichnis
    $scriptPath = if ($MyInvocation.PSScriptRoot) { $MyInvocation.PSScriptRoot } else { $PSScriptRoot }
    if (-not $scriptPath) {
        $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    $testRoot = $scriptPath
    while ($testRoot -and -not (Test-Path (Join-Path $testRoot "TestAll.ps1"))) {
        $testRoot = Split-Path -Parent $testRoot
    }
    
    if (-not $testRoot) {
        # Fallback: Verwende aktuelles Verzeichnis
        $testRoot = Get-Location
    }
    
    # NUR lokales Test-Data-Verzeichnis verwenden - NIEMALS System-Temp!
    if ($TempDirectory) {
        # Prüfen ob absoluter Pfad - wenn nicht, relativ zu testRoot machen
        if ([System.IO.Path]::IsPathRooted($TempDirectory)) {
            $Global:TestFramework.TempDirectory = $TempDirectory
        } else {
            $Global:TestFramework.TempDirectory = Join-Path $testRoot $TempDirectory
        }
    } else {
        $Global:TestFramework.TempDirectory = Join-Path $testRoot "test-data" "temp"
    }
    
    # Sicherstellen dass das Verzeichnis existiert
    if (-not (Test-Path $Global:TestFramework.TempDirectory)) {
        New-Item -ItemType Directory -Path $Global:TestFramework.TempDirectory -Force | Out-Null
    }
    
    # Test-Session-Verzeichnis erstellen
    $testDataPath = Join-Path $Global:TestFramework.TempDirectory "syncray-session-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    New-Item -ItemType Directory -Path $testDataPath -Force | Out-Null
    $Global:TestFramework.TestDataDirectory = $testDataPath
    
    Write-Verbose "Test-Framework initialisiert. Test-Daten: $testDataPath"
}

function Get-TestTempDirectory {
    if (-not $Global:TestFramework.TestDataDirectory) {
        Initialize-TestFramework
    }
    return $Global:TestFramework.TestDataDirectory
}

function Get-TestDataDirectory {
    param([string]$Category = "temp")
    
    if (-not $Global:TestFramework.TestDataDirectory) {
        Initialize-TestFramework
    }
    
    # Finde Test-Root
    $scriptPath = if ($MyInvocation.PSScriptRoot) { $MyInvocation.PSScriptRoot } else { $PSScriptRoot }
    if (-not $scriptPath) {
        $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    $testRoot = $scriptPath
    while ($testRoot -and -not (Test-Path (Join-Path $testRoot "TestAll.ps1"))) {
        $testRoot = Split-Path -Parent $testRoot
    }
    
    if (-not $testRoot) {
        $testRoot = Get-Location
    }
    
    $testDataDir = Join-Path $testRoot "test-data" $Category
    if (-not (Test-Path $testDataDir)) {
        New-Item -ItemType Directory -Path $testDataDir -Force | Out-Null
    }
    
    return $testDataDir
}

function New-TestDatabase {
    param(
        [string]$Name,
        [string]$Category = "unit",
        [string]$Extension = ".db"
    )
    
    $testDataDir = Get-TestDataDirectory -Category $Category
    $dbPath = Join-Path $testDataDir "$Name-$(Get-Random)$Extension"
    
    return $dbPath
}

function Clear-TestData {
    if ($Global:TestFramework.TestDataDirectory -and (Test-Path $Global:TestFramework.TestDataDirectory)) {
        try {
            Remove-Item -Path $Global:TestFramework.TestDataDirectory -Recurse -Force
            Write-Verbose "Test-Daten gelöscht: $($Global:TestFramework.TestDataDirectory)"
        } catch {
            Write-Warning "Fehler beim Löschen der Test-Daten: $_"
        }
    }
}

# Mock-Framework für Funktionen
$Global:MockRegistry = @{}

function Mock-Function {
    param([string]$FunctionName, [scriptblock]$MockImplementation)
    
    if (-not $Global:MockRegistry.ContainsKey($FunctionName)) {
        $Global:MockRegistry[$FunctionName] = @{
            OriginalFunction = Get-Command $FunctionName -ErrorAction SilentlyContinue
            MockImplementation = $MockImplementation
            CallCount = 0
            CallHistory = @()
        }
    } else {
        $Global:MockRegistry[$FunctionName].MockImplementation = $MockImplementation
    }
    
    # Dynamische Mock-Funktion erstellen
    $mockScript = {
        param($args)
        $Global:MockRegistry[$FunctionName].CallCount++
        $Global:MockRegistry[$FunctionName].CallHistory += @{
            Timestamp = Get-Date
            Arguments = $args
        }
        & $Global:MockRegistry[$FunctionName].MockImplementation @args
    }.GetNewClosure()
    
    Set-Item -Path "Function:\$FunctionName" -Value $mockScript
}

function Restore-Function {
    param([string]$FunctionName)
    
    if ($Global:MockRegistry.ContainsKey($FunctionName)) {
        $original = $Global:MockRegistry[$FunctionName].OriginalFunction
        if ($original) {
            Set-Item -Path "Function:\$FunctionName" -Value $original.ScriptBlock
        } else {
            Remove-Item -Path "Function:\$FunctionName" -ErrorAction SilentlyContinue
        }
        $Global:MockRegistry.Remove($FunctionName)
    }
}

function Get-MockCallCount {
    param([string]$FunctionName)
    
    if ($Global:MockRegistry.ContainsKey($FunctionName)) {
        return $Global:MockRegistry[$FunctionName].CallCount
    }
    return 0
}

function Get-MockCallHistory {
    param([string]$FunctionName)
    
    if ($Global:MockRegistry.ContainsKey($FunctionName)) {
        return $Global:MockRegistry[$FunctionName].CallHistory
    }
    return @()
}

function Clear-AllMocks {
    foreach ($functionName in $Global:MockRegistry.Keys) {
        Restore-Function -FunctionName $functionName
    }
    $Global:MockRegistry.Clear()
}

# Utility-Funktionen für Tests
function Invoke-WithTimeout {
    param([scriptblock]$ScriptBlock, [int]$TimeoutSeconds = 30)
    
    $job = Start-Job -ScriptBlock $ScriptBlock
    $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds
    
    if ($completed) {
        $result = Receive-Job -Job $job
        Remove-Job -Job $job
        return $result
    } else {
        Stop-Job -Job $job
        Remove-Job -Job $job
        throw "Operation timed out after $TimeoutSeconds seconds"
    }
}

function Test-IsRunningInCI {
    return ($env:CI -eq "true") -or ($env:GITHUB_ACTIONS -eq "true") -or ($env:BUILD_ID -ne $null)
}

function Get-RandomTestName {
    param([string]$Prefix = "Test")
    return "$Prefix-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$(Get-Random -Maximum 9999)"
}

# Test-Daten Generatoren
function New-TestUser {
    param([int]$Id, [string]$Prefix = "TestUser")
    
    return @{
        UserID = $Id
        Username = "$Prefix$Id"
        Email = "$Prefix$Id@test.local"
        FirstName = "Test"
        LastName = "User$Id"
        IsActive = 1
        Salary = 50000 + ($Id * 1000)
        Department = @("IT", "Sales", "HR", "Finance")[$Id % 4]
        Manager = if ($Id -gt 1) { $Id - 1 } else { $null }
        Settings = @{ theme = "dark"; language = "de" } | ConvertTo-Json -Compress
    }
}

function New-TestProduct {
    param([int]$Id, [string]$Prefix = "TestProduct")
    
    return @{
        ProductID = $Id
        ProductCode = "$Prefix-$('{0:D4}' -f $Id)"
        ProductName = "$Prefix $Id"
        CategoryID = ($Id % 5) + 1
        Price = [math]::Round((Get-Random -Minimum 10 -Maximum 1000) + ($Id * 0.1), 2)
        Stock = Get-Random -Minimum 0 -Maximum 100
        LastModified = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        ModifiedBy = "test-system"
    }
}

function New-TestOrderItem {
    param([int]$OrderId, [int]$ProductId, [int]$LineNumber)
    
    $quantity = Get-Random -Minimum 1 -Maximum 10
    $unitPrice = [math]::Round((Get-Random -Minimum 10 -Maximum 100), 2)
    $discount = [math]::Round((Get-Random -Minimum 0 -Maximum 20) / 100, 2)
    
    return @{
        OrderID = $OrderId
        ProductID = $ProductId
        LineNumber = $LineNumber
        Quantity = $quantity
        UnitPrice = $unitPrice
        Discount = $discount
        Total = [math]::Round($quantity * $unitPrice * (1 - $discount), 2)
    }
}

# Export für Module-System (deaktiviert für Dot-Sourcing)
# if ($MyInvocation.MyCommand.Path -and $MyInvocation.MyCommand.ModuleName) {
#     Export-ModuleMember -Function @(
#         "Assert-*",
#         "New-TestSuite", 
#         "Initialize-TestFramework",
#         "Get-TestTempDirectory",
#         "Clear-TestData",
#         "Mock-Function",
#         "Restore-Function",
#         "Get-MockCallCount",
#         "Get-MockCallHistory",
#         "Clear-AllMocks",
#         "Invoke-WithTimeout",
#         "Test-IsRunningInCI",
#         "Get-RandomTestName",
#         "New-TestUser",
#         "New-TestProduct",
#         "New-TestOrderItem"
#     ) -Variable "TestFramework"
# }