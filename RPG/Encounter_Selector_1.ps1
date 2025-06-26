# Encounter Selector - Stage 2 (DEBUG VERSION)
# Uses a smarter model to select best encounter variations and output structured JSON

param(
    [string]$VariationsPath = ".\outputs\encounters\latest_variations.json",
    [string]$CharactersPath = ".\outputs\characters\latest_characters.json",
    [string]$SchemaPath = ".\outputs\schema.json",
    [string]$OutputPath = ".\outputs\encounters",
    [string]$Selection_Model = "gemma-3-1b-it-qat"  # Default model that can be overridden by schema
)

Write-Host "=== DEBUG MODE ENABLED ==="
Write-Host "Script Parameters:"
Write-Host "- VariationsPath: $VariationsPath"
Write-Host "- CharactersPath: $CharactersPath"
Write-Host "- SchemaPath: $SchemaPath"
Write-Host "- Default Model: $Selection_Model"
Write-Host ""

# Load data files
function Load-JsonFile {
    param([string]$FilePath)
    
    Write-Host "DEBUG: Attempting to load file: $FilePath"
    
    if (!(Test-Path $FilePath)) {
        Write-Host "DEBUG: File not found: $FilePath"
        return $null
    }
    
    try {
        $content = Get-Content $FilePath -Raw -Encoding UTF8
        $parsed = $content | ConvertFrom-Json
        Write-Host "DEBUG: Successfully loaded and parsed: $FilePath"
        return $parsed
    } catch {
        Write-Host "DEBUG: Error parsing JSON file: $($_.Exception.Message)"
        return $null
    }
}

function Get-AISetting {
    param(
        $Schema,
        [string]$SettingName,
        $DefaultValue
    )
    
    Write-Host "DEBUG: Getting AI setting '$SettingName' with default '$DefaultValue'"
    
    if (!$Schema) {
        Write-Host "DEBUG: Schema is null!"
        return $DefaultValue
    }
    
    if (!$Schema.ai_settings) {
        Write-Host "DEBUG: Schema has no ai_settings section"
        return $DefaultValue
    }
    
    Write-Host "DEBUG: Schema ai_settings found with properties: $($Schema.ai_settings.PSObject.Properties.Name -join ', ')"
    
    if ($Schema.ai_settings.PSObject.Properties[$SettingName]) {
        $value = $Schema.ai_settings.$SettingName
        Write-Host "DEBUG: Found setting '$SettingName' = '$value'"
        return $value
    } else {
        Write-Host "DEBUG: Setting '$SettingName' not found, using default '$DefaultValue'"
        return $DefaultValue
    }
}

