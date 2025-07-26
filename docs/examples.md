# Usage Examples

## Basic Synchronization

### Full Database Sync
Export all configured tables and sync to target:

```powershell
# Export from production
./src/sync-export.ps1 -From prod

# Preview changes (dry-run)
./src/sync-import.ps1 -To dev

# Apply changes
./src/sync-import.ps1 -To dev -Execute
```

### Single Table Sync
Sync specific tables only:

```powershell
# Export specific tables
./src/sync-export.ps1 -From prod -Tables "Users,Orders"

# Import specific tables
./src/sync-import.ps1 -To dev -Tables "Users" -Execute
```

## Common Scenarios

### 1. Development Database Refresh
Refresh development database with production data (anonymized):

```json
{
  "syncTables": [{
    "sourceTable": "Users",
    "matchOn": ["UserID"],
    "ignoreColumns": ["Password", "Email"],
    "allowDeletes": true
  }]
}
```

### 2. Data Archival
Move old records to archive database:

```json
{
  "syncTables": [{
    "sourceTable": "Orders",
    "targetTable": "Orders_Archive",
    "matchOn": ["OrderID"],
    "allowInserts": true,
    "allowUpdates": false,
    "allowDeletes": false,
    "exportWhere": "OrderDate < '2023-01-01'"
  }]
}
```

### 3. Partial Data Sync
Sync only active records:

```json
{
  "syncTables": [{
    "sourceTable": "Customers",
    "matchOn": ["CustomerID"],
    "exportWhere": "IsActive = 1 AND Country = 'USA'"
  }]
}
```

### 4. Master Data Distribution
Distribute reference data to multiple databases:

```powershell
# Export master data once
./src/sync-export.ps1 -From master -Tables "Products,Categories"

# Import to multiple targets
./src/sync-import.ps1 -To store1 -Execute
./src/sync-import.ps1 -To store2 -Execute
./src/sync-import.ps1 -To store3 -Execute
```

## Advanced Usage

### Composite Key Matching
For tables without single primary keys:

```json
{
  "syncTables": [{
    "sourceTable": "OrderDetails",
    "matchOn": ["OrderID", "ProductID"],
    "allowDeletes": true
  }]
}
```

### Read-Only Sync
Only add new records, never modify existing:

```json
{
  "syncTables": [{
    "sourceTable": "AuditLogs",
    "matchOn": ["LogID"],
    "allowInserts": true,
    "allowUpdates": false,
    "allowDeletes": false
  }]
}
```

### Identity Column Handling
Preserve identity values during sync:

```json
{
  "syncTables": [{
    "sourceTable": "Products",
    "matchOn": ["ProductID"],
    "preserveIdentity": true,
    "ignoreColumns": []
  }]
}
```

## Workflow Examples

### Daily Sync Workflow
```powershell
# Morning sync script
$date = Get-Date -Format "yyyy-MM-dd"
Write-Host "Starting daily sync for $date"

# Export production data
./src/sync-export.ps1 -From prod

# Backup current dev data (optional)
Invoke-SqlCmd -Query "BACKUP DATABASE DevDB TO DISK='C:\Backups\DevDB_$date.bak'"

# Sync to development
./src/sync-import.ps1 -To dev -Execute

Write-Host "Daily sync completed"
```

### Selective Table Refresh
```powershell
# Refresh only specific tables
$tables = @("Users", "Orders", "Products")

foreach ($table in $tables) {
    Write-Host "Syncing $table..."
    ./src/sync-export.ps1 -From prod -Tables $table
    ./src/sync-import.ps1 -To dev -Tables $table -Execute
}
```

### Pre-sync Validation
```powershell
# Validate before sync
./src/sync-export.ps1 -From prod -Tables "NonExistent"

if ($LASTEXITCODE -eq 0) {
    Write-Host "Validation passed, proceeding with sync"
    ./src/sync-export.ps1 -From prod
    ./src/sync-import.ps1 -To dev -Execute
} else {
    Write-Host "Validation failed, sync aborted" -ForegroundColor Red
}
```

## Output Examples

### Dry-Run Output
```
=== SYNC IMPORT ===
Target: dev (DEV-SERVER)
Mode: DRY-RUN

Analyzing Users...
Analyzing Orders...

=== CHANGES DETECTED ===

Table                    | Insert | Update | Delete
-------------------------------------------------
Users                    |     15 |     82 |      3
Orders                   |    234 |      0 |      0
-------------------------------------------------
TOTAL                    |    249 |     82 |      3

[DRY-RUN] No changes were made
Run with -Execute to apply these changes
```

### Execution Output
```
=== SYNC IMPORT ===
Target: dev (DEV-SERVER)
Mode: EXECUTE

=== CHANGES DETECTED ===
Table                    | Insert | Update | Delete
-------------------------------------------------
Users                    |     15 |     82 |      3
-------------------------------------------------

WARNING: You are about to modify the database!

Do you want to execute these changes? (yes/no): yes

=== EXECUTING CHANGES ===

→ Users
  Inserting 15 rows... [OK]
  Updating 82 rows... [OK]
  Deleting 3 rows... [OK]
  ✓ Transaction committed

✓ All changes executed successfully

=== EXECUTION STATISTICS ===
Table                    | Insert | Update | Delete
-------------------------------------------------
Users                    |     15 |     82 |      3
-------------------------------------------------
TOTAL                    |     15 |     82 |      3
```