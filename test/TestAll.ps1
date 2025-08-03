# SyncRay Master Test Orchestrator
# 100% Funktions-Abdeckung mit visueller Ausgabe und Coverage-Reports
# Verwendung: ./test/TestAll.ps1 [-Category unit|integration|performance|security] [-Module validation|export|import|adapters|orchestration] [-Coverage] [-Verbose] [-Visual] [-CI]

param(
    [string[]]$Category = @("unit", "integration", "performance", "security"),
    [string[]]$Module = @(),
    [switch]$Coverage,
    [switch]$Verbose,
    [switch]$Visual = $true,
    [switch]$CI,
    [switch]$SkipSetup,
    [switch]$KeepTestData,
    [int]$Parallel = 1
)

$ErrorActionPreference = "Stop"
$VerbosePreference = if ($Verbose) { "Continue" } else { "SilentlyContinue" }

# Test-Konfiguration laden
$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$testConfigPath = Join-Path $testRoot "TestConfig.json"
$srcRoot = Join-Path (Split-Path -Parent $testRoot) "src"

if (-not (Test-Path $testConfigPath)) {
    Write-Error "Test-Konfiguration nicht gefunden: $testConfigPath"
    exit 1
}

try {
    $config = Get-Content $testConfigPath | ConvertFrom-Json
} catch {
    Write-Error "Fehler beim Laden der Test-Konfiguration: $_"
    exit 1
}

# Test-Framework laden
$sharedPath = Join-Path $testRoot "shared"
$frameworkPath = Join-Path $sharedPath "Test-Framework.ps1"

if (-not (Test-Path $frameworkPath)) {
    Write-Error "Test-Framework nicht gefunden: $frameworkPath"
    exit 1
}

. $frameworkPath

# Globale Test-Statistiken
$global:TestStats = @{
    TotalTests = 0
    PassedTests = 0
    FailedTests = 0
    SkippedTests = 0
    Categories = @{}
    Modules = @{}
    StartTime = Get-Date
    TestResults = @()
    Coverage = @{}
}

# Visuelle Ausgabe-Funktionen
function Write-TestHeader {
    param([string]$Title, [string]$Color = "Cyan")
    
    if ($Visual) {
        $border = "═" * ($Title.Length + 4)
        Write-Host "`n╔$border╗" -ForegroundColor $Color
        Write-Host "║  $Title  ║" -ForegroundColor $Color
        Write-Host "╚$border╝" -ForegroundColor $Color
    } else {
        Write-Host "`n=== $Title ===" -ForegroundColor $Color
    }
}

function Write-TestProgress {
    param([string]$Message, [int]$Current, [int]$Total)
    
    if ($Visual -and -not $CI) {
        $percent = [math]::Round(($Current / $Total) * 100, 1)
        $progressBar = "█" * [math]::Floor($percent / 5) + "░" * (20 - [math]::Floor($percent / 5))
        Write-Host "`r[$progressBar] $percent% - $Message" -NoNewline -ForegroundColor Green
    } else {
        Write-Host "$Message ($Current/$Total)" -ForegroundColor Yellow
    }
}

function Write-TestResult {
    param([string]$TestName, [bool]$Success, [string]$Message = "", [timespan]$Duration)
    
    $icon = if ($Success) { "✅" } else { "❌" }
    $color = if ($Success) { "Green" } else { "Red" }
    $durationText = "{0:F3}s" -f $Duration.TotalSeconds
    
    if ($Visual) {
        Write-Host "`n  $icon $TestName" -ForegroundColor $color -NoNewline
        Write-Host " ($durationText)" -ForegroundColor Gray
        if ($Message -and -not $Success) {
            Write-Host "    ⚠️  $Message" -ForegroundColor Yellow
        }
    } else {
        $status = if ($Success) { "PASS" } else { "FAIL" }
        Write-Host "[$status] $TestName ($durationText)" -ForegroundColor $color
        if ($Message) {
            Write-Host "  $Message" -ForegroundColor Yellow
        }
    }
}

