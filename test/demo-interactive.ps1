# Demo interactive mode with automated input
param(
    [int]$Scenario = 1
)

Write-Host "`n=== INTERACTIVE MODE DEMO ===" -ForegroundColor Cyan
Write-Host "Demonstrating scenario $Scenario" -ForegroundColor Yellow
Write-Host ""

# Define scenarios
$scenarios = @{
    1 = @{
        name = "Export with analysis"
        inputs = "1`n1`n1`n3`n2`ny"
        description = "Export -> dev -> All tables -> Analyze -> Yes reports -> Confirm"
        expected = "-From dev -Analyze -CreateReport"
    }
    2 = @{
        name = "Import preview"
        inputs = "2`n1`n2`nSedBPCVs`n1`n1`ny"
        description = "Import -> dev -> Specific tables -> SedBPCVs -> Preview -> No reports -> Confirm"
        expected = "-To dev -Tables SedBPCVs"
    }
    3 = @{
        name = "Full sync"
        inputs = "3`n2`n1`n1`n2`n2`ny"
        description = "Sync -> prod -> dev -> All tables -> Execute -> Yes reports -> Confirm"
        expected = "-From prod -To dev -Execute -CreateReport"
    }
    4 = @{
        name = "Target analysis"
        inputs = "4`n2`n1`n2`ny"
        description = "Analyze -> Target database -> dev -> Yes reports -> Confirm"
        expected = "-To dev -Analyze -CreateReport"
    }
}

$scenario = $scenarios[$Scenario]

Write-Host "Scenario: $($scenario.name)" -ForegroundColor White
Write-Host "Steps: $($scenario.description)" -ForegroundColor Gray
Write-Host "Expected command: syncray.ps1 $($scenario.expected)" -ForegroundColor Green
Write-Host ""
Write-Host "Input sequence: $($scenario.inputs -replace "`n", " -> ")" -ForegroundColor Yellow
Write-Host ""

# Run with piped input
Write-Host "Running interactive mode..." -ForegroundColor Cyan
Write-Host ""

$scenario.inputs | & "$PSScriptRoot\..\src\syncray.ps1"