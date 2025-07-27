# SyncRay Test Suite

This directory contains comprehensive test scenarios for the SyncRay database synchronization tool.

## Test Structure

### `/postgres/` - PostgreSQL Test Environment
**Note**: SyncRay currently only supports SQL Server. These PostgreSQL tests are prepared for future PostgreSQL support.

- `setup-test-databases.sql` - Creates test databases with complex scenarios
- `run-postgres-setup.sh` - Shell script to set up PostgreSQL test environment
- `test-config-postgres.json` - PostgreSQL test configuration
- `test-duplicate-scenarios.ps1` - Specific tests for duplicate handling

### Test Scripts

- `test-sync-scenarios.ps1` - Main test suite covering all functionality
- Run with: `./test/test-sync-scenarios.ps1`

## Test Scenarios

### 1. Basic Functionality
- Simple table export/import
- Table name mapping (source → target with different names)
- Filtered exports using WHERE clauses
- Multiple table operations

### 2. Duplicate Handling
- **NonInteractive Mode**: Automatically skips tables with duplicates
- **Interactive Mode**:
  - Continue (y): Exports with duplicates grouped
  - Skip (n): Skips current table
  - Abort (a): Cancels entire export
- **ShowSQL Mode**: Shows detailed duplicate analysis

### 3. Data Types and Edge Cases
- All SQL data types (int, varchar, decimal, datetime, bit, etc.)
- NULL value handling
- Empty tables
- Tables without primary keys
- Large datasets (performance testing)

### 4. Error Scenarios
- Missing tables
- Invalid configuration
- Permission issues
- Constraint violations

## PostgreSQL Test Database Schema

The PostgreSQL test environment includes:

1. **users** - Basic user data with various types
2. **products** - Composite unique constraints
3. **orders/order_items** - Foreign key relationships
4. **settings** → **app_settings** - Table name mapping test
5. **audit_log** - Large dataset (10k rows) for performance
6. **duplicate_test** - Intentional duplicates for testing
7. **no_pk_table** - Table without primary key
8. **binary_data** - Binary data handling
9. **complex_types** - PostgreSQL-specific types (for future support)

## Running Tests

### SQL Server Tests (Current)
```powershell
# Run all test scenarios
./test/test-sync-scenarios.ps1

# Run with specific config
./test/test-sync-scenarios.ps1 -ConfigFile "path/to/config.json"
```

### PostgreSQL Tests (Future)
```bash
# Set up PostgreSQL test databases
cd test/postgres
./run-postgres-setup.sh

# Note: Requires modifying SyncRay to support PostgreSQL
```

## Duplicate Handling Test Examples

### NonInteractive Mode
```powershell
./src/sync-export.ps1 -From source -NonInteractive
# Automatically skips tables with duplicates
```

### Interactive Mode
```powershell
./src/sync-export.ps1 -From source
# Prompts: Continue with export? (y=yes, n=no/skip, a=abort all):
```

### Debug Mode
```powershell
./src/sync-export.ps1 -From source -ShowSQL
# Shows detailed SQL queries and duplicate analysis
```

## Expected Test Outputs

### Successful Export
```
Processing TableName... checking duplicates... [OK]
Exporting TableName... [OK] 147 rows, 25 KB
```

### Duplicate Detection
```
Processing TableName... checking duplicates... [DUPLICATES FOUND]
    Found 84 duplicate records in 42 groups
    Example duplicates:
    - Key1='A', Key2='B' (3 occurrences)
    
    Continue with export? (y=yes, n=no/skip, a=abort all):
```

### With ShowSQL Flag
```
[DEBUG] Checking uniqueness:
WITH DuplicateCheck AS (...)
[DEBUG] Query execution time: 15ms

Detailed duplicate records (max 200 rows):
ID    Key1    Key2    Data              DuplicateGroup
---   ----    ----    ----              --------------
101   A       B       First record      1
102   A       B       Duplicate         1
```

## Notes

- Current tests focus on SQL Server functionality
- PostgreSQL tests are prepared for future enhancement
- Interactive tests require manual simulation or expect scripts
- Performance tests assume sufficient test data (e.g., audit_log with 10k+ rows)