# Test-Entdeckung
function Get-TestFiles {
    param([string[]]$Categories, [string[]]$Modules)
    
    $testFiles = @()
    
    foreach ($cat in $Categories) {
        $categoryPath = Join-Path $testRoot $cat
        if (Test-Path $categoryPath) {
            if ($Modules.Count -gt 0) {
                foreach ($mod in $Modules) {
                    $modulePath = Join-Path $categoryPath $mod
                    if (Test-Path $modulePath) {
                        $testFiles += Get-ChildItem -Path $modulePath -Filter "*.ps1" -Recurse
                    }
                }
            } else {
                $testFiles += Get-ChildItem -Path $categoryPath -Filter "*.ps1" -Recurse
            }
        }
    }
    
    return $testFiles | Sort-Object FullName
}

# Test-Ausführung
function Invoke-TestFile {
    param([System.IO.FileInfo]$TestFile)
    
    $testName = $TestFile.BaseName
    $category = Split-Path (Split-Path $TestFile.Directory) -Leaf
    $module = Split-Path $TestFile.Directory -Leaf
    
    $startTime = Get-Date
    $success = $false
    $message = ""
    
    try {
        Write-Verbose "Ausführung: $($TestFile.FullName)"
        
        # Test-Skript ausführen
        $result = & $TestFile.FullName
        
        if ($result -is [hashtable] -and $result.ContainsKey('Success')) {
            $success = $result.Success
            $message = $result.Message
        } elseif ($result -is [bool]) {
            $success = $result
        } else {
            $success = $true  # Annahme: Erfolg wenn kein Fehler geworfen
        }
        
    } catch {
        $success = $false
        $message = $_.Exception.Message
        Write-Verbose "Test-Fehler: $_"
    }
    
    $duration = (Get-Date) - $startTime
    
    # Statistiken aktualisieren
    $global:TestStats.TotalTests++
    if ($success) {
        $global:TestStats.PassedTests++
    } else {
        $global:TestStats.FailedTests++
    }
    
    if (-not $global:TestStats.Categories.ContainsKey($category)) {
        $global:TestStats.Categories[$category] = @{ Passed = 0; Failed = 0; Total = 0 }
    }
    $global:TestStats.Categories[$category].Total++
    if ($success) {
        $global:TestStats.Categories[$category].Passed++
    } else {
        $global:TestStats.Categories[$category].Failed++
    }
    
    if (-not $global:TestStats.Modules.ContainsKey($module)) {
        $global:TestStats.Modules[$module] = @{ Passed = 0; Failed = 0; Total = 0 }
    }
    $global:TestStats.Modules[$module].Total++
    if ($success) {
        $global:TestStats.Modules[$module].Passed++
    } else {
        $global:TestStats.Modules[$module].Failed++
    }
    
    # Test-Ergebnis speichern
    $testResult = @{
        TestName = $testName
        Category = $category
        Module = $module
        Success = $success
        Message = $message
        Duration = $duration
        Timestamp = Get-Date
        FilePath = $TestFile.FullName
    }
    $global:TestStats.TestResults += $testResult
    
    Write-TestResult -TestName "$category/$module/$testName" -Success $success -Message $message -Duration $duration
    
    return $testResult
}

