# Troubleshooting Guide

## Common Issues and Solutions

### Connection Errors

#### "Cannot connect to SQL Server"
**Symptoms**: Connection timeout or server not found

**Solutions**:
1. Verify server name and instance
   ```powershell
   Test-NetConnection -ComputerName servername -Port 1433
   ```
2. Check SQL Server Browser service for named instances
3. Try using IP address instead of hostname
4. Verify firewall allows SQL Server port (default 1433)

#### "Login failed for user"
**Symptoms**: Authentication error

**Solutions**:
1. For SQL Auth: Verify username/password
2. For Windows Auth: Check current user permissions
3. Ensure SQL Server allows mixed mode authentication
4. Verify user has database access

### Validation Errors

#### "Table not found in database"
**Cause**: Table doesn't exist in source/target database

**Solution**: 
- Verify table name and case sensitivity
- Check if user has VIEW DEFINITION permission
- Ensure correct database is specified

#### "Match fields not found"
**Cause**: Specified matchOn columns don't exist

**Solution**:
- Check column names in configuration
- Remove matchOn to use primary key automatically
- Verify columns exist with:
  ```sql
  SELECT COLUMN_NAME 
  FROM INFORMATION_SCHEMA.COLUMNS 
  WHERE TABLE_NAME = 'YourTable'
  ```

#### "matchOn fields produce duplicates"
**Cause**: The matchOn fields don't uniquely identify records

**Solution**:
- Add more fields to matchOn array
- Use primary key columns
- Check for duplicate data:
  ```sql
  SELECT Field1, Field2, COUNT(*) 
  FROM YourTable 
  GROUP BY Field1, Field2 
  HAVING COUNT(*) > 1
  ```

### Execution Errors

#### "IDENTITY_INSERT is set to OFF"
**Cause**: Trying to insert identity values without permission

**Solution**:
1. Set `preserveIdentity: true` in configuration
2. Or add identity column to `ignoreColumns`
3. Ensure user has ALTER permission on table

#### "String or binary data would be truncated"
**Cause**: Data too large for target column

**Solution**:
- Compare column sizes between source and target
- Increase target column size
- Add column to ignoreColumns if not needed

#### "Transaction rolled back"
**Cause**: Error during execution

**Solution**:
- Check error message for specific issue
- Verify all constraints are met
- Check for triggers that might interfere
- Review foreign key relationships

### Performance Issues

#### Slow Export
**Symptoms**: Export takes very long time

**Solutions**:
1. Use exportWhere to limit data
2. Export specific tables only
3. Check for missing indexes
4. Monitor SQL Server performance

#### Memory Issues
**Symptoms**: Out of memory errors

**Solutions**:
1. Process fewer tables at once
2. Use exportWhere to reduce data volume
3. Increase PowerShell memory limit:
   ```powershell
   $PSVersionTable.PSVersion
   # If using Windows PowerShell, consider PowerShell Core
   ```

### Configuration Issues

#### "Config file not found"
**Solution**:
```bash
cp src/sync-config.example.json src/sync-config.json
```

#### "No matchOn fields specified and primary key columns are ignored"
**Cause**: Primary key is in ignoreColumns but no matchOn specified

**Solution**:
- Specify matchOn explicitly
- Remove primary key from ignoreColumns
- Use different fields for matching

### Platform-Specific Issues

#### macOS/Linux: "The term 'powershell' is not recognized"
**Solution**: Use `pwsh` instead of `powershell`

#### Windows: "Running scripts is disabled"
**Solution**:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

#### Docker: Connection timeouts
**Solution**:
- Use container name as server
- Verify port mapping
- Use SQL authentication

## Debug Mode

To get more detailed error information:

1. **Enable SQL Profiler** to see actual queries
2. **Check SQL Server Error Log** for detailed messages
3. **Add verbose output** to scripts:
   ```powershell
   $VerbosePreference = "Continue"
   ./src/sync-export.ps1 -From source -Verbose
   ```

## Getting Help

If you encounter issues not covered here:

1. Check the error message carefully
2. Verify your configuration
3. Test with a simple single-table sync first
4. Create an issue on GitHub with:
   - Error message
   - Configuration (without passwords)
   - PowerShell version
   - SQL Server version