# syncray.ps1 - Central SyncRay database synchronization tool
[CmdletBinding()]
param(
    # Database parameters
    [Parameter(Mandatory=$false)]
    [string]$From,  # Source database
    
    [Parameter(Mandatory=$false)]
    [string]$To,  # Target database
    
    # Common parameters
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile = "sync-config.json",
    
    [Parameter(Mandatory=$false)]
    [string]$Tables,  # Comma-separated list of tables
    
    # Action modifiers
    [Parameter(Mandatory=$false)]
    [switch]$Execute,  # Execute mode - apply changes (default is preview/dry-run)
    
    # Output options
    [Parameter(Mandatory=$false)]
    [switch]$CreateReport,  # Create context-aware reports/documentation
    
    [Parameter(Mandatory=$false)]
    [switch]$Quiet,  # Minimal output
    
    # Export-specific options
    [Parameter(Mandatory=$false)]
    [switch]$SkipOnDuplicates,  # Skip tables with duplicates
    
    [Parameter(Mandatory=$false)]
    [string]$ReportPath,  # Path for CSV reports
    
    [Parameter(Mandatory=$false)]
    [string]$CsvDelimiter,  # CSV delimiter
    
    # General options
    [Parameter(Mandatory=$false)]
    [switch]$ShowSQL,  # Show SQL debug output
    
    [Parameter(Mandatory=$false)]
    [switch]$Help,  # Show help
    
    # Help context switches
    [Parameter(Mandatory=$false)]
    [switch]$HelpFrom,  # Show export help
    
    [Parameter(Mandatory=$false)]
    [switch]$HelpTo,  # Show import help
    
    # Interactive mode
    [Parameter(Mandatory=$false)]
    [switch]$Interactive  # Start interactive mode
)