# Coverage-Analyse
function Get-CoverageReport {
    if (-not $Coverage) { return }
    
    Write-TestHeader "📊 CODE COVERAGE ANALYSE" "Magenta"
    
    $srcFiles = Get-ChildItem -Path $srcRoot -Filter "*.ps1" -Recurse | Where-Object { $_.Name -ne "sync-config.example.json" }
    
    foreach ($srcFile in $srcFiles) {
        $moduleName = $srcFile.BaseName
        $functions = @()
        
        # Funktionen aus Quellcode extrahieren
        try {
            $content = Get-Content $srcFile.FullName -Raw
            $functionMatches = [regex]::Matches($content, 'function\s+([a-zA-Z-]+)')
            $functions = $functionMatches | ForEach-Object { $_.Groups[1].Value }
        } catch {
            Write-Verbose "Fehler beim Analysieren von $($srcFile.Name): $_"
        }
        
        $tested = 0
        $total = $functions.Count
        
        # Prüfen welche Funktionen getestet werden
        foreach ($function in $functions) {
            $testPattern = "*$function*"
            $hasTest = $global:TestStats.TestResults | Where-Object { $_.TestName -like $testPattern }
            if ($hasTest) { $tested++ }
        }
        
        $coverage = if ($total -gt 0) { [math]::Round(($tested / $total) * 100, 1) } else { 100 }
        $color = if ($coverage -ge 90) { "Green" } elseif ($coverage -ge 70) { "Yellow" } else { "Red" }
        
        $global:TestStats.Coverage[$moduleName] = @{
            TotalFunctions = $total
            TestedFunctions = $tested
            CoveragePercent = $coverage
        }
        
        if ($Visual) {
            $bar = "█" * [math]::Floor($coverage / 5) + "░" * (20 - [math]::Floor($coverage / 5))
            Write-Host "  [$bar] $coverage% - $moduleName ($tested/$total Funktionen)" -ForegroundColor $color
        } else {
            Write-Host "${moduleName}: $coverage% ($tested/$total)" -ForegroundColor $color
        }
    }
}

# Abschließender Bericht
function Write-FinalReport {
    $endTime = Get-Date
    $totalDuration = $endTime - $global:TestStats.StartTime
    $passRate = if ($global:TestStats.TotalTests -gt 0) { 
        [math]::Round(($global:TestStats.PassedTests / $global:TestStats.TotalTests) * 100, 1) 
    } else { 0 }
    
    Write-TestHeader "📋 TEST ZUSAMMENFASSUNG" "Cyan"
    
    if ($Visual) {
        Write-Host "`nGesamtergebnis:" -ForegroundColor White
        Write-Host "  Gesamt: $($global:TestStats.TotalTests) Tests" -ForegroundColor Gray
        Write-Host "  ✅ Bestanden: $($global:TestStats.PassedTests)" -ForegroundColor Green
        Write-Host "  ❌ Fehlgeschlagen: $($global:TestStats.FailedTests)" -ForegroundColor Red
        Write-Host "  📊 Erfolgsquote: $passRate%" -ForegroundColor $(if ($passRate -ge 90) { "Green" } elseif ($passRate -ge 70) { "Yellow" } else { "Red" })
        Write-Host "  ⏱️  Dauer: $($totalDuration.ToString('mm\:ss\.fff'))" -ForegroundColor Gray
        
        if ($global:TestStats.Categories.Count -gt 0) {
            Write-Host "`nErgebnisse nach Kategorie:" -ForegroundColor White
            foreach ($cat in $global:TestStats.Categories.Keys) {
                $catStats = $global:TestStats.Categories[$cat]
                $catRate = [math]::Round(($catStats.Passed / $catStats.Total) * 100, 1)
                Write-Host "  ${cat}: $($catStats.Passed)/$($catStats.Total) ($catRate%)" -ForegroundColor $(if ($catRate -eq 100) { "Green" } else { "Yellow" })
            }
        }
        
        if ($global:TestStats.Modules.Count -gt 0) {
            Write-Host "`nErgebnisse nach Modul:" -ForegroundColor White
            foreach ($mod in $global:TestStats.Modules.Keys) {
                $modStats = $global:TestStats.Modules[$mod]
                $modRate = [math]::Round(($modStats.Passed / $modStats.Total) * 100, 1)
                Write-Host "  ${mod}: $($modStats.Passed)/$($modStats.Total) ($modRate%)" -ForegroundColor $(if ($modRate -eq 100) { "Green" } else { "Yellow" })
            }
        }
    } else {
        Write-Host "Tests: $($global:TestStats.PassedTests)/$($global:TestStats.TotalTests) passed ($passRate%)"
        Write-Host "Duration: $($totalDuration.ToString('mm\:ss\.fff'))"
    }
    
    # CI Export
    if ($CI) {
        $ciResults = @{
            TestSuite = "SyncRay-Complete"
            Total = $global:TestStats.TotalTests
            Passed = $global:TestStats.PassedTests
            Failed = $global:TestStats.FailedTests
            PassRate = $passRate
            Duration = $totalDuration.TotalSeconds
            Categories = $global:TestStats.Categories
            Modules = $global:TestStats.Modules
            Coverage = $global:TestStats.Coverage
            Timestamp = Get-Date
            TestResults = $global:TestStats.TestResults
        }
        
        $ciPath = Join-Path $testRoot "reports" "test-results.json"
        $reportsDir = Split-Path $ciPath
        if (-not (Test-Path $reportsDir)) {
            New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null
        }
        
        $ciResults | ConvertTo-Json -Depth 10 | Set-Content $ciPath
        Write-Host "`n📄 CI-Ergebnisse exportiert: $ciPath" -ForegroundColor Gray
    }
    
    # Coverage-Report
    if ($Coverage) {
        Get-CoverageReport
        
        $overallCoverage = if ($global:TestStats.Coverage.Count -gt 0) {
            $totalFunctions = ($global:TestStats.Coverage.Values | Measure-Object -Property TotalFunctions -Sum).Sum
            $testedFunctions = ($global:TestStats.Coverage.Values | Measure-Object -Property TestedFunctions -Sum).Sum
            if ($totalFunctions -gt 0) { [math]::Round(($testedFunctions / $totalFunctions) * 100, 1) } else { 0 }
        } else { 0 }
        
        Write-Host "`n📊 Gesamt-Coverage: $overallCoverage%" -ForegroundColor $(if ($overallCoverage -ge 90) { "Green" } elseif ($overallCoverage -ge 70) { "Yellow" } else { "Red" })
    }
    
    # Zusammenfassung
    if ($global:TestStats.FailedTests -eq 0) {
        Write-Host "`n🎉 Alle Tests erfolgreich! SyncRay ist bereit für Production." -ForegroundColor Green
    } else {
        Write-Host "`n⚠️  $($global:TestStats.FailedTests) Test(s) fehlgeschlagen. Bitte Fehler beheben." -ForegroundColor Yellow
    }
    
    return $global:TestStats.FailedTests -eq 0
}

