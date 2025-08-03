# SyncRay Assertion Helpers - Erweiterte Assertions für komplexe Test-Szenarien

# JSON-spezifische Assertions
function Assert-JsonEqual {
    param($Expected, $Actual, [string]$Message = "JSON-Objekte sind nicht gleich")
    
    try {
        $expectedObj = if ($Expected -is [string]) { $Expected | ConvertFrom-Json } else { $Expected }
        $actualObj = if ($Actual -is [string]) { $Actual | ConvertFrom-Json } else { $Actual }
        
        $expectedJson = $expectedObj | ConvertTo-Json -Depth 10 -Compress | Sort-Object
        $actualJson = $actualObj | ConvertTo-Json -Depth 10 -Compress | Sort-Object
        
        if ($expectedJson -ne $actualJson) {
            throw "Assert-JsonEqual: $Message`nErwartet: $expectedJson`nTatsächlich: $actualJson"
        }
    } catch {
        throw "Assert-JsonEqual: Fehler beim JSON-Vergleich: $_"
    }
}

function Assert-JsonProperty {
    param($JsonObject, [string]$PropertyPath, $ExpectedValue = $null, [string]$Message = "JSON-Property nicht gefunden oder falsch")
    
    try {
        $obj = if ($JsonObject -is [string]) { $JsonObject | ConvertFrom-Json } else { $JsonObject }
        
        # Property-Pfad auflösen (z.B. "user.settings.theme")
        $pathParts = $PropertyPath -split '\.'
        $currentObj = $obj
        
        foreach ($part in $pathParts) {
            if ($currentObj -eq $null) {
                throw "Property-Pfad '$PropertyPath' nicht gefunden"
            }
            
            if ($currentObj.PSObject.Properties.Name -contains $part) {
                $currentObj = $currentObj.$part
            } else {
                throw "Property '$part' nicht gefunden in Pfad '$PropertyPath'"
            }
        }
        
        if ($ExpectedValue -ne $null -and $currentObj -ne $ExpectedValue) {
            throw "Property '$PropertyPath' hat falschen Wert. Erwartet: '$ExpectedValue', Tatsächlich: '$currentObj'"
        }
        
    } catch {
        throw "Assert-JsonProperty: $Message - $_"
    }
}

function Assert-JsonSchema {
    param($JsonObject, [hashtable]$Schema, [string]$Message = "JSON entspricht nicht dem Schema")
    
    try {
        $obj = if ($JsonObject -is [string]) { $JsonObject | ConvertFrom-Json } else { $JsonObject }
        
        foreach ($property in $Schema.GetEnumerator()) {
            $propName = $property.Key
            $propRequirements = $property.Value
            
            if ($propRequirements.Required -and -not ($obj.PSObject.Properties.Name -contains $propName)) {
                throw "Erforderliche Property '$propName' fehlt"
            }
            
            if ($obj.PSObject.Properties.Name -contains $propName) {
                $value = $obj.$propName
                
                if ($propRequirements.Type) {
                    $expectedType = $propRequirements.Type
                    $actualType = $value.GetType().Name
                    
                    if ($actualType -ne $expectedType) {
                        throw "Property '$propName' hat falschen Typ. Erwartet: $expectedType, Tatsächlich: $actualType"
                    }
                }
                
                if ($propRequirements.MinLength -and $value.Length -lt $propRequirements.MinLength) {
                    throw "Property '$propName' ist zu kurz. Minimum: $($propRequirements.MinLength), Tatsächlich: $($value.Length)"
                }
                
                if ($propRequirements.MaxLength -and $value.Length -gt $propRequirements.MaxLength) {
                    throw "Property '$propName' ist zu lang. Maximum: $($propRequirements.MaxLength), Tatsächlich: $($value.Length)"
                }
                
                if ($propRequirements.Pattern -and $value -notmatch $propRequirements.Pattern) {
                    throw "Property '$propName' entspricht nicht dem Pattern '$($propRequirements.Pattern)'"
                }
            }
        }
        
    } catch {
        throw "Assert-JsonSchema: $Message - $_"
    }
}

# CSV-spezifische Assertions
function Assert-CsvStructure {
    param([string]$CsvContent, [string[]]$ExpectedHeaders, [string]$Message = "CSV-Struktur entspricht nicht der Erwartung")
    
    try {
        $lines = $CsvContent -split "`n" | Where-Object { $_.Trim() -ne "" }
        
        if ($lines.Count -eq 0) {
            throw "CSV ist leer"
        }
        
        $headers = $lines[0] -split "," | ForEach-Object { $_.Trim('"') }
        
        foreach ($expectedHeader in $ExpectedHeaders) {
            if ($headers -notcontains $expectedHeader) {
                throw "Erwarteter Header '$expectedHeader' nicht gefunden. Verfügbare Headers: $($headers -join ', ')"
            }
        }
        
        # Prüfen ob alle Zeilen die gleiche Anzahl Spalten haben
        $expectedColumnCount = $headers.Count
        for ($i = 1; $i -lt $lines.Count; $i++) {
            $columns = ($lines[$i] -split ",").Count
            if ($columns -ne $expectedColumnCount) {
                throw "Zeile $($i + 1) hat $columns Spalten, erwartet: $expectedColumnCount"
            }
        }
        
    } catch {
        throw "Assert-CsvStructure: $Message - $_"
    }
}

function Assert-CsvRecordCount {
    param([string]$CsvContent, [int]$ExpectedCount, [string]$Message = "CSV-Datensatz-Anzahl entspricht nicht der Erwartung")
    
    try {
        $lines = $CsvContent -split "`n" | Where-Object { $_.Trim() -ne "" }
        $recordCount = $lines.Count - 1  # Header abziehen
        
        if ($recordCount -ne $ExpectedCount) {
            throw "CSV hat $recordCount Datensätze, erwartet: $ExpectedCount"
        }
        
    } catch {
        throw "Assert-CsvRecordCount: $Message - $_"
    }
}

# File-System Assertions
function Assert-FileContent {
    param([string]$FilePath, [string]$ExpectedContent, [string]$Message = "Datei-Inhalt entspricht nicht der Erwartung")
    
    Assert-FileExists -Path $FilePath
    
    try {
        $actualContent = Get-Content $FilePath -Raw
        
        if ($actualContent.Trim() -ne $ExpectedContent.Trim()) {
            throw "Datei-Inhalt unterscheidet sich.`nErwartet: $ExpectedContent`nTatsächlich: $actualContent"
        }
        
    } catch {
        throw "Assert-FileContent: $Message - $_"
    }
}

function Assert-FileSize {
    param([string]$FilePath, [long]$MinSizeBytes = 0, [long]$MaxSizeBytes = [long]::MaxValue, [string]$Message = "Datei-Größe außerhalb des erwarteten Bereichs")
    
    Assert-FileExists -Path $FilePath
    
    try {
        $fileSize = (Get-Item $FilePath).Length
        
        if ($fileSize -lt $MinSizeBytes -or $fileSize -gt $MaxSizeBytes) {
            throw "Datei-Größe $fileSize Bytes ist außerhalb des Bereichs $MinSizeBytes - $MaxSizeBytes Bytes"
        }
        
    } catch {
        throw "Assert-FileSize: $Message - $_"
    }
}

function Assert-FileAge {
    param([string]$FilePath, [timespan]$MaxAge, [string]$Message = "Datei ist zu alt")
    
    Assert-FileExists -Path $FilePath
    
    try {
        $fileAge = (Get-Date) - (Get-Item $FilePath).CreationTime
        
        if ($fileAge -gt $MaxAge) {
            throw "Datei ist $fileAge alt, maximum erlaubt: $MaxAge"
        }
        
    } catch {
        throw "Assert-FileAge: $Message - $_"
    }
}

# PowerShell-spezifische Assertions
function Assert-HasProperty {
    param($Object, [string]$PropertyName, [string]$Message = "Property nicht gefunden")
    
    if (-not ($Object.PSObject.Properties.Name -contains $PropertyName)) {
        throw "Assert-HasProperty: $Message. Property '$PropertyName' nicht in Objekt gefunden. Verfügbare Properties: $($Object.PSObject.Properties.Name -join ', ')"
    }
}

function Assert-HasMethod {
    param($Object, [string]$MethodName, [string]$Message = "Methode nicht gefunden")
    
    if (-not ($Object.PSObject.Methods.Name -contains $MethodName)) {
        throw "Assert-HasMethod: $Message. Methode '$MethodName' nicht in Objekt gefunden. Verfügbare Methoden: $($Object.PSObject.Methods.Name -join ', ')"
    }
}

function Assert-IsType {
    param($Object, [type]$ExpectedType, [string]$Message = "Objekt hat falschen Typ")
    
    $actualType = $Object.GetType()
    
    if ($actualType -ne $ExpectedType) {
        throw "Assert-IsType: $Message. Erwartet: $($ExpectedType.Name), Tatsächlich: $($actualType.Name)"
    }
}

function Assert-IsArray {
    param($Object, [int]$ExpectedLength = -1, [string]$Message = "Objekt ist kein Array")
    
    if (-not ($Object -is [array] -or $Object -is [System.Collections.IEnumerable])) {
        throw "Assert-IsArray: $Message. Typ: $($Object.GetType().Name)"
    }
    
    if ($ExpectedLength -ge 0) {
        $actualLength = if ($Object -is [array]) { $Object.Length } else { @($Object).Count }
        
        if ($actualLength -ne $ExpectedLength) {
            throw "Assert-IsArray: Array hat falsche Länge. Erwartet: $ExpectedLength, Tatsächlich: $actualLength"
        }
    }
}

function Assert-IsHashTable {
    param($Object, [string[]]$RequiredKeys = @(), [string]$Message = "Objekt ist keine Hashtable")
    
    if (-not ($Object -is [hashtable] -or $Object -is [System.Collections.IDictionary])) {
        throw "Assert-IsHashTable: $Message. Typ: $($Object.GetType().Name)"
    }
    
    foreach ($key in $RequiredKeys) {
        if (-not $Object.ContainsKey($key)) {
            throw "Assert-IsHashTable: Erforderlicher Key '$key' nicht gefunden. Verfügbare Keys: $($Object.Keys -join ', ')"
        }
    }
}

# Numeric Assertions
function Assert-InRange {
    param($Value, $MinValue, $MaxValue, [string]$Message = "Wert außerhalb des erwarteten Bereichs")
    
    if ($Value -lt $MinValue -or $Value -gt $MaxValue) {
        throw "Assert-InRange: $Message. Wert: $Value, Bereich: $MinValue - $MaxValue"
    }
}

function Assert-Approximately {
    param($Expected, $Actual, $Tolerance = 0.01, [string]$Message = "Werte sind nicht annähernd gleich")
    
    $difference = [math]::Abs($Expected - $Actual)
    
    if ($difference -gt $Tolerance) {
        throw "Assert-Approximately: $Message. Erwartet: $Expected, Tatsächlich: $Actual, Toleranz: $Tolerance, Differenz: $difference"
    }
}

function Assert-Positive {
    param($Value, [string]$Message = "Wert ist nicht positiv")
    
    if ($Value -le 0) {
        throw "Assert-Positive: $Message. Wert: $Value"
    }
}

function Assert-Negative {
    param($Value, [string]$Message = "Wert ist nicht negativ")
    
    if ($Value -ge 0) {
        throw "Assert-Negative: $Message. Wert: $Value"
    }
}

# String Assertions
function Assert-StartsWith {
    param([string]$String, [string]$Prefix, [string]$Message = "String startet nicht mit dem erwarteten Präfix")
    
    if (-not $String.StartsWith($Prefix)) {
        throw "Assert-StartsWith: $Message. String: '$String', Präfix: '$Prefix'"
    }
}

function Assert-EndsWith {
    param([string]$String, [string]$Suffix, [string]$Message = "String endet nicht mit dem erwarteten Suffix")
    
    if (-not $String.EndsWith($Suffix)) {
        throw "Assert-EndsWith: $Message. String: '$String', Suffix: '$Suffix'"
    }
}

function Assert-IsEmpty {
    param($Value, [string]$Message = "Wert ist nicht leer")
    
    $isEmpty = switch ($Value.GetType().Name) {
        "String" { [string]::IsNullOrWhiteSpace($Value) }
        "Array" { $Value.Length -eq 0 }
        "Hashtable" { $Value.Count -eq 0 }
        "ArrayList" { $Value.Count -eq 0 }
        default { $Value -eq $null }
    }
    
    if (-not $isEmpty) {
        throw "Assert-IsEmpty: $Message. Wert: '$Value'"
    }
}

function Assert-IsNotEmpty {
    param($Value, [string]$Message = "Wert ist leer")
    
    $isEmpty = switch ($Value.GetType().Name) {
        "String" { [string]::IsNullOrWhiteSpace($Value) }
        "Array" { $Value.Length -eq 0 }
        "Hashtable" { $Value.Count -eq 0 }
        "ArrayList" { $Value.Count -eq 0 }
        default { $Value -eq $null }
    }
    
    if ($isEmpty) {
        throw "Assert-IsNotEmpty: $Message"
    }
}

# DateTime Assertions
function Assert-DateInRange {
    param([datetime]$Date, [datetime]$MinDate, [datetime]$MaxDate, [string]$Message = "Datum außerhalb des erwarteten Bereichs")
    
    if ($Date -lt $MinDate -or $Date -gt $MaxDate) {
        throw "Assert-DateInRange: $Message. Datum: $Date, Bereich: $MinDate - $MaxDate"
    }
}

function Assert-IsRecent {
    param([datetime]$Date, [timespan]$MaxAge = [timespan]::FromHours(1), [string]$Message = "Datum ist nicht aktuell")
    
    $age = (Get-Date) - $Date
    
    if ($age -gt $MaxAge) {
        throw "Assert-IsRecent: $Message. Datum: $Date, Alter: $age, Maximum: $MaxAge"
    }
}

# Collection Assertions
function Assert-AllElementsMatch {
    param($Collection, [scriptblock]$Predicate, [string]$Message = "Nicht alle Elemente erfüllen die Bedingung")
    
    foreach ($item in $Collection) {
        $result = & $Predicate $item
        if (-not $result) {
            throw "Assert-AllElementsMatch: $Message. Element '$item' erfüllt Bedingung nicht"
        }
    }
}

function Assert-AnyElementMatches {
    param($Collection, [scriptblock]$Predicate, [string]$Message = "Kein Element erfüllt die Bedingung")
    
    foreach ($item in $Collection) {
        $result = & $Predicate $item
        if ($result) {
            return  # Mindestens ein Element erfüllt die Bedingung
        }
    }
    
    throw "Assert-AnyElementMatches: $Message"
}

function Assert-UniqueElements {
    param($Collection, [string]$Message = "Collection enthält doppelte Elemente")
    
    $unique = $Collection | Select-Object -Unique
    
    if ($unique.Count -ne $Collection.Count) {
        throw "Assert-UniqueElements: $Message. Original: $($Collection.Count), Unique: $($unique.Count)"
    }
}

function Assert-CollectionContainsAll {
    param($Collection, $ExpectedItems, [string]$Message = "Collection enthält nicht alle erwarteten Elemente")
    
    foreach ($expectedItem in $ExpectedItems) {
        if ($Collection -notcontains $expectedItem) {
            throw "Assert-CollectionContainsAll: $Message. Fehlendes Element: '$expectedItem'"
        }
    }
}

# Export für Module-System (deaktiviert für Dot-Sourcing)
# if ($MyInvocation.MyCommand.Path -and $MyInvocation.MyCommand.ModuleName) {
#     Export-ModuleMember -Function @(
#         "Assert-JsonEqual",
#         "Assert-JsonProperty", 
#         "Assert-JsonSchema",
#         "Assert-CsvStructure",
#         "Assert-CsvRecordCount",
#         "Assert-FileContent",
#         "Assert-FileSize",
#         "Assert-FileAge",
#         "Assert-HasProperty",
#         "Assert-HasMethod",
#         "Assert-IsType",
#         "Assert-IsArray",
#         "Assert-IsHashTable",
#         "Assert-InRange",
#         "Assert-Approximately",
#         "Assert-Positive",
#         "Assert-Negative",
#         "Assert-StartsWith",
#         "Assert-EndsWith",
#         "Assert-IsEmpty",
#         "Assert-IsNotEmpty",
#         "Assert-DateInRange",
#         "Assert-IsRecent",
#         "Assert-AllElementsMatch",
#         "Assert-AnyElementMatches",
#         "Assert-UniqueElements",
#         "Assert-CollectionContainsAll"
#     )
# }