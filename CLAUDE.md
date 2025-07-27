# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with the SyncRay project.

## Important Guidelines

- **Never include Claude references in commit messages** - No "Generated with Claude" or similar
- **Keep commit messages professional** - Focus on what changed and why

## Project Overview

SyncRay is a PowerShell-based database synchronization tool for SQL Server that enables data migration between databases with full INSERT, UPDATE, and DELETE support. The tool is designed for flexibility, safety, and ease of use.

## Key Features

- **Flexible Matching**: Match records on any combination of fields, not just primary keys
- **Transaction Safety**: All operations wrapped in transactions with automatic rollback
- **Dry-Run Mode**: Preview changes before execution (default behavior)
- **Comprehensive Validation**: Pre-flight checks for configuration, tables, and permissions
- **Export Filtering**: WHERE clause support for selective data export

## Architecture

### Core Scripts
- `src/sync-export.ps1` - Exports data from source database to JSON files
- `src/sync-import.ps1` - Imports/syncs data from JSON files to target database
- `src/sync-validation.ps1` - Common validation functions used by both scripts
- `src/sync-config.json` - Configuration file (not in git)
- `src/sync-config.example.json` - Example configuration template

### Data Flow
1. Export reads from source database and writes to JSON files in `sync-data/`
2. Import reads JSON files and syncs to target database
3. Validation runs before any operation to ensure configuration is valid

## Development Guidelines

### PowerShell Compatibility
- Must be compatible with PowerShell 5.0 (Windows PowerShell)
- Use only .NET Framework classes available in PowerShell 5
- Test on both Windows PowerShell and PowerShell Core

### Error Handling
- All database operations should be wrapped in try-catch blocks
- Provide clear, actionable error messages
- Use transactions for all write operations
- Always close database connections in finally blocks

### Validation
- Validate configuration before any database operation
- Check table existence, column existence, and permissions
- Verify matchOn fields produce unique matches
- Display primary key information in validation errors when possible

### Safety Features
- Default to dry-run mode
- Require explicit confirmation for execution
- Show detailed change preview before execution
- Support operation-level control (allowInserts, allowUpdates, allowDeletes)

## Common Tasks

### Adding New Features
1. Update validation logic in `sync-validation.ps1` if needed
2. Implement feature in appropriate script
3. Update example configuration
4. Update documentation in all languages:
   - README.md (English)
   - README.de.md (German/Deutsch)
   - README.fr.md (French/Français)
   - README.es.md (Spanish/Español)
5. Test with PowerShell 5.0

### Testing Changes
```powershell
# Test export
./src/sync-export.ps1 -From source -Tables TestTable

# Test import (dry-run)
./src/sync-import.ps1 -To target -Tables TestTable

# Test with specific configuration
./src/sync-export.ps1 -From source -ConfigPath ./test-config.json
```

### Debugging
- Use Write-Host for user-facing messages
- Use Write-Verbose for debug information
- Check SQL Server Profiler for actual queries
- Enable verbose mode: `$VerbosePreference = "Continue"`

## Configuration Notes

### matchOn Behavior
- If empty, automatically uses primary key columns
- Must produce unique matches (validated before execution)
- Can use composite keys: `["Field1", "Field2"]`
- Primary key info shown in validation errors

### Special Handling
- Identity columns: Use `preserveIdentity: true` or add to `ignoreColumns`
- Boolean/bit columns: Automatically converted between SQL and JSON
- NULL values: Properly handled in comparisons and updates

## Important Reminders

1. **Always validate before execution** - The tool validates configuration, but always test with dry-run first
2. **Connection strings** - Never commit real passwords to git
3. **Primary keys** - When validation fails, primary key information is shown to help diagnosis
4. **Transaction safety** - All write operations are transactional
5. **Cross-platform** - Test on both Windows and Unix-like systems
6. **Documentation** - Always maintain README files in all four languages (English, German, French, Spanish) when making changes