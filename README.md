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

3. **Export data from source**:
   ```powershell
   ./src/sync-export.ps1 -From prod
   
   # With debug output
   ./src/sync-export.ps1 -From prod -ShowSQL
   
   # Non-interactive mode (auto-skip tables with duplicates)
   ./src/sync-export.ps1 -From prod -NonInteractive
   ```

4. **Preview changes** (dry-run):
   ```powershell
   ./src/sync-import.ps1 -To dev
   ```

5. **Apply changes**:
   ```powershell
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

## Safety Features

- **Validation First**: Comprehensive pre-flight checks before any operation
- **Dry-Run Default**: Always preview changes before execution
- **Safety Confirmation**: Explicit confirmation required for execution
- **Transaction Rollback**: Automatic rollback on any error
- **Duplicate Detection**: Ensures matchOn fields identify unique records

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