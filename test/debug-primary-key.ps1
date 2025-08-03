# Debug Primary Key Parsing Issue

$ErrorActionPreference = "Stop"

# Create temporary database
$dbPath = "debug-pk-test.db"
"CREATE TABLE single_pk (id INTEGER PRIMARY KEY, name TEXT);" | sqlite3 $dbPath

# Test PRAGMA output
Write-Host "=== Raw PRAGMA Output ===" -ForegroundColor Yellow
$rawResult = "PRAGMA table_info(single_pk)" | sqlite3 $dbPath
Write-Host $rawResult

Write-Host "`n=== CSV PRAGMA Output ===" -ForegroundColor Yellow
$csvResult = "PRAGMA table_info(single_pk)" | sqlite3 -header -csv $dbPath
Write-Host $csvResult

Write-Host "`n=== Line Processing ===" -ForegroundColor Yellow
$lines = $csvResult -split "\r?\n" | Where-Object { $_.Trim() -ne "" }
for ($i = 0; $i -lt $lines.Count; $i++) {
    Write-Host "Line $i`: '$($lines[$i])'"
}

Write-Host "`n=== Regex Test ===" -ForegroundColor Yellow
if ($lines.Count -gt 1) {
    $line = $lines[1]  # First data line
    Write-Host "Testing line: '$line'"
    
    if ($line -match '^(\d+),([^,]+),([^,]+),(\d+),([^,]*),(\d+)$') {
        Write-Host "Regex matched!"
        Write-Host "  cid: '$($matches[1])'"
        Write-Host "  columnName: '$($matches[2])'"
        Write-Host "  type: '$($matches[3])'"
        Write-Host "  notnull: '$($matches[4])'"
        Write-Host "  defaultValue: '$($matches[5])'"
        Write-Host "  pk: '$($matches[6])'"
        
        $columnName = $matches[2].Trim('"').Trim("'")
        Write-Host "  processed columnName: '$columnName'"
    } else {
        Write-Host "Regex did not match!"
        Write-Host "Trying fallback split..."
        $parts = $line -split ","
        Write-Host "Split result count: $($parts.Count)"
        for ($j = 0; $j -lt $parts.Count; $j++) {
            Write-Host "  Part $j`: '$($parts[$j])'"
        }
    }
}

# Clean up
Remove-Item $dbPath -Force