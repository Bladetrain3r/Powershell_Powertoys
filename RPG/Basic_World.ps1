# Adventure Planning - Pre-Phase
# Generates overall adventure arc, theme, and setting for consistency

param(
    [string]$SchemaPath = ".\outputs\schema.json",
    [string]$CharactersPath = ".\outputs\characters\latest_characters.json",
    [string]$OutputPath = ".\outputs\adventures",
    [string]$PlanningModel = "gemma-3-4b-it-qat"  # Default model for planning
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

function Get-AISetting {
    param(
        $Schema,
        [string]$SettingName,
        $DefaultValue
    )
    
    if ($Schema.ai_settings -and $Schema.ai_settings.PSObject.Properties[$SettingName]) {
        return $Schema.ai_settings.$SettingName
    }
    return $DefaultValue
}

# Generate adventure plan using AI
function Generate-AdventurePlan {
    param($Schema, $Characters, $ModelToUse)
    
    # Build character summary
    $partySummary = ""
    $partyThemes = @()
    foreach ($char in $Characters) {
        $partySummary += "$($char.name) - Level $($char.level) $($char.class) ($($char.background)). "
        
        # Extract thematic elements from backgrounds
        if ($char.background -match "seeking redemption|former soldier|ex-") {
            $partyThemes += "redemption"
        }
        if ($char.background -match "noble|trust fund|wealthy") {
            $partyThemes += "nobility"
        }
        if ($char.background -match "orphan|street|humble") {
            $partyThemes += "underdog"
        }
        if ($char.background -match "scholar|knowledge|research") {
            $partyThemes += "knowledge"
        }
        if ($char.background -match "escaped|exiled|refugee") {
            $partyThemes += "exile"
        }
    }
    
    # Get available themes and environments from schema
    $availableThemes = if ($Schema.story_themes) { $Schema.story_themes -join ", " } else { "ancient mysteries, political intrigue, treasure hunting" }
    $availableEnvironments = if ($Schema.environments) { $Schema.environments -join ", " } else { "dungeons, cities, wilderness" }
    $encounterTypes = ($Schema.encounter_types.PSObject.Properties.Name) -join ", "
    $totalEncounters = Get-AISetting -Schema $Schema -SettingName "encounter_count" -DefaultValue $Schema.game_rules.encounter_count
    
    $prompt = @"
You are planning a cohesive adventure for a fantasy RPG party. Create an overarching story structure that will guide $totalEncounters encounters.

PARTY COMPOSITION:
$partySummary

PARTY THEMES: $(if($partyThemes.Count -gt 0){($partyThemes | Select-Object -Unique) -join ', '}else{'Various backgrounds'})

AVAILABLE STORY THEMES: $availableThemes
AVAILABLE ENVIRONMENTS: $availableEnvironments  
ENCOUNTER TYPES: $encounterTypes

Your task:
1. Choose ONE primary theme that fits the party
2. Select 2-3 environments that connect logically
3. Create a story arc with clear progression
4. Define the central conflict/goal
5. Provide encounter guidance for consistency

Output EXACTLY this structure:

TITLE: [Adventure title]
THEME: [Primary theme from available options]
ENVIRONMENTS: [2-3 environments that connect]
CENTRAL_CONFLICT: [What drives the adventure]
GOAL: [What the party is trying to achieve]
ANTAGONIST: [Main opposing force]
PROGRESSION: [How the adventure escalates - beginning, middle, climax]
ENCOUNTER_GUIDANCE: [2-3 sentences on how encounters should connect to theme and progress the story]
SETTING_DETAILS: [Key locations, atmosphere, recurring elements that should appear across encounters]
"@

    try {
        $body = @{
            model = $ModelToUse
            messages = @(
                @{
                    role = "user"
                    content = $prompt
                }
            )
            max_tokens = Get-AISetting -Schema $Schema -SettingName "narrative_tokens" -DefaultValue 800
            temperature = Get-AISetting -Schema $Schema -SettingName "narrative_temperature" -DefaultValue 0.6
        } | ConvertTo-Json -Depth 5
        
        $headers = @{
            'Content-Type' = 'application/json; charset=utf-8'
        }
        
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/chat/completions" -Method POST -Body $bodyBytes -Headers $headers
        $responseData = $response.Content | ConvertFrom-Json
        $aiResponse = $responseData.choices[0].message.content
        
        Write-Host "Generated adventure plan"
        return $aiResponse
        
    } catch {
        Write-Host "Error generating adventure plan: $($_.Exception.Message)"
        return $null
    }
}

# Parse adventure plan into structured data
function Parse-AdventurePlan {
    param([string]$AiResponse)
    
    $plan = @{
        title = "Generated Adventure"
        theme = "adventure"
        environments = @()
        central_conflict = "Unknown conflict"
        goal = "Complete the quest"
        antagonist = "Unknown enemy"
        progression = "Standard adventure progression"
        encounter_guidance = "Create varied encounters"
        setting_details = "Fantasy adventure setting"
        raw_response = $AiResponse
    }
    
    # Extract structured data using regex
    if ($AiResponse -match "TITLE:\s*(.+?)(?=\n|\r|$)") {
        $plan.title = $matches[1].Trim()
    }
    
    if ($AiResponse -match "THEME:\s*(.+?)(?=\n|\r|$)") {
        $plan.theme = $matches[1].Trim()
    }
    
    if ($AiResponse -match "ENVIRONMENTS:\s*(.+?)(?=\n|\r|$)") {
        $envString = $matches[1].Trim()
        $plan.environments = $envString -split ',' | ForEach-Object { $_.Trim() }
    }
    
    if ($AiResponse -match "CENTRAL_CONFLICT:\s*(.+?)(?=\n|\r|$)") {
        $plan.central_conflict = $matches[1].Trim()
    }
    
    if ($AiResponse -match "GOAL:\s*(.+?)(?=\n|\r|$)") {
        $plan.goal = $matches[1].Trim()
    }
    
    if ($AiResponse -match "ANTAGONIST:\s*(.+?)(?=\n|\r|$)") {
        $plan.antagonist = $matches[1].Trim()
    }
    
    if ($AiResponse -match "PROGRESSION:\s*(.+?)(?=ENCOUNTER_GUIDANCE|$)") {
        $plan.progression = $matches[1].Trim()
    }
    
    if ($AiResponse -match "ENCOUNTER_GUIDANCE:\s*(.+?)(?=SETTING_DETAILS|$)") {
        $plan.encounter_guidance = $matches[1].Trim()
    }
    
    if ($AiResponse -match "SETTING_DETAILS:\s*(.+?)$") {
        $plan.setting_details = $matches[1].Trim()
    }
    
    return $plan
}

# Main execution
Write-Host "Loading game data for adventure planning..."

$schema = Load-JsonFile -FilePath $SchemaPath
$characters = Load-JsonFile -FilePath $CharactersPath

if (!$schema -or !$characters) {
    Write-Host "Failed to load required data files"
    exit
}

# Get planning model from schema
$modelToUse = Get-AISetting -Schema $schema -SettingName "selection_model" -DefaultValue $PlanningModel

Write-Host "Planning adventure structure..."
Write-Host "Using model: $modelToUse"

# Generate adventure plan
$aiResponse = Generate-AdventurePlan -Schema $schema -Characters $characters -ModelToUse $modelToUse

if (!$aiResponse) {
    Write-Host "Failed to generate adventure plan"
    exit
}

# Parse the plan
$adventurePlan = Parse-AdventurePlan -AiResponse $aiResponse

# Add metadata
$adventurePlan.generated_at = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$adventurePlan.party = $characters
$adventurePlan.encounter_count = Get-AISetting -Schema $schema -SettingName "encounter_count" -DefaultValue $schema.game_rules.encounter_count

# Save adventure plan
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = "$OutputPath\adventure_plan_$timestamp.json"
$adventurePlan | ConvertTo-Json -Depth 6 | Out-File -FilePath $outputFile -Encoding UTF8

# Also save as latest for the encounter generator
$latestFile = "$OutputPath\latest_plan.json"
$adventurePlan | ConvertTo-Json -Depth 6 | Out-File -FilePath $latestFile -Encoding UTF8

# Display summary
Write-Host "`nAdventure Planning Complete!"
Write-Host "============================="
Write-Host "Title: $($adventurePlan.title)"
Write-Host "Theme: $($adventurePlan.theme)"
Write-Host "Environments: $($adventurePlan.environments -join ', ')"
Write-Host "Central Conflict: $($adventurePlan.central_conflict)"
Write-Host "Goal: $($adventurePlan.goal)"
Write-Host "Antagonist: $($adventurePlan.antagonist)"
Write-Host ""
Write-Host "Encounter Guidance:"
Write-Host "$($adventurePlan.encounter_guidance)"
Write-Host ""
Write-Host "Setting Details:"
Write-Host "$($adventurePlan.setting_details)"
Write-Host ""
Write-Host "Files saved:"
Write-Host "- Timestamped: $outputFile"
Write-Host "- Latest: $latestFile"
Write-Host ""
Write-Host "Ready for encounter generation!"

return $adventurePlan
