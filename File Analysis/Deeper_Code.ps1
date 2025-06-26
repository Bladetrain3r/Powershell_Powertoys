# Advanced Code to Natural Language Translator - With validation and retry logic
param(
    [string]$InputPath = ".",
    [string[]]$FileExtensions = @("*.ps1", "*.py", "*.js", "*.ts", "*.java", "*.cs", "*.cpp", "*.c", "*.php", "*.rb", "*.go", "*.sql", "*.bat", "*.cmd"),
    [int]$MaxFiles = 20,
    [int]$MaxFileSize = 500KB,
    [switch]$Recursive,
    [string]$OutputDirectory = "outputs\Explained",
    [int]$MaxRetries = 3
)

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# Ensure output directory exists
if (!(Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

Write-Host "Advanced Code to Natural Language Translator - Starting..."
Write-Host "Input Path: $InputPath"
Write-Host "Max retries per file: $MaxRetries"
Write-Host "Looking for: $($FileExtensions -join ', ')"

# Get files to process
try {
    $allFiles = @()
    foreach ($ext in $FileExtensions) {
        if ($Recursive) {
            $files = Get-ChildItem -Path $InputPath -Filter $ext -Recurse -File
        } else {
            $files = Get-ChildItem -Path $InputPath -Filter $ext -File
        }
        $allFiles += $files
    }
    
    # Filter by size and limit count
    $validFiles = $allFiles | Where-Object { $_.Length -le $MaxFileSize } | Sort-Object Name
    
    if ($MaxFiles -gt 0 -and $validFiles.Count -gt $MaxFiles) {
        $validFiles = $validFiles | Select-Object -First $MaxFiles
        Write-Host "Limited to first $MaxFiles files"
    }
    
    if ($validFiles.Count -eq 0) {
        Write-Host "No valid code files found to process"
        exit
    }
    
    Write-Host "Found $($validFiles.Count) code files to translate"
    
} catch {
    Write-Host "Error finding files: $($_.Exception.Message)"
    exit
}

# Function to clean code for API processing
function Format-CodeForAPI {
    param([string]$Code, [int]$MaxLength = 10000)
    
    # Keep code structure but clean problematic characters
    $clean = $Code -replace '[\x00-\x1F\x7F]', ' '  # Remove control chars but keep newlines
    $clean = $clean -replace '\\', '\\'             # Escape backslashes
    $clean = $clean -replace '"', '\"'              # Escape quotes
    $clean = $clean.Trim()
    
    if ($clean.Length -gt $MaxLength) {
        $clean = $clean.Substring(0, $MaxLength) + "`n... [code truncated for analysis]"
    }
    
    return $clean
}

# Function to call API with retry logic
function Invoke-ModelAPI {
    param(
        [string]$Prompt,
        [int]$MaxTokens = 2000,
        [float]$Temperature = 0.3,
        [int]$RetryCount = 3
    )
    
    for ($i = 0; $i -lt $RetryCount; $i++) {
        try {
            $body = @{
                model = "gemma-3-12b-it-qat"
                messages = @(
                    @{
                        role = "user"
                        content = $Prompt
                    }
                )
                max_tokens = $MaxTokens
                temperature = $Temperature
            } | ConvertTo-Json -Depth 5
            
            $headers = @{
                'Content-Type' = 'application/json; charset=utf-8'
            }
            
            $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/chat/completions" -Method POST -Body $bodyBytes -Headers $headers -TimeoutSec 300
            $responseData = $response.Content | ConvertFrom-Json
            
            return $responseData.choices[0].message.content.Trim()
            
        } catch {
            Write-Host "    API call attempt $($i + 1) failed: $($_.Exception.Message)"
            if ($i -eq $RetryCount - 1) {
                return "ERROR: Failed to get response after $RetryCount attempts"
            }
            Start-Sleep -Seconds 2
        }
    }
}

# Function to validate explanation against code
function Test-ExplanationQuality {
    param([string]$Code, [string]$Explanation, [string]$FileName)
    
    try {
        $validationPrompt = @"
You are validating whether a natural language explanation accurately describes the given code.

Respond with ONLY either "GOOD" or "BAD" - nothing else. One of those two words, by itself, in caps.

GOOD means:
- The explanation accurately describes what the code does
- Key functionality is covered
- The explanation is clear and understandable
- No major inaccuracies or missing critical elements

BAD means:
- The explanation is inaccurate or misleading
- Major functionality is missed or incorrectly described
- The explanation is unclear or confusing
- Contains significant errors about what the code does

CODE:
$Code

EXPLANATION TO VALIDATE:
$Explanation

RESPOND WITH ONLY "GOOD" OR "BAD":
"@

        $validationResult = Invoke-ModelAPI -Prompt $validationPrompt -MaxTokens 10 -Temperature 0.1 -RetryCount 2
        
        # Clean the response and check for valid result
        $validationResult = $validationResult.Trim().ToUpper()
        
        if ($validationResult -eq "GOOD" -or $validationResult -eq "BAD") {
            return $validationResult
        } else {
            Write-Host "    Invalid validation response: '$validationResult' - treating as BAD"
            return "BAD"
        }
        
    } catch {
        Write-Host "    Validation failed: $($_.Exception.Message) - treating as BAD"
        return "BAD"
    }
}

# Function to generate natural language explanation with validation and retry
function Get-ValidatedExplanation {
    param([string]$FileName, [string]$Code, [int]$MaxAttempts = 3)
    
    $cleanCode = Format-CodeForAPI -Code $Code -MaxLength 12000
    
    # Detect file type for context
    $fileType = switch ([System.IO.Path]::GetExtension($FileName).ToLower()) {
        ".ps1" { "PowerShell script" }
        ".py" { "Python script" }
        ".js" { "JavaScript code" }
        ".ts" { "TypeScript code" }
        ".java" { "Java code" }
        ".cs" { "C# code" }
        ".cpp" { "C++ code" }
        ".c" { "C code" }
        ".php" { "PHP code" }
        ".rb" { "Ruby code" }
        ".go" { "Go code" }
        ".sql" { "SQL script" }
        ".bat" { "Batch script" }
        ".cmd" { "Command script" }
        default { "code file" }
    }
    
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        Write-Host "    Attempt $attempt of $MaxAttempts..."
        
        # Generate explanation with varying prompts to improve chances
        $basePrompt = @"
Convert this $fileType into a detailed, natural language explanation that a non-programmer can understand.
IMPORTANT: This is an automated analysis not a conversation, so do not, DO NOT, specifically, include any greetings or pleasantries.
Reminder: Not a chat, a document.

REQUIREMENTS:
- Explain what the code does in plain English
- Break down the logic step by step
- Explain any complex concepts in simple terms
- Describe the purpose and workflow clearly
- Mention what inputs it expects and what outputs it produces
- Use everyday language, avoid technical jargon where possible
- When technical terms are necessary, explain them briefly
- Structure the explanation logically from start to finish
- Be thorough and accurate - cover all important functionality

DO NOT:
- Include the actual code in your response
- Use programming terminology without explanation
- Assume prior coding knowledge
- Be overly brief - provide detailed explanations
- Make assumptions about what the code might do

File: $FileName
Code to explain:
$cleanCode
"@

        # Vary the prompt slightly on retries to get different perspectives
        $explanationPrompt = if ($attempt -eq 1) {
            $basePrompt
        } elseif ($attempt -eq 2) {
            $basePrompt + "`n`nFOCUS: Pay special attention to accuracy and completeness in your explanation."
        } else {
            $basePrompt + "`n`nIMPORTANT: Previous explanations were inadequate. Provide a thorough, step-by-step breakdown of exactly what this code accomplishes."
        }
        
        # Generate explanation
        $explanation = Invoke-ModelAPI -Prompt $explanationPrompt -MaxTokens 2500 -Temperature (0.2 + ($attempt * 0.1))
        
        if ($explanation -like "ERROR:*") {
            Write-Host "    Failed to generate explanation: $explanation"
            continue
        }
        
        # Validate the explanation
        Write-Host "    Validating explanation quality..."
        $validationResult = Test-ExplanationQuality -Code $cleanCode -Explanation $explanation -FileName $FileName
        
        Write-Host "    Validation result: $validationResult"
        
        if ($validationResult -eq "GOOD") {
            return @{
                Explanation = $explanation
                ValidationResult = $validationResult
                AttemptsUsed = $attempt
                Success = $true
            }
        } else {
            Write-Host "    Explanation marked as BAD, retrying..."
            Start-Sleep -Seconds 1  # Brief pause before retry
        }
    }
    
    # If we get here, all attempts failed validation
    return @{
        Explanation = $explanation  # Return the last attempt
        ValidationResult = "BAD"
        AttemptsUsed = $MaxAttempts
        Success = $false
    }
}

# Process each code file with validation and retry
Write-Host "`nTranslating code files to natural language with validation..."
$explanations = @()
$processedCount = 0
$successCount = 0
$failureCount = 0

foreach ($file in $validFiles) {
    try {
        $processedCount++
        Write-Host "[$processedCount/$($validFiles.Count)] Translating: $($file.Name)"
        
        # Read file content
        $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop
        
        if ([string]::IsNullOrWhiteSpace($content)) {
            Write-Host "  Skipping empty file"
            continue
        }
        
        # Generate validated explanation
        $result = Get-ValidatedExplanation -FileName $file.Name -Code $content -MaxAttempts $MaxRetries
        
        if ($result.Success) {
            $successCount++
            Write-Host "  SUCCESS: Valid explanation generated in $($result.AttemptsUsed) attempts" -ForegroundColor Green
        } else {
            $failureCount++
            Write-Host "  FAILURE: Could not generate valid explanation after $($result.AttemptsUsed) attempts" -ForegroundColor Red
        }
        
        $explanations += [PSCustomObject]@{
            FileName = $file.Name
            FilePath = $file.FullName
            FileSize = $file.Length
            FileType = [System.IO.Path]::GetExtension($file.Name)
            Explanation = $result.Explanation
            ValidationResult = $result.ValidationResult
            AttemptsUsed = $result.AttemptsUsed
            Success = $result.Success
            ProcessedTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        
        # Save individual explanation file
        $safeFileName = $file.BaseName -replace '[^\w\-_]', '_'
        $explanationPath = Join-Path $OutputDirectory "explained_$safeFileName`_$timestamp.txt"
        
        $qualityIndicator = if ($result.Success) { "[VALIDATED]" } else { "[NEEDS REVIEW]" }
        
        $individualExplanation = @"
NATURAL LANGUAGE EXPLANATION - $($file.Name)
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Quality Check: $qualityIndicator ($($result.ValidationResult), $($result.AttemptsUsed) attempts)
File Size: $($file.Length) bytes
File Type: $([System.IO.Path]::GetExtension($file.Name))
Source Path: $($file.FullName)

WHAT THIS CODE DOES:
$($result.Explanation)

---
PROCESSING NOTES:
- Validation Result: $($result.ValidationResult)
- Attempts Required: $($result.AttemptsUsed) of $MaxRetries
- Success: $($result.Success)

This explanation was generated automatically and $(if ($result.Success) { "passed validation checks" } else { "may need manual review" }).
Generated by Advanced Code to Natural Language Translator
"@
        
        $individualExplanation | Out-File -FilePath $explanationPath -Encoding UTF8
        
        Write-Host "  Saved: $explanationPath"
        
        # Longer delay between files to avoid overwhelming the API
        Start-Sleep -Milliseconds 1200
        
    } catch {
        Write-Host "  Error processing $($file.Name): $($_.Exception.Message)" -ForegroundColor Red
        $failureCount++
        continue
    }
}

if ($explanations.Count -eq 0) {
    Write-Host "No files were successfully processed"
    exit
}

# Create comprehensive summary with validation statistics
$indexPath = Join-Path $OutputDirectory "explanation_index_$timestamp.txt"
$indexContent = @"
ADVANCED CODE EXPLANATION INDEX
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Files Processed: $($explanations.Count)
Successful Validations: $successCount
Failed Validations: $failureCount
Success Rate: $([math]::Round(($successCount / $explanations.Count) * 100, 1))%

VALIDATION SUMMARY:
$(foreach ($group in ($explanations | Group-Object -Property ValidationResult)) {
"- $($group.Name): $($group.Count) files"
})

ATTEMPT STATISTICS:
$(foreach ($group in ($explanations | Group-Object -Property AttemptsUsed | Sort-Object Name)) {
"- $($group.Name) attempts: $($group.Count) files"
})

EXPLAINED FILES:
$(foreach ($exp in $explanations) {
$statusIcon = if ($exp.Success) { "[PASS]" } else { "[REVIEW]" }
"
$statusIcon FILE: $($exp.FileName) ($($exp.FileType))
Size: $($exp.FileSize) bytes | Validation: $($exp.ValidationResult) | Attempts: $($exp.AttemptsUsed)
Explanation File: explained_$($exp.FileName -replace '[^\w\-_]', '_')_$timestamp.txt
Processed: $($exp.ProcessedTime)

SUMMARY: $($exp.Explanation.Substring(0, [Math]::Min(300, $exp.Explanation.Length)))...
"
})

FILES NEEDING REVIEW:
$(if ($failureCount -eq 0) {
"None - all explanations passed validation!"
} else {
foreach ($exp in ($explanations | Where-Object { -not $_.Success })) {
"[REVIEW] $($exp.FileName) - Failed validation after $($exp.AttemptsUsed) attempts"
}
})

PROCESSING SUMMARY:
- Total files translated: $($explanations.Count)
- Successful validations: $successCount
- Failed validations: $failureCount
- Total code size processed: $(($explanations | Measure-Object -Property FileSize -Sum).Sum) bytes
- File types processed: $(($explanations | Group-Object -Property FileType | ForEach-Object { $_.Name }) -join ', ')
- Average attempts per file: $([math]::Round(($explanations | Measure-Object -Property AttemptsUsed -Average).Average, 1))
- Output directory: $OutputDirectory

---
Generated by Advanced Code to Natural Language Translator with Validation
"@

$indexContent | Out-File -FilePath $indexPath -Encoding UTF8

# Create combined explanations file (validated ones first)
$combinedPath = Join-Path $OutputDirectory "all_explanations_$timestamp.txt"
$sortedExplanations = $explanations | Sort-Object -Property Success, AttemptsUsed -Descending
$combinedContent = @"
ALL CODE EXPLANATIONS - COMBINED DOCUMENT
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Validation Success Rate: $([math]::Round(($successCount / $explanations.Count) * 100, 1))%

$(foreach ($exp in $sortedExplanations) {
$statusIcon = if ($exp.Success) { "[VALIDATED]" } else { "[NEEDS REVIEW]" }
"
================================================================================
FILE: $($exp.FileName) [$statusIcon]
TYPE: $($exp.FileType) | SIZE: $($exp.FileSize) bytes
VALIDATION: $($exp.ValidationResult) after $($exp.AttemptsUsed) attempts
PATH: $($exp.FilePath)
PROCESSED: $($exp.ProcessedTime)
================================================================================

$($exp.Explanation)

"
})

---
Generated by Advanced Code to Natural Language Translator with Validation
Total files explained: $($explanations.Count) | Validated: $successCount | Failed: $failureCount
"@

$combinedContent | Out-File -FilePath $combinedPath -Encoding UTF8

# Create summary for clipboard
$summaryText = @"
Advanced Code Translation Complete: Processed $($explanations.Count) files with validation.
Success rate: $([math]::Round(($successCount / $explanations.Count) * 100, 1))% ($successCount validated, $failureCount failed).
File types: $(($explanations | Group-Object -Property FileType | ForEach-Object { $_.Name }) -join ', ').
All explanations saved to $OutputDirectory with quality indicators.
"@

$summaryText | Set-Clipboard

Write-Host ""
Write-Host "ADVANCED CODE TO NATURAL LANGUAGE TRANSLATION COMPLETE!"
Write-Host "Files processed: $($explanations.Count)"
Write-Host "Validation success rate: $([math]::Round(($successCount / $explanations.Count) * 100, 1))%" -ForegroundColor $(if ($successCount -eq $explanations.Count) { "Green" } elseif ($successCount -gt $failureCount) { "Yellow" } else { "Red" })
Write-Host "Successful validations: $successCount" -ForegroundColor Green
Write-Host "Failed validations: $failureCount" -ForegroundColor Red
Write-Host "Output directory: $OutputDirectory"
Write-Host ""
Write-Host "Generated files:"
Write-Host "- Index with validation stats: $indexPath"
Write-Host "- Combined explanations: $combinedPath"
Write-Host "- Individual explanation files: $($explanations.Count) files"
Write-Host ""
Write-Host "Summary copied to clipboard"

# Show validation statistics
Write-Host ""
Write-Host "VALIDATION STATISTICS:" -ForegroundColor Cyan
foreach ($group in ($explanations | Group-Object -Property ValidationResult)) {
    $color = if ($group.Name -eq "GOOD") { "Green" } else { "Red" }
    Write-Host "- $($group.Name): $($group.Count) files" -ForegroundColor $color
}

Write-Host ""
Write-Host "ATTEMPT DISTRIBUTION:" -ForegroundColor Cyan
foreach ($group in ($explanations | Group-Object -Property AttemptsUsed | Sort-Object Name)) {
    Write-Host "- $($group.Name) attempts: $($group.Count) files"
}

# Show sample of successful explanations
if ($successCount -gt 0) {
    Write-Host ""
    Write-Host "SAMPLE VALIDATED EXPLANATIONS:" -ForegroundColor Green
    $explanations | Where-Object Success | Select-Object -First 2 | ForEach-Object {
        Write-Host ""
        Write-Host "[PASS] FILE: $($_.FileName) (validated in $($_.AttemptsUsed) attempts)" -ForegroundColor Green
        $preview = $_.Explanation.Substring(0, [Math]::Min(400, $_.Explanation.Length))
        Write-Host $preview
        if ($_.Explanation.Length -gt 400) { Write-Host "..." }
    }
}

# Show files that need review
if ($failureCount -gt 0) {
    Write-Host ""
    Write-Host "FILES NEEDING MANUAL REVIEW:" -ForegroundColor Red
    $explanations | Where-Object { -not $_.Success } | ForEach-Object {
        Write-Host "[REVIEW] $($_.FileName) - Failed validation after $($_.AttemptsUsed) attempts" -ForegroundColor Red
    }
}

# Generate audio summary
Write-Host "`nGenerating audio summary..."
try {
    $audioText = "Advanced code translation complete. Processed $($explanations.Count) files with $([math]::Round(($successCount / $explanations.Count) * 100, 1))% validation success rate. $successCount explanations passed quality checks, $failureCount may need manual review."
    
    $ttsBody = @{
        model = "kokoro"
        input = $audioText
        voice = "af_sky"
        response_format = "mp3"
        speed = 1.0
        stream = $false
    } | ConvertTo-Json -Depth 3
    
    $audioPath = Join-Path $OutputDirectory "advanced_translation_summary_$timestamp.mp3"
    
    $ttsHeaders = @{
        'Content-Type' = 'application/json; charset=utf-8'
        'Accept' = 'audio/mpeg'
    }
    
    $ttsBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($ttsBody)
    $ttsResponse = Invoke-WebRequest -Uri "http://127.0.0.1:8880/v1/audio/speech" -Method POST -Body $ttsBodyBytes -Headers $ttsHeaders -TimeoutSec 60
    [System.IO.File]::WriteAllBytes($audioPath, $ttsResponse.Content)
    
    # Check if VLC exists before trying to use it
    $vlcPath = "C:\Program Files\VideoLAN\VLC\vlc.exe"
    if (Test-Path $vlcPath) {
        Start-Sleep 1
        Start-Process -FilePath $vlcPath -ArgumentList "--intf dummy --play-and-exit `"$audioPath`"" -NoNewWindow -Wait
        Write-Host "Audio summary played!"
    } else {
        Write-Host "Audio generated but VLC not found. Audio saved to: $audioPath"
    }
    
} catch {
    Write-Host "Audio generation failed: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Advanced translation complete! Check files marked with [PASS] for validated explanations and [REVIEW] for those needing review."
