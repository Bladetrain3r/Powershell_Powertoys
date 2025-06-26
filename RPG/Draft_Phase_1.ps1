# Encounter Variation Generator
# Stage 1: Generate multiple encounter variations using low-parameter model

param(
    [string]$SchemaPath = ".\outputs\schema.json",
    [string]$CharactersPath = ".\outputs\characters\latest_characters.json",
    [string]$OutputPath = ".\outputs\encounters",
    [string]$ModelName = "llama-3.2-8x3b-moe-dark-champion-instruct-uncensored-abliterated-18.4b",  # Low parameter model for variation generation
    [int]$VariationsPerEncounter = 5
)

# Ensure output directory exists
if (!(Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force
    Write-Host "Created output directory: $OutputPath"
}

# Load data files
function Load-JsonFile {
    param([string]$FilePath)
    
    if (!(Test-Path $FilePath)) {
        Write-Host "File not found: $FilePath"
        return $null
    }
    
    try {
        $content = Get-Content $FilePath -Raw -Encoding UTF8
        return $content | ConvertFrom-Json
    } catch {
        Write-Host "Error parsing JSON file: $($_.Exception.Message)"
        return $null
    }
}

# Generate encounter variations using AI
function Generate-EncounterVariations {
    param(
        $Schema,
        $Characters,
        $EncounterType,
        $EncounterNumber
    )
    
    $encounterData = $Schema.encounter_types.$EncounterType
    $partyLevel = ($Characters | Measure-Object -Property level -Average).Average
    $partySize = $Characters.Count
    
    # Build character summary for context
    $partySummary = ""
    foreach ($char in $Characters) {
        $partySummary += "$($char.name) (Level $($char.level) $($char.class)): "
        $partySummary += "STR:$($char.stats.strength) AGI:$($char.stats.agility) INT:$($char.stats.intellect) CHA:$($char.stats.charisma) LCK:$($char.stats.luck). "
    }
    
    $prompt = @"
You are generating encounter variations for a fantasy RPG adventure. Create $VariationsPerEncounter different variations of a $($encounterData.name).

PARTY CONTEXT:
$partySummary

ENCOUNTER TYPE: $($encounterData.name)
Description: $($encounterData.description)
Primary Stat: $($encounterData.primary_stat)
Secondary Stat: $($encounterData.secondary_stat)
Difficulty Range: $($encounterData.difficulty_range[0])-$($encounterData.difficulty_range[1])

For each variation, provide:
1. A brief scenario description (2-3 sentences)
2. The specific challenge or obstacle
3. Required dice roll difficulty (DC between $($encounterData.difficulty_range[0])-$($encounterData.difficulty_range[1]))
4. Which character(s) should make the roll and why
5. What stat(s) to use for the roll

Make each variation distinct and interesting. Consider the party's strengths and weaknesses.

Format each variation as:
VARIATION X:
Scenario: [description]
Challenge: [specific challenge]
DC: [number]
Roller: [character name and reason]
Stats: [primary stat, secondary stat if needed]
---
"@

    try {
        $body = @{
            model = $ModelName
            messages = @(
                @{
                    role = "user"
                    content = $prompt
                }
            )
            max_tokens = 1000
            temperature = 0.8  # Higher temperature for creative variations
            top_p = 0.9
            repeat_penalty = 1.5
        } | ConvertTo-Json -Depth 5
        
        $headers = @{
            'Content-Type' = 'application/json; charset=utf-8'
        }
        
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/chat/completions" -Method POST -Body $bodyBytes -Headers $headers
        $responseData = $response.Content | ConvertFrom-Json
        $aiResponse = $responseData.choices[0].message.content
        
        Write-Host "Generated variations for $EncounterType encounter"
        return $aiResponse
        
    } catch {
        Write-Host "Error generating encounter variations: $($_.Exception.Message)"
        return $null
    }
}

# Parse AI response into structured variations
function Parse-EncounterVariations {
    param([string]$AiResponse)
    
    $variations = @()
    $variationBlocks = $AiResponse -split "VARIATION \d+:" | Where-Object { $_.Trim() -ne "" }
    
    foreach ($block in $variationBlocks) {
        if ($block -match "Scenario:\s*(.+?)(?=Challenge:|$)") {
            $scenario = $matches[1].Trim()
        } else { $scenario = "Unknown scenario" }
        
        if ($block -match "Challenge:\s*(.+?)(?=DC:|$)") {
            $challenge = $matches[1].Trim()
        } else { $challenge = "Unknown challenge" }
        
        if ($block -match "DC:\s*(\d+)") {
            $dc = [int]$matches[1]
        } else { $dc = 12 }  # Default DC
        
        if ($block -match "Roller:\s*(.+?)(?=Stats:|$)") {
            $roller = $matches[1].Trim()
        } else { $roller = "Any character" }
        
        if ($block -match "Stats:\s*(.+?)(?=---|$)") {
            $stats = $matches[1].Trim()
        } else { $stats = "strength" }
        
        $variations += @{
            scenario = $scenario
            challenge = $challenge
            dc = $dc
            roller = $roller
            stats = $stats
            raw_text = $block.Trim()
        }
    }
    
    return $variations
}

# Main execution
Write-Host "Loading game data..."

$schema = Load-JsonFile -FilePath $SchemaPath
$characters = Load-JsonFile -FilePath $CharactersPath

if (!$schema -or !$characters) {
    Write-Host "Failed to load required data files"
    exit
}

# Get available encounter types
$encounterTypes = @($schema.encounter_types.PSObject.Properties.Name)
$encounterCount = $schema.game_rules.encounter_count

Write-Host "Generating $encounterCount encounters with $VariationsPerEncounter variations each..."
Write-Host "Available encounter types: $($encounterTypes -join ', ')"

$allEncounters = @()
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

for ($i = 1; $i -le $encounterCount; $i++) {
    # Select random encounter type (could be weighted by character preferences later)
    $encounterType = $encounterTypes | Get-Random
    
    Write-Host "Encounter $i`: Generating $encounterType variations..."
    
    # Generate variations
    $aiResponse = Generate-EncounterVariations -Schema $schema -Characters $characters -EncounterType $encounterType -EncounterNumber $i
    
    if ($aiResponse) {
        $variations = Parse-EncounterVariations -AiResponse $aiResponse
        
        $encounterData = @{
            encounter_number = $i
            encounter_type = $encounterType
            variations = $variations
            raw_ai_response = $aiResponse
            generated_at = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        
        $allEncounters += $encounterData
        
        Write-Host "  Generated $($variations.Count) variations"
    } else {
        Write-Host "  Failed to generate variations for encounter $i"
    }
    
    # Small delay to avoid overwhelming the API
    Start-Sleep -Milliseconds 1000
}

# Save all encounter variations
$outputFile = "$OutputPath\encounter_variations_$timestamp.json"
$allEncounters | ConvertTo-Json -Depth 6 | Out-File -FilePath $outputFile -Encoding UTF8

# Also save as latest for pipeline
$latestFile = "$OutputPath\latest_variations.json"
$allEncounters | ConvertTo-Json -Depth 6 | Out-File -FilePath $latestFile -Encoding UTF8

# Display summary
Write-Host "`nEncounter Generation Complete!"
Write-Host "================================"
Write-Host "Generated $($allEncounters.Count) encounters"
foreach ($encounter in $allEncounters) {
    Write-Host "Encounter $($encounter.encounter_number): $($encounter.encounter_type) ($($encounter.variations.Count) variations)"
}

Write-Host "`nFiles saved:"
Write-Host "- Timestamped: $outputFile"
Write-Host "- Latest: $latestFile"
Write-Host "`nReady for encounter selection phase!"

return @{
    encounters = $allEncounters
    timestamp = $timestamp
    total_variations = ($allEncounters | ForEach-Object { $_.variations.Count } | Measure-Object -Sum).Sum
}
