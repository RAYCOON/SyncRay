# test-sync-scenarios.ps1 - Comprehensive test scenarios for SyncRay

param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile = "src/sync-config.json",
    
    [Parameter(Mandatory=$false)]
    [switch]$PostgreSQL  # Use PostgreSQL test config
)

# Use PostgreSQL config if specified
if ($PostgreSQL) {
    $ConfigFile = "test/postgres/test-config-postgres.json"
    Write-Host "NOTE: PostgreSQL testing requires modifying SyncRay to support PostgreSQL" -ForegroundColor Yellow
    Write-Host "Currently SyncRay only supports SQL Server" -ForegroundColor Yellow
    exit 1
}

Write-Host "`n=== SYNCRAY TEST SUITE ===" -ForegroundColor Cyan
Write-Host "Configuration: $ConfigFile" -ForegroundColor Gray

# Test results tracking
$testResults = @{
    Passed = 0
    Failed = 0
    Skipped = 0
    Details = @()
}

function Test-Scenario {
    param(
        [string]$Name,
        [string]$Description,
        [scriptblock]$Test
    )
    
    Write-Host "`n--- Test: $Name ---" -ForegroundColor Yellow
    Write-Host "Description: $Description" -ForegroundColor Gray
    
    try {
        $result = & $Test
        if ($result.Success) {
            Write-Host "[PASS] $($result.Message)" -ForegroundColor Green
            $script:testResults.Passed++
        } else {
            Write-Host "[FAIL] $($result.Message)" -ForegroundColor Red
            $script:testResults.Failed++
        }
        $script:testResults.Details += @{
            Name = $Name
            Result = $result.Success
            Message = $result.Message
        }
    } catch {
        Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
        $script:testResults.Failed++
        $script:testResults.Details += @{
            Name = $Name
            Result = $false
            Message = $_.Exception.Message
        }
    }
}

# Test 1: Basic Export/Import
Test-Scenario -Name "Basic Export/Import" -Description "Test basic table sync without complications" -Test {
    # Export single table
    $exportOutput = & ./src/sync-export.ps1 -From source -Tables "settings" -ConfigFile $ConfigFile -NonInteractive 2>&1
    if ($LASTEXITCODE -ne 0) {
        return @{ Success = $false; Message = "Export failed: $exportOutput" }
    }
    
    # Check if export file exists
    $exportFile = Join-Path (Split-Path $ConfigFile) "sync-data/settings.json"
    if (-not (Test-Path $exportFile)) {
        return @{ Success = $false; Message = "Export file not created" }
    }
    
    # Dry-run import
    $importOutput = & ./src/sync-import.ps1 -To target -Tables "settings" -ConfigFile $ConfigFile 2>&1
    if ($LASTEXITCODE -ne 0) {
        return @{ Success = $false; Message = "Import dry-run failed: $importOutput" }
    }
    
    return @{ Success = $true; Message = "Basic export/import completed successfully" }
}

# Test 2: Duplicate Handling - Interactive Mode Simulation
Test-Scenario -Name "Duplicate Detection" -Description "Test duplicate detection and reporting" -Test {
    # This would need a table with duplicates in test data
    $exportOutput = & ./src/sync-export.ps1 -From source -Tables "duplicate_test" -ConfigFile $ConfigFile -NonInteractive 2>&1 | Out-String
    
    if ($exportOutput -match "DUPLICATES FOUND") {
        if ($exportOutput -match "Skipping table due to duplicates") {
            return @{ Success = $true; Message = "Duplicates correctly detected and skipped in NonInteractive mode" }
        } else {
            return @{ Success = $false; Message = "Duplicates found but not handled correctly" }
        }
    } else {
        return @{ Success = $false; Message = "Failed to detect known duplicates in test data" }
    }
}

# Test 3: ShowSQL Parameter
Test-Scenario -Name "ShowSQL Debug Output" -Description "Test debug SQL output functionality" -Test {
    $exportOutput = & ./src/sync-export.ps1 -From source -Tables "settings" -ConfigFile $ConfigFile -ShowSQL -NonInteractive 2>&1 | Out-String
    
    if ($exportOutput -match "\[DEBUG\].*SQL") {
        return @{ Success = $true; Message = "ShowSQL parameter working - debug output present" }
    } else {
        return @{ Success = $false; Message = "ShowSQL parameter not producing debug output" }
    }
}

# Test 4: Table Mapping
Test-Scenario -Name "Table Name Mapping" -Description "Test syncing between tables with different names" -Test {
    # Requires config with sourceTable != targetTable
    # Check if such config exists
    $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
    $mappedTable = $config.syncTables | Where-Object { $_.sourceTable -ne $_.targetTable -and $null -ne $_.targetTable } | Select-Object -First 1
    
    if ($mappedTable) {
        $exportOutput = & ./src/sync-export.ps1 -From source -Tables $mappedTable.sourceTable -ConfigFile $ConfigFile -NonInteractive 2>&1
        if ($LASTEXITCODE -eq 0) {
            return @{ Success = $true; Message = "Table mapping test passed for $($mappedTable.sourceTable) -> $($mappedTable.targetTable)" }
        } else {
            return @{ Success = $false; Message = "Table mapping export failed" }
        }
    } else {
        return @{ Success = $false; Message = "No table mapping configuration found for testing" }
    }
}

