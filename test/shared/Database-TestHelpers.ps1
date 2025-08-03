# SyncRay Database Test Helpers
# Spezialisierte Hilfsfunktionen für Datenbank-Tests mit SQLite und SQL Server Support

# Datenbank-spezifische Konfiguration
$Global:DatabaseTestConfig = @{
    SQLiteCommandTimeout = 30
    SQLServerCommandTimeout = 300
    TestDatabasePrefix = "syncray_test_"
    RetryAttempts = 3
    RetryDelay = 1000
}

# Sichere SQL-Ausführung mit Retry-Logik
function Invoke-SqlQuery {
    param(
        $Connection,
        [string]$Query,
        [hashtable]$Parameters = @{},
        [int]$TimeoutSeconds = 30,
        [int]$RetryAttempts = 3
    )
    
    $attempt = 0
    $lastError = $null
    
    while ($attempt -lt $RetryAttempts) {
        try {
            $attempt++
            
            if (Test-IsSQLite -Connection $Connection) {
                return Invoke-SQLiteQuery -Connection $Connection -Query $Query -Parameters $Parameters -TimeoutSeconds $TimeoutSeconds
            } else {
                return Invoke-SqlServerQuery -Connection $Connection -Query $Query -Parameters $Parameters -TimeoutSeconds $TimeoutSeconds
            }
            
        } catch {
            $lastError = $_
            Write-Verbose "SQL-Query Attempt $attempt failed: $_"
            
            if ($attempt -lt $RetryAttempts) {
                Start-Sleep -Milliseconds $Global:DatabaseTestConfig.RetryDelay
            }
        }
    }
    
    throw "SQL-Query failed after $RetryAttempts attempts. Last error: $lastError"
}

# SQLite-spezifische Query-Ausführung
function Invoke-SQLiteQuery {
    param(
        $Connection,
        [string]$Query,
        [hashtable]$Parameters = @{},
        [int]$TimeoutSeconds = 30
    )
    
    if ($Connection -is [string]) {
        # Wenn Connection ein String ist, handelt es sich um eine Datei
        $dbPath = $Connection
        
        # Parameter in Query einsetzen
        $finalQuery = $Query
        foreach ($param in $Parameters.GetEnumerator()) {
            $finalQuery = $finalQuery -replace "@$($param.Key)", "'$($param.Value)'"
        }
        
        # SQLite3 Command ausführen
        $tempFile = Join-Path (Get-TestTempDirectory) "query_$(Get-Random).sql"
        $finalQuery | Set-Content $tempFile
        
        try {
            $result = sqlite3 -header -csv $dbPath ".read $tempFile"
            
            if ($LASTEXITCODE -ne 0) {
                throw "SQLite3 command failed with exit code $LASTEXITCODE"
            }
            
            # CSV-Ergebnis in Objekte konvertieren
            if ($result -and $result.Count -gt 0) {
                return $result | ConvertFrom-Csv
            } else {
                return @()
            }
            
        } finally {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    } else {
        throw "SQLite .NET Connection objects not supported in test environment. Use file path instead."
    }
}

# SQL Server-spezifische Query-Ausführung
function Invoke-SqlServerQuery {
    param(
        $Connection,
        [string]$Query,
        [hashtable]$Parameters = @{},
        [int]$TimeoutSeconds = 300
    )
    
    throw "SQL Server testing not implemented in this test environment. Use SQLite for testing."
}

# Datenbank-Typ erkennen
function Test-IsSQLite {
    param($Connection)
    
    if ($Connection -is [string]) {
        return $Connection.EndsWith('.db') -or $Connection.EndsWith('.sqlite') -or $Connection.EndsWith('.sqlite3')
    }
    
    if ($Connection -is [hashtable] -and $Connection.ContainsKey('ConnectionString')) {
        return $Connection.ConnectionString -like "*Data Source=*" -and $Connection.ConnectionString -like "*.db*"
    }
    
    return $true  # Default zu SQLite in Test-Umgebung
}

# Test-Datenbank erstellen
function New-TestDatabase {
    param(
        [string]$DatabaseName = $null,
        [string]$Schema = "standard",
        [switch]$InMemory = $false
    )
    
    if (-not $DatabaseName) {
        $DatabaseName = Get-RandomTestName -Prefix "syncray_test"
    }
    
    $dbPath = if ($InMemory) {
        ":memory:"
    } else {
        Join-Path (Get-TestTempDirectory) "$DatabaseName.db"
    }
    
    # Schema erstellen
    $schemaQueries = Get-TestDatabaseSchema -Schema $Schema
    
    foreach ($query in $schemaQueries) {
        Write-Verbose "Executing schema query: $($query.Substring(0, [math]::Min(50, $query.Length)))..."
        $query | sqlite3 $dbPath
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create schema in test database: $dbPath"
        }
    }
    
    Write-Verbose "Test database created: $dbPath"
    return $dbPath
}