# Start interactive mode if requested or no parameters
if ($Interactive -or (-not $From -and -not $To -and -not $Help -and -not $HelpFrom -and -not $HelpTo -and $PSBoundParameters.Count -eq 0)) {
    Write-Host "`n=== SYNCRAY INTERACTIVE MODE ===" -ForegroundColor Cyan
    Write-Host "Welcome to SyncRay - Database Synchronization Tool" -ForegroundColor White
    Write-Host ""
    
    # Load configuration to show available databases
    $configPath = Join-Path $PSScriptRoot $ConfigFile
    if (-not (Test-Path $configPath)) {
        Write-Host "[ERROR] Config file not found: $configPath" -ForegroundColor Red
        Write-Host "Please create a sync-config.json file first." -ForegroundColor Yellow
        exit 1
    }
    
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    $availableDatabases = @($config.databases.PSObject.Properties.Name)
    
    # Step 1: Choose operation mode
    Write-Host "What would you like to do?" -ForegroundColor Yellow
    Write-Host "1) Export data from a database" -ForegroundColor White
    Write-Host "2) Import data to a database" -ForegroundColor White
    Write-Host "3) Sync data between databases" -ForegroundColor White
    Write-Host "4) Show help" -ForegroundColor White
    Write-Host "5) Exit" -ForegroundColor White
    Write-Host ""
    
    do {
        $choice = Read-Host "Select an option (1-6)"
    } while ($choice -notmatch '^[1-6]$')
    
    # Handle exit or help immediately
    if ($choice -eq '6') {
        Write-Host "`nExiting SyncRay. Goodbye!" -ForegroundColor Cyan
        exit 0
    }
    
    if ($choice -eq '5') {
        # Show help and restart
        & $PSCommandPath -Help
        exit 0
    }
    
    # Variables to build the command
    $selectedFrom = $null
    $selectedTo = $null
    $selectedAction = "preview"  # default
    $selectedTables = $null
    $createReports = $false
    
    # Step 2: Based on choice, get database selection
    switch ($choice) {
        '1' {  # Export
            Write-Host "`nAvailable databases:" -ForegroundColor Yellow
            for ($i = 0; $i -lt $availableDatabases.Count; $i++) {
                Write-Host "$($i + 1)) $($availableDatabases[$i])" -ForegroundColor White
            }
            Write-Host ""
            
            do {
                $dbChoice = Read-Host "Select source database (1-$($availableDatabases.Count))"
            } while ($dbChoice -notmatch "^[1-$($availableDatabases.Count)]$")
            
            $selectedFrom = $availableDatabases[[int]$dbChoice - 1]
            Write-Host "Selected: $selectedFrom" -ForegroundColor Green
        }
        
        '2' {  # Import
            Write-Host "`nAvailable databases:" -ForegroundColor Yellow
            for ($i = 0; $i -lt $availableDatabases.Count; $i++) {
                Write-Host "$($i + 1)) $($availableDatabases[$i])" -ForegroundColor White
            }
            Write-Host ""
            
            do {
                $dbChoice = Read-Host "Select target database (1-$($availableDatabases.Count))"
            } while ($dbChoice -notmatch "^[1-$($availableDatabases.Count)]$")
            
            $selectedTo = $availableDatabases[[int]$dbChoice - 1]
            Write-Host "Selected: $selectedTo" -ForegroundColor Green
        }
        
        '3' {  # Sync
            Write-Host "`nSelect SOURCE database:" -ForegroundColor Yellow
            for ($i = 0; $i -lt $availableDatabases.Count; $i++) {
                Write-Host "$($i + 1)) $($availableDatabases[$i])" -ForegroundColor White
            }
            Write-Host ""
            
            do {
                $dbChoice = Read-Host "Select source database (1-$($availableDatabases.Count))"
            } while ($dbChoice -notmatch "^[1-$($availableDatabases.Count)]$")
            
            $selectedFrom = $availableDatabases[[int]$dbChoice - 1]
            Write-Host "Source: $selectedFrom" -ForegroundColor Green
            
            Write-Host "`nSelect TARGET database:" -ForegroundColor Yellow
            for ($i = 0; $i -lt $availableDatabases.Count; $i++) {
                if ($availableDatabases[$i] -ne $selectedFrom) {
                    Write-Host "$($i + 1)) $($availableDatabases[$i])" -ForegroundColor White
                }
            }
            Write-Host ""
            
            do {
                $dbChoice = Read-Host "Select target database (1-$($availableDatabases.Count))"
            } while ($dbChoice -notmatch "^[1-$($availableDatabases.Count)]$" -or $availableDatabases[[int]$dbChoice - 1] -eq $selectedFrom)
            
            $selectedTo = $availableDatabases[[int]$dbChoice - 1]
            Write-Host "Target: $selectedTo" -ForegroundColor Green
        }
        
        '4' {  # Analyze
            Write-Host "`nWhat would you like to analyze?" -ForegroundColor Yellow
            Write-Host "1) Source database (export analysis)" -ForegroundColor White
            Write-Host "2) Target database (import readiness)" -ForegroundColor White
            Write-Host ""
            
            do {
                $analyzeChoice = Read-Host "Select option (1-2)"
            } while ($analyzeChoice -notmatch '^[1-2]$')
            
            Write-Host "`nAvailable databases:" -ForegroundColor Yellow
            for ($i = 0; $i -lt $availableDatabases.Count; $i++) {
                Write-Host "$($i + 1)) $($availableDatabases[$i])" -ForegroundColor White
            }
            Write-Host ""
            
            do {
                $dbChoice = Read-Host "Select database (1-$($availableDatabases.Count))"
            } while ($dbChoice -notmatch "^[1-$($availableDatabases.Count)]$")
            
            if ($analyzeChoice -eq '1') {
                $selectedFrom = $availableDatabases[[int]$dbChoice - 1]
                Write-Host "Analyzing source: $selectedFrom" -ForegroundColor Green
            } else {
                $selectedTo = $availableDatabases[[int]$dbChoice - 1]
                Write-Host "Analyzing target: $selectedTo" -ForegroundColor Green
            }
            
            $selectedAction = "analyze"
        }
    }
    
    # Step 3: Table selection (if not analyze mode)
    if ($choice -ne '4') {
        Write-Host "`nTable selection:" -ForegroundColor Yellow
        Write-Host "1) All configured tables" -ForegroundColor White
        Write-Host "2) Specific tables" -ForegroundColor White
        Write-Host ""
        
        do {
            $tableChoice = Read-Host "Select option (1-2)"
        } while ($tableChoice -notmatch '^[1-2]$')
        
        if ($tableChoice -eq '2') {
            # Get unique table names from configuration
            $configuredTables = @()
            if ($choice -eq '1' -or $choice -eq '3') {
                # For export or sync, show source tables
                $configuredTables = $config.syncTables | ForEach-Object { $_.sourceTable } | Sort-Object -Unique
            } else {
                # For import, show target tables
                $configuredTables = $config.syncTables | ForEach-Object { 
                    if ($_.targetTable) { $_.targetTable } else { $_.sourceTable }
                } | Sort-Object -Unique
            }
            
            Write-Host "`nConfigured tables:" -ForegroundColor Yellow
            for ($i = 0; $i -lt $configuredTables.Count; $i++) {
                Write-Host "$($i + 1)) $($configuredTables[$i])" -ForegroundColor White
            }
            Write-Host ""
            Write-Host "Enter table numbers (comma-separated, e.g., 1,3,5) or table names:" -ForegroundColor Yellow
            Write-Host "Examples: '1,2,3' or 'Users,Orders' or 'ALL' for all tables" -ForegroundColor Gray
            
            $tableInput = Read-Host "Tables"
            
            if ($tableInput -eq 'ALL' -or $tableInput -eq 'all') {
                # User wants all tables
                Write-Host "Selected: All tables" -ForegroundColor Green
            } else {
                # Check if input is numbers or names
                if ($tableInput -match '^[\d,\s]+$') {
                    # Numbers provided
                    $selectedIndices = $tableInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' }
                    $selectedTableNames = @()
                    foreach ($index in $selectedIndices) {
                        $idx = [int]$index - 1
                        if ($idx -ge 0 -and $idx -lt $configuredTables.Count) {
                            $selectedTableNames += $configuredTables[$idx]
                        }
                    }
                    $selectedTables = $selectedTableNames -join ','
                } else {
                    # Table names provided directly
                    $selectedTables = $tableInput
                }
                Write-Host "Selected tables: $selectedTables" -ForegroundColor Green
            }
        }
    }
    
    # Step 4: Action mode
    if ($choice -ne '4') {
        Write-Host "`nAction mode:" -ForegroundColor Yellow
        Write-Host "1) Preview (dry-run) - Show what would happen with full analysis" -ForegroundColor White
        Write-Host "2) Execute - Actually perform the operation" -ForegroundColor White
        Write-Host ""
        
        do {
            $actionChoice = Read-Host "Select action (1-2)"
        } while ($actionChoice -notmatch "^[1-2]$")
        
        switch ($actionChoice) {
            '1' { $selectedAction = "preview" }
            '2' { $selectedAction = "execute" }
        }
        
        Write-Host "Mode: $($selectedAction.ToUpper())" -ForegroundColor Green
    }
    
    # Step 5: Reports
    Write-Host "`nGenerate reports?" -ForegroundColor Yellow
    Write-Host "1) No - Console output only" -ForegroundColor White
    Write-Host "2) Yes - Create CSV/JSON reports" -ForegroundColor White
    Write-Host ""
    
    do {
        $reportChoice = Read-Host "Select option (1-2)"
    } while ($reportChoice -notmatch '^[1-2]$')
    
    if ($reportChoice -eq '2') {
        $createReports = $true
        Write-Host "Reports: Enabled" -ForegroundColor Green
    }
    
    # Step 6: Confirm and execute
    Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
    if ($selectedFrom) { Write-Host "From: $selectedFrom" -ForegroundColor White }
    if ($selectedTo) { Write-Host "To: $selectedTo" -ForegroundColor White }
    if ($selectedTables) { Write-Host "Tables: $selectedTables" -ForegroundColor White }
    Write-Host "Action: $($selectedAction.ToUpper())" -ForegroundColor $(if ($selectedAction -eq "execute") { "Yellow" } else { "White" })
    if ($createReports) { Write-Host "Reports: Enabled" -ForegroundColor White }
    Write-Host ""
    
    $confirm = Read-Host "Execute this operation? (y/n)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Host "`nOperation cancelled." -ForegroundColor Yellow
        exit 0
    }
    
    # Build and execute the command
    Write-Host "`nExecuting..." -ForegroundColor Cyan
    $params = @{}
    if ($selectedFrom) { $params['From'] = $selectedFrom }
    if ($selectedTo) { $params['To'] = $selectedTo }
    if ($selectedTables) { $params['Tables'] = $selectedTables }
    if ($selectedAction -eq 'analyze') { $params['Analyze'] = $true }
    if ($selectedAction -eq 'execute') { $params['Execute'] = $true }
    if ($createReports) { $params['CreateReport'] = $true }
    if ($ConfigFile) { $params['ConfigFile'] = $ConfigFile }
    
    # Re-invoke the script with the selected parameters
    & $PSCommandPath @params
    exit $LASTEXITCODE
}