# Use AI to select best encounter and format as JSON
function Select-BestEncounter {
    param(
        $EncounterData,
        $Characters,
        $Schema,
        $SelectionModel,
        $SelectionTokens,
        $SelectionTemperature
    )
    
    Write-Host "DEBUG: Starting encounter selection for encounter $($EncounterData.encounter_number)"
    
    $encounterNumber = $EncounterData.encounter_number
    $encounterType = $EncounterData.encounter_type
    $rawResponse = $EncounterData.raw_ai_response
    
    Write-Host "DEBUG: Encounter type: $encounterType"
    Write-Host "DEBUG: Raw response length: $($rawResponse.Length) characters"
    
    # Build character summary for context
    $partySummary = ""
    foreach ($char in $Characters) {
        $partySummary += "$($char.name) (Level $($char.level) $($char.class)): "
        $statList = ""
        foreach ($statName in $char.stats.PSObject.Properties.Name) {
            $statList += "$($statName.ToUpper()):$($char.stats.$statName) "
        }
        $partySummary += "$statList, Equipment: $($char.equipment -join ', '). "
    }
    
    Write-Host "DEBUG: Party summary length: $($partySummary.Length) characters"
    
    # Get valid stat names from schema
    $validStats = @()
    if ($Schema.character_classes) {
        $firstClass = $Schema.character_classes.PSObject.Properties.Value | Select-Object -First 1
        if ($firstClass.base_stats) {
            $validStats = $firstClass.base_stats.PSObject.Properties.Name
        }
    }
    $validStatsString = $validStats -join ", "
    
    Write-Host "DEBUG: Valid stats: $validStatsString"
    
    $prompt = @"
You are selecting the best encounter variation from multiple options for an RPG adventure. 

PARTY CONTEXT:
$partySummary

ENCOUNTER TYPE: $encounterType
ENCOUNTER NUMBER: $encounterNumber

AVAILABLE VARIATIONS:
$rawResponse

Your task:
1. Select the BEST variation that is most interesting, balanced, and suited to the party
2. Extract the key details and format them properly
3. Output ONLY a valid JSON object with this exact structure (no explanatory text before or after):

{
  "encounter_number": $encounterNumber,
  "encounter_type": "$encounterType",
  "title": "Brief descriptive title",
  "scenario": "Clear 2-3 sentence description",
  "challenge": "Specific challenge to overcome",
  "difficulty_class": 12,
  "primary_character": "Character name",
  "primary_stat": "stat_name",
  "secondary_stat": "optional_stat",
  "reasoning": "Why this character was chosen",
  "success_outcome": "What happens on success",
  "failure_outcome": "What happens on failure"
}

IMPORTANT: 
- Output ONLY the JSON object, no other text
- Use only these stat names: $validStatsString
- Ensure all JSON is properly formatted with quotes around strings
- Do not include any explanatory text before or after the JSON
- Choose characters and stats that actually exist in the party data provided
"@

    Write-Host "DEBUG: Prompt length: $($prompt.Length) characters"
    Write-Host "DEBUG: Using model: $SelectionModel, tokens: $SelectionTokens, temperature: $SelectionTemperature"

    try {
        $body = @{
            model = $SelectionModel
            messages = @(
                @{
                    role = "user"
                    content = $prompt
                }
            )
            max_tokens = $SelectionTokens
            temperature = $SelectionTemperature
        } | ConvertTo-Json -Depth 5
        
        Write-Host "DEBUG: Request body length: $($body.Length) characters"
        
        $headers = @{
            'Content-Type' = 'application/json; charset=utf-8'
        }
        
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        Write-Host "DEBUG: Sending API request..."
        
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/chat/completions" -Method POST -Body $bodyBytes -Headers $headers
        Write-Host "DEBUG: API response status: $($response.StatusCode)"
        
        $responseData = $response.Content | ConvertFrom-Json
        $aiResponse = $responseData.choices[0].message.content
        
        Write-Host "DEBUG: AI response length: $($aiResponse.Length) characters"
        Write-Host "DEBUG: Raw AI Response (first 300 chars): $($aiResponse.Substring(0, [Math]::Min(300, $aiResponse.Length)))..."
        
        # Try multiple extraction methods
        $jsonString = $null
        
        # Method 1: Look for complete JSON block
        if ($aiResponse -match '(?s)\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}') {
            $jsonString = $matches[0]
            Write-Host "DEBUG: JSON extraction method 1 succeeded"
        }
        # Method 2: Extract everything between first { and last }
        elseif ($aiResponse -match '\{.*\}') {
            $jsonString = $matches[0]
            Write-Host "DEBUG: JSON extraction method 2 succeeded"
        }
        # Method 3: Try to find JSON-like structure line by line
        else {
            Write-Host "DEBUG: Trying method 3 - line by line extraction"
            $lines = $aiResponse -split "`n"
            $jsonLines = @()
            $inJson = $false
            foreach ($line in $lines) {
                if ($line -match '^\s*\{') { 
                    $inJson = $true 
                    Write-Host "DEBUG: Found JSON start at line: $line"
                }
                if ($inJson) { $jsonLines += $line }
                if ($line -match '^\s*\}') { 
                    Write-Host "DEBUG: Found JSON end at line: $line"
                    break 
                }
            }
            if ($jsonLines.Count -gt 0) {
                $jsonString = $jsonLines -join "`n"
                Write-Host "DEBUG: JSON extraction method 3 succeeded with $($jsonLines.Count) lines"
            }
        }
        
        if ($jsonString) {
            Write-Host "DEBUG: Extracted JSON length: $($jsonString.Length) characters"
            Write-Host "DEBUG: Extracted JSON: $($jsonString.Substring(0, [Math]::Min(200, $jsonString.Length)))..."
            
            try {
                # Clean up common issues
                $originalLength = $jsonString.Length
                $jsonString = $jsonString -replace '[\x00-\x1F]', ''  # Remove control chars
                $jsonString = $jsonString -replace ',(\s*[}\]])', '$1'  # Remove trailing commas
                
                if ($jsonString.Length -ne $originalLength) {
                    Write-Host "DEBUG: JSON cleaned, length changed from $originalLength to $($jsonString.Length)"
                }
                
                Write-Host "DEBUG: Attempting to parse cleaned JSON..."
                $selectedEncounter = $jsonString | ConvertFrom-Json
                Write-Host "DEBUG: JSON parsing successful!"
                Write-Host "DEBUG: Encounter title: $($selectedEncounter.title)"
                return $selectedEncounter
            } catch {
                Write-Host "DEBUG: JSON parse error: $($_.Exception.Message)"
                Write-Host "DEBUG: Problematic JSON: $jsonString"
                
                # Fallback: create a basic structure manually
                Write-Host "DEBUG: Creating fallback encounter structure"
                $fallback = @{
                    encounter_number = $encounterNumber
                    encounter_type = $encounterType
                    title = "Encounter $encounterNumber"
                    scenario = "AI generated encounter (parsing failed)"
                    challenge = "Overcome the obstacle"
                    difficulty_class = 12
                    primary_character = $Characters[0].name
                    primary_stat = if ($validStats.Count -gt 0) { $validStats[0] } else { "command" }
                    reasoning = "Default assignment due to parsing failure"
                    success_outcome = "Progress continues"
                    failure_outcome = "Setback occurs"
                }
                Write-Host "DEBUG: Fallback encounter created with primary stat: $($fallback.primary_stat)"
                return $fallback
            }
        } else {
            Write-Host "DEBUG: No JSON structure found in AI response"
            Write-Host "DEBUG: Full response: $aiResponse"
            return $null
        }
        
    } catch {
        Write-Host "DEBUG: Exception in Select-BestEncounter: $($_.Exception.Message)"
        Write-Host "DEBUG: Exception type: $($_.Exception.GetType().Name)"
        return $null
    }
}