# Main Execution
try {
    Write-TestHeader "🚀 SYNCRAY MASTER TEST SUITE" "Green"
    Write-Host "Konfiguration: $testConfigPath" -ForegroundColor Gray
    Write-Host "Kategorien: $($Category -join ', ')" -ForegroundColor Gray
    if ($Module.Count -gt 0) {
        Write-Host "Module: $($Module -join ', ')" -ForegroundColor Gray
    }
    if ($Coverage) {
        Write-Host "Coverage-Analyse: Aktiviert" -ForegroundColor Gray
    }
    
    # Test-Dateien sammeln
    $testFiles = Get-TestFiles -Categories $Category -Modules $Module
    
    if ($testFiles.Count -eq 0) {
        Write-Host "`n⚠️  Keine Test-Dateien gefunden für die angegebenen Kriterien." -ForegroundColor Yellow
        exit 0
    }
    
    Write-Host "`n📁 $($testFiles.Count) Test-Dateien gefunden" -ForegroundColor Gray
    
    # Tests ausführen
    Write-TestHeader "🧪 TEST AUSFÜHRUNG" "Yellow"
    
    for ($i = 0; $i -lt $testFiles.Count; $i++) {
        $testFile = $testFiles[$i]
        Write-TestProgress -Message "Ausführung $($testFile.BaseName)" -Current ($i + 1) -Total $testFiles.Count
        
        Invoke-TestFile -TestFile $testFile
    }
    
    # Abschlussbericht
    if ($Visual -and -not $CI) {
        Write-Host "`n" # Neue Zeile nach Progress Bar
    }
    
    $success = Write-FinalReport
    
    exit $(if ($success) { 0 } else { 1 })
    
} catch {
    Write-Host "`n❌ Kritischer Fehler in Test-Orchestrator: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}