# Test 5: Export Where Clause
Test-Scenario -Name "Filtered Export" -Description "Test export with WHERE clause filtering" -Test {
    $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
    $filteredTable = $config.syncTables | Where-Object { $null -ne $_.exportWhere } | Select-Object -First 1
    
    if ($filteredTable) {
        $exportOutput = & ./src/sync-export.ps1 -From source -Tables $filteredTable.sourceTable -ConfigFile $ConfigFile -NonInteractive 2>&1 | Out-String
        
        if ($exportOutput -match "filtered:") {
            return @{ Success = $true; Message = "WHERE clause filtering applied successfully" }
        } else {
            return @{ Success = $false; Message = "WHERE clause not detected in output" }
        }
    } else {
        return @{ Success = $false; Message = "No exportWhere configuration found for testing" }
    }
}

# Test 6: Multiple Tables Export
Test-Scenario -Name "Multiple Tables" -Description "Test exporting multiple tables at once" -Test {
    $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
    $tables = ($config.syncTables | Select-Object -First 3).sourceTable -join ","
    
    if ($tables) {
        $exportOutput = & ./src/sync-export.ps1 -From source -Tables $tables -ConfigFile $ConfigFile -NonInteractive 2>&1
        if ($LASTEXITCODE -eq 0) {
            return @{ Success = $true; Message = "Multiple tables export successful" }
        } else {
            return @{ Success = $false; Message = "Multiple tables export failed" }
        }
    } else {
        return @{ Success = $false; Message = "Not enough tables in config for testing" }
    }
}

# Test 7: Missing Table Handling
Test-Scenario -Name "Missing Table" -Description "Test handling of non-existent tables" -Test {
    $exportOutput = & ./src/sync-export.ps1 -From source -Tables "non_existent_table" -ConfigFile $ConfigFile -NonInteractive 2>&1 | Out-String
    
    if ($exportOutput -match "SKIP.*Not in config") {
        return @{ Success = $true; Message = "Missing table handled gracefully" }
    } else {
        return @{ Success = $false; Message = "Missing table not handled properly" }
    }
}

# Test 8: Import Dry-Run vs Execute
Test-Scenario -Name "Import Modes" -Description "Test dry-run vs execute modes" -Test {
    # First ensure we have an export
    $null = & ./src/sync-export.ps1 -From source -Tables "settings" -ConfigFile $ConfigFile -NonInteractive 2>&1
    
    # Test dry-run (default)
    $dryRunOutput = & ./src/sync-import.ps1 -To target -Tables "settings" -ConfigFile $ConfigFile 2>&1 | Out-String
    
    if ($dryRunOutput -match "DRY-RUN.*No changes were made") {
        return @{ Success = $true; Message = "Dry-run mode working correctly" }
    } else {
        return @{ Success = $false; Message = "Dry-run mode not functioning as expected" }
    }
}

# Test 9: Validation Errors
Test-Scenario -Name "Validation" -Description "Test configuration validation" -Test {
    # Create invalid config
    $invalidConfig = @{
        databases = @{
            invalid_source = @{
                server = "nonexistent"
                database = "nonexistent"
                auth = "windows"
            }
        }
        syncTables = @()
        exportPath = "./sync-data"
    } | ConvertTo-Json -Depth 10
    
    $tempConfig = "test/temp-invalid-config.json"
    $invalidConfig | Out-File -FilePath $tempConfig -Encoding UTF8
    
    $validationOutput = & ./src/sync-export.ps1 -From invalid_source -ConfigFile $tempConfig 2>&1 | Out-String
    Remove-Item $tempConfig -ErrorAction SilentlyContinue
    
    if ($validationOutput -match "validation failed|not found|error") {
        return @{ Success = $true; Message = "Validation errors caught correctly" }
    } else {
        return @{ Success = $false; Message = "Validation should have failed but didn't" }
    }
}

# Test 10: Performance with Large Dataset
Test-Scenario -Name "Performance" -Description "Test performance with larger dataset" -Test {
    # This assumes audit_log table has many rows
    $startTime = Get-Date
    $exportOutput = & ./src/sync-export.ps1 -From source -Tables "audit_log" -ConfigFile $ConfigFile -NonInteractive 2>&1 | Out-String
    $duration = (Get-Date) - $startTime
    
    if ($LASTEXITCODE -eq 0) {
        if ($exportOutput -match "(\d+) rows") {
            $rowCount = $Matches[1]
            $rowsPerSecond = [int]($rowCount / $duration.TotalSeconds)
            return @{ Success = $true; Message = "Exported $rowCount rows in $($duration.TotalSeconds)s ($rowsPerSecond rows/sec)" }
        } else {
            return @{ Success = $true; Message = "Export completed in $($duration.TotalSeconds)s" }
        }
    } else {
        return @{ Success = $false; Message = "Performance test export failed" }
    }
}

# Summary Report
Write-Host "`n=== TEST SUMMARY ===" -ForegroundColor Cyan
Write-Host "Total Tests: $($testResults.Passed + $testResults.Failed + $testResults.Skipped)" -ForegroundColor White
Write-Host "Passed: $($testResults.Passed)" -ForegroundColor Green
Write-Host "Failed: $($testResults.Failed)" -ForegroundColor Red
Write-Host "Skipped: $($testResults.Skipped)" -ForegroundColor Yellow

if ($testResults.Failed -gt 0) {
    Write-Host "`nFailed Tests:" -ForegroundColor Red
    $testResults.Details | Where-Object { -not $_.Result } | ForEach-Object {
        Write-Host "  - $($_.Name): $($_.Message)" -ForegroundColor Red
    }
}

# Return exit code based on results
exit $testResults.Failed