# Show help if requested
if ($Help -or $HelpFrom -or $HelpTo) {
    # Check for context-sensitive help
    if (($Help -or $HelpFrom -or $HelpTo) -and ($HelpFrom -or $HelpTo -or $From -or $To)) {
        if (($HelpFrom -and $HelpTo) -or ($From -and $To)) {
            # Sync mode help
            Write-Host @"
`n=== SYNCRAY SYNC MODE HELP ===

DESCRIPTION:
    Direct synchronization from source to target database.

SYNTAX:
    syncray.ps1 -From <source> -To <target> [options]

AVAILABLE PARAMETERS:
    -From <string>      Source database key (required)
    -To <string>        Target database key (required)
    -Execute            Apply changes (default is dry-run preview)
    
    Export Phase Options:
    -SkipOnDuplicates   Automatically skip tables with duplicate records
    -CreateReports      Create CSV reports during export phase
    -ReportPath <path>  Custom path for CSV reports
    -CsvDelimiter <char> CSV delimiter
    
    Common Options:
    -ConfigFile <path>  Configuration file (default: sync-config.json)
    -Tables <list>      Comma-separated list of specific tables
    -ShowSQL            Show SQL statements for debugging

EXAMPLES:
    # Preview sync (dry-run)
    syncray.ps1 -From production -To development
    
    # Execute sync
    syncray.ps1 -From production -To development -Execute
    
    # Sync with duplicate handling
    syncray.ps1 -From production -To development -SkipOnDuplicates -Execute
    
    # Sync specific tables with reports
    syncray.ps1 -From production -To development -Tables "Users" -CreateReports

"@ -ForegroundColor Cyan
            exit 0
        } elseif ($HelpFrom -or ($From -and -not $To -and -not $HelpTo)) {
            # Export-specific help
            Write-Host @"
`n=== SYNCRAY EXPORT MODE HELP ===

DESCRIPTION:
    Export data from source database to JSON files.

SYNTAX:
    syncray.ps1 -From <database> [export options] [common options]

AVAILABLE PARAMETERS:
    -From <string>      Source database key (required)
    -Execute            Execute export (default: preview with analysis)
    -CreateReports      Create CSV, JSON and Markdown reports
    -SkipOnDuplicates   Automatically skip tables with duplicate records
    -ReportPath <path>  Custom path for CSV reports
    -CsvDelimiter <char> CSV delimiter (default: culture-specific)
    -ConfigFile <path>  Configuration file (default: sync-config.json)
    -Tables <list>      Comma-separated list of specific tables
    -ShowSQL            Show SQL statements for debugging

EXAMPLES:
    # Standard export
    syncray.ps1 -From production
    
    # Preview with reports (duplicates, data quality)
    syncray.ps1 -From production -CreateReports
    
    # Export specific tables
    syncray.ps1 -From production -Tables "Users,Orders"
    
    # Skip duplicates automatically
    syncray.ps1 -From production -SkipOnDuplicates

"@ -ForegroundColor Cyan
            exit 0
        } elseif ($HelpTo -or ($To -and -not $From -and -not $HelpFrom)) {
            # Import-specific help
            Write-Host @"
`n=== SYNCRAY IMPORT MODE HELP ===

DESCRIPTION:
    Import data from JSON files to target database.

SYNTAX:
    syncray.ps1 -To <database> [import options] [common options]

AVAILABLE PARAMETERS:
    -To <string>        Target database key (required)
    -Execute            Apply changes (default: preview with analysis)
    -CreateReports      Create detailed reports (CSV, JSON, Markdown)
    -ReportPath <path>  Custom path for reports
    -ConfigFile <path>  Configuration file (default: sync-config.json)
    -Tables <list>      Comma-separated list of specific tables
    -ShowSQL            Show SQL statements for debugging

EXAMPLES:
    # Preview import (analyze compatibility, show changes)
    syncray.ps1 -To development
    
    # Preview with detailed reports
    syncray.ps1 -To development -CreateReports
    
    # Execute import
    syncray.ps1 -To development -Execute
    
    # Import specific tables only
    syncray.ps1 -To development -Tables "Users,Orders" -Execute
    
    # Debug SQL statements
    syncray.ps1 -To development -ShowSQL

SAFETY:
    Import operations are transactional and will rollback on any error.
    Always preview changes before using -Execute.

"@ -ForegroundColor Cyan
            exit 0
        }
    }
    
    # Show full help if no context
    Write-Host @"
`n=== SYNCRAY - Database Synchronization Tool ===

DESCRIPTION:
    Central tool for database synchronization between SQL Server instances.
    Automatically determines operation based on -From and -To parameters.

SYNTAX:
    syncray.ps1 [-From <db>] [-To <db>] [options]

OPERATION MODES:
    1. Export Mode (only -From specified)
       Export data from source database to JSON files
       Example: syncray.ps1 -From production

    2. Import Mode (only -To specified)
       Import data from JSON files to target database
       Example: syncray.ps1 -To development

    3. Sync Mode (both -From and -To specified)
       Direct synchronization from source to target
       Example: syncray.ps1 -From production -To development

ACTION MODES:
    Default (Preview)   Show what would happen without making changes (includes full analysis)
    -Execute           Actually perform the operation

DATABASE PARAMETERS:
    -From <string>      Source database key from configuration
    -To <string>        Target database key from configuration

ACTION PARAMETERS:
    -Execute            Execute mode - apply changes (default: preview with full analysis)

OUTPUT PARAMETERS:
    -CreateReport       Create context-aware reports/documentation
    -Quiet              Minimal output
    -ShowSQL            Show SQL statements for debugging

EXPORT PARAMETERS (use with -From):
    -SkipOnDuplicates   Automatically skip tables with duplicate records
    -ReportPath <path>  Custom path for reports
    -CsvDelimiter <char> CSV delimiter (default: culture-specific)

COMMON PARAMETERS:
    -ConfigFile <path>  Configuration file (default: sync-config.json)
    -Tables <list>      Comma-separated list of specific tables
    -Help               Show this help message
    -HelpFrom           Show export mode help
    -HelpTo             Show import mode help
    -Interactive        Start interactive mode

PARAMETER COMPATIBILITY:
    Preview Mode (default):
        [OK] All parameters except -Execute
        Shows what would happen without changes

    Execute Mode (-Execute):
        [OK] Works with all operation modes
        [OK] -CreateReport generates operation documentation

EXAMPLES:
    # Preview what would be exported
    syncray.ps1 -From production
    
    # Analyze source data quality (full analysis)
    syncray.ps1 -From production
    
    # Preview with detailed reports
    syncray.ps1 -From production -CreateReport
    
    # Execute export with documentation
    syncray.ps1 -From production -Execute -CreateReport
    
    # Preview import changes
    syncray.ps1 -To development
    
    # Preview target database (check compatibility)
    syncray.ps1 -To development
    
    # Execute import
    syncray.ps1 -To development -Execute
    
    # Full sync with documentation
    syncray.ps1 -From production -To development -Execute -CreateReport
    
    # Interactive mode
    syncray.ps1 -Interactive
    
    # Get context-specific help
    syncray.ps1 -HelpFrom        # Export mode help
    syncray.ps1 -HelpTo          # Import mode help
    syncray.ps1 -HelpFrom -HelpTo # Sync mode help

SAFETY FEATURES:
    - Comprehensive validation before operations
    - Preview by default (use -Execute to apply changes)
    - Transaction rollback on errors
    - Duplicate detection with detailed reporting

CONSOLE OUTPUT:
    Preview Mode:
    - Full duplicate analysis with example records
    - Data quality issues and validation errors
    - Summary statistics and recommendations
    
    Execute Mode:
    - Operation timing and duration
    - Per-table results (rows/operations/size)
    - Success/failure status with details
    - Complete execution summary

REPORT FILES (with -CreateReport):
    ./reports/[timestamp]/
    ├── analysis_report.md       # Preview: Analysis summary
    ├── export_report.md         # Execute: Export results
    ├── execution_report.md      # Execute: Import results
    ├── preview_report.md        # Preview: Planned changes
    ├── duplicates/              # Detailed duplicate records
    │   └── [Table]_duplicates.csv
    ├── *_summary.csv            # Operation summaries
    └── *_log.json               # Detailed operation data

"@ -ForegroundColor Cyan
    exit 0
}

# Determine operation mode first to provide better error messages
$mode = ""
if ($From -and $To) {
    $mode = "sync"
} elseif ($From) {
    $mode = "export"
} elseif ($To) {
    $mode = "import"
} else {
    Write-Host "[ERROR] Either -From, -To, or both must be specified" -ForegroundColor Red
    exit 1
}

# Validate action parameter combinations
# (Execute is now the only action parameter)

# Validate mode-specific parameter combinations
if ($mode -eq "import") {
    # Check for export-only parameters used with import
    $invalidParams = @()
    if ($SkipOnDuplicates) { $invalidParams += "-SkipOnDuplicates" }
    if ($CsvDelimiter) { $invalidParams += "-CsvDelimiter" }
    
    if ($invalidParams.Count -gt 0) {
        Write-Host "[ERROR] The following parameters cannot be used with -To (import mode):" -ForegroundColor Red
        Write-Host "        $($invalidParams -join ', ')" -ForegroundColor Red
        Write-Host "" -ForegroundColor Red
        Write-Host "These parameters are only available for export operations." -ForegroundColor Yellow
        exit 1
    }
}

# Determine action mode
$actionMode = "preview"  # Default
if ($Execute) {
    $actionMode = "execute"
}

# Get script directory
$scriptDir = $PSScriptRoot

# Show operation header
Write-Host "`n=== SYNCRAY OPERATION ===" -ForegroundColor Cyan
Write-Host "Mode: $($mode.ToUpper())" -ForegroundColor White
Write-Host "Action: $($actionMode.ToUpper())" -ForegroundColor $(if ($actionMode -eq "execute") { "Yellow" } else { "White" })
if ($From) { Write-Host "From: $From" -ForegroundColor White }
if ($To) { Write-Host "To: $To" -ForegroundColor White }
if ($Tables) { Write-Host "Tables: $Tables" -ForegroundColor White }
if ($CreateReport) { Write-Host "Reports: Enabled" -ForegroundColor Green }
Write-Host ""

# Build parameter hashtables for sub-scripts
$exportParams = @{}
$importParams = @{}

# Common parameters
if ($ConfigFile) { 
    $exportParams['ConfigFile'] = $ConfigFile
    $importParams['ConfigFile'] = $ConfigFile
}
if ($Tables) {
    $exportParams['Tables'] = $Tables
    $importParams['Tables'] = $Tables
}
if ($ShowSQL) {
    $exportParams['ShowSQL'] = $true
    $importParams['ShowSQL'] = $true
}

# Export-specific parameters
if ($From) { $exportParams['From'] = $From }
if ($actionMode -eq "preview" -and $mode -eq "export") { $exportParams['Preview'] = $true }
if ($SkipOnDuplicates) { $exportParams['SkipOnDuplicates'] = $true }
if ($CreateReport) { $exportParams['CreateReports'] = $true }
if ($ReportPath) { $exportParams['ReportPath'] = $ReportPath }
if ($CsvDelimiter) { $exportParams['CsvDelimiter'] = $CsvDelimiter }

# Import-specific parameters
if ($To) { $importParams['To'] = $To }
if ($Execute -and $mode -ne "export") { $importParams['Execute'] = $true }
if ($CreateReport) { $importParams['CreateReports'] = $true }
if ($ReportPath) { $importParams['ReportPath'] = $ReportPath }

# Execute based on mode
switch ($mode) {
    "export" {
        & "$scriptDir\sync-export.ps1" @exportParams
        $exportSuccess = $LASTEXITCODE -eq 0
        
        if (-not $exportSuccess) {
            Write-Host "`n[ERROR] Export failed" -ForegroundColor Red
            exit 1
        }
    }
    
    "import" {
        & "$scriptDir\sync-import.ps1" @importParams
        $importSuccess = $LASTEXITCODE -eq 0
        
        if (-not $importSuccess) {
            Write-Host "`n[ERROR] Import failed" -ForegroundColor Red
            exit 1
        }
    }
    
    "sync" {
        # In preview mode for sync, we need to pass preview to export but not import
        if ($actionMode -eq "preview") {
            $exportParams['Preview'] = $true
        }
        
        # First export
        Write-Host "=== STEP 1: EXPORT ===" -ForegroundColor Cyan
        & "$scriptDir\sync-export.ps1" @exportParams
        $exportSuccess = $LASTEXITCODE -eq 0
        
        if (-not $exportSuccess) {
            Write-Host "`n[ERROR] Export failed - sync aborted" -ForegroundColor Red
            exit 1
        }
        
        # Then import
        Write-Host "`n=== STEP 2: IMPORT ===" -ForegroundColor Cyan
        & "$scriptDir\sync-import.ps1" @importParams
        $importSuccess = $LASTEXITCODE -eq 0
        
        if (-not $importSuccess) {
            Write-Host "`n[ERROR] Import failed" -ForegroundColor Red
            exit 1
        }
        
        Write-Host "`n=== SYNC COMPLETE ===" -ForegroundColor Green
    }
}