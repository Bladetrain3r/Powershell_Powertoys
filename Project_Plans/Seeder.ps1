# Project Seed Generator - Interactive questionnaire to create project specifications
param(
    [string]$OutputDirectory = "outputs",
    [switch]$SkipAudio,
    [switch]$QuickMode  # Skip optional questions
)

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$projectName = ""

# Ensure output directory exists
if (!(Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

Write-Host "PROJECT SEED GENERATOR - Let's turn your idea into a specification!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

# Store all answers
$answers = @{}

# Function to ask questions with validation
function Ask-Question {
    param(
        [string]$Question,
        [string[]]$Options = @(),
        [string]$Default = "",
        [switch]$AllowMultiple,
        [switch]$Required,
        [scriptblock]$Validator
    )
    
    Write-Host ""
    Write-Host $Question -ForegroundColor Cyan
    
    if ($Options.Count -gt 0) {
        Write-Host "Options:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $Options.Count; $i++) {
            Write-Host "  [$($i+1)] $($Options[$i])"
        }
        if ($AllowMultiple) {
            Write-Host "  (Enter multiple numbers separated by commas)" -ForegroundColor Gray
        }
    }
    
    if ($Default) {
        Write-Host "Default: $Default" -ForegroundColor Gray
    }
    
    while ($true) {
        $answer = Read-Host ">"
        
        if ([string]::IsNullOrWhiteSpace($answer) -and $Default) {
            return $Default
        }
        
        if ([string]::IsNullOrWhiteSpace($answer) -and $Required) {
            Write-Host "This question is required!" -ForegroundColor Red
            continue
        }
        
        if ($Options.Count -gt 0) {
            if ($AllowMultiple) {
                $selections = $answer -split ',' | ForEach-Object { $_.Trim() }
                $valid = $true
                $results = @()
                
                foreach ($sel in $selections) {
                    if ($sel -match '^\d+$') {
                        $num = [int]$sel
                        if ($num -ge 1 -and $num -le $Options.Count) {
                            $results += $Options[$num - 1]
                        } else {
                            $valid = $false
                            break
                        }
                    } else {
                        $valid = $false
                        break
                    }
                }
                
                if ($valid) {
                    return $results -join ", "
                } else {
                    Write-Host "Invalid selection! Please enter numbers between 1 and $($Options.Count)" -ForegroundColor Red
                    continue
                }
            } else {
                if ($answer -match '^\d+$') {
                    $num = [int]$answer
                    if ($num -ge 1 -and $num -le $Options.Count) {
                        return $Options[$num - 1]
                    }
                }
                Write-Host "Invalid selection! Please enter a number between 1 and $($Options.Count)" -ForegroundColor Red
                continue
            }
        }
        
        if ($Validator) {
            $validationResult = & $Validator $answer
            if ($validationResult -ne $true) {
                Write-Host $validationResult -ForegroundColor Red
                continue
            }
        }
        
        return $answer
    }
}

# CORE QUESTIONS
Write-Host "=== CORE PROJECT DEFINITION ===" -ForegroundColor Green

# Project name
$projectName = Ask-Question -Question "What's the name of your project?" -Required -Validator {
    param($ans)
    if ($ans -match '^[\w\-\s]+$') { return $true }
    return "Project name should only contain letters, numbers, spaces, hyphens, and underscores"
}
$answers['ProjectName'] = $projectName

# Project description
$answers['Description'] = Ask-Question -Question "Brief description of what this project does (one sentence):" -Required

# Scope
$answers['Scope'] = Ask-Question -Question "What's the intended scope?" -Options @(
    "Local (just for me)",
    "Private (team/organization)",
    "Public (open source/commercial)"
) -Required

# Primary output type
$answers['OutputType'] = Ask-Question -Question "What type of output does it primarily produce?" -Options @(
    "Text (reports, summaries, data)",
    "Image (graphics, visualizations, screenshots)",
    "Audio (speech, music, sounds)",
    "Video (animations, recordings)",
    "File (documents, archives, configs)",
    "System change (settings, automation)",
    "Interactive (UI, dashboard, game)",
    "API/Service (backend, server)",
    "Mixed/Multiple"
) -Required

# Input handling
$answers['InputType'] = Ask-Question -Question "What kind of inputs does it accept?" -Options @(
    "None (generates from scratch)",
    "Single file",
    "Multiple files", 
    "Directory/folder",
    "Text/clipboard",
    "Command line arguments",
    "Interactive prompts",
    "API calls",
    "System state",
    "Mixed/Multiple"
) -AllowMultiple

# Unix philosophy
$answers['UnixCompliance'] = Ask-Question -Question "How closely should it follow Unix philosophy?" -Options @(
    "Single purpose tool (do one thing well)",
    "Composable (works in pipelines)",
    "Multi-function suite",
    "Standalone application"
) -Required

# Technical stack
Write-Host ""
Write-Host "=== TECHNICAL REQUIREMENTS ===" -ForegroundColor Green

$answers['Language'] = Ask-Question -Question "Primary programming language?" -Options @(
    "PowerShell",
    "Python",
    "JavaScript/TypeScript",
    "C#/.NET",
    "Go",
    "Rust",
    "Java",
    "C/C++",
    "Ruby",
    "Other"
) -Required

$answers['Dependencies'] = Ask-Question -Question "External dependencies/APIs needed?" -Options @(
    "None (pure language)",
    "AI/ML models",
    "Database",
    "Web APIs",
    "System APIs",
    "UI framework",
    "Media libraries",
    "Cloud services"
) -AllowMultiple

# Platform
$answers['Platform'] = Ask-Question -Question "Target platform(s)?" -Options @(
    "Windows",
    "Linux",
    "macOS",
    "Cross-platform",
    "Web browser",
    "Mobile",
    "Cloud/Server"
) -AllowMultiple

# FEATURES & BEHAVIOR
Write-Host ""
Write-Host "=== FEATURES & BEHAVIOR ===" -ForegroundColor Green

$answers['ErrorHandling'] = Ask-Question -Question "Error handling approach?" -Options @(
    "Fail fast (exit on first error)",
    "Graceful degradation (continue with warnings)",
    "Interactive recovery (ask user)",
    "Automatic retry with backoff",
    "Comprehensive logging"
) -AllowMultiple

$answers['Performance'] = Ask-Question -Question "Performance requirements?" -Options @(
    "Speed critical (real-time)",
    "Responsive (< 1 second)",
    "Batch processing (minutes OK)",
    "Background task (hours OK)",
    "Not critical"
)

$answers['DataVolume'] = Ask-Question -Question "Expected data volume?" -Options @(
    "Small (KB - single items)",
    "Medium (MB - documents/images)",
    "Large (GB - videos/datasets)",
    "Massive (TB+ - big data)",
    "Variable/Unknown"
)

if (!$QuickMode) {
    Write-Host ""
    Write-Host "=== OPTIONAL DETAILS ===" -ForegroundColor Green
    
    $answers['UserInterface'] = Ask-Question -Question "User interface type?" -Options @(
        "Command line only",
        "CLI with rich output",
        "GUI application",
        "Web interface",
        "API only",
        "Mixed modes"
    )
    
    $answers['Configuration'] = Ask-Question -Question "Configuration approach?" -Options @(
        "Command line arguments only",
        "Config file",
        "Environment variables",
        "Interactive setup",
        "Hardcoded defaults",
        "Database/registry"
    ) -AllowMultiple
    
    $answers['Security'] = Ask-Question -Question "Security considerations?" -Options @(
        "None needed",
        "Basic input validation",
        "Authentication required",
        "Encryption needed",
        "Audit logging",
        "Compliance requirements"
    ) -AllowMultiple
    
    $answers['Testing'] = Ask-Question -Question "Testing strategy?" -Options @(
        "Manual testing only",
        "Unit tests",
        "Integration tests",
        "End-to-end tests",
        "Performance tests",
        "User acceptance tests"
    ) -AllowMultiple
}

# SPECIFIC FEATURES
Write-Host ""
Write-Host "=== SPECIFIC FEATURES ===" -ForegroundColor Green

$answers['CoreFeatures'] = Ask-Question -Question "List 3-5 core features (comma separated):" -Required

$answers['NiceToHave'] = Ask-Question -Question "Nice-to-have features (comma separated):"

$answers['Inspiration'] = Ask-Question -Question "Similar tools or inspiration sources:"

# MVP DEFINITION
Write-Host ""
Write-Host "=== MVP (Minimum Viable Product) ===" -ForegroundColor Green

$answers['MVPGoal'] = Ask-Question -Question "What's the ONE thing the MVP must do?" -Required

$answers['SuccessCriteria'] = Ask-Question -Question "How will you know it's working? (success criteria):" -Required

# Clean text for API
function Clean-TextForAPI {
    param([string]$Text)
    
    $clean = $Text -replace '[\x00-\x1F\x7F]', ' '
    $clean = $clean -replace '\\', '\\'
    $clean = $clean -replace '"', '\"'
    $clean = $clean -replace "`t", ' '
    $clean = $clean -replace "`r`n", ' '
    $clean = $clean -replace "`n", ' '
    $clean = $clean -replace '\s+', ' '
    return $clean.Trim()
}

# Generate project specification with AI
Write-Host ""
Write-Host "Generating comprehensive project specification..." -ForegroundColor Yellow

try {
    # Build structured prompt
    $answersText = ""
    foreach ($key in $answers.Keys) {
        $answersText += "$key`: $($answers[$key])`n"
    }
    
    $cleanAnswers = Clean-TextForAPI -Text $answersText
    
    $specPrompt = @"
Create a comprehensive project specification document based on these requirements. Include:

1. EXECUTIVE SUMMARY - Clear project vision and goals
2. TECHNICAL ARCHITECTURE - Components, data flow, technology choices
3. IMPLEMENTATION PHASES - Step-by-step development plan
4. FILE STRUCTURE - Recommended project organization
5. CORE ALGORITHMS - Key logic and processing steps
6. ERROR HANDLING STRATEGY - Comprehensive approach
7. TESTING PLAN - Specific test scenarios
8. DEPLOYMENT CONSIDERATIONS - How to ship and maintain
9. FUTURE ROADMAP - Evolution beyond MVP
10. QUICK START CODE - Initial boilerplate to begin

Make it actionable and specific, not generic. Focus on THIS project's unique needs.

Project Requirements:
$cleanAnswers
"@

    $specBody = @{
        model = "gemma-3-12b-it-qat"
        messages = @(
            @{
                role = "user"
                content = $specPrompt
            }
        )
        max_tokens = 3000
        temperature = 0.3
    } | ConvertTo-Json -Depth 5
    
    $headers = @{
        'Content-Type' = 'application/json; charset=utf-8'
    }
    
    $specBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($specBody)
    $specResponse = Invoke-WebRequest -Uri "http://localhost:1234/v1/chat/completions" -Method POST -Body $specBodyBytes -Headers $headers
    $specData = $specResponse.Content | ConvertFrom-Json
    $specification = $specData.choices[0].message.content
    
    Write-Host "Specification generated successfully!" -ForegroundColor Green
    
} catch {
    Write-Host "Error generating specification: $($_.Exception.Message)" -ForegroundColor Red
    $specification = "Error generating AI specification. See questionnaire answers above."
}

# Generate implementation checklist
Write-Host "Creating implementation checklist..." -ForegroundColor Yellow

try {
    $checklistPrompt = @"
Create a concise implementation checklist (20-30 items) for building this project. 
Format as a simple checkbox list that can be printed and checked off.
Order by implementation sequence, not importance.
Include setup, core features, testing, and deployment.
ONLY include items mentioned in the requirements, no extra features.

Project: $($answers['ProjectName'])
Description: $($answers['Description'])
MVP Goal: $($answers['MVPGoal'])
Core Features: $($answers['CoreFeatures'])
"@

    $checklistBody = @{
        model = "gemma-3-12b-it-qat"
        messages = @(
            @{
                role = "user"
                content = $checklistPrompt
            }
        )
        max_tokens = 1000
        temperature = 0.2
    } | ConvertTo-Json -Depth 5
    
    $checklistBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($checklistBody)
    $checklistResponse = Invoke-WebRequest -Uri "http://localhost:1234/v1/chat/completions" -Method POST -Body $checklistBodyBytes -Headers $headers
    $checklistData = $checklistResponse.Content | ConvertFrom-Json
    $checklist = $checklistData.choices[0].message.content
    
} catch {
    Write-Host "Error generating checklist: $($_.Exception.Message)" -ForegroundColor Red
    $checklist = "[ ] Define requirements`n[ ] Set up development environment`n[ ] Create initial structure`n[ ] Implement core feature`n[ ] Add error handling`n[ ] Write tests`n[ ] Document usage`n[ ] Deploy MVP"
}

# MULTI-STAGE VERIFICATION
Write-Host ""
Write-Host "PHASE: Multi-stage verification..." -ForegroundColor Yellow

# Verification 1: Check for consistency between requirements and specification
Write-Host "  Verifying spec consistency..." -ForegroundColor Gray
try {
    $consistencyPrompt = @"
Check if this specification is consistent with the requirements. Look for:
- Dependencies mentioned that weren't in requirements
- Features added beyond what was requested
- Technical choices that contradict the requirements
- Scope creep or feature bloat

Respond ONLY with "CONSISTENT" or "INCONSISTENT: [brief reason]"

REQUIREMENTS:
$cleanAnswers

SPECIFICATION:
$specification
"@

    $consistencyBody = @{
        model = "gemma-3-12b-it-qat"
        messages = @(@{ role = "user"; content = $consistencyPrompt })
        max_tokens = 200
        temperature = 0.1
    } | ConvertTo-Json -Depth 5
    
    $consistencyBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($consistencyBody)
    $consistencyResponse = Invoke-WebRequest -Uri "http://localhost:1234/v1/chat/completions" -Method POST -Body $consistencyBodyBytes -Headers $headers
    $consistencyData = $consistencyResponse.Content | ConvertFrom-Json
    $consistencyCheck = $consistencyData.choices[0].message.content
    
    if ($consistencyCheck -like "INCONSISTENT:*") {
        Write-Host "  Warning: $consistencyCheck" -ForegroundColor Yellow
    } else {
        Write-Host "  [OK] Specification consistent with requirements" -ForegroundColor Green
    }
} catch {
    Write-Host "  Consistency check failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Verification 2: Technical accuracy check
Write-Host "  Verifying technical accuracy..." -ForegroundColor Gray
try {
    $accuracyPrompt = @"
Check the technical accuracy of any code examples in this specification.
Look for:
- Syntax errors
- Missing imports
- Incorrect API usage
- Logic errors

Respond ONLY with "ACCURATE" or "ISSUES: [brief list of problems]"

SPECIFICATION:
$specification
"@

    $accuracyBody = @{
        model = "gemma-3-12b-it-qat"
        messages = @(@{ role = "user"; content = $accuracyPrompt })
        max_tokens = 300
        temperature = 0.1
    } | ConvertTo-Json -Depth 5
    
    $accuracyBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($accuracyBody)
    $accuracyResponse = Invoke-WebRequest -Uri "http://localhost:1234/v1/chat/completions" -Method POST -Body $accuracyBodyBytes -Headers $headers
    $accuracyData = $accuracyResponse.Content | ConvertFrom-Json
    $accuracyCheck = $accuracyData.choices[0].message.content
    
    if ($accuracyCheck -like "ISSUES:*") {
        Write-Host "  Warning: $accuracyCheck" -ForegroundColor Yellow
    } else {
        Write-Host "  [OK] Technical examples appear accurate" -ForegroundColor Green
    }
} catch {
    Write-Host "  Accuracy check failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Verification 3: Checklist alignment
Write-Host "  Verifying checklist alignment..." -ForegroundColor Gray
try {
    $alignmentPrompt = @"
Check if this checklist matches the stated MVP goal and core features.
Look for:
- Items not related to the MVP goal
- Missing essential MVP items
- Features that weren't requested

Respond ONLY with "ALIGNED" or "MISALIGNED: [brief reason]"

MVP Goal: $($answers['MVPGoal'])
Core Features: $($answers['CoreFeatures'])

CHECKLIST:
$checklist
"@

    $alignmentBody = @{
        model = "gemma-3-12b-it-qat"
        messages = @(@{ role = "user"; content = $alignmentPrompt })
        max_tokens = 200
        temperature = 0.1
    } | ConvertTo-Json -Depth 5
    
    $alignmentBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($alignmentBody)
    $alignmentResponse = Invoke-WebRequest -Uri "http://localhost:1234/v1/chat/completions" -Method POST -Body $alignmentBodyBytes -Headers $headers
    $alignmentData = $alignmentResponse.Content | ConvertFrom-Json
    $alignmentCheck = $alignmentData.choices[0].message.content
    
    if ($alignmentCheck -like "MISALIGNED:*") {
        Write-Host "  Warning: $alignmentCheck" -ForegroundColor Yellow
    } else {
        Write-Host "  [OK] Checklist aligned with MVP goals" -ForegroundColor Green
    }
} catch {
    Write-Host "  Alignment check failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Store verification results
$verificationResults = @"

## VERIFICATION RESULTS

- Consistency Check: $consistencyCheck
- Technical Accuracy: $accuracyCheck
- Checklist Alignment: $alignmentCheck
"@

# Save all outputs
$safeProjectName = $projectName -replace '[^\w\-]', '_'
$seedPath = Join-Path $OutputDirectory "$safeProjectName`_seed_$timestamp.md"
$checklistPath = Join-Path $OutputDirectory "$safeProjectName`_checklist_$timestamp.txt"
$answersPath = Join-Path $OutputDirectory "$safeProjectName`_answers_$timestamp.txt"

# Create comprehensive seed document
$seedDocument = @"
# $projectName - Project Seed Document

Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

## Quick Reference

**Description**: $($answers['Description'])
**Scope**: $($answers['Scope'])
**Primary Output**: $($answers['OutputType'])
**Language**: $($answers['Language'])
**MVP Goal**: $($answers['MVPGoal'])

---

## Questionnaire Answers

$answersText

---

## PROJECT SPECIFICATION

$specification

---

## IMPLEMENTATION CHECKLIST

$checklist

---
$verificationResults

---

## NOTES

- This seed document was generated by Project Seed Generator
- Review and refine the specification before starting development
- Keep this document updated as the project evolves
- Use the checklist to track progress
- Address any verification warnings before starting implementation

## Next Steps

1. Review this specification thoroughly
2. Address any verification warnings
3. Set up your development environment
4. Create the project structure
5. Start with the MVP goal: $($answers['MVPGoal'])
6. Use the checklist to track progress

---
*Generated by Project Seed Generator*
"@

# Save files
$seedDocument | Out-File -FilePath $seedPath -Encoding UTF8
$checklist | Out-File -FilePath $checklistPath -Encoding UTF8
$answersText | Out-File -FilePath $answersPath -Encoding UTF8

# Copy specification to clipboard
$specification | Set-Clipboard

Write-Host ""
Write-Host "PROJECT SEED GENERATION COMPLETE!" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Green
Write-Host ""
Write-Host "Project: $projectName" -ForegroundColor Cyan
Write-Host "Files generated:"
Write-Host "  - Seed document: $seedPath" -ForegroundColor Yellow
Write-Host "  - Checklist: $checklistPath" -ForegroundColor Yellow
Write-Host "  - Raw answers: $answersPath" -ForegroundColor Yellow
Write-Host ""
Write-Host "Specification copied to clipboard!" -ForegroundColor Green
Write-Host ""

# Generate audio summary
if (!$SkipAudio) {
    Write-Host "Generating audio summary..." -ForegroundColor Yellow
    try {
        $audioSummary = "$projectName project seed generated. $($answers['Description']) The MVP will $($answers['MVPGoal']). It's a $($answers['Scope']) project using $($answers['Language']) that produces $($answers['OutputType']). Check the generated specification for complete implementation details."
        
        $ttsBody = @{
            model = "kokoro"
            input = $audioSummary
            voice = "af_sky"
            response_format = "mp3"
            speed = 1.0
            stream = $false
        } | ConvertTo-Json -Depth 3
        
        $audioPath = Join-Path $OutputDirectory "$safeProjectName`_summary_$timestamp.mp3"
        
        $ttsHeaders = @{
            'Content-Type' = 'application/json; charset=utf-8'
            'Accept' = 'audio/mpeg'
        }
        
        $ttsBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($ttsBody)
        $ttsResponse = Invoke-WebRequest -Uri "http://localhost:8880/v1/audio/speech" -Method POST -Body $ttsBodyBytes -Headers $ttsHeaders
        [System.IO.File]::WriteAllBytes($audioPath, $ttsResponse.Content)
        
        # Play audio if VLC is available
        $vlcPath = "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"
        if (Test-Path $vlcPath) {
            Start-Sleep 1
            Start-Process -FilePath $vlcPath -ArgumentList "--intf dummy --play-and-exit `"$audioPath`"" -NoNewWindow -Wait
            Write-Host "Audio summary played!" -ForegroundColor Green
        }
        
    } catch {
        Write-Host "Audio generation skipped: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Ready to build something awesome!" -ForegroundColor Cyan