# RPG Adventure Generator

A multi-stage AI pipeline for generating complete RPG adventures with character creation, encounter design, resolution mechanics, and narrative output.

## Overview

This system creates procedural RPG adventures using a 4-stage AI pipeline that produces cohesive stories with dice mechanics, character interactions, and narrative flow. The generator is schema-driven, allowing different genres (fantasy, sword & sorcery, corporate thriller, sci-fi) through configuration files.

## Architecture

```
Schema Definition → Character Generation → Adventure Planning → Encounter Generation → Encounter Selection → Adventure Resolution → Narrative Generation
```

### Core Components

1. **Schema System** - JSON-based configuration defining stats, encounters, equipment, AI models
2. **Character Generator** - Creates balanced party members with backgrounds and equipment
3. **Adventure Planner** - Establishes theme, setting, and story arc for consistency
4. **Encounter Pipeline** - Multi-stage AI system for creating and selecting encounters
5. **Resolution Engine** - Dice rolling, stat application, multi-character teamwork
6. **Narrative Generator** - Converts mechanical results into prose stories

## File Structure

```
.\outputs\
├── schemas/
│   ├── schema.json              # Classic fantasy
│   ├── sword_sorcery_schema.json # Gritty action
│   ├── corporate_schema.json     # Business thriller
│   └── starship_schema.json      # Space opera
├── characters/
│   ├── latest_characters.json   # Current party
│   └── characters_[timestamp].json
├── adventures/
│   ├── latest_plan.json         # Current adventure plan
│   └── adventure_plan_[timestamp].json
├── encounters/
│   ├── latest_variations.json   # AI-generated options
│   ├── latest_adventure.json    # Selected encounters
│   └── encounter_variations_[timestamp].json
├── adventures/
│   ├── latest_completed.json    # Resolved adventure
│   └── completed_adventure_[timestamp].json
└── stories/
    ├── latest_story.md          # Final narrative
    ├── encounter_1_[timestamp].md # Individual scenes
    └── adventure_story_[timestamp].md
```

## Scripts

### Core Pipeline Scripts

| Script | Purpose | Input | Output |
|--------|---------|-------|--------|
| `Character_Gen.ps1` | Create party | Schema | Character JSON |
| `Basic_World.ps1` | Plan story arc | Schema + Characters | Adventure plan |
| `Draft_Phase_1.ps1` | Generate variations | Plan + Characters | Encounter options |
| `Encounter_Selector.ps1` | Select best options | Variations + Schema | Structured encounters |
| `Resolution_Generator.ps1` | Roll dice & resolve | Encounters + Schema | Adventure results |
| `Story_Generator.ps1` | Create story | Results | Markdown story |

### Utility Scripts

| Script | Purpose |
|--------|---------|
| `encounter_selector_debug.ps1` | Debug encounter selection issues |
| `resolution_debug.ps1` | Debug dice rolling and character stats |

## Schema Configuration

Each schema defines a complete game system:

### Required Sections

```json
{
  "game_rules": {
    "stat_range": [3, 12],
    "encounter_count": 6,
    "variation_count": 5,
    "dice_type": "d20"
  },
  "ai_settings": {
    "variation_model": "gemma-3-1b-it-qat",
    "selection_model": "gemma-3-4b-it-qat", 
    "narrative_model": "gemma-3-4b-it-qat",
    "variation_tokens": 1000,
    "selection_tokens": 600,
    "narrative_tokens": 1500,
    "variation_temperature": 0.8,
    "selection_temperature": 0.3,
    "narrative_temperature": 0.7
  },
  "character_classes": {
    "warrior": {
      "name": "Warrior",
      "base_stats": { "strength": 8, "agility": 5 },
      "preferred_encounters": ["combat"]
    }
  },
  "encounter_types": {
    "combat": {
      "name": "Combat Encounter",
      "primary_stat": "strength",
      "difficulty_range": [12, 18],
      "success_outcomes": ["victory"],
      "failure_outcomes": ["defeat"]
    }
  },
  "equipment_bonuses": {
    "weapon": 2,
    "armor": 1
  },
  "available_equipment": ["weapon", "armor"],
  "character_names": {
    "first_names": ["Hero", "Champion"],
    "last_names": ["Brave", "Bold"]
  },
  "character_backgrounds": [
    "A noble seeking adventure"
  ],
  "story_themes": ["heroic_quest"],
  "environments": ["castle", "dungeon"]
}
```

### AI Model Configuration

The `ai_settings` section allows different models and parameters per genre:

- **variation_model**: Creative encounter brainstorming (faster models)
- **selection_model**: Analytical decision-making (mid-range models)  
- **narrative_model**: Prose generation (larger/specialized models)

## Usage Workflows

### Complete Adventure Generation

```powershell
# 1. Generate characters
.\Character_Gen.ps1 -SchemaPath ".\outputs\schema.json"

# 2. Plan adventure arc
.\Basic_World.ps1 -SchemaPath ".\outputs\schema.json"

# 3. Generate encounter variations
.\Draft_Phase_1.ps1 -SchemaPath ".\outputs\schema.json"

# 4. Select best encounters
.\Encounter_Selector.ps1 -SchemaPath ".\outputs\schema.json"

# 5. Resolve with dice rolls
.\Resolution_Generator.ps1 -SchemaPath ".\outputs\schema.json"

# 6. Generate narrative
.\Story_Generator.ps1
```

### Genre-Specific Adventures

```powershell
# Sword & Sorcery (gritty action)
.\Character_Gen.ps1 -SchemaPath ".\outputs\sword_sorcery_schema.json"

# Corporate Thriller (business setting)
.\Character_Gen.ps1 -SchemaPath ".\outputs\corporate_schema.json"

# Starship Crew (space opera)
.\Character_Gen.ps1 -SchemaPath ".\outputs\starship_schema.json"
```

## Key Features

### Multi-Character Resolution
- Random number of participants per encounter (1 to full party)
- Three resolution methods: best roll, average roll, combined effort
- Equipment bonuses applied contextually
- Natural 20/1 handling for critical results

### Adventure Consistency  
- Pre-planning phase establishes theme and setting
- All encounters reference central conflict and environments
- Story progression (opening → middle → climax)
- Character backgrounds influence adventure themes

### Modular Narrative Generation
- Individual encounter stories (300-500 words each)
- Transition text between encounters  
- Combined final story with technical appendix
- Separate files for easy editing and reuse

### Schema-Driven Flexibility
- Different stat systems per genre
- Genre-appropriate equipment and bonuses
- Encounter types matched to setting
- AI model selection optimized per genre

## Technical Notes

### PowerShell Compatibility
- Built for PowerShell 5.1 (Windows PowerShell)
- Avoids PowerShell 6+ cmdlets like `Join-String`
- Uses `-join` operator for string concatenation

### AI API Requirements
- Local LMStudio server on `localhost:1234`
- OpenAI-compatible API endpoints
- Multiple model support for different pipeline stages

### File Dependencies
- Each stage depends on output from previous stage
- "latest_*.json" files for pipeline continuity
- Timestamped files for historical tracking

## Troubleshooting

### Common Issues

**Empty character names in resolution:**
- Party data structure mismatch
- Use debug scripts to trace data flow

**Stat name mismatches:**
- Schema stats vs encounter requirements
- Case sensitivity issues between stages

**JSON parsing failures:**
- AI model not outputting valid JSON
- Use debug versions to see raw responses

**Missing equipment bonuses:**
- Equipment names not matching schema definitions
- Check `available_equipment` vs `equipment_bonuses`

### Debug Scripts

Use debug versions when issues occur:
```powershell
.\encounter_selector_debug.ps1  # Shows AI responses and JSON parsing
.\resolution_debug.ps1          # Shows character data and stat matching
```

## Extension Points

### Adding New Genres
1. Create new schema JSON with appropriate stats/encounters
2. Define character classes for the setting
3. Configure AI models optimized for the genre
4. Add genre-specific equipment and themes

### Custom Resolution Methods
- Modify `Resolve-Encounter` function
- Add new success level calculations
- Implement genre-specific mechanics

### Enhanced AI Integration
- Add more sophisticated model routing
- Implement multi-turn conversations for complex encounters
- Add vision models for character/scene generation

## Output Examples

### Character Generation
```json
{
  "name": "Aria Stormwind", 
  "class": "mage",
  "level": 3,
  "stats": {"strength": 4, "intellect": 10},
  "equipment": ["spellbook", "robes"],
  "background": "Scholar seeking forbidden knowledge"
}
```

### Adventure Plan
```
Title: The Shadow of Eldermere
Theme: Ancient corruption threatens the realm
Environments: Cursed forest, underground ruins, corrupted temple
Central Conflict: Ancient evil artifact corrupting the land
```

### Final Output
- Complete adventure story (1000+ words)
- Individual encounter narratives  
- Technical dice roll details
- Modular markdown files for reuse

## Future Enhancements

- **Visual character generation** using image AI
- **Voice narration** of final stories
- **Interactive decision trees** for player choice
- **Campaign continuity** across multiple adventures
- **Integration with VTT platforms** for actual play

---

*Generated adventure stories can be used for inspiration, actual tabletop play, or as writing prompts for longer narratives.*