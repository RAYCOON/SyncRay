#!/bin/bash
# run-postgres-setup.sh - Setup PostgreSQL test databases for SyncRay

# PostgreSQL connection parameters
export PGUSER=svassistent
export PGPASSWORD=SvAssistent2024!
export PGHOST=localhost
export PGPORT=5432

echo "=== SyncRay PostgreSQL Test Setup ==="
echo "Setting up test databases..."

# Run the setup SQL script
psql -h localhost -U postgres -f setup-test-databases.sql

echo ""
echo "=== Database Setup Complete ==="
echo ""
echo "Created databases:"
echo "  - syncray_source (with test data)"
echo "  - syncray_target (with some initial data)"
echo ""
echo "Test tables created:"
echo "  - users: Basic user data with various types"
echo "  - products: Product catalog with composite unique key"
echo "  - orders/order_items: Related tables with foreign keys"
echo "  - settings: Key-value configuration (different name in target)"
echo "  - audit_log: Large table for performance testing (10k rows)"
echo "  - duplicate_test: Table with intentional duplicates"
echo "  - no_pk_table: Table without primary key"
echo "  - binary_data: For testing binary data handling"
echo "  - complex_types: PostgreSQL-specific data types"
echo ""
echo "To run sync tests:"
echo "  1. Update scripts to support PostgreSQL (currently SQL Server only)"
echo "  2. Use test-config-postgres.json for configuration"
echo "  3. Run: ./src/sync-export.ps1 -From pg_source -ConfigFile test/postgres/test-config-postgres.json"