# SyncRay Development History

## Project Timeline

### Initial Request (January 2025)
- Started with a request for a PowerShell 5 compatible database query tool
- Needed support for both Windows and SQL Server authentication
- Created initial `merge.ps1` script

### Evolution to Sync Tool
1. **Basic Query Tool** (`merge.ps1`)
   - SQL query capabilities
   - Parameter conflict resolution (-S ambiguity)
   - Authentication flexibility

2. **Export/Import Development**
   - JSON as exchange format
   - Table mapping with different source/target names
   - Dry-run mode as default

3. **Key Challenges Solved**
   - IDENTITY_INSERT handling
   - Boolean/bit data type conversion
   - Transaction safety
   - Composite key matching

4. **Advanced Features Added**
   - WHERE clause filtering for exports
   - Operation control (allowInserts/Updates/Deletes)
   - Comprehensive validation
   - Primary key auto-detection
   - Safety confirmation prompts

### Configuration Evolution

Started with simple table names:
```json
{"sourceTable": "Table1"}
```

Evolved to comprehensive configuration:
```json
{
  "sourceTable": "Table1",
  "targetTable": "Table1_New",
  "matchOn": ["Field1", "Field2"],
  "ignoreColumns": ["LastModified"],
  "allowInserts": true,
  "allowUpdates": true,
  "allowDeletes": false,
  "preserveIdentity": false,
  "exportWhere": "IsActive = 1"
}
```

### Key Design Decisions

1. **JSON over SQL Scripts**
   - Preserves data types
   - Cross-platform compatible
   - Human-readable for debugging

2. **Flexible Matching**
   - Not limited to primary keys
   - Supports composite keys
   - Validates uniqueness

3. **Safety First**
   - Dry-run by default
   - Transaction wrapping
   - Explicit execution confirmation

4. **Validation**
   - Pre-flight checks
   - Shows primary keys in errors
   - Detects configuration issues early

### Project Naming
- User selected "SyncRay" as the project name
- Created GitHub-ready structure
- Bilingual documentation (EN/DE)

## Technical Learnings

1. **PowerShell 5 Compatibility**
   - Stick to .NET Framework classes
   - Avoid PowerShell Core features
   - Test on both platforms

2. **SQL Server Quirks**
   - IDENTITY_INSERT requires specific handling
   - Boolean values need special conversion
   - Connection string formats vary by auth type

3. **Error Handling**
   - Always show actionable errors
   - Include context (like primary keys)
   - Validate before execution

## Future Considerations

- Batch processing for large tables
- Progress reporting for long operations
- Parallel table processing
- Schema change detection
- Audit trail generation