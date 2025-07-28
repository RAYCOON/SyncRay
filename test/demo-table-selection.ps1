# Demo enhanced table selection in interactive mode

Write-Host "`n=== ENHANCED TABLE SELECTION DEMO ===" -ForegroundColor Cyan
Write-Host "Interactive mode now shows configured tables when selecting 'Specific tables'" -ForegroundColor Yellow
Write-Host ""

# Load configuration to show what tables would be displayed
$configPath = Join-Path $PSScriptRoot "../src/sync-config.json"
if (Test-Path $configPath) {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    
    # Get unique source tables
    $sourceTables = $config.syncTables | ForEach-Object { $_.sourceTable } | Sort-Object -Unique
    
    Write-Host "For EXPORT or SYNC operations, these tables would be shown:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Configured tables:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $sourceTables.Count; $i++) {
        Write-Host "$($i + 1)) $($sourceTables[$i])" -ForegroundColor White
    }
    Write-Host ""
    
    # Get unique target tables
    $targetTables = $config.syncTables | ForEach-Object { 
        if ($_.targetTable) { $_.targetTable } else { $_.sourceTable }
    } | Sort-Object -Unique
    
    Write-Host "`nFor IMPORT operations, these tables would be shown:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Configured tables:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $targetTables.Count; $i++) {
        Write-Host "$($i + 1)) $($targetTables[$i])" -ForegroundColor White
    }
    Write-Host ""
} else {
    Write-Host "[ERROR] Configuration file not found" -ForegroundColor Red
}

Write-Host "=== INPUT OPTIONS ===" -ForegroundColor Cyan
Write-Host "Users can now enter:" -ForegroundColor Yellow
Write-Host "  • Table numbers: '1,3,5' to select tables 1, 3, and 5" -ForegroundColor White
Write-Host "  • Table names: 'Users,Orders' to select by name" -ForegroundColor White
Write-Host "  • ALL: Type 'ALL' to select all tables" -ForegroundColor White
Write-Host ""

Write-Host "=== EXAMPLE INTERACTIONS ===" -ForegroundColor Cyan
Write-Host ""

Write-Host "Example 1: Selecting by numbers" -ForegroundColor Yellow
Write-Host "  Enter table numbers (comma-separated, e.g., 1,3,5) or table names:" -ForegroundColor Gray
Write-Host "  Tables: 1,2,4" -ForegroundColor Green
Write-Host "  Selected tables: SedBPCVs,VSD_PropertyPathes,StateTransitions" -ForegroundColor Green
Write-Host ""

Write-Host "Example 2: Selecting by names" -ForegroundColor Yellow
Write-Host "  Enter table numbers (comma-separated, e.g., 1,3,5) or table names:" -ForegroundColor Gray
Write-Host "  Tables: SedBPCVs,VersionBundles" -ForegroundColor Green
Write-Host "  Selected tables: SedBPCVs,VersionBundles" -ForegroundColor Green
Write-Host ""

Write-Host "Example 3: Selecting all" -ForegroundColor Yellow
Write-Host "  Enter table numbers (comma-separated, e.g., 1,3,5) or table names:" -ForegroundColor Gray
Write-Host "  Tables: ALL" -ForegroundColor Green
Write-Host "  Selected: All tables" -ForegroundColor Green
Write-Host ""

Write-Host "To test this feature, run:" -ForegroundColor Yellow
Write-Host "  ./syncray.ps1" -ForegroundColor White
Write-Host "Then select option 2 (Specific tables) when prompted for table selection" -ForegroundColor Gray
Write-Host ""