# Standard Test-Schema definieren
function Get-TestDatabaseSchema {
    param([string]$Schema = "standard")
    
    switch ($Schema) {
        "standard" {
            return @(
                @"
CREATE TABLE Users (
    UserID INTEGER PRIMARY KEY AUTOINCREMENT,
    Username TEXT NOT NULL UNIQUE,
    Email TEXT NOT NULL UNIQUE,
    FirstName TEXT NOT NULL,
    LastName TEXT NOT NULL,
    IsActive INTEGER DEFAULT 1,
    Salary REAL,
    Department TEXT,
    Manager INTEGER,
    Settings TEXT,
    FOREIGN KEY (Manager) REFERENCES Users(UserID)
);
"@,
                @"
CREATE TABLE Categories (
    CategoryID INTEGER PRIMARY KEY AUTOINCREMENT,
    CategoryName TEXT NOT NULL UNIQUE,
    Description TEXT,
    ParentCategoryID INTEGER,
    IsActive INTEGER DEFAULT 1,
    FOREIGN KEY (ParentCategoryID) REFERENCES Categories(CategoryID)
);
"@,
                @"
CREATE TABLE Products (
    ProductID INTEGER PRIMARY KEY AUTOINCREMENT,
    ProductCode TEXT NOT NULL UNIQUE,
    ProductName TEXT NOT NULL,
    CategoryID INTEGER NOT NULL,
    Price REAL NOT NULL CHECK (Price >= 0),
    Stock INTEGER DEFAULT 0 CHECK (Stock >= 0),
    LastModified TEXT DEFAULT CURRENT_TIMESTAMP,
    ModifiedBy TEXT DEFAULT 'system',
    FOREIGN KEY (CategoryID) REFERENCES Categories(CategoryID)
);
"@,
                @"
CREATE TABLE Orders (
    OrderID INTEGER PRIMARY KEY AUTOINCREMENT,
    UserID INTEGER NOT NULL,
    OrderDate TEXT DEFAULT CURRENT_TIMESTAMP,
    Status TEXT DEFAULT 'pending',
    TotalAmount REAL DEFAULT 0,
    FOREIGN KEY (UserID) REFERENCES Users(UserID)
);
"@,
                @"
CREATE TABLE OrderItems (
    OrderID INTEGER NOT NULL,
    ProductID INTEGER NOT NULL,
    LineNumber INTEGER NOT NULL,
    Quantity INTEGER NOT NULL CHECK (Quantity > 0),
    UnitPrice REAL NOT NULL CHECK (UnitPrice >= 0),
    Discount REAL DEFAULT 0 CHECK (Discount >= 0 AND Discount <= 1),
    Total REAL NOT NULL,
    PRIMARY KEY (OrderID, ProductID, LineNumber),
    FOREIGN KEY (OrderID) REFERENCES Orders(OrderID),
    FOREIGN KEY (ProductID) REFERENCES Products(ProductID)
);
"@,
                @"
CREATE INDEX idx_users_email ON Users(Email);
CREATE INDEX idx_users_department ON Users(Department);
CREATE INDEX idx_products_category ON Products(CategoryID);
CREATE INDEX idx_products_code ON Products(ProductCode);
CREATE INDEX idx_orders_user ON Orders(UserID);
CREATE INDEX idx_orders_date ON Orders(OrderDate);
CREATE INDEX idx_orderitems_order ON OrderItems(OrderID);
CREATE INDEX idx_orderitems_product ON OrderItems(ProductID);
"@
            )
        }
        "minimal" {
            return @(
                @"
CREATE TABLE TestTable (
    ID INTEGER PRIMARY KEY AUTOINCREMENT,
    Name TEXT NOT NULL,
    Value INTEGER,
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP
);
"@
            )
        }
        "complex" {
            return Get-TestDatabaseSchema -Schema "standard" + @(
                @"
CREATE TABLE AuditLog (
    LogID INTEGER PRIMARY KEY AUTOINCREMENT,
    TableName TEXT NOT NULL,
    Operation TEXT NOT NULL,
    OldValues TEXT,
    NewValues TEXT,
    UserID INTEGER,
    Timestamp TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (UserID) REFERENCES Users(UserID)
);
"@,
                @"
CREATE VIEW UserOrderSummary AS
SELECT 
    u.UserID,
    u.Username,
    u.Email,
    COUNT(o.OrderID) as OrderCount,
    COALESCE(SUM(o.TotalAmount), 0) as TotalSpent,
    MAX(o.OrderDate) as LastOrderDate
FROM Users u
LEFT JOIN Orders o ON u.UserID = o.UserID
GROUP BY u.UserID, u.Username, u.Email;
"@,
                @"
CREATE TRIGGER update_order_total 
AFTER INSERT ON OrderItems
BEGIN
    UPDATE Orders 
    SET TotalAmount = (
        SELECT SUM(Total) 
        FROM OrderItems 
        WHERE OrderID = NEW.OrderID
    )
    WHERE OrderID = NEW.OrderID;
END;
"@
            )
        }
        default {
            throw "Unknown schema: $Schema"
        }
    }
}

# Test-Daten einfügen
function Initialize-TestData {
    param(
        $Connection,
        [string]$DataSet = "small",
        [switch]$IncludeEdgeCases = $false
    )
    
    $dataConfig = switch ($DataSet) {
        "small" { @{ Users = 5; Categories = 3; Products = 10; Orders = 8; OrderItems = 15 } }
        "medium" { @{ Users = 50; Categories = 10; Products = 100; Orders = 200; OrderItems = 500 } }
        "large" { @{ Users = 500; Categories = 20; Products = 1000; Orders = 2000; OrderItems = 5000 } }
        default { @{ Users = 5; Categories = 3; Products = 10; Orders = 8; OrderItems = 15 } }
    }
    
    Write-Verbose "Initialisiere Test-Daten: $DataSet"
    
    # Kategorien erstellen
    $categories = @(
        @{ CategoryID = 1; CategoryName = "Electronics"; Description = "Electronic devices"; ParentCategoryID = $null },
        @{ CategoryID = 2; CategoryName = "Books"; Description = "Books and literature"; ParentCategoryID = $null },
        @{ CategoryID = 3; CategoryName = "Clothing"; Description = "Clothing and accessories"; ParentCategoryID = $null }
    )
    
    if ($dataConfig.Categories -gt 3) {
        for ($i = 4; $i -le $dataConfig.Categories; $i++) {
            $categories += @{
                CategoryID = $i
                CategoryName = "Category$i"
                Description = "Test Category $i"
                ParentCategoryID = if ($i % 3 -eq 0) { $i - 1 } else { $null }
            }
        }
    }
    
    foreach ($cat in $categories) {
        $query = "INSERT INTO Categories (CategoryID, CategoryName, Description, ParentCategoryID) VALUES (@CategoryID, @CategoryName, @Description, @ParentCategoryID)"
        Invoke-SqlQuery -Connection $Connection -Query $query -Parameters $cat
    }
    
    # Benutzer erstellen
    for ($i = 1; $i -le $dataConfig.Users; $i++) {
        $user = New-TestUser -Id $i
        $query = "INSERT INTO Users (UserID, Username, Email, FirstName, LastName, IsActive, Salary, Department, Manager, Settings) VALUES (@UserID, @Username, @Email, @FirstName, @LastName, @IsActive, @Salary, @Department, @Manager, @Settings)"
        Invoke-SqlQuery -Connection $Connection -Query $query -Parameters $user
    }
    
    # Produkte erstellen
    for ($i = 1; $i -le $dataConfig.Products; $i++) {
        $product = New-TestProduct -Id $i
        $product.CategoryID = (($i - 1) % $categories.Count) + 1
        $query = "INSERT INTO Products (ProductID, ProductCode, ProductName, CategoryID, Price, Stock, LastModified, ModifiedBy) VALUES (@ProductID, @ProductCode, @ProductName, @CategoryID, @Price, @Stock, @LastModified, @ModifiedBy)"
        Invoke-SqlQuery -Connection $Connection -Query $query -Parameters $product
    }
    
    # Bestellungen erstellen
    for ($i = 1; $i -le $dataConfig.Orders; $i++) {
        $order = @{
            OrderID = $i
            UserID = (($i - 1) % $dataConfig.Users) + 1
            OrderDate = (Get-Date).AddDays(-($i * 2)).ToString("yyyy-MM-dd HH:mm:ss")
            Status = @("pending", "completed", "cancelled")[$i % 3]
            TotalAmount = 0  # Wird durch Trigger berechnet
        }
        $query = "INSERT INTO Orders (OrderID, UserID, OrderDate, Status, TotalAmount) VALUES (@OrderID, @UserID, @OrderDate, @Status, @TotalAmount)"
        Invoke-SqlQuery -Connection $Connection -Query $query -Parameters $order
    }
    
    # Bestellpositionen erstellen
    $orderItemId = 1
    for ($orderId = 1; $orderId -le $dataConfig.Orders; $orderId++) {
        $itemsPerOrder = Get-Random -Minimum 1 -Maximum 5
        
        for ($lineNum = 1; $lineNum -le $itemsPerOrder; $lineNum++) {
            if ($orderItemId -gt $dataConfig.OrderItems) { break }
            
            $productId = (($orderItemId - 1) % $dataConfig.Products) + 1
            $orderItem = New-TestOrderItem -OrderId $orderId -ProductId $productId -LineNumber $lineNum
            
            $query = "INSERT INTO OrderItems (OrderID, ProductID, LineNumber, Quantity, UnitPrice, Discount, Total) VALUES (@OrderID, @ProductID, @LineNumber, @Quantity, @UnitPrice, @Discount, @Total)"
            Invoke-SqlQuery -Connection $Connection -Query $query -Parameters $orderItem
            
            $orderItemId++
        }
        
        if ($orderItemId -gt $dataConfig.OrderItems) { break }
    }
    
    # Edge Cases hinzufügen
    if ($IncludeEdgeCases) {
        Add-EdgeCaseData -Connection $Connection
    }
    
    Write-Verbose "Test-Daten initialisiert: $($dataConfig.Users) Users, $($dataConfig.Products) Products, $($dataConfig.Orders) Orders"
}

# Edge-Case Test-Daten hinzufügen
function Add-EdgeCaseData {
    param($Connection)
    
    Write-Verbose "Füge Edge-Case Test-Daten hinzu"
    
    # Benutzer mit speziellen Zeichen
    $edgeUsers = @(
        @{ Username = "user_with_underscore"; Email = "user@test.local"; FirstName = "Test"; LastName = "O'Connor"; Settings = '{"unicode": "äöüß€", "quote": "He said \"Hello\""}' },
        @{ Username = "user.with.dots"; Email = "user.dots@test.local"; FirstName = "Test"; LastName = "van der Berg"; Settings = '{"null_value": null, "empty": ""}' },
        @{ Username = "user-with-dashes"; Email = "user-dash@test.local"; FirstName = "Test"; LastName = "Smith & Jones"; Settings = '{"special": "Line1\nLine2\tTab"}' }
    )
    
    foreach ($user in $edgeUsers) {
        try {
            $query = "INSERT INTO Users (Username, Email, FirstName, LastName, Settings) VALUES (@Username, @Email, @FirstName, @LastName, @Settings)"
            Invoke-SqlQuery -Connection $Connection -Query $query -Parameters $user
        } catch {
            Write-Verbose "Edge case user skipped: $($user.Username) - $_"
        }
    }
    
    # Produkte mit besonderen Eigenschaften
    $edgeProducts = @(
        @{ ProductCode = "PROD-000"; ProductName = "Product with 'quotes'"; Price = 0.01; Stock = 0 },
        @{ ProductCode = "PROD-NULL"; ProductName = "Product (NULL test)"; Price = 999999.99; Stock = $null },
        @{ ProductCode = "PROD-UNICODE"; ProductName = "Ürünü Naməsi 商品名"; Price = 42.42; Stock = 42 }
    )
    
    foreach ($product in $edgeProducts) {
        try {
            $query = "INSERT INTO Products (ProductCode, ProductName, CategoryID, Price, Stock) VALUES (@ProductCode, @ProductName, 1, @Price, @Stock)"
            Invoke-SqlQuery -Connection $Connection -Query $query -Parameters $product
        } catch {
            Write-Verbose "Edge case product skipped: $($product.ProductCode) - $_"
        }
    }
}

# Datenbank-Status prüfen
function Test-DatabaseIntegrity {
    param($Connection)
    
    $checks = @()
    
    # Tabellen-Existenz prüfen
    $requiredTables = @("Users", "Categories", "Products", "Orders", "OrderItems")
    
    foreach ($table in $requiredTables) {
        try {
            $exists = Invoke-SqlQuery -Connection $Connection -Query "SELECT name FROM sqlite_master WHERE type='table' AND name='$table'"
            $checks += @{
                Check = "Table $table exists"
                Result = $exists -ne $null
                Message = if ($exists) { "OK" } else { "Table missing" }
            }
        } catch {
            $checks += @{
                Check = "Table $table exists"
                Result = $false
                Message = "Error: $_"
            }
        }
    }
    
    # Referenzielle Integrität prüfen
    try {
        $orphanProducts = Invoke-SqlQuery -Connection $Connection -Query "SELECT COUNT(*) as Count FROM Products p LEFT JOIN Categories c ON p.CategoryID = c.CategoryID WHERE c.CategoryID IS NULL"
        $checks += @{
            Check = "Product-Category integrity"
            Result = $orphanProducts.Count -eq 0
            Message = if ($orphanProducts.Count -eq 0) { "OK" } else { "$($orphanProducts.Count) orphaned products" }
        }
    } catch {
        $checks += @{
            Check = "Product-Category integrity"
            Result = $false
            Message = "Error: $_"
        }
    }
    
    # Datenqualität prüfen
    try {
        $nullEmails = Invoke-SqlQuery -Connection $Connection -Query "SELECT COUNT(*) as Count FROM Users WHERE Email IS NULL OR Email = ''"
        $checks += @{
            Check = "User email quality"
            Result = $nullEmails.Count -eq 0
            Message = if ($nullEmails.Count -eq 0) { "OK" } else { "$($nullEmails.Count) users with missing email" }
        }
    } catch {
        $checks += @{
            Check = "User email quality"
            Result = $false
            Message = "Error: $_"
        }
    }
    
    return $checks
}

# Datenbank-Cleanup
function Remove-TestDatabase {
    param([string]$DatabasePath)
    
    if ($DatabasePath -and $DatabasePath -ne ":memory:" -and (Test-Path $DatabasePath)) {
        try {
            Remove-Item $DatabasePath -Force
            Write-Verbose "Test database removed: $DatabasePath"
        } catch {
            Write-Warning "Failed to remove test database: $DatabasePath - $_"
        }
    }
}

# Datenbank-Backup und Restore für Tests
function Backup-TestDatabase {
    param($Connection, [string]$BackupPath = $null)
    
    if (-not $BackupPath) {
        $BackupPath = Join-Path (Get-TestTempDirectory) "backup_$(Get-Random).db"
    }
    
    if (Test-IsSQLite -Connection $Connection) {
        $dbPath = if ($Connection -is [string]) { $Connection } else { $Connection.DataSource }
        Copy-Item $dbPath $BackupPath
        return $BackupPath
    } else {
        throw "Backup only supported for SQLite databases"
    }
}

function Restore-TestDatabase {
    param($Connection, [string]$BackupPath)
    
    if (Test-IsSQLite -Connection $Connection) {
        $dbPath = if ($Connection -is [string]) { $Connection } else { $Connection.DataSource }
        Copy-Item $BackupPath $dbPath -Force
    } else {
        throw "Restore only supported for SQLite databases"
    }
}

# Performance-Monitoring für Tests
function Measure-DatabaseOperation {
    param([scriptblock]$Operation, [string]$OperationName = "Database Operation")
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $initialMemory = [System.GC]::GetTotalMemory($false)
    
    try {
        $result = & $Operation
        return @{
            Result = $result
            Duration = $stopwatch.Elapsed
            MemoryUsed = [System.GC]::GetTotalMemory($false) - $initialMemory
            Success = $true
            OperationName = $OperationName
        }
    } catch {
        return @{
            Result = $null
            Duration = $stopwatch.Elapsed
            MemoryUsed = [System.GC]::GetTotalMemory($false) - $initialMemory
            Success = $false
            Error = $_.Exception.Message
            OperationName = $OperationName
        }
    } finally {
        $stopwatch.Stop()
    }
}

# Export für Module-System (deaktiviert für Dot-Sourcing)
# if ($MyInvocation.MyCommand.Path -and $MyInvocation.MyCommand.ModuleName) {
#     Export-ModuleMember -Function @(
#         "Invoke-SqlQuery",
#         "Invoke-SQLiteQuery", 
#         "Invoke-SqlServerQuery",
#         "Test-IsSQLite",
#         "New-TestDatabase",
#         "Get-TestDatabaseSchema",
#         "Initialize-TestData",
#         "Add-EdgeCaseData",
#         "Test-DatabaseIntegrity",
#         "Remove-TestDatabase",
#         "Backup-TestDatabase",
#         "Restore-TestDatabase",
#         "Measure-DatabaseOperation"
#     ) -Variable "DatabaseTestConfig"
# }