# Main execution
Write-Host "DEBUG: Starting main execution..."

$variations = Load-JsonFile -FilePath $VariationsPath
$characters = Load-JsonFile -FilePath $CharactersPath
$schema = Load-JsonFile -FilePath $SchemaPath

Write-Host "DEBUG: File loading results:"
Write-Host "- Variations: $(if($variations){'Loaded'}else{'Failed'})"
Write-Host "- Characters: $(if($characters){'Loaded'}else{'Failed'})"
Write-Host "- Schema: $(if($schema){'Loaded'}else{'Failed'})"

if (!$variations -or !$characters -or !$schema) {
    Write-Host "DEBUG: Failed to load required data files, exiting"
    exit
}

# Get AI settings from schema after it's loaded
Write-Host "DEBUG: Extracting AI settings from schema..."
$SelectionModel = Get-AISetting -Schema $schema -SettingName "selection_model" -DefaultValue $Selection_Model
$selectionTokens = Get-AISetting -Schema $schema -SettingName "selection_tokens" -DefaultValue 600
$selectionTemperature = Get-AISetting -Schema $schema -SettingName "selection_temperature" -DefaultValue 0.3

Write-Host "DEBUG: Final AI settings:"
Write-Host "- Model: $SelectionModel"
Write-Host "- Tokens: $selectionTokens"
Write-Host "- Temperature: $selectionTemperature"

Write-Host "DEBUG: Processing $($variations.Count) encounters for selection..."

$selectedEncounters = @()
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

foreach ($encounterData in $variations) {
    Write-Host "DEBUG: ================================================"
    Write-Host "DEBUG: Processing encounter $($encounterData.encounter_number) of $($variations.Count)"
    
    $selected = Select-BestEncounter -EncounterData $encounterData -Characters $characters -Schema $schema -SelectionModel $SelectionModel -SelectionTokens $selectionTokens -SelectionTemperature $selectionTemperature
    
    if ($selected) {
        Write-Host "DEBUG: Successfully selected encounter: $($selected.title)"
        $selectedEncounters += $selected
    } else {
        Write-Host "DEBUG: Failed to select encounter $($encounterData.encounter_number)"
    }
    
    # Small delay to avoid overwhelming the API
    Write-Host "DEBUG: Waiting 1 second before next request..."
    Start-Sleep -Milliseconds 1000
}

Write-Host "DEBUG: ================================================"
Write-Host "DEBUG: Selection phase complete. Selected $($selectedEncounters.Count) encounters"

# Create final adventure structure
$adventure = @{
    title = "Generated Adventure"
    party = $characters
    encounters = $selectedEncounters
    generated_at = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    total_encounters = $selectedEncounters.Count
}

# Save selected encounters
$outputFile = "$OutputPath\selected_encounters_$timestamp.json"
$adventure | ConvertTo-Json -Depth 6 | Out-File -FilePath $outputFile -Encoding UTF8

# Also save as latest for next stage
$latestFile = "$OutputPath\latest_adventure.json"
$adventure | ConvertTo-Json -Depth 6 | Out-File -FilePath $latestFile -Encoding UTF8

Write-Host "DEBUG: Files saved successfully"

# Display summary
Write-Host "`nEncounter Selection Complete!"
Write-Host "============================"
Write-Host "Selected $($selectedEncounters.Count) encounters for the adventure"
Write-Host ""

foreach ($encounter in $selectedEncounters) {
    Write-Host "Encounter $($encounter.encounter_number): $($encounter.title)"
    Write-Host "  Type: $($encounter.encounter_type)"
    Write-Host "  Challenge: $($encounter.challenge)"
    Write-Host "  DC: $($encounter.difficulty_class) ($($encounter.primary_character) - $($encounter.primary_stat))"
    Write-Host ""
}

Write-Host "Files saved:"
Write-Host "- Timestamped: $outputFile"
Write-Host "- Latest: $latestFile"
Write-Host ""
Write-Host "Ready for adventure resolution!"

return @{
    adventure = $adventure
    timestamp = $timestamp
    selected_count = $selectedEncounters.Count
}
