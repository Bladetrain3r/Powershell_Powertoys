# Adventure Resolution Engine - Stage 3 (DEBUG VERSION)
# Rolls dice, applies stats/bonuses, determines outcomes

param(
    [string]$AdventurePath = ".\outputs\encounters\latest_adventure.json",
    [string]$SchemaPath = ".\outputs\schema.json",
    [string]$OutputPath = ".\outputs\adventures",
    [switch]$AutoRoll = $true  # If false, prompts for manual rolls
)

Write-Host "=== DEBUG MODE ENABLED ==="
Write-Host "Script Parameters:"
Write-Host "- AdventurePath: $AdventurePath"
Write-Host "- SchemaPath: $SchemaPath"
Write-Host "- AutoRoll: $AutoRoll"
Write-Host ""

# Ensure output directory exists
if (!(Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force
    Write-Host "DEBUG: Created output directory: $OutputPath"
}

# Load data files
function Load-JsonFile {
    param([string]$FilePath)
    
    Write-Host "DEBUG: Loading file: $FilePath"
    
    if (!(Test-Path $FilePath)) {
        Write-Host "DEBUG: File not found: $FilePath"
        return $null
    }
    
    try {
        $content = Get-Content $FilePath -Raw -Encoding UTF8
        $result = $content | ConvertFrom-Json
        Write-Host "DEBUG: Successfully loaded $FilePath"
        return $result
    } catch {
        Write-Host "DEBUG: Error parsing JSON file: $($_.Exception.Message)"
        return $null
    }
}

# Roll a d20
function Roll-D20 {
    return Get-Random -Minimum 1 -Maximum 21
}

# Get equipment bonus for a character and stat combination
function Get-EquipmentBonus {
    param($Character, $Stat, $Schema)
    
    Write-Host "DEBUG: Getting equipment bonus for $($Character.name), stat: $Stat"
    
    $bonus = 0
    $bonusItems = @()
    
    if (!$Character.equipment) {
        Write-Host "DEBUG: Character has no equipment"
        return @{ bonus = 0; items = @() }
    }
    
    Write-Host "DEBUG: Character equipment: $($Character.equipment -join ', ')"
    
    foreach ($item in $Character.equipment) {
        if ($Schema.equipment_bonuses.$item) {
            $itemBonus = $Schema.equipment_bonuses.$item
            Write-Host "DEBUG: Item $item has bonus $itemBonus"
            
            # Apply specific bonuses based on stat/encounter type - use generic approach
            $statLower = $Stat.ToLower()
            
            # Generic equipment bonus application
            if ($Schema.equipment_bonuses.$item) {
                $bonus += $itemBonus
                $bonusItems += $item
                Write-Host "DEBUG: Applied bonus $itemBonus from $item for stat $Stat"
            }
        } else {
            Write-Host "DEBUG: No bonus defined for item: $item"
        }
    }
    
    Write-Host "DEBUG: Total equipment bonus: $bonus from items: $($bonusItems -join ', ')"
    
    return @{
        bonus = $bonus
        items = $bonusItems
    }
}

# Resolve a single encounter with multiple party members potentially contributing
function Resolve-Encounter {
    param($Encounter, $Party, $Schema)
    
    Write-Host "DEBUG: ================================================"
    Write-Host "DEBUG: Resolving encounter: $($Encounter.title)"
    Write-Host "DEBUG: Primary character should be: $($Encounter.primary_character)"
    Write-Host "DEBUG: Primary stat: $($Encounter.primary_stat)"
    Write-Host "DEBUG: Party size: $($Party.Count)"
    
    # Debug party information
    for ($i = 0; $i -lt $Party.Count; $i++) {
        $char = $Party[$i]
        Write-Host "DEBUG: Party member $i`: Name='$($char.name)', Class='$($char.class)'"
        if ($char.stats) {
            $statNames = $char.stats.PSObject.Properties.Name
            Write-Host "DEBUG:   Stats: $($statNames -join ', ')"
            foreach ($statName in $statNames) {
                Write-Host "DEBUG:     $statName = $($char.stats.$statName)"
            }
        } else {
            Write-Host "DEBUG:   No stats found!"
        }
    }
    
    # Determine how many characters will participate (1 to all party members)
    $maxParticipants = $Party.Count
    $participantCount = Get-Random -Minimum 1 -Maximum ($maxParticipants + 1)
    
    Write-Host "DEBUG: Will use $participantCount participants out of $maxParticipants"
    
    # Always include the primary character
    $primaryCharacter = $Party | Where-Object { $_.name -eq $Encounter.primary_character }
    if (!$primaryCharacter) {
        Write-Host "DEBUG: Primary character '$($Encounter.primary_character)' not found!"
        Write-Host "DEBUG: Available characters: $(($Party | ForEach-Object { "'$($_.name)'" }) -join ', ')"
        $primaryCharacter = $Party[0]  # Fallback to first character
        Write-Host "DEBUG: Using fallback character: $($primaryCharacter.name)"
    } else {
        Write-Host "DEBUG: Found primary character: $($primaryCharacter.name)"
    }
    
    $participants = @($primaryCharacter)
    
    # Add additional participants if needed
    if ($participantCount -gt 1) {
        $otherCharacters = $Party | Where-Object { $_.name -ne $primaryCharacter.name }
        $additionalCount = [Math]::Min($participantCount - 1, $otherCharacters.Count)
        if ($additionalCount -gt 0) {
            $additional = $otherCharacters | Get-Random -Count $additionalCount
            $participants += $additional
            Write-Host "DEBUG: Added $additionalCount additional participants"
        }
    }
    
    Write-Host "DEBUG: Final participants: $(($participants | ForEach-Object { $_.name }) -join ', ')"
    
    # Roll for each participant
    $allRolls = @()
    $totalBonus = 0
    $allBonusItems = @()
    
    foreach ($character in $participants) {
        Write-Host "DEBUG: ------ Processing character: $($character.name) ------"
        
        # Get character's stat value for primary stat
        $encounterStat = $Encounter.primary_stat
        Write-Host "DEBUG: Looking for stat: '$encounterStat'"
        
        # Try exact match first
        $statValue = $character.stats.$encounterStat
        
        if (!$statValue) {
            Write-Host "DEBUG: Exact match failed, trying case-insensitive search"
            $statLower = $encounterStat.ToLower()
            
            # Try to find case-insensitive match
            foreach ($statName in $character.stats.PSObject.Properties.Name) {
                if ($statName.ToLower() -eq $statLower) {
                    $statValue = $character.stats.$statName
                    Write-Host "DEBUG: Found case-insensitive match: $statName = $statValue"
                    break
                }
            }
        } else {
            Write-Host "DEBUG: Found exact stat match: $encounterStat = $statValue"
        }
        
        if (!$statValue) {
            $statValue = 5  # Default stat value
            Write-Host "DEBUG: No stat match found, using default value 5"
            Write-Host "DEBUG: Available stats: $($character.stats.PSObject.Properties.Name -join ', ')"
        }
        
        # Calculate equipment bonus for this character
        $equipmentResult = Get-EquipmentBonus -Character $character -Stat $encounterStat -Schema $Schema
        $equipmentBonus = $equipmentResult.bonus
        $bonusItems = $equipmentResult.items
        
        # Roll the dice
        if ($AutoRoll) {
            $diceRoll = Roll-D20
        } else {
            do {
                $input = Read-Host "Roll d20 for $($character.name) (or enter number 1-20)"
                $diceRoll = $input -as [int]
            } while ($diceRoll -lt 1 -or $diceRoll -gt 20)
        }
        
        # Calculate this character's total
        $characterTotal = $diceRoll + $statValue + $equipmentBonus
        
        $rollData = [PSCustomObject]@{
            character_name = $character.name
            character_class = $character.class
            dice_roll = $diceRoll
            stat_value = $statValue
            equipment_bonus = $equipmentBonus
            bonus_items = $bonusItems
            total_roll = $characterTotal
        }
        
        $allRolls += $rollData
        $totalBonus += $equipmentBonus
        $allBonusItems += $bonusItems
        
        Write-Host "DEBUG: $($character.name): $diceRoll + $statValue ($encounterStat) + $equipmentBonus (equipment) = $characterTotal"
    }
    
    # Determine overall result method
    $resultMethod = @("best_roll", "average_roll", "combined_roll") | Get-Random
    
    Write-Host "DEBUG: Using resolution method: $resultMethod"
    
    switch ($resultMethod) {
        "best_roll" {
            $bestRoll = ($allRolls | Measure-Object -Property total_roll -Maximum).Maximum
            $finalTotal = $bestRoll
            $method = "Best individual roll"
        }
        "average_roll" {
            $avgRoll = ($allRolls | Measure-Object -Property total_roll -Average).Average
            $finalTotal = [Math]::Round($avgRoll)
            $method = "Average of all rolls"
        }
        "combined_roll" {
            # Sum all dice, take average stats/equipment, but cap it reasonably
            $totalDice = ($allRolls | Measure-Object -Property dice_roll -Sum).Sum
            $avgStat = [Math]::Round(($allRolls | Measure-Object -Property stat_value -Average).Average)
            $avgEquipment = [Math]::Round(($allRolls | Measure-Object -Property equipment_bonus -Average).Average)
            $finalTotal = [Math]::Min(35, $totalDice + $avgStat + $avgEquipment)  # Cap at 35 to prevent ridiculous results
            $method = "Combined effort"
        }
    }
    
    $difficultyClass = $Encounter.difficulty_class
    
    Write-Host "DEBUG: Resolution method: $method"
    Write-Host "DEBUG: Final total: $finalTotal vs DC $difficultyClass"
    
    # Determine success level
    $success = $false
    $successLevel = ""
    $outcome = ""
    $margin = $finalTotal - $difficultyClass
    
    # Check for natural 20s or 1s in the rolls
    $hasNat20 = ($allRolls | Where-Object { $_.dice_roll -eq 20 }).Count -gt 0
    $hasNat1 = ($allRolls | Where-Object { $_.dice_roll -eq 1 }).Count -gt 0
    
    if ($hasNat20 -and $finalTotal -ge $difficultyClass) {
        $success = $true
        $successLevel = "Critical Success"
        $outcome = $Encounter.success_outcome + " (Critical: Exceptional teamwork!)"
    } elseif ($hasNat1 -and $finalTotal -lt $difficultyClass) {
        $success = $false
        $successLevel = "Critical Failure"
        $outcome = $Encounter.failure_outcome + " (Critical: Everything went wrong!)"
    } elseif ($finalTotal -ge $difficultyClass + 10) {
        $success = $true
        $successLevel = "Outstanding Success"
        $outcome = $Encounter.success_outcome + " (Outstanding: Perfect execution!)"
    } elseif ($finalTotal -ge $difficultyClass) {
        $success = $true
        $successLevel = "Success"
        $outcome = $Encounter.success_outcome
    } elseif ($finalTotal -ge $difficultyClass - 3) {
        $success = $false
        $successLevel = "Partial Success"
        $outcome = "Mixed result: " + $Encounter.success_outcome + " but with complications."
    } else {
        $success = $false
        $successLevel = "Failure"
        $outcome = $Encounter.failure_outcome
    }
    
    Write-Host "DEBUG: Success level: $successLevel"
    
    # Create resolution record
    $resolution = @{
        encounter_number = $Encounter.encounter_number
        encounter_type = $Encounter.encounter_type
        title = $Encounter.title
        participants = $participants.Count
        participant_names = ($participants | ForEach-Object { $_.name })
        resolution_method = $resultMethod
        resolution_description = $method
        individual_rolls = $allRolls
        final_total = $finalTotal
        difficulty_class = $difficultyClass
        success = $success
        success_level = $successLevel
        outcome = $outcome
        margin = $margin
        primary_character = $primaryCharacter.name
        stat_used = $Encounter.primary_stat
    }
    
    return $resolution
}

# Main execution
Write-Host "DEBUG: Starting main execution..."

$adventure = Load-JsonFile -FilePath $AdventurePath
$schema = Load-JsonFile -FilePath $SchemaPath

Write-Host "DEBUG: File loading results:"
Write-Host "- Adventure: $(if($adventure){'Loaded'}else{'Failed'})"
Write-Host "- Schema: $(if($schema){'Loaded'}else{'Failed'})"

if (!$adventure -or !$schema) {
    Write-Host "DEBUG: Failed to load required data files, exiting"
    exit
}

Write-Host "DEBUG: Adventure structure:"
Write-Host "- Title: $($adventure.title)"
Write-Host "- Total encounters: $($adventure.total_encounters)"

# Debug party data structure
Write-Host "DEBUG: Party data structure analysis:"
Write-Host "- Party type: $($adventure.party.GetType().Name)"

if ($adventure.party -is [Array]) {
    Write-Host "- Party is array with $($adventure.party.Count) members"
} elseif ($adventure.party.value) {
    Write-Host "- Party has 'value' property with $($adventure.party.value.Count) members"
    Write-Host "- Value type: $($adventure.party.value.GetType().Name)"
} elseif ($adventure.party.Count) {
    Write-Host "- Party object has Count property: $($adventure.party.Count)"
} else {
    Write-Host "- Party structure unknown"
}

# Fix party data structure if needed
$party = $adventure.party

# DON'T use .value if party is already an array!
if ($party -is [Array]) {
    Write-Host "DEBUG: Party is already an array, using directly"
} elseif ($party.value) {
    Write-Host "DEBUG: Using party.value structure"
    $party = $party.value
} elseif (!($party -is [Array])) {
    Write-Host "DEBUG: Party is not an array, trying to convert"
    if ($party.PSObject.Properties.Count -gt 0) {
        $party = @($party)
    }
}

Write-Host "DEBUG: Final party setup:"
Write-Host "- Party count: $($party.Count)"
Write-Host "- Party type: $($party.GetType().Name)"

# Debug individual characters more safely
for ($i = 0; $i -lt $party.Count; $i++) {
    $char = $party[$i]
    Write-Host "DEBUG: Character $i details:"
    
    if ($char -eq $null) {
        Write-Host "  - Character is NULL!"
        continue
    }
    
    Write-Host "  - Object type: $($char.GetType().Name)"
    Write-Host "  - Name property exists: $(if($char.PSObject.Properties['name']){'Yes'}else{'No'})"
    Write-Host "  - Name value: '$($char.name)'"
    Write-Host "  - Class: '$($char.class)'"
    Write-Host "  - Level: '$($char.level)'"
    if ($char.stats) {
        Write-Host "  - Stats available: $($char.stats.PSObject.Properties.Name -join ', ')"
    } else {
        Write-Host "  - No stats found"
    }
}

# Try different ways to get names
$nameMethod1 = ($party | ForEach-Object { $_.name }) -join ', '
$nameMethod2 = ($party | Select-Object -ExpandProperty name) -join ', '

Write-Host "DEBUG: Name extraction methods:"
Write-Host "- Method 1 (ForEach-Object): '$nameMethod1'"
Write-Host "- Method 2 (Select-Object): '$nameMethod2'"

$resolutions = @()
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

foreach ($encounter in $adventure.encounters) {
    Write-Host "=== Encounter $($encounter.encounter_number): $($encounter.title) ==="
    Write-Host "Type: $($encounter.encounter_type)"
    Write-Host "Challenge: $($encounter.challenge)"
    Write-Host "DC: $($encounter.difficulty_class)"
    Write-Host ""
    
    $resolution = Resolve-Encounter -Encounter $encounter -Party $party -Schema $schema
    $resolutions += $resolution
    
    # Display result
    Write-Host "Resolution: $($resolution.resolution_description)"
    Write-Host "Participants: $(($resolution.participant_names) -join ', ')"
    Write-Host "Final Total: $($resolution.final_total) vs DC $($resolution.difficulty_class)"
    Write-Host "Result: $($resolution.success_level) (Margin: $($resolution.margin))"
    Write-Host "Outcome: $($resolution.outcome)"
    Write-Host ""
}

Write-Host "DEBUG: Adventure resolution complete!"
Write-Host "DEBUG: Generated $($resolutions.Count) resolutions"