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
    [switch]$Analyze,  # Analyze data quality only
    
    [Parameter(Mandatory=$false)]
    [switch]$Validate,  # Validate configuration only
    
    [Parameter(Mandatory=$false)]
    [switch]$Execute,  # Execute import/sync (default is dry-run)
    
    # Export options
    [Parameter(Mandatory=$false)]
    [switch]$SkipOnDuplicates,  # Skip tables with duplicates
    
    [Parameter(Mandatory=$false)]
    [switch]$CreateReports,  # Create CSV problem reports
    
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
    [switch]$HelpTo  # Show import help
)

# Show help if requested or no parameters
if ($Help -or $HelpFrom -or $HelpTo -or (-not $From -and -not $To -and -not $Analyze -and -not $Validate)) {
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
    -Analyze            Analyze data quality without exporting
    -Validate           Quick validation without export or reports
    -CreateReports      Create CSV reports for data quality issues
    -SkipOnDuplicates   Automatically skip tables with duplicate records
    -ReportPath <path>  Custom path for CSV reports
    -CsvDelimiter <char> CSV delimiter (default: culture-specific)
    -ConfigFile <path>  Configuration file (default: sync-config.json)
    -Tables <list>      Comma-separated list of specific tables
    -ShowSQL            Show SQL statements for debugging

EXAMPLES:
    # Standard export
    syncray.ps1 -From production
    
    # Analyze duplicates and create reports
    syncray.ps1 -From production -Analyze -CreateReports
    
    # Export specific tables with validation
    syncray.ps1 -From production -Tables "Users,Orders" -Validate
    
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
    -Execute            Apply changes (default is dry-run preview)
    -ConfigFile <path>  Configuration file (default: sync-config.json)
    -Tables <list>      Comma-separated list of specific tables
    -ShowSQL            Show SQL statements for debugging

EXAMPLES:
    # Preview import (dry-run)
    syncray.ps1 -To development
    
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

DATABASE PARAMETERS:
    -From <string>      Source database key from configuration
    -To <string>        Target database key from configuration

EXPORT PARAMETERS (use with -From):
    -Analyze            Analyze data quality without exporting
    -Validate           Quick validation without export or reports
    -CreateReports      Create CSV reports for data quality issues
    -SkipOnDuplicates   Automatically skip tables with duplicate records
    -ReportPath <path>  Custom path for CSV reports
    -CsvDelimiter <char> CSV delimiter (default: culture-specific)

IMPORT PARAMETERS (use with -To):
    -Execute            Apply changes (default is dry-run preview)

COMMON PARAMETERS (use with any mode):
    -ConfigFile <path>  Configuration file (default: sync-config.json)
    -Tables <list>      Comma-separated list of specific tables
    -ShowSQL            Show SQL statements for debugging
    -Help               Show this help message
    -HelpFrom           Show export mode help
    -HelpTo             Show import mode help

PARAMETER COMPATIBILITY:
    Export Mode (-From only):
        ✓ All export parameters
        ✓ Common parameters
        ✗ -Execute (import only)

    Import Mode (-To only):
        ✓ -Execute
        ✓ Common parameters
        ✗ Export parameters (-Analyze, -Validate, -CreateReports, etc.)

    Sync Mode (-From + -To):
        ✓ -Execute
        ✓ Export parameters (applied to export phase)
        ✓ Common parameters

EXAMPLES:
    # Export from production
    syncray.ps1 -From production
    
    # Export with duplicate analysis and reports
    syncray.ps1 -From production -Analyze -CreateReports
    
    # Preview import to development (dry-run)
    syncray.ps1 -To development
    
    # Execute import to development
    syncray.ps1 -To development -Execute
    
    # Direct sync with automatic duplicate skipping
    syncray.ps1 -From production -To development -SkipOnDuplicates -Execute
    
    # Export specific tables with SQL debugging
    syncray.ps1 -From production -Tables "Users,Orders" -ShowSQL
    
    # Get context-specific help
    syncray.ps1 -HelpFrom        # Export mode help
    syncray.ps1 -HelpTo          # Import mode help
    syncray.ps1 -HelpFrom -HelpTo # Sync mode help

SAFETY FEATURES:
    - Comprehensive validation before operations
    - Dry-run by default (use -Execute to apply)
    - Transaction rollback on errors
    - Duplicate detection and handling

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

# Validate parameter combinations based on mode
if ($mode -eq "import") {
    # Check for export-only parameters used with import
    $invalidParams = @()
    if ($Analyze) { $invalidParams += "-Analyze" }
    if ($Validate) { $invalidParams += "-Validate" }
    if ($CreateReports) { $invalidParams += "-CreateReports" }
    if ($SkipOnDuplicates) { $invalidParams += "-SkipOnDuplicates" }
    if ($ReportPath) { $invalidParams += "-ReportPath" }
    if ($CsvDelimiter) { $invalidParams += "-CsvDelimiter" }
    
    if ($invalidParams.Count -gt 0) {
        Write-Host "[ERROR] The following parameters cannot be used with -To (import mode):" -ForegroundColor Red
        Write-Host "        $($invalidParams -join ', ')" -ForegroundColor Red
        Write-Host "" -ForegroundColor Red
        Write-Host "These parameters are only available for export operations." -ForegroundColor Yellow
        Write-Host "To analyze or validate data, use: syncray.ps1 -From $To -Analyze" -ForegroundColor Cyan
        exit 1
    }
}

if ($mode -eq "export" -and $Execute) {
    Write-Host "[ERROR] -Execute cannot be used with -From only (export mode)" -ForegroundColor Red
    Write-Host "       -Execute is only valid for import (-To) or sync (-From + -To) operations" -ForegroundColor Yellow
    Write-Host "" -ForegroundColor Yellow
    Write-Host "For export, data is always written to JSON files. Use -To to import and execute changes." -ForegroundColor Cyan
    exit 1
}

# Get script directory
$scriptDir = $PSScriptRoot

# Show operation header
Write-Host "`n=== SYNCRAY OPERATION ===" -ForegroundColor Cyan
Write-Host "Mode: $($mode.ToUpper())" -ForegroundColor White
if ($From) { Write-Host "From: $From" -ForegroundColor White }
if ($To) { Write-Host "To: $To" -ForegroundColor White }
if ($Tables) { Write-Host "Tables: $Tables" -ForegroundColor White }
if ($Analyze) { Write-Host "Action: Analyze" -ForegroundColor Yellow }
if ($Validate) { Write-Host "Action: Validate" -ForegroundColor Yellow }
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
if ($Analyze) { $exportParams['Analyze'] = $true }
if ($Validate) { $exportParams['Validate'] = $true }
if ($SkipOnDuplicates) { $exportParams['SkipOnDuplicates'] = $true }
if ($CreateReports) { $exportParams['CreateReports'] = $true }
if ($ReportPath) { $exportParams['ReportPath'] = $ReportPath }
if ($CsvDelimiter) { $exportParams['CsvDelimiter'] = $CsvDelimiter }

# Import-specific parameters
if ($To) { $importParams['To'] = $To }
if ($Execute) { $importParams['Execute'] = $true }

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