# Komplexe Test-Datenbank Schema für SyncRay Testing
# Hierarchische Strukturen, Foreign Keys, Many-to-Many, Self-References

function Get-ComplexDatabaseSchema {
    param([string]$SchemaType = "full")
    
    $schemas = @{
        full = @(
            # 1. COMPANIES (Root der Hierarchie)
            @"
CREATE TABLE Companies (
    CompanyID INTEGER PRIMARY KEY AUTOINCREMENT,
    CompanyName TEXT NOT NULL UNIQUE,
    CompanyCode TEXT NOT NULL UNIQUE,
    Industry TEXT NOT NULL,
    FoundedYear INTEGER,
    HeadquartersCountry TEXT,
    IsActive INTEGER DEFAULT 1,
    AnnualRevenue REAL,
    EmployeeCount INTEGER,
    Website TEXT,
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    ModifiedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    CreatedBy TEXT DEFAULT 'system',
    ModifiedBy TEXT DEFAULT 'system'
);
"@,
            # 2. DEPARTMENTS (Company -> Departments)
            @"
CREATE TABLE Departments (
    DepartmentID INTEGER PRIMARY KEY AUTOINCREMENT,
    CompanyID INTEGER NOT NULL,
    DepartmentName TEXT NOT NULL,
    DepartmentCode TEXT NOT NULL,
    ParentDepartmentID INTEGER, -- Self-reference für Hierarchie
    BudgetAmount REAL DEFAULT 0,
    CostCenter TEXT,
    ManagerUserID INTEGER, -- FK zu Users (wird später erstellt)
    Location TEXT,
    IsActive INTEGER DEFAULT 1,
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    ModifiedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (CompanyID) REFERENCES Companies(CompanyID),
    FOREIGN KEY (ParentDepartmentID) REFERENCES Departments(DepartmentID),
    UNIQUE(CompanyID, DepartmentCode)
);
"@,
            # 3. TEAMS (Department -> Teams)
            @"
CREATE TABLE Teams (
    TeamID INTEGER PRIMARY KEY AUTOINCREMENT,
    DepartmentID INTEGER NOT NULL,
    TeamName TEXT NOT NULL,
    TeamType TEXT CHECK (TeamType IN ('permanent', 'project', 'temporary')),
    TeamLeaderUserID INTEGER, -- FK zu Users
    MaxMembers INTEGER DEFAULT 10,
    CurrentMembers INTEGER DEFAULT 0,
    IsActive INTEGER DEFAULT 1,
    StartDate TEXT,
    EndDate TEXT,
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    ModifiedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (DepartmentID) REFERENCES Departments(DepartmentID)
);
"@,
            # 4. USERS (Team -> Users mit komplexer Self-Reference)
            @"
CREATE TABLE Users (
    UserID INTEGER PRIMARY KEY AUTOINCREMENT,
    Username TEXT NOT NULL UNIQUE,
    Email TEXT NOT NULL UNIQUE,
    FirstName TEXT NOT NULL,
    LastName TEXT NOT NULL,
    EmployeeID TEXT UNIQUE,
    TeamID INTEGER,
    ManagerUserID INTEGER, -- Self-reference
    JobTitle TEXT,
    HireDate TEXT,
    Salary REAL,
    BonusPercentage REAL DEFAULT 0,
    IsActive INTEGER DEFAULT 1,
    AccessLevel INTEGER DEFAULT 1 CHECK (AccessLevel BETWEEN 1 AND 5),
    LastLoginAt TEXT,
    PreferredLanguage TEXT DEFAULT 'en',
    TimeZone TEXT DEFAULT 'UTC',
    ProfilePicture BLOB,
    Settings TEXT, -- JSON
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    ModifiedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (TeamID) REFERENCES Teams(TeamID),
    FOREIGN KEY (ManagerUserID) REFERENCES Users(UserID)
);
"@,
            # 5. ROLES (Security Model)
            @"
CREATE TABLE Roles (
    RoleID INTEGER PRIMARY KEY AUTOINCREMENT,
    RoleName TEXT NOT NULL UNIQUE,
    RoleCode TEXT NOT NULL UNIQUE,
    Description TEXT,
    Permissions TEXT, -- JSON array of permissions
    IsSystemRole INTEGER DEFAULT 0,
    IsActive INTEGER DEFAULT 1,
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    ModifiedAt TEXT DEFAULT CURRENT_TIMESTAMP
);
"@,
            # 6. USER_ROLES (Many-to-Many: Users <-> Roles)
            @"
CREATE TABLE UserRoles (
    UserRoleID INTEGER PRIMARY KEY AUTOINCREMENT,
    UserID INTEGER NOT NULL,
    RoleID INTEGER NOT NULL,
    AssignedDate TEXT DEFAULT CURRENT_TIMESTAMP,
    ExpiryDate TEXT,
    AssignedByUserID INTEGER,
    IsActive INTEGER DEFAULT 1,
    Notes TEXT,
    FOREIGN KEY (UserID) REFERENCES Users(UserID),
    FOREIGN KEY (RoleID) REFERENCES Roles(RoleID),
    FOREIGN KEY (AssignedByUserID) REFERENCES Users(UserID),
    UNIQUE(UserID, RoleID) -- Ein User kann eine Rolle nur einmal haben
);
"@,
            # 7. PROJECTS (Cross-departmental)
            @"
CREATE TABLE Projects (
    ProjectID INTEGER PRIMARY KEY AUTOINCREMENT,
    CompanyID INTEGER NOT NULL,
    ProjectName TEXT NOT NULL,
    ProjectCode TEXT NOT NULL,
    Description TEXT,
    ProjectManagerUserID INTEGER,
    SponsorDepartmentID INTEGER,
    Status TEXT DEFAULT 'planning' CHECK (Status IN ('planning', 'active', 'on_hold', 'completed', 'cancelled')),
    Priority TEXT DEFAULT 'medium' CHECK (Priority IN ('low', 'medium', 'high', 'critical')),
    BudgetAllocated REAL DEFAULT 0,
    BudgetSpent REAL DEFAULT 0,
    StartDate TEXT,
    PlannedEndDate TEXT,
    ActualEndDate TEXT,
    PercentComplete INTEGER DEFAULT 0 CHECK (PercentComplete BETWEEN 0 AND 100),
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    ModifiedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (CompanyID) REFERENCES Companies(CompanyID),
    FOREIGN KEY (ProjectManagerUserID) REFERENCES Users(UserID),
    FOREIGN KEY (SponsorDepartmentID) REFERENCES Departments(DepartmentID),
    UNIQUE(CompanyID, ProjectCode)
);
"@,
            # 8. SKILLS (Master Data)
            @"
CREATE TABLE Skills (
    SkillID INTEGER PRIMARY KEY AUTOINCREMENT,
    SkillName TEXT NOT NULL UNIQUE,
    SkillCategory TEXT NOT NULL,
    Description TEXT,
    IsActive INTEGER DEFAULT 1,
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP
);
"@,
            # 9. PROJECT_SKILLS (Many-to-Many: Projects <-> Skills)
            @"
CREATE TABLE ProjectSkills (
    ProjectSkillID INTEGER PRIMARY KEY AUTOINCREMENT,
    ProjectID INTEGER NOT NULL,
    SkillID INTEGER NOT NULL,
    RequiredLevel INTEGER CHECK (RequiredLevel BETWEEN 1 AND 5),
    RequiredCount INTEGER DEFAULT 1,
    CurrentCount INTEGER DEFAULT 0,
    FOREIGN KEY (ProjectID) REFERENCES Projects(ProjectID),
    FOREIGN KEY (SkillID) REFERENCES Skills(SkillID),
    UNIQUE(ProjectID, SkillID)
);
"@,
            # 10. USER_SKILLS (Many-to-Many: Users <-> Skills)
            @"
CREATE TABLE UserSkills (
    UserSkillID INTEGER PRIMARY KEY AUTOINCREMENT,
    UserID INTEGER NOT NULL,
    SkillID INTEGER NOT NULL,
    SkillLevel INTEGER CHECK (SkillLevel BETWEEN 1 AND 5),
    YearsExperience REAL DEFAULT 0,
    LastAssessedDate TEXT,
    CertificationLevel TEXT,
    FOREIGN KEY (UserID) REFERENCES Users(UserID),
    FOREIGN KEY (SkillID) REFERENCES Skills(SkillID),
    UNIQUE(UserID, SkillID)
);
"@,
            # 11. TASKS (Project breakdown)
            @"
CREATE TABLE Tasks (
    TaskID INTEGER PRIMARY KEY AUTOINCREMENT,
    ProjectID INTEGER NOT NULL,
    ParentTaskID INTEGER, -- Self-reference für Task-Hierarchie
    TaskName TEXT NOT NULL,
    Description TEXT,
    AssignedToUserID INTEGER,
    Status TEXT DEFAULT 'new' CHECK (Status IN ('new', 'in_progress', 'review', 'completed', 'cancelled')),
    Priority TEXT DEFAULT 'medium' CHECK (Priority IN ('low', 'medium', 'high', 'critical')),
    EstimatedHours REAL DEFAULT 0,
    ActualHours REAL DEFAULT 0,
    PercentComplete INTEGER DEFAULT 0 CHECK (PercentComplete BETWEEN 0 AND 100),
    StartDate TEXT,
    DueDate TEXT,
    CompletedDate TEXT,
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    ModifiedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (ProjectID) REFERENCES Projects(ProjectID),
    FOREIGN KEY (ParentTaskID) REFERENCES Tasks(TaskID),
    FOREIGN KEY (AssignedToUserID) REFERENCES Users(UserID)
);
"@,
            # 12. TASK_ASSIGNMENTS (Many-to-Many: Tasks <-> Users für kollaborative Tasks)
            @"
CREATE TABLE TaskAssignments (
    TaskAssignmentID INTEGER PRIMARY KEY AUTOINCREMENT,
    TaskID INTEGER NOT NULL,
    UserID INTEGER NOT NULL,
    Role TEXT DEFAULT 'contributor' CHECK (Role IN ('owner', 'contributor', 'reviewer', 'observer')),
    AssignedDate TEXT DEFAULT CURRENT_TIMESTAMP,
    StartDate TEXT,
    CompletedDate TEXT,
    HoursAllocated REAL DEFAULT 0,
    HoursSpent REAL DEFAULT 0,
    Notes TEXT,
    FOREIGN KEY (TaskID) REFERENCES Tasks(TaskID),
    FOREIGN KEY (UserID) REFERENCES Users(UserID),
    UNIQUE(TaskID, UserID, Role) -- Gleiche Person kann verschiedene Rollen haben
);
"@,
            # 13. CATEGORIES (Hierarchische Kategorisierung)
            @"
CREATE TABLE Categories (
    CategoryID INTEGER PRIMARY KEY AUTOINCREMENT,
    CategoryName TEXT NOT NULL,
    CategoryCode TEXT NOT NULL UNIQUE,
    ParentCategoryID INTEGER, -- Self-reference für unbegrenzte Hierarchie
    CategoryType TEXT CHECK (CategoryType IN ('department', 'project', 'skill', 'expense', 'asset')),
    SortOrder INTEGER DEFAULT 0,
    Icon TEXT,
    Color TEXT,
    IsActive INTEGER DEFAULT 1,
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (ParentCategoryID) REFERENCES Categories(CategoryID)
);
"@,
            # 14. BUDGETS (Department + Project Budgets mit Hierarchie)
            @"
CREATE TABLE Budgets (
    BudgetID INTEGER PRIMARY KEY AUTOINCREMENT,
    DepartmentID INTEGER,
    ProjectID INTEGER,
    BudgetYear INTEGER NOT NULL,
    BudgetQuarter INTEGER CHECK (BudgetQuarter BETWEEN 1 AND 4),
    CategoryID INTEGER,
    AllocatedAmount REAL NOT NULL DEFAULT 0,
    SpentAmount REAL DEFAULT 0,
    CommittedAmount REAL DEFAULT 0,
    RemainingAmount REAL GENERATED ALWAYS AS (AllocatedAmount - SpentAmount - CommittedAmount) STORED,
    ApprovedByUserID INTEGER,
    ApprovedDate TEXT,
    Status TEXT DEFAULT 'draft' CHECK (Status IN ('draft', 'approved', 'active', 'closed')),
    Notes TEXT,
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    ModifiedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (DepartmentID) REFERENCES Departments(DepartmentID),
    FOREIGN KEY (ProjectID) REFERENCES Projects(ProjectID),
    FOREIGN KEY (CategoryID) REFERENCES Categories(CategoryID),
    FOREIGN KEY (ApprovedByUserID) REFERENCES Users(UserID),
    CHECK ((DepartmentID IS NOT NULL AND ProjectID IS NULL) OR (DepartmentID IS NULL AND ProjectID IS NOT NULL))
);
"@,
            # 15. EXPENSES (Budget tracking mit komplexen Dependencies)
            @"
CREATE TABLE Expenses (
    ExpenseID INTEGER PRIMARY KEY AUTOINCREMENT,
    BudgetID INTEGER NOT NULL,
    UserID INTEGER NOT NULL,
    ProjectID INTEGER,
    TaskID INTEGER,
    ExpenseDate TEXT NOT NULL,
    Amount REAL NOT NULL CHECK (Amount > 0),
    Currency TEXT DEFAULT 'USD',
    ExchangeRate REAL DEFAULT 1.0,
    AmountUSD REAL GENERATED ALWAYS AS (Amount * ExchangeRate) STORED,
    CategoryID INTEGER,
    Description TEXT NOT NULL,
    Vendor TEXT,
    InvoiceNumber TEXT,
    ReceiptAttachment BLOB,
    Status TEXT DEFAULT 'submitted' CHECK (Status IN ('draft', 'submitted', 'approved', 'rejected', 'paid')),
    ApprovedByUserID INTEGER,
    ApprovedDate TEXT,
    PaidDate TEXT,
    ReimbursementRequired INTEGER DEFAULT 0,
    TaxAmount REAL DEFAULT 0,
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    ModifiedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (BudgetID) REFERENCES Budgets(BudgetID),
    FOREIGN KEY (UserID) REFERENCES Users(UserID),
    FOREIGN KEY (ProjectID) REFERENCES Projects(ProjectID),
    FOREIGN KEY (TaskID) REFERENCES Tasks(TaskID),
    FOREIGN KEY (CategoryID) REFERENCES Categories(CategoryID),
    FOREIGN KEY (ApprovedByUserID) REFERENCES Users(UserID)
);
"@,
            # 16. AUDIT_LOG (Comprehensive audit trail)
            @"
CREATE TABLE AuditLog (
    AuditID INTEGER PRIMARY KEY AUTOINCREMENT,
    TableName TEXT NOT NULL,
    RecordID INTEGER NOT NULL,
    Operation TEXT NOT NULL CHECK (Operation IN ('INSERT', 'UPDATE', 'DELETE')),
    OldValues TEXT, -- JSON
    NewValues TEXT, -- JSON
    ChangedColumns TEXT, -- JSON array
    UserID INTEGER,
    SessionID TEXT,
    IPAddress TEXT,
    UserAgent TEXT,
    Timestamp TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (UserID) REFERENCES Users(UserID)
);
"@,
            # INDICES für Performance
            @"
CREATE INDEX idx_departments_company ON Departments(CompanyID);
CREATE INDEX idx_departments_parent ON Departments(ParentDepartmentID);
CREATE INDEX idx_departments_manager ON Departments(ManagerUserID);
CREATE INDEX idx_teams_department ON Teams(DepartmentID);
CREATE INDEX idx_teams_leader ON Teams(TeamLeaderUserID);
CREATE INDEX idx_users_team ON Users(TeamID);
CREATE INDEX idx_users_manager ON Users(ManagerUserID);
CREATE INDEX idx_users_email ON Users(Email);
CREATE INDEX idx_users_employee_id ON Users(EmployeeID);
CREATE INDEX idx_user_roles_user ON UserRoles(UserID);
CREATE INDEX idx_user_roles_role ON UserRoles(RoleID);
CREATE INDEX idx_projects_company ON Projects(CompanyID);
CREATE INDEX idx_projects_manager ON Projects(ProjectManagerUserID);
CREATE INDEX idx_projects_department ON Projects(SponsorDepartmentID);
CREATE INDEX idx_project_skills_project ON ProjectSkills(ProjectID);
CREATE INDEX idx_project_skills_skill ON ProjectSkills(SkillID);
CREATE INDEX idx_user_skills_user ON UserSkills(UserID);
CREATE INDEX idx_user_skills_skill ON UserSkills(SkillID);
CREATE INDEX idx_tasks_project ON Tasks(ProjectID);
CREATE INDEX idx_tasks_parent ON Tasks(ParentTaskID);
CREATE INDEX idx_tasks_assigned ON Tasks(AssignedToUserID);
CREATE INDEX idx_task_assignments_task ON TaskAssignments(TaskID);
CREATE INDEX idx_task_assignments_user ON TaskAssignments(UserID);
CREATE INDEX idx_categories_parent ON Categories(ParentCategoryID);
CREATE INDEX idx_budgets_department ON Budgets(DepartmentID);
CREATE INDEX idx_budgets_project ON Budgets(ProjectID);
CREATE INDEX idx_expenses_budget ON Expenses(BudgetID);
CREATE INDEX idx_expenses_user ON Expenses(UserID);
CREATE INDEX idx_expenses_project ON Expenses(ProjectID);
CREATE INDEX idx_expenses_date ON Expenses(ExpenseDate);
CREATE INDEX idx_audit_table_record ON AuditLog(TableName, RecordID);
CREATE INDEX idx_audit_user ON AuditLog(UserID);
CREATE INDEX idx_audit_timestamp ON AuditLog(Timestamp);
"@,
            # VIEWS für komplexe Joins
            @"
CREATE VIEW UserHierarchy AS
SELECT 
    u.UserID,
    u.Username,
    u.FirstName || ' ' || u.LastName as FullName,
    u.JobTitle,
    t.TeamName,
    d.DepartmentName,
    c.CompanyName,
    m.FirstName || ' ' || m.LastName as ManagerName,
    u.IsActive
FROM Users u
LEFT JOIN Teams t ON u.TeamID = t.TeamID
LEFT JOIN Departments d ON t.DepartmentID = d.DepartmentID
LEFT JOIN Companies c ON d.CompanyID = c.CompanyID
LEFT JOIN Users m ON u.ManagerUserID = m.UserID;
"@,
            @"
CREATE VIEW ProjectSummary AS
SELECT 
    p.ProjectID,
    p.ProjectName,
    p.Status,
    p.Priority,
    c.CompanyName,
    d.DepartmentName as SponsorDepartment,
    pm.FirstName || ' ' || pm.LastName as ProjectManager,
    p.BudgetAllocated,
    p.BudgetSpent,
    (p.BudgetAllocated - p.BudgetSpent) as BudgetRemaining,
    p.PercentComplete,
    COUNT(t.TaskID) as TotalTasks,
    COUNT(CASE WHEN t.Status = 'completed' THEN 1 END) as CompletedTasks
FROM Projects p
JOIN Companies c ON p.CompanyID = c.CompanyID
LEFT JOIN Departments d ON p.SponsorDepartmentID = d.DepartmentID
LEFT JOIN Users pm ON p.ProjectManagerUserID = pm.UserID
LEFT JOIN Tasks t ON p.ProjectID = t.ProjectID
GROUP BY p.ProjectID, p.ProjectName, p.Status, p.Priority, c.CompanyName, d.DepartmentName, pm.FirstName, pm.LastName, p.BudgetAllocated, p.BudgetSpent, p.PercentComplete;
"@,
            @"
CREATE VIEW DepartmentBudgetSummary AS
SELECT 
    d.DepartmentID,
    d.DepartmentName,
    c.CompanyName,
    b.BudgetYear,
    SUM(b.AllocatedAmount) as TotalAllocated,
    SUM(b.SpentAmount) as TotalSpent,
    SUM(b.CommittedAmount) as TotalCommitted,
    SUM(b.RemainingAmount) as TotalRemaining,
    COUNT(b.BudgetID) as BudgetCount
FROM Departments d
JOIN Companies c ON d.CompanyID = c.CompanyID
LEFT JOIN Budgets b ON d.DepartmentID = b.DepartmentID
GROUP BY d.DepartmentID, d.DepartmentName, c.CompanyName, b.BudgetYear;
"@
        )
        minimal = @(
            @"
CREATE TABLE SimpleTable (
    ID INTEGER PRIMARY KEY,
    Name TEXT NOT NULL,
    Value INTEGER,
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP
);
"@
        )
    }
    
    return $schemas[$SchemaType]
}

function Initialize-ComplexTestData {
    param(
        $Connection,
        [string]$DataSize = "medium",
        [switch]$IncludeEdgeCases = $false
    )
    
    Write-Verbose "Initialisiere komplexe Test-Daten: $DataSize"
    
    $dataSizes = @{
        "small" = @{ Companies = 2; DepartmentsPerCompany = 3; TeamsPerDepartment = 2; UsersPerTeam = 5; ProjectsPerCompany = 3; SkillsTotal = 20 }
        "medium" = @{ Companies = 5; DepartmentsPerCompany = 5; TeamsPerDepartment = 3; UsersPerTeam = 8; ProjectsPerCompany = 8; SkillsTotal = 50 }
        "large" = @{ Companies = 10; DepartmentsPerCompany = 10; TeamsPerDepartment = 5; UsersPerTeam = 12; ProjectsPerCompany = 15; SkillsTotal = 100 }
    }
    
    $config = $dataSizes[$DataSize]
    $adapter = New-DatabaseAdapter -ConnectionString $Connection
    
    # 1. Companies
    Write-Verbose "Erstelle Companies..."
    $companies = @()
    $industries = @("Technology", "Healthcare", "Finance", "Manufacturing", "Retail", "Education", "Government")
    $countries = @("USA", "Germany", "UK", "Japan", "Canada", "Australia", "France")
    
    for ($i = 1; $i -le $config.Companies; $i++) {
        $company = @{
            CompanyID = $i
            CompanyName = "Company $i Corp"
            CompanyCode = "COMP$('{0:D3}' -f $i)"
            Industry = $industries[($i - 1) % $industries.Count]
            FoundedYear = Get-Random -Minimum 1950 -Maximum 2020
            HeadquartersCountry = $countries[($i - 1) % $countries.Count]
            AnnualRevenue = (Get-Random -Minimum 1000000 -Maximum 1000000000)
            EmployeeCount = Get-Random -Minimum 50 -Maximum 10000
            Website = "https://company$i.com"
        }
        $companies += $company
        
        $query = "INSERT INTO Companies (CompanyID, CompanyName, CompanyCode, Industry, FoundedYear, HeadquartersCountry, AnnualRevenue, EmployeeCount, Website) VALUES (@CompanyID, @CompanyName, @CompanyCode, @Industry, @FoundedYear, @HeadquartersCountry, @AnnualRevenue, @EmployeeCount, @Website)"
        $adapter.ExecuteNonQuery($query, $company) | Out-Null
    }
    
    # 2. Departments (mit Hierarchie)
    Write-Verbose "Erstelle Departments..."
    $departments = @()
    $deptNames = @("Engineering", "Sales", "Marketing", "HR", "Finance", "Operations", "R&D", "Customer Support", "Legal", "IT")
    $deptId = 1
    
    foreach ($company in $companies) {
        $companyDepts = @()
        
        for ($d = 0; $d -lt $config.DepartmentsPerCompany; $d++) {
            $dept = @{
                DepartmentID = $deptId
                CompanyID = $company.CompanyID
                DepartmentName = $deptNames[$d % $deptNames.Count]
                DepartmentCode = "DEPT$('{0:D3}' -f $deptId)"
                ParentDepartmentID = if ($d -gt 0 -and (Get-Random -Maximum 3) -eq 0) { $companyDepts[0].DepartmentID } else { $null }
                BudgetAmount = Get-Random -Minimum 100000 -Maximum 5000000
                CostCenter = "CC$deptId"
                Location = @("HQ", "Remote", "Branch A", "Branch B")[(Get-Random -Maximum 4)]
            }
            $departments += $dept
            $companyDepts += $dept
            $deptId++
            
            $query = "INSERT INTO Departments (DepartmentID, CompanyID, DepartmentName, DepartmentCode, ParentDepartmentID, BudgetAmount, CostCenter, Location) VALUES (@DepartmentID, @CompanyID, @DepartmentName, @DepartmentCode, @ParentDepartmentID, @BudgetAmount, @CostCenter, @Location)"
            $adapter.ExecuteNonQuery($query, $dept) | Out-Null
        }
    }
    
    # 3. Teams
    Write-Verbose "Erstelle Teams..."
    $teams = @()
    $teamTypes = @("permanent", "project", "temporary")
    $teamId = 1
    
    foreach ($dept in $departments) {
        for ($t = 1; $t -le $config.TeamsPerDepartment; $t++) {
            $team = @{
                TeamID = $teamId
                DepartmentID = $dept.DepartmentID
                TeamName = "$($dept.DepartmentName) Team $t"
                TeamType = $teamTypes[(Get-Random -Maximum 3)]
                MaxMembers = Get-Random -Minimum 5 -Maximum 15
                StartDate = (Get-Date).AddDays(-(Get-Random -Maximum 365)).ToString("yyyy-MM-dd")
                EndDate = if ($teamTypes[(Get-Random -Maximum 3)] -eq "temporary") { (Get-Date).AddDays((Get-Random -Maximum 365)).ToString("yyyy-MM-dd") } else { $null }
            }
            $teams += $team
            $teamId++
            
            $query = "INSERT INTO Teams (TeamID, DepartmentID, TeamName, TeamType, MaxMembers, StartDate, EndDate) VALUES (@TeamID, @DepartmentID, @TeamName, @TeamType, @MaxMembers, @StartDate, @EndDate)"
            $adapter.ExecuteNonQuery($query, $team) | Out-Null
        }
    }
    
    # 4. Users (mit Manager-Hierarchie)
    Write-Verbose "Erstelle Users..."
    $users = @()
    $firstNames = @("John", "Jane", "Mike", "Sarah", "David", "Lisa", "Chris", "Amy", "Tom", "Emma", "Alex", "Maria")
    $lastNames = @("Smith", "Johnson", "Brown", "Davis", "Miller", "Wilson", "Moore", "Taylor", "Anderson", "Thomas", "Jackson", "White")
    $jobTitles = @("Developer", "Manager", "Analyst", "Specialist", "Coordinator", "Lead", "Senior Developer", "Junior Developer", "Architect", "Consultant")
    $languages = @("en", "de", "fr", "es", "ja")
    $timezones = @("UTC", "EST", "PST", "CET", "JST")
    $userId = 1
    
    foreach ($team in $teams) {
        $teamUsers = @()
        
        for ($u = 1; $u -le $config.UsersPerTeam; $u++) {
            $firstName = $firstNames[(Get-Random -Maximum $firstNames.Count)]
            $lastName = $lastNames[(Get-Random -Maximum $lastNames.Count)]
            
            $user = @{
                UserID = $userId
                Username = "$firstName$lastName$userId".ToLower()
                Email = "$firstName.$lastName$userId@company.com".ToLower()
                FirstName = $firstName
                LastName = $lastName
                EmployeeID = "EMP$('{0:D6}' -f $userId)"
                TeamID = $team.TeamID
                ManagerUserID = if ($u -gt 1 -and $teamUsers.Count -gt 0) { $teamUsers[0].UserID } else { $null }
                JobTitle = $jobTitles[(Get-Random -Maximum $jobTitles.Count)]
                HireDate = (Get-Date).AddDays(-(Get-Random -Maximum 1825)).ToString("yyyy-MM-dd")
                Salary = Get-Random -Minimum 40000 -Maximum 150000
                BonusPercentage = (Get-Random -Maximum 30) / 100.0
                AccessLevel = Get-Random -Minimum 1 -Maximum 5
                PreferredLanguage = $languages[(Get-Random -Maximum $languages.Count)]
                TimeZone = $timezones[(Get-Random -Maximum $timezones.Count)]
                Settings = @{ notifications = $true; theme = "dark"; language = $languages[(Get-Random -Maximum $languages.Count)] } | ConvertTo-Json -Compress
            }
            $users += $user
            $teamUsers += $user
            $userId++
            
            $query = "INSERT INTO Users (UserID, Username, Email, FirstName, LastName, EmployeeID, TeamID, ManagerUserID, JobTitle, HireDate, Salary, BonusPercentage, AccessLevel, PreferredLanguage, TimeZone, Settings) VALUES (@UserID, @Username, @Email, @FirstName, @LastName, @EmployeeID, @TeamID, @ManagerUserID, @JobTitle, @HireDate, @Salary, @BonusPercentage, @AccessLevel, @PreferredLanguage, @TimeZone, @Settings)"
            $adapter.ExecuteNonQuery($query, $user) | Out-Null
        }
    }
    
    # 5. Roles
    Write-Verbose "Erstelle Roles..."
    $roles = @(
        @{ RoleID = 1; RoleName = "Administrator"; RoleCode = "ADMIN"; Description = "Full system access"; Permissions = '["all"]'; IsSystemRole = 1 },
        @{ RoleID = 2; RoleName = "Manager"; RoleCode = "MGR"; Description = "Management access"; Permissions = '["read", "write", "manage_team"]'; IsSystemRole = 0 },
        @{ RoleID = 3; RoleName = "Employee"; RoleCode = "EMP"; Description = "Standard employee access"; Permissions = '["read", "write_own"]'; IsSystemRole = 0 },
        @{ RoleID = 4; RoleName = "Project Manager"; RoleCode = "PM"; Description = "Project management access"; Permissions = '["read", "write", "manage_projects"]'; IsSystemRole = 0 },
        @{ RoleID = 5; RoleName = "Finance"; RoleCode = "FIN"; Description = "Financial data access"; Permissions = '["read", "write", "finance"]'; IsSystemRole = 0 },
        @{ RoleID = 6; RoleName = "HR"; RoleCode = "HR"; Description = "Human resources access"; Permissions = '["read", "write", "hr"]'; IsSystemRole = 0 },
        @{ RoleID = 7; RoleName = "Read Only"; RoleCode = "RO"; Description = "Read-only access"; Permissions = '["read"]'; IsSystemRole = 0 }
    )
    
    foreach ($role in $roles) {
        $query = "INSERT INTO Roles (RoleID, RoleName, RoleCode, Description, Permissions, IsSystemRole) VALUES (@RoleID, @RoleName, @RoleCode, @Description, @Permissions, @IsSystemRole)"
        $adapter.ExecuteNonQuery($query, $role) | Out-Null
    }
    
    # 6. UserRoles (Many-to-Many)
    Write-Verbose "Erstelle UserRoles..."
    $userRoleId = 1
    foreach ($user in $users) {
        # Jeder User bekommt mindestens Employee-Rolle
        $userRole = @{
            UserRoleID = $userRoleId
            UserID = $user.UserID
            RoleID = 3  # Employee
            AssignedDate = $user.HireDate
            AssignedByUserID = if ($user.ManagerUserID) { $user.ManagerUserID } else { 1 }
        }
        $userRoleId++
        
        $query = "INSERT INTO UserRoles (UserRoleID, UserID, RoleID, AssignedDate, AssignedByUserID) VALUES (@UserRoleID, @UserID, @RoleID, @AssignedDate, @AssignedByUserID)"
        $adapter.ExecuteNonQuery($query, $userRole) | Out-Null
        
        # 20% bekommen zusätzliche Rollen (aber nicht Employee-Rolle, die haben sie schon)
        if ((Get-Random -Maximum 5) -eq 0) {
            $availableRoles = @(2, 4, 5, 6, 7)  # Manager, PM, Finance, HR, ReadOnly (nicht Employee=3)
            $roleId = $availableRoles[(Get-Random -Maximum $availableRoles.Count)]
            
            $additionalRole = @{
                UserRoleID = $userRoleId
                UserID = $user.UserID
                RoleID = $roleId
                AssignedDate = (Get-Date).AddDays(-(Get-Random -Maximum 365)).ToString("yyyy-MM-dd")
                AssignedByUserID = 1
            }
            $userRoleId++
            
            $adapter.ExecuteNonQuery($query, $additionalRole) | Out-Null
        }
    }
    
    Write-Verbose "Komplexe Test-Daten erfolgreich erstellt:"
    Write-Verbose "  - $($companies.Count) Companies"
    Write-Verbose "  - $($departments.Count) Departments"
    Write-Verbose "  - $($teams.Count) Teams"
    Write-Verbose "  - $($users.Count) Users"
    Write-Verbose "  - $($roles.Count) Roles"
    Write-Verbose "  - $(($users.Count * 1.2).ToString('F0')) UserRoles"
    
    return @{
        Companies = $companies.Count
        Departments = $departments.Count
        Teams = $teams.Count
        Users = $users.Count
        Roles = $roles.Count
        UserRoles = $userRoleId - 1
    }
}

# Test-Funktionen für komplexe Szenarien
function Test-HierarchicalIntegrity {
    param($Connection)
    
    $adapter = New-DatabaseAdapter -ConnectionString $Connection
    $issues = @()
    
    # Test 1: Orphaned Departments
    $orphanedDepts = $adapter.ExecuteQuery("SELECT d.DepartmentID, d.DepartmentName FROM Departments d LEFT JOIN Companies c ON d.CompanyID = c.CompanyID WHERE c.CompanyID IS NULL", @{})
    if ($orphanedDepts.Count -gt 0) {
        $issues += "Found $($orphanedDepts.Count) orphaned departments"
    }
    
    # Test 2: Circular Manager References  
    $circularManagers = $adapter.ExecuteQuery("WITH RECURSIVE manager_hierarchy AS (SELECT UserID, ManagerUserID, 1 as level FROM Users WHERE ManagerUserID IS NOT NULL UNION ALL SELECT u.UserID, u.ManagerUserID, mh.level + 1 FROM Users u JOIN manager_hierarchy mh ON u.UserID = mh.ManagerUserID WHERE mh.level < 10) SELECT UserID FROM manager_hierarchy WHERE level >= 10", @{})
    if ($circularManagers.Count -gt 0) {
        $issues += "Found potential circular manager references"
    }
    
    # Test 3: Department Hierarchy Depth
    $maxDepth = $adapter.ExecuteQuery("WITH RECURSIVE dept_hierarchy AS (SELECT DepartmentID, ParentDepartmentID, 0 as depth FROM Departments WHERE ParentDepartmentID IS NULL UNION ALL SELECT d.DepartmentID, d.ParentDepartmentID, dh.depth + 1 FROM Departments d JOIN dept_hierarchy dh ON d.ParentDepartmentID = dh.DepartmentID) SELECT MAX(depth) as MaxDepth FROM dept_hierarchy", @{})
    if ($maxDepth[0].MaxDepth -gt 5) {
        $issues += "Department hierarchy exceeds 5 levels: $($maxDepth[0].MaxDepth)"
    }
    
    return @{
        IsValid = $issues.Count -eq 0
        Issues = $issues
    }
}

function Test-ReferentialIntegrity {
    param($Connection)
    
    $adapter = New-DatabaseAdapter -ConnectionString $Connection
    $issues = @()
    
    # Test alle Foreign Key Beziehungen
    $fkTests = @(
        @{ Table = "Users"; Column = "TeamID"; RefTable = "Teams"; RefColumn = "TeamID" },
        @{ Table = "Users"; Column = "ManagerUserID"; RefTable = "Users"; RefColumn = "UserID" },
        @{ Table = "Teams"; Column = "DepartmentID"; RefTable = "Departments"; RefColumn = "DepartmentID" },
        @{ Table = "Departments"; Column = "CompanyID"; RefTable = "Companies"; RefColumn = "CompanyID" },
        @{ Table = "UserRoles"; Column = "UserID"; RefTable = "Users"; RefColumn = "UserID" },
        @{ Table = "UserRoles"; Column = "RoleID"; RefTable = "Roles"; RefColumn = "RoleID" }
    )
    
    foreach ($fkTest in $fkTests) {
        $query = "SELECT COUNT(*) as Count FROM $($fkTest.Table) t LEFT JOIN $($fkTest.RefTable) r ON t.$($fkTest.Column) = r.$($fkTest.RefColumn) WHERE t.$($fkTest.Column) IS NOT NULL AND r.$($fkTest.RefColumn) IS NULL"
        $result = $adapter.ExecuteQuery($query, @{})
        
        if ($result[0].Count -gt 0) {
            $issues += "Found $($result[0].Count) orphaned records in $($fkTest.Table).$($fkTest.Column)"
        }
    }
    
    return @{
        IsValid = $issues.Count -eq 0
        Issues = $issues
    }
}

Write-Verbose "Complex Database Schema loaded successfully"