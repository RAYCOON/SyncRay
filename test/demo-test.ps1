# Demo Test for SyncRay
# Shows how the tools work together

Write-Host "`n=== SyncRay Demo Test ===" -ForegroundColor Cyan
Write-Host "This demo shows SyncRay's capabilities without requiring a database" -ForegroundColor Gray

# Create a demo configuration
$demoConfig = @{
    databases = @{
        demo_source = @{
            server = "demo-server"
            database = "DemoSourceDB"
            auth = "windows"
        }
        demo_target = @{
            server = "demo-server"
            database = "DemoTargetDB"
            auth = "windows"
        }
    }
    syncTables = @(
        @{
            sourceTable = "Users"
            matchOn = @("UserID")
            allowInserts = $true
            allowUpdates = $true
            allowDeletes = $true
        },
        @{
            sourceTable = "Products"
            matchOn = @("ProductID")
            ignoreColumns = @("LastModified", "ModifiedBy")
            allowInserts = $true
            allowUpdates = $true
            allowDeletes = $false
        },
        @{
            sourceTable = "Orders"
            matchOn = @("OrderID")
            exportWhere = "Status = 'Completed'"
            allowInserts = $true
            allowUpdates = $true
            allowDeletes = $false
        }
    )
    exportPath = "./demo-sync-data"
}

$demoConfig | ConvertTo-Json -Depth 10 | Set-Content "demo-config.json"
Write-Host "`n✓ Created demo configuration" -ForegroundColor Green

# Test 1: Show help
Write-Host "`n1. Testing Help System" -ForegroundColor Yellow
Write-Host "   Running: syncray.ps1 -Help" -ForegroundColor Gray
$help = & ../src/syncray.ps1 -Help 2>&1 | Select-Object -First 20 | Out-String
Write-Host $help

# Test 2: Test configuration validation
Write-Host "`n2. Testing Configuration Validation" -ForegroundColor Yellow
Write-Host "   Running: sync-export.ps1 -From demo_source -ConfigFile demo-config.json" -ForegroundColor Gray
Write-Host "   (This will fail because the database doesn't exist, but shows validation)" -ForegroundColor DarkGray

$result = & ../src/sync-export.ps1 -From demo_source -ConfigFile demo-config.json 2>&1 | Out-String
Write-Host $result

# Test 3: Show what happens with missing database
Write-Host "`n3. Testing Error Handling" -ForegroundColor Yellow
Write-Host "   Running: sync-export.ps1 -From nonexistent -ConfigFile demo-config.json" -ForegroundColor Gray

$result = & ../src/sync-export.ps1 -From nonexistent -ConfigFile demo-config.json 2>&1 | Out-String
Write-Host $result

# Test 4: Create fake export data
Write-Host "`n4. Creating Sample Export Data" -ForegroundColor Yellow
$exportPath = "./demo-sync-data"
if (-not (Test-Path $exportPath)) {
    New-Item -ItemType Directory -Path $exportPath | Out-Null
}

# Create sample Users export
$usersData = @{
    metadata = @{
        sourceTable = "Users"
        exportDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        rowCount = 3
        columns = @(
            @{ name = "UserID"; type = "int"; isPrimaryKey = $true }
            @{ name = "Username"; type = "nvarchar"; maxLength = 50 }
            @{ name = "Email"; type = "nvarchar"; maxLength = 100 }
            @{ name = "IsActive"; type = "bit" }
        )
        primaryKeys = @("UserID")
        matchOn = @("UserID")
        ignoreColumns = @()
        allowDeletes = $true
    }
    data = @(
        @{ UserID = 1; Username = "john_doe"; Email = "john@example.com"; IsActive = $true }
        @{ UserID = 2; Username = "jane_smith"; Email = "jane@example.com"; IsActive = $true }
        @{ UserID = 3; Username = "bob_wilson"; Email = "bob@example.com"; IsActive = $false }
    )
}

$usersData | ConvertTo-Json -Depth 10 | Set-Content "$exportPath/Users.json"
Write-Host "✓ Created sample Users.json export file" -ForegroundColor Green

# Test 5: Test import preview (will fail but shows the process)
Write-Host "`n5. Testing Import Preview" -ForegroundColor Yellow
Write-Host "   Running: sync-import.ps1 -To demo_target -ConfigFile demo-config.json" -ForegroundColor Gray
Write-Host "   (This will fail at database connection, but shows the import process)" -ForegroundColor DarkGray

$result = & ../src/sync-import.ps1 -To demo_target -ConfigFile demo-config.json -Tables "Users" 2>&1 | Out-String
Write-Host $result

# Cleanup
Write-Host "`n6. Cleanup" -ForegroundColor Yellow
Remove-Item "demo-config.json" -Force -ErrorAction SilentlyContinue
Remove-Item $exportPath -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "✓ Cleaned up demo files" -ForegroundColor Green

Write-Host "`n=== Demo Complete ===" -ForegroundColor Cyan
Write-Host @"

This demo showed:
- Configuration structure and validation
- Error handling for missing databases
- Export file format
- Import preview process

To run actual tests, you need:
1. SQL Server instances with test databases
2. Update the configuration with real connection details
3. Run the comprehensive test suite

For more information, see test/TESTING.md
"@ -ForegroundColor Gray