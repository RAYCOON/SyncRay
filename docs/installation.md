# Installation Guide

## Prerequisites

### PowerShell
- Windows: PowerShell 5.0+ (included in Windows 10)
- macOS/Linux: PowerShell Core 6.0+ ([Download](https://github.com/PowerShell/PowerShell))

### SQL Server Requirements
- SQL Server 2012 or higher
- SQL Server Authentication or Windows Authentication
- Network access to SQL Server instances

### Required Permissions
- SELECT on source tables
- SELECT, INSERT, UPDATE, DELETE on target tables
- VIEW DEFINITION for schema information

## Installation Steps

### 1. Clone or Download

```bash
# Clone from GitHub
git clone https://github.com/yourusername/SyncRay.git
cd SyncRay

# Or download and extract ZIP
```

### 2. Configure Database Connections

1. Copy the example configuration:
   ```bash
   cp src/sync-config.example.json src/sync-config.json
   ```

2. Edit `src/sync-config.json` with your database details:
   ```json
   {
     "databases": {
       "source": {
         "server": "SERVER1\\INSTANCE",
         "database": "ProductionDB",
         "auth": "windows"
       },
       "target": {
         "server": "SERVER2",
         "database": "TestDB",
         "auth": "sql",
         "user": "sa",
         "password": "your-password"
       }
     }
   }
   ```

### 3. Test Connection

Run validation to test your configuration:

```powershell
# Windows
.\src\sync-export.ps1 -From source -Tables NonExistentTable

# macOS/Linux
pwsh src/sync-export.ps1 -From source -Tables NonExistentTable
```

This will validate your connection without exporting data.

## Platform-Specific Notes

### Windows
- Use PowerShell or PowerShell ISE
- Windows Authentication works out of the box
- Use backslash for named instances: `SERVER\INSTANCE`

### macOS/Linux
- Install PowerShell Core first
- Use `pwsh` command instead of `powershell`
- SQL Authentication recommended
- Forward slash for paths: `./src/sync-export.ps1`

### Docker Containers
- Ensure container ports are exposed
- Use container name or IP as server
- SQL Authentication required

## Troubleshooting

### Connection Issues
- Verify SQL Server is accessible: `Test-NetConnection -ComputerName servername -Port 1433`
- Check firewall rules
- Verify SQL Server Browser service for named instances
- Try IP address instead of hostname

### Permission Errors
- Ensure user has required database permissions
- For Windows Auth, run PowerShell as the appropriate user
- Check SQL Server error logs for detailed messages

### PowerShell Execution Policy
If scripts won't run:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## Next Steps

After successful installation:
1. Review [Configuration Reference](configuration.md)
2. Try the [Usage Examples](examples.md)
3. Set up your table synchronization rules