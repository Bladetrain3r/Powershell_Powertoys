# RPG Character Generator
# Generates random characters based on the JSON schema

param(
    [string]$SchemaPath = ".\outputs\schema.json",
    [string]$OutputPath = ".\outputs\characters",
    [int]$CharacterCount = 4
)

# Ensure output directory exists
if (!(Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force
    Write-Host "Created output directory: $OutputPath"
}

# Load JSON schema
function Load-Schema {
    param([string]$FilePath)
    
    if (!(Test-Path $FilePath)) {
        Write-Host "Schema file not found: $FilePath"
        return $null
    }
    
    try {
        $content = Get-Content $FilePath -Raw -Encoding UTF8
        $schema = $content | ConvertFrom-Json
        return $schema
    } catch {
        Write-Host "Error parsing JSON schema: $($_.Exception.Message)"
        return $null
    }
}

# Generate random name
function Get-RandomName {
    param($Schema)
    
    if ($Schema.character_names) {
        $firstName = $Schema.character_names.first_names | Get-Random
        $lastName = $Schema.character_names.last_names | Get-Random
    } else {
        # Fallback names if schema doesn't have them
        $firstNames = @("Aria", "Bren", "Cora", "Dain", "Elara", "Finn", "Gilda", "Hale", "Ivy", "Jace")
        $lastNames = @("Brightblade", "Shadowmere", "Stormwind", "Ironforge", "Goldleaf")
        $firstName = $firstNames | Get-Random
        $lastName = $lastNames | Get-Random
    }
    
    return "$firstName $lastName"
}

# Generate character with stat variation
function New-Character {
    param($Schema, $ClassName)
    
    $classData = $Schema.character_classes.$ClassName
    $character = @{
        name = Get-RandomName -Schema $Schema
        class = $className
        level = Get-Random -Minimum 1 -Maximum 6
        stats = @{}
        equipment = @()
        background = ""
    }
    
    # Apply stat variations (-1 to +2 from base)
    foreach ($statName in $classData.base_stats.PSObject.Properties.Name) {
        $baseStat = $classData.base_stats.$statName
        $variation = Get-Random -Minimum -1 -Maximum 3
        $finalStat = [Math]::Max(3, [Math]::Min(12, $baseStat + $variation))
        $character.stats[$statName] = $finalStat
    }
    
    # Add random equipment from schema
    if ($Schema.available_equipment) {
        $allEquipment = $Schema.available_equipment
    } else {
        # Fallback equipment list
        $allEquipment = @("weapon", "armor", "supplies")
    }
    $equipmentCount = Get-Random -Minimum 2 -Maximum 4
    $character.equipment = $allEquipment | Get-Random -Count $equipmentCount
    
    # Generate background from schema
    if ($Schema.character_backgrounds) {
        $character.background = $Schema.character_backgrounds | Get-Random
    } else {
        $character.background = "A mysterious wanderer"
    }
    
    return $character
}

# Load schema
Write-Host "Loading schema from: $SchemaPath"
$schema = Load-Schema -FilePath $SchemaPath

if (!$schema) {
    Write-Host "Failed to load schema"
    exit
}

$availableClasses = @($schema.character_classes.PSObject.Properties.Name)
$characters = @()

# Generate characters
Write-Host "Generating $CharacterCount characters..."

for ($i = 1; $i -le $CharacterCount; $i++) {
    $className = $availableClasses | Get-Random
    $character = New-Character -Schema $schema -ClassName $className
    $characters += $character
    
    Write-Host "Generated: $($character.name) the $($character.class)"
}

# Save characters to JSON
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$charactersPath = "$OutputPath\characters_$timestamp.json"
$characters | ConvertTo-Json -Depth 4 | Out-File -FilePath $charactersPath -Encoding UTF8

# Also save as latest for easy pipeline access
$latestPath = "$OutputPath\latest_characters.json"
$characters | ConvertTo-Json -Depth 4 | Out-File -FilePath $latestPath -Encoding UTF8

# Display summary
Write-Host "`nCharacter Party Generated:"
Write-Host "========================"
foreach ($char in $characters) {
    Write-Host "$($char.name) - Level $($char.level) $($char.class)"
    Write-Host "  Stats: STR:$($char.stats.strength) AGI:$($char.stats.agility) INT:$($char.stats.intellect) CHA:$($char.stats.charisma) LCK:$($char.stats.luck)"
    Write-Host "  Equipment: $($char.equipment -join ', ')"
    Write-Host "  Background: $($char.background)"
    Write-Host ""
}

Write-Host "Characters saved to: $charactersPath"
Write-Host "Latest copy saved to: $latestPath"
Write-Host "Ready for adventure generation!"

# Return character data for potential use
$output = @{
    characters = $characters
    schema = $schema
    timestamp = $timestamp
}

return $output