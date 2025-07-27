-- setup-test-databases.sql
-- Creates test databases and tables for SyncRay testing with PostgreSQL
-- Note: SyncRay currently only supports SQL Server, this is for future PostgreSQL support testing

-- Drop databases if they exist (be careful!)
DROP DATABASE IF EXISTS syncray_source;
DROP DATABASE IF EXISTS syncray_target;

-- Create test databases
CREATE DATABASE syncray_source;
CREATE DATABASE syncray_target;

-- Connect to source database
\c syncray_source;

-- Create test tables with various scenarios

-- 1. Users table - Basic table with identity, various data types
CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) NOT NULL,
    full_name VARCHAR(200),
    age INTEGER CHECK (age >= 0),
    salary DECIMAL(10,2),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP,
    last_login DATE,
    preferences JSONB,
    profile_image BYTEA,
    notes TEXT
);

-- 2. Products table - Table with composite unique constraint
CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    category VARCHAR(50) NOT NULL,
    sku VARCHAR(50) NOT NULL,
    name VARCHAR(200) NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL CHECK (price >= 0),
    stock_quantity INTEGER DEFAULT 0,
    is_available BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(category, sku)
);

-- 3. Orders table - Foreign key relationships
CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(user_id),
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) CHECK (status IN ('pending', 'processing', 'shipped', 'delivered', 'cancelled')),
    total_amount DECIMAL(10,2) NOT NULL,
    shipping_address TEXT,
    notes TEXT
);

-- 4. Order_items table - Composite primary key
CREATE TABLE order_items (
    order_id INTEGER REFERENCES orders(order_id),
    product_id INTEGER REFERENCES products(product_id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(10,2) NOT NULL,
    discount_percent DECIMAL(5,2) DEFAULT 0,
    PRIMARY KEY (order_id, product_id)
);

-- 5. Settings table - Key-value pairs
CREATE TABLE settings (
    key VARCHAR(100) PRIMARY KEY,
    value TEXT,
    description TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 6. Audit_log table - Large table for performance testing
CREATE TABLE audit_log (
    log_id BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    operation VARCHAR(10) NOT NULL,
    user_name VARCHAR(100),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    old_values JSONB,
    new_values JSONB,
    ip_address INET,
    session_id UUID
);

-- 7. Binary_data table - Testing binary data handling
CREATE TABLE binary_data (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    file_data BYTEA NOT NULL,
    file_size BIGINT,
    mime_type VARCHAR(100),
    checksum VARCHAR(64),
    uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 8. Complex_types table - Testing various PostgreSQL-specific types
CREATE TABLE complex_types (
    id SERIAL PRIMARY KEY,
    array_int INTEGER[],
    array_text TEXT[],
    json_data JSON,
    jsonb_data JSONB,
    uuid_field UUID DEFAULT gen_random_uuid(),
    ip_address INET,
    mac_address MACADDR,
    time_range TSRANGE,
    tags TEXT[]
);

-- 9. Table with duplicates for testing duplicate handling
CREATE TABLE duplicate_test (
    id SERIAL PRIMARY KEY,
    group_key VARCHAR(50),
    value1 VARCHAR(100),
    value2 VARCHAR(100),
    data TEXT
);

-- 10. Table without primary key
CREATE TABLE no_pk_table (
    col1 VARCHAR(50),
    col2 VARCHAR(50),
    col3 INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert test data
-- Users
INSERT INTO users (username, email, full_name, age, salary, is_active, preferences) VALUES
('john_doe', 'john@example.com', 'John Doe', 30, 75000.00, true, '{"theme": "dark", "notifications": true}'),
('jane_smith', 'jane@example.com', 'Jane Smith', 28, 82000.00, true, '{"theme": "light", "notifications": false}'),
('bob_wilson', 'bob@example.com', 'Bob Wilson', 45, 95000.00, false, '{"theme": "auto", "language": "en"}'),
('alice_brown', 'alice@example.com', 'Alice Brown', 33, 68000.00, true, null),
('charlie_davis', 'charlie@example.com', 'Charlie Davis', 52, 120000.00, true, '{"beta_features": true}');

-- Products
INSERT INTO products (category, sku, name, description, price, stock_quantity) VALUES
('Electronics', 'ELEC-001', 'Laptop Pro 15', 'High-performance laptop', 1299.99, 50),
('Electronics', 'ELEC-002', 'Wireless Mouse', 'Ergonomic wireless mouse', 29.99, 200),
('Books', 'BOOK-001', 'PostgreSQL Guide', 'Complete PostgreSQL reference', 49.99, 100),
('Books', 'BOOK-002', 'SQL Performance', 'SQL optimization techniques', 39.99, 75),
('Clothing', 'CLTH-001', 'T-Shirt Blue', 'Cotton t-shirt', 19.99, 300);

-- Orders
INSERT INTO orders (user_id, status, total_amount, shipping_address) VALUES
(1, 'delivered', 1329.98, '123 Main St, City, State 12345'),
(2, 'processing', 89.97, '456 Oak Ave, Town, State 67890'),
(1, 'pending', 49.99, '123 Main St, City, State 12345'),
(3, 'cancelled', 39.99, '789 Pine Rd, Village, State 13579');

-- Order items
INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES
(1, 1, 1, 1299.99),
(1, 2, 1, 29.99),
(2, 3, 1, 49.99),
(2, 4, 1, 39.99),
(3, 3, 1, 49.99);

-- Settings
INSERT INTO settings (key, value, description) VALUES
('app.name', 'SyncRay Test', 'Application name'),
('app.version', '1.0.0', 'Current version'),
('maintenance.mode', 'false', 'Maintenance mode flag'),
('max.batch.size', '1000', 'Maximum batch size for sync');

-- Duplicate test data (intentional duplicates)
INSERT INTO duplicate_test (group_key, value1, value2, data) VALUES
('GROUP1', 'A', 'X', 'First record'),
('GROUP1', 'A', 'X', 'Duplicate 1'),
('GROUP1', 'A', 'X', 'Duplicate 2'),
('GROUP2', 'B', 'Y', 'Another group'),
('GROUP2', 'B', 'Y', 'Another duplicate'),
('GROUP3', 'C', 'Z', 'Unique record');

-- No PK table data
INSERT INTO no_pk_table (col1, col2, col3) VALUES
('Value1', 'Data1', 100),
('Value2', 'Data2', 200),
('Value1', 'Data1', 100); -- Intentional duplicate

-- Generate large dataset for performance testing
INSERT INTO audit_log (table_name, operation, user_name, old_values, new_values)
SELECT 
    CASE (random() * 4)::int 
        WHEN 0 THEN 'users'
        WHEN 1 THEN 'products'
        WHEN 2 THEN 'orders'
        ELSE 'settings'
    END,
    CASE (random() * 3)::int
        WHEN 0 THEN 'INSERT'
        WHEN 1 THEN 'UPDATE'
        ELSE 'DELETE'
    END,
    'user_' || (random() * 10)::int,
    '{"old": "value"}',
    '{"new": "value"}'
FROM generate_series(1, 10000);

-- Create same structure in target database
\c syncray_target;

-- Create identical tables in target (some with slight differences for testing)
-- Users table - same structure
CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) NOT NULL,
    full_name VARCHAR(200),
    age INTEGER CHECK (age >= 0),
    salary DECIMAL(10,2),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP,
    last_login DATE,
    preferences JSONB,
    profile_image BYTEA,
    notes TEXT
);

-- Products table - same structure
CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    category VARCHAR(50) NOT NULL,
    sku VARCHAR(50) NOT NULL,
    name VARCHAR(200) NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL CHECK (price >= 0),
    stock_quantity INTEGER DEFAULT 0,
    is_available BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(category, sku)
);

-- Orders table - same structure
CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(user_id),
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) CHECK (status IN ('pending', 'processing', 'shipped', 'delivered', 'cancelled')),
    total_amount DECIMAL(10,2) NOT NULL,
    shipping_address TEXT,
    notes TEXT
);

-- Order_items table - same structure
CREATE TABLE order_items (
    order_id INTEGER REFERENCES orders(order_id),
    product_id INTEGER REFERENCES products(product_id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(10,2) NOT NULL,
    discount_percent DECIMAL(5,2) DEFAULT 0,
    PRIMARY KEY (order_id, product_id)
);

-- Settings table - with different name for testing table mapping
CREATE TABLE app_settings (
    key VARCHAR(100) PRIMARY KEY,
    value TEXT,
    description TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Other tables same as source
CREATE TABLE audit_log (
    log_id BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    operation VARCHAR(10) NOT NULL,
    user_name VARCHAR(100),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    old_values JSONB,
    new_values JSONB,
    ip_address INET,
    session_id UUID
);

CREATE TABLE binary_data (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    file_data BYTEA NOT NULL,
    file_size BIGINT,
    mime_type VARCHAR(100),
    checksum VARCHAR(64),
    uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE complex_types (
    id SERIAL PRIMARY KEY,
    array_int INTEGER[],
    array_text TEXT[],
    json_data JSON,
    jsonb_data JSONB,
    uuid_field UUID DEFAULT gen_random_uuid(),
    ip_address INET,
    mac_address MACADDR,
    time_range TSRANGE,
    tags TEXT[]
);

CREATE TABLE duplicate_test (
    id SERIAL PRIMARY KEY,
    group_key VARCHAR(50),
    value1 VARCHAR(100),
    value2 VARCHAR(100),
    data TEXT
);

CREATE TABLE no_pk_table (
    col1 VARCHAR(50),
    col2 VARCHAR(50),
    col3 INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert some initial data in target (to test updates and deletes)
INSERT INTO users (username, email, full_name, age, salary, is_active) VALUES
('john_doe', 'john.old@example.com', 'John Doe Sr.', 31, 70000.00, false), -- Different data
('jane_smith', 'jane@example.com', 'Jane Smith', 28, 82000.00, true), -- Same data
('deleted_user', 'deleted@example.com', 'To Be Deleted', 25, 50000.00, true); -- Not in source

INSERT INTO products (category, sku, name, description, price, stock_quantity) VALUES
('Electronics', 'ELEC-001', 'Laptop Pro 15', 'Old description', 1199.99, 30), -- Different price
('Electronics', 'ELEC-999', 'Old Product', 'To be deleted', 99.99, 0); -- Not in source

INSERT INTO app_settings (key, value, description) VALUES
('app.name', 'Old App Name', 'Application name'), -- Different value
('old.setting', 'delete me', 'To be deleted'); -- Not in source

-- Grant permissions (adjust as needed)
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO svassistent;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO svassistent;

\c syncray_source;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO svassistent;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO svassistent;