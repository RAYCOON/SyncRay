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

## Interactive Mode

### Using syncray.ps1 Without Parameters
When you run `syncray.ps1` without any parameters, it enters interactive mode:

```powershell
./src/syncray.ps1
```

Interactive prompts guide you through:
1. **Operation Selection**: Export, Import, Sync, or Analyze
2. **Database Selection**: Choose from configured databases
3. **Table Selection**: All tables or specific tables
4. **Mode Selection**: Preview or Execute
5. **Report Options**: Create CSV reports (optional)

Example interaction:
```
=== SYNCRAY INTERACTIVE MODE ===

Available operations:
1. Export - Export data from source database
2. Import - Import data to target database
3. Sync - Direct sync from source to target
4. Analyze - Analyze data quality only

Select operation (1-4): 3

Available source databases:
1. prod
2. dev
3. staging

Select source database (1-3): 1

Available target databases:
1. dev
2. staging

Select target database (1-2): 1

Sync tables:
1. All configured tables
2. Select specific tables

Select option (1-2): 2

Available tables:
1. Users
2. Orders
3. Products
4. Categories

Select tables (comma-separated numbers): 1,2

Execution mode:
1. Preview changes (dry-run)
2. Execute changes

Select mode (1-2): 1
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

### Replace Mode Example
Complete table replacement (useful for reference data):

```json
{
  "syncTables": [{
    "sourceTable": "Countries",
    "replaceMode": true,
    "preserveIdentity": true
  }, {
    "sourceTable": "States",
    "replaceMode": true,
    "preserveIdentity": true
  }, {
    "sourceTable": "Cities",
    "replaceMode": true,
    "preserveIdentity": true
  }]
}
```

**Note**: Tables are processed in configuration order. For foreign key dependencies, list child tables before parent tables.

### Handling Duplicates
When duplicates are detected during import with `-Execute`:

```
[WARNING] Validation failed due to duplicate records in the following tables:
  - Users
  - Orders

Would you like to:
1) View detailed duplicate records
2) Automatically remove duplicates (keeps record with lowest primary key)
3) Cancel operation

Select option (1-3): 1

=== Duplicate Records in Users ===
UserID | Email           | Name        | DuplicateGroup
-------|-----------------|-------------|---------------
1234   | john@email.com  | John Doe    | 1
5678   | john@email.com  | John D.     | 1
2345   | jane@email.com  | Jane Smith  | 2
6789   | jane@email.com  | J. Smith    | 2

Now would you like to:
1) Automatically remove duplicates
2) Cancel operation

Select option (1-2): 1
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

### Data Quality Analysis
Analyze data without exporting:

```powershell
# Analyze all tables
./src/sync-export.ps1 -From prod -Analyze

# Analyze with CSV reports
./src/sync-export.ps1 -From prod -Analyze -CreateReports

# Analyze specific tables
./src/sync-export.ps1 -From prod -Tables "Users,Orders" -Analyze -CreateReports -ReportPath ./reports
```

Analysis report includes:
- Duplicate records by matchOn fields
- Tables that would be skipped
- Validation issues
- Row counts and data volumes

Example CSV reports generated:
- `duplicate_issues.csv` - All duplicate records found
- `skipped_tables.csv` - Tables that would be skipped
- `data_quality_summary.csv` - Overall quality metrics

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