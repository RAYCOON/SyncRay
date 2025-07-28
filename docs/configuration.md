# Configuration Reference

## Configuration File Structure

SyncRay uses a JSON configuration file (`sync-config.json`) to define database connections and synchronization rules.

## Database Configuration

### Connection Properties

```json
{
  "databases": {
    "connectionName": {
      "server": "servername",
      "database": "databasename",
      "auth": "windows|sql",
      "user": "username",        // Only for SQL auth
      "password": "password"      // Only for SQL auth
    }
  }
}
```

### Authentication Types

**Windows Authentication**
```json
{
  "server": "MYSERVER\\SQLEXPRESS",
  "database": "MyDatabase",
  "auth": "windows"
}
```

**SQL Server Authentication**
```json
{
  "server": "myserver.database.windows.net,1433",
  "database": "MyDatabase",
  "auth": "sql",
  "user": "myuser",
  "password": "mypassword"
}
```

## Table Synchronization Settings

### Basic Configuration

```json
{
  "syncTables": [{
    "sourceTable": "TableName",
    "matchOn": ["PrimaryKeyField"]
  }]
}
```

### Advanced Configuration

```json
{
  "syncTables": [{
    "sourceTable": "Users",
    "targetTable": "Users_Archive",
    "matchOn": ["UserID", "CompanyID"],
    "ignoreColumns": ["LastModified", "UpdatedBy"],
    "allowInserts": true,
    "allowUpdates": true,
    "allowDeletes": false,
    "preserveIdentity": false,
    "exportWhere": "IsActive = 1 AND CreatedDate > '2024-01-01'"
  }]
}
```

### Table Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `sourceTable` | string | required | Source table name |
| `targetTable` | string | sourceTable | Target table name (if different) |
| `matchOn` | array | auto (PK) | Fields for record matching |
| `ignoreColumns` | array | [] | Columns to ignore in comparison |
| `allowInserts` | boolean | true | Allow INSERT operations |
| `allowUpdates` | boolean | true | Allow UPDATE operations |
| `allowDeletes` | boolean | false | Allow DELETE operations |
| `preserveIdentity` | boolean | false | Use IDENTITY_INSERT |
| `exportWhere` | string | null | WHERE clause for filtering |
| `replaceMode` | boolean | false | Delete all records before inserting |

## Global Settings

```json
{
  "exportPath": "./sync-data",
  "defaultDryRun": true,
  "batchSize": 1000
}
```

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `exportPath` | string | "./sync-data" | Directory for export files |
| `defaultDryRun` | boolean | true | Always dry-run by default |
| `batchSize` | integer | 1000 | Records per batch (future use) |

## Best Practices

### matchOn Fields
- **Always specify explicitly** for clarity
- Must uniquely identify records
- Can use composite keys: `["Field1", "Field2"]`
- Auto-detects primary key if not specified

### ignoreColumns Usage
- Use for timestamp columns
- Use for computed columns
- Use for identity columns (when not preserving)

### Export Filtering
- Use `exportWhere` to sync subsets of data
- Test WHERE clause syntax in SQL first
- Consider performance impact on large tables

### Security
- Never commit passwords to git
- Use environment variables for sensitive data
- Consider using integrated authentication where possible

## Configuration Examples

### Simple Mirror
```json
{
  "syncTables": [{
    "sourceTable": "Products",
    "matchOn": ["ProductID"],
    "allowDeletes": true
  }]
}
```

### Archive Pattern
```json
{
  "syncTables": [{
    "sourceTable": "Orders",
    "targetTable": "Orders_Archive",
    "matchOn": ["OrderID"],
    "allowInserts": true,
    "allowUpdates": false,
    "allowDeletes": false,
    "exportWhere": "OrderDate < DATEADD(year, -1, GETDATE())"
  }]
}
```

### Partial Sync
```json
{
  "syncTables": [{
    "sourceTable": "Customers",
    "matchOn": ["CustomerID"],
    "ignoreColumns": ["LastLogin", "SessionToken"],
    "allowInserts": true,
    "allowUpdates": true,
    "allowDeletes": false,
    "exportWhere": "IsActive = 1"
  }]
}
```

### Replace Mode (Full Table Replacement)
```json
{
  "syncTables": [{
    "sourceTable": "ReferenceData",
    "replaceMode": true,
    "preserveIdentity": true
  }]
}
```

When `replaceMode` is enabled:
- All existing records in the target table are deleted
- All records from the export are inserted
- No UPDATE or individual DELETE operations are performed
- matchOn fields are not required (and ignored if specified)
- Duplicate checking is skipped
- Executes in a transaction for safety

**Important**: Order matters for tables with foreign key relationships:
```json
{
  "syncTables": [
    { "sourceTable": "OrderDetails", "replaceMode": true },
    { "sourceTable": "Orders", "replaceMode": true },
    { "sourceTable": "Customers", "replaceMode": true }
  ]
}
```

## Validation

Before any operation, SyncRay validates:
- Database connectivity
- Table existence
- Column existence for matchOn fields
- matchOn field uniqueness (skipped for replaceMode)
- WHERE clause syntax
- User permissions

Run validation only:
```powershell
./src/sync-export.ps1 -From source -Validate
```

This runs all checks without exporting data.

## Command Line Parameters

### syncray.ps1 (Main Entry Point)

| Parameter | Type | Description |
|-----------|------|-------------|
| `-From` | string | Source database key (triggers export mode) |
| `-To` | string | Target database key (triggers import mode) |
| `-Interactive` | switch | Interactive mode with prompts |
| `-Analyze` | switch | Analyze data quality without exporting |
| `-Validate` | switch | Validate configuration only |
| `-Execute` | switch | Apply changes (for import/sync) |
| `-Tables` | string | Comma-separated list of tables |
| `-SkipOnDuplicates` | switch | Skip tables with duplicates |
| `-CreateReports` | switch | Create CSV reports |
| `-ReportPath` | string | Custom report directory |
| `-CsvDelimiter` | string | CSV delimiter character |
| `-ShowSQL` | switch | Show SQL statements |
| `-Help` | switch | Show help information |

### sync-export.ps1

| Parameter | Type | Description |
|-----------|------|-------------|
| `-From` | string | **Required** - Source database key |
| `-ConfigFile` | string | Configuration file path |
| `-Tables` | string | Specific tables to export |
| `-Analyze` | switch | Analyze only, no export |
| `-Validate` | switch | Validate only |
| `-SkipOnDuplicates` | switch | Skip duplicate tables |
| `-CreateReports` | switch | Create quality reports |
| `-ReportPath` | string | Report output directory |
| `-CsvDelimiter` | string | CSV delimiter |
| `-ShowSQL` | switch | Debug SQL output |

### sync-import.ps1

| Parameter | Type | Description |
|-----------|------|-------------|
| `-To` | string | **Required** - Target database key |
| `-ConfigFile` | string | Configuration file path |
| `-Tables` | string | Specific tables to import |
| `-Execute` | switch | Apply changes (default: preview) |
| `-ShowSQL` | switch | Debug SQL output |

**Note**: Import offers interactive duplicate cleanup when duplicates are detected in Execute mode.