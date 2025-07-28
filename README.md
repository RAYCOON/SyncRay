# SyncRay

A powerful PowerShell-based database synchronization tool that enables seamless data migration between SQL Server databases with full INSERT, UPDATE, and DELETE support.

![PowerShell](https://img.shields.io/badge/PowerShell-5.0%2B-blue)
![SQL Server](https://img.shields.io/badge/SQL%20Server-2012%2B-red)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Full CRUD Support**: Synchronize tables with INSERT, UPDATE, and DELETE operations
- **Intelligent Matching**: Flexible field matching beyond primary keys
- **Dry-Run Mode**: Preview changes before execution (default behavior)
- **Transaction Safety**: All operations wrapped in transactions with automatic rollback
- **Comprehensive Validation**: Pre-flight checks for configuration, tables, and permissions
- **Export Filtering**: WHERE clause support for selective data export
- **Identity Handling**: Configurable IDENTITY_INSERT support
- **Detailed Reporting**: Table-formatted change summaries and execution statistics

## Requirements

- PowerShell 5.0 or higher
- SQL Server 2012 or higher
- Appropriate database permissions (SELECT, INSERT, UPDATE, DELETE)

## Quick Start

### New: Central SyncRay Command

The easiest way to use SyncRay is through the central `syncray.ps1` script:

```powershell
# Export from production
./src/syncray.ps1 -From production

# Import to development (preview)
./src/syncray.ps1 -To development

# Direct sync from production to development
./src/syncray.ps1 -From production -To development

# Analyze data quality
./src/syncray.ps1 -From production -Analyze

# Get help
./src/syncray.ps1 -Help
```

### Setup Instructions

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/SyncRay.git
   cd SyncRay
   ```

2. **Configure your databases** in `src/sync-config.json`:
   ```json
   {
     "databases": {
       "prod": {
         "server": "PROD-SERVER",
         "database": "ProductionDB",
         "auth": "windows"
       },
       "dev": {
         "server": "DEV-SERVER",
         "database": "DevelopmentDB",
         "auth": "sql",
         "user": "sa",
         "password": "password"
       }
     }
   }
   ```

3. **Use SyncRay**:

   **Option A: Using Central Script (Recommended)**
   ```powershell
   # Export data
   ./src/syncray.ps1 -From prod
   
   # Import data (preview)
   ./src/syncray.ps1 -To dev
   
   # Direct sync
   ./src/syncray.ps1 -From prod -To dev -Execute
   ```

   **Option B: Using Individual Scripts**
   ```powershell
   # Export
   ./src/sync-export.ps1 -From prod
   
   # Import (preview)
   ./src/sync-import.ps1 -To dev
   
   # Import (execute)
   ./src/sync-import.ps1 -To dev -Execute
   ```

## Documentation

- [Installation Guide](docs/installation.md)
- [Configuration Reference](docs/configuration.md)
- [Usage Examples](docs/examples.md)
- [Troubleshooting](docs/troubleshooting.md)

## Configuration

### Table Synchronization Settings

```json
{
  "syncTables": [{
    "sourceTable": "Users",
    "targetTable": "Users_Archive",
    "matchOn": ["UserID"],
    "ignoreColumns": ["LastModified"],
    "allowInserts": true,
    "allowUpdates": true,
    "allowDeletes": false,
    "exportWhere": "IsActive = 1"
  }]
}
```

### Key Parameters

- **matchOn**: Fields for record matching (auto-detects primary key if empty)
- **ignoreColumns**: Columns to exclude from comparison
- **allowInserts/Updates/Deletes**: Control allowed operations
- **exportWhere**: Filter source data with SQL WHERE clause
- **replaceMode**: Delete all records before inserting (full table replacement)

### Replace Mode (New Feature)

When `replaceMode: true` is set for a table:
1. **All existing records are deleted** from the target table
2. **All records from export are inserted** 
3. **No UPDATE or individual DELETE** operations are performed
4. Useful for reference tables or complete data refreshes
5. Executes in transaction for safety

Example configuration:
```json
{
  "sourceTable": "ReferenceData",
  "replaceMode": true,
  "preserveIdentity": true
}
```

## Command Reference

### syncray.ps1 (Central Tool)

The main entry point for all SyncRay operations. Automatically determines the operation based on parameters.

**Parameters:**
- `-From <string>`: Source database (triggers export mode)
- `-To <string>`: Target database (triggers import mode)
- `-From <string> -To <string>`: Both (triggers sync mode)
- `-Analyze`: Analyze data quality without exporting
- `-Validate`: Validate configuration without processing
- `-Execute`: Apply changes (for import/sync modes)
- `-SkipOnDuplicates`: Skip tables with duplicate records
- `-CreateReports`: Create CSV reports for problems
- `-ReportPath <string>`: Custom path for CSV reports
- `-CsvDelimiter <string>`: CSV delimiter
- `-ShowSQL`: Show SQL statements for debugging
- `-Help`: Show help information

**Examples:**
```powershell
# Export mode
./src/syncray.ps1 -From production

# Import mode (preview)
./src/syncray.ps1 -To development

# Sync mode (direct transfer)
./src/syncray.ps1 -From production -To development -Execute

# Analysis mode
./src/syncray.ps1 -From production -Analyze
```

### sync-export.ps1

Export data from source database to JSON files.

**Parameters:**
- `-From <string>` (required): Source database key from configuration
- `-ConfigFile <string>`: Path to configuration file (default: sync-config.json)
- `-Tables <string>`: Comma-separated list of specific tables to export
- `-Analyze`: Analyze data quality and create reports without exporting
- `-Validate`: Validate configuration and data without exporting or creating reports
- `-SkipOnDuplicates`: Automatically skip tables with duplicate records
- `-CreateReports`: Create CSV reports for data quality issues
- `-ReportPath <string>`: Custom path for CSV reports
- `-CsvDelimiter <string>`: CSV delimiter (default: culture-specific)
- `-ShowSQL`: Show SQL statements and detailed debugging information

**Usage Examples:**
```powershell
# Standard export
./src/sync-export.ps1 -From prod

# Export with problem reports
./src/sync-export.ps1 -From prod -CreateReports

# Analyze data quality only
./src/sync-export.ps1 -From prod -Analyze

# Export specific tables with SQL debug output
./src/sync-export.ps1 -From prod -Tables "Users,Orders" -ShowSQL
```

### sync-import.ps1

Import data from JSON files to target database.

**Parameters:**
- `-To <string>` (required): Target database key from configuration
- `-ConfigFile <string>`: Path to configuration file (default: sync-config.json)
- `-Tables <string>`: Comma-separated list of specific tables to import
- `-Execute`: Apply changes (default is dry-run)
- `-ShowSQL`: Show SQL statements for debugging

**Duplicate Handling (New):**
When duplicates are detected during import validation, the tool offers interactive options:
1. **View detailed duplicate records** - Shows all duplicate records with their data
2. **Automatically remove duplicates** - Removes duplicates keeping the record with the lowest primary key
3. **Cancel operation** - Abort the import

## Safety Features

- **Validation First**: Comprehensive pre-flight checks before any operation
- **Dry-Run Default**: Always preview changes before execution
- **Safety Confirmation**: Explicit confirmation required for execution
- **Transaction Rollback**: Automatic rollback on any error
- **Duplicate Detection**: Ensures matchOn fields identify unique records
- **Safe Duplicate Removal**: Interactive confirmation with transaction protection

## Example Output

```
=== CHANGES DETECTED ===

Table                    | Insert | Update | Delete
-------------------------------------------------
Users                    |    125 |     37 |      5
Orders                   |    450 |      0 |      0
Products                 |      0 |     15 |      2
-------------------------------------------------
TOTAL                    |    575 |     52 |      7

WARNING: You are about to modify the database!

Do you want to execute these changes? (yes/no):
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with PowerShell and SQL Server
- Inspired by the need for reliable database synchronization

---

Developed by the Raycoon Team