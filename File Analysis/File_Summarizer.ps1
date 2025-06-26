# Multi-File Analyzer - Hierarchical summarization with consistency validation
param(
    [string]$InputPath = ".",
    [string[]]$FileExtensions = @("*.txt", "*.md", "*.log", "*.json", "*.xml", "*.csv", "*.ps1", "*.py", "*.js", "*.html", "*.css", "*.sql"),
    [int]$MaxFiles = 50,
    [int]$MaxFileSize = 500KB,
    [switch]$Recursive
)

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputDir = "outputs"

# Ensure output directory exists
if (!(Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force
}

Write-Host "Multi-File Analyzer Starting..."
Write-Host "Input Path: $InputPath"
Write-Host "Extensions: $($FileExtensions -join ', ')"

# Model configurations
$largeModel = "gemma-3-12b-it-qat"    # For individual file analysis and validation
$smallModel = "gemma-3-12b-it-qat"     # For overview summary

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
        Write-Host "No valid files found to process"
        exit
    }
    
    Write-Host "Found $($validFiles.Count) files to analyze"
    
} catch {
    Write-Host "Error finding files: $($_.Exception.Message)"
    exit
}

# Function to clean text for API processing
function Clean-TextForAPI {
    param([string]$Text, [int]$MaxLength = 8000)
    
    $clean = $Text -replace '[\x00-\x1F\x7F]', ' '
    $clean = $clean -replace '\\', '\\'
    $clean = $clean -replace '"', '\"'
    $clean = $clean -replace "`t", ' '
    $clean = $clean -replace "`r`n", ' '
    $clean = $clean -replace "`n", ' '
    $clean = $clean -replace '\s+', ' '
    $clean = $clean.Trim()
    
    if ($clean.Length -gt $MaxLength) {
        $clean = $clean.Substring(0, $MaxLength) + "... [truncated]"
    }
    
    return $clean
}

# Function to call API with retry logic
function Invoke-ModelAPI {
    param(
        [string]$Model,
        [string]$Prompt,
        [int]$MaxTokens = 1000,
        [float]$Temperature = 0.3,
        [int]$RetryCount = 3
    )
    
    for ($i = 0; $i -lt $RetryCount; $i++) {
        try {
            $body = @{
                model = $Model
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
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/chat/completions" -Method POST -Body $bodyBytes -Headers $headers
            $responseData = $response.Content | ConvertFrom-Json
            
            return $responseData.choices[0].message.content.Trim()
            
        } catch {
            Write-Host "API call attempt $($i + 1) failed: $($_.Exception.Message)"
            if ($i -eq $RetryCount - 1) {
                return "ERROR: Failed to get response after $RetryCount attempts"
            }
            Start-Sleep -Seconds 2
        }
    }
}

# PHASE 1: Individual file analysis with large model
Write-Host "`nPHASE 1: Analyzing individual files..."
$fileSummaries = @()
$processedCount = 0

foreach ($file in $validFiles) {
    try {
        $processedCount++
        Write-Host "[$processedCount/$($validFiles.Count)] Processing: $($file.Name)"
        
        # Read file content
        $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop
        
        if ([string]::IsNullOrWhiteSpace($content)) {
            Write-Host "  Skipping empty file"
            continue
        }
        
        # Clean content for API
        $cleanContent = Clean-TextForAPI -Text $content -MaxLength 12000
        
        # Generate individual summary with large model
        $individualPrompt = @"
Analyze this file content and create a summary. 
Each line should be one sentence describing one thing. 
Format it only as newline separated text. 
Don't include any confirmations or extra explanations.
Keep it brief please.

You are simply summarizing the content of the file as simply and parsably as possible.
Don't say "here's a summary" or something like that all I want is the content of the file nothing else at all
To reiterate, this is supposed to be programmatic not conversational.
DO NOT SAY ANYTHING ELSE.
SILENCE BESIDES THAT.
THANK YOU.

File: $($file.Name)
Content:
$cleanContent
"@
        
        Write-Host "  Generating summary..."
        $summary = Invoke-ModelAPI -Model $largeModel -Prompt $individualPrompt -MaxTokens 800 -Temperature 0.2
        
        if ($summary -notlike "ERROR:*") {
            $fileSummaries += [PSCustomObject]@{
                FileName = $file.Name
                FilePath = $file.FullName
                FileSize = $file.Length
                Summary = $summary
                ContentPreview = $content.Substring(0, [Math]::Min(200, $content.Length)) + "..."
            }
            
            # Save individual summary
            $individualSummaryPath = "$outputDir\file_summary_$($file.BaseName)_$timestamp.txt"
            @"
FILE ANALYSIS - $($file.Name)
Generated: $(Get-Date)
File Size: $($file.Length) bytes
Path: $($file.FullName)

SUMMARY:
$summary

CONTENT PREVIEW:
$($content.Substring(0, [Math]::Min(500, $content.Length)))...
"@ | Out-File -FilePath $individualSummaryPath -Encoding UTF8
            
            Write-Host "  Summary complete"
        } else {
            Write-Host "  Failed to generate summary: $summary"
        }
        
        # Small delay between files
        Start-Sleep -Milliseconds 500
        
    } catch {
        Write-Host "  Error processing $($file.Name): $($_.Exception.Message)"
        continue
    }
}

if ($fileSummaries.Count -eq 0) {
    Write-Host "No files were successfully processed"
    exit
}

Write-Host "Individual analysis complete: $($fileSummaries.Count) files processed"

# PHASE 2: Overview summary with smaller model
Write-Host "`nPHASE 2: Creating overview summary..."

# Combine all individual summaries
$combinedSummaries = ""
foreach ($fileSummary in $fileSummaries) {
    $combinedSummaries += "FILE: $($fileSummary.FileName)`n$($fileSummary.Summary)`n`n"
}

$cleanCombined = Clean-TextForAPI -Text $combinedSummaries -MaxLength 15000

$overviewPrompt = @"
Create a comprehensive overview summary of these file analyses. Identify:
• Common themes across files
• Overall purpose or project scope
• Key relationships between files
• Major findings or patterns
• Summary of the collective content

IMPORTANT: This is an automated analysis not a conversation, so do not, DO NOT, specifically, include any greetings or pleasantries.
Reminder: Not a chat, a document.

Individual File Summaries:
$cleanCombined
"@

Write-Host "Generating overview with smaller model..."
$overviewSummary = Invoke-ModelAPI -Model $largeModel -Prompt $overviewPrompt -MaxTokens 1000 -Temperature 0.1

# PHASE 3: Enhanced consistency validation with 2/3 majority rule
Write-Host "`nPHASE 3: Validating consistency (2/3 majority required)..."

$validationPrompt = @"
Confirm these individual and overview summaries are in line with each other. Respond with ONLY "GOOD" if they are consistent, or "BAD" if they are not. Do not provide any explanations or additional text.

Respond with ONLY either "GOOD" or "BAD" - nothing else. One of those two words, by itself, in caps.

OVERVIEW SUMMARY:
$overviewSummary

INDIVIDUAL SUMMARIES:
$cleanCombined
"@

# Perform 3 validation attempts
$validationAttempts = 3
$validationResponses = @()
$goodCount = 0
$badCount = 0

Write-Host "Performing $validationAttempts validation checks..."

for ($attempt = 1; $attempt -le $validationAttempts; $attempt++) {
    Write-Host "  Validation check $attempt/$validationAttempts..."
    
    $validationResponse = Invoke-ModelAPI -Model $smallModel -Prompt $validationPrompt -MaxTokens 50 -Temperature 0.1
    
    if ($validationResponse -eq "GOOD") {
        $validationResponses += "GOOD"
        $goodCount++
        Write-Host "    Result: GOOD ($goodCount/$attempt)"
    } elseif ($validationResponse -eq "BAD") {
        $validationResponses += "BAD"
        $badCount++
        Write-Host "    Result: BAD ($badCount/$attempt)"
    } else {
        Write-Host "    Invalid response: '$validationResponse' - treating as inconclusive"
        $validationResponses += "INVALID"
    }
    
    # Early exit if we already have 2 of the same result
    if ($goodCount -ge 2) {
        Write-Host "  Early exit: Already have 2 GOOD responses"
        break
    } elseif ($badCount -ge 2) {
        Write-Host "  Early exit: Already have 2 BAD responses"
        break
    }
    
    # Small delay between validation attempts
    if ($attempt -lt $validationAttempts) {
        Start-Sleep -Seconds 1
    }
}

# Determine final validation result based on 2/3 majority
if ($goodCount -ge 2) {
    $validationResult = "GOOD"
    $validationDetails = "PASSED (${goodCount}/3 GOOD)"
} elseif ($badCount -ge 2) {
    $validationResult = "BAD"
    $validationDetails = "FAILED (${badCount}/3 BAD)"
} else {
    $validationResult = "INCONCLUSIVE"
    $validationDetails = "No majority (GOOD: $goodCount, BAD: $badCount)"
}

Write-Host "Final validation result: $validationResult - $validationDetails"
Write-Host "Individual responses: $($validationResponses -join ', ')"

# Create final comprehensive report
$reportPath = "$outputDir\file_analysis_report_$timestamp.txt"
$report = @"
MULTI-FILE ANALYSIS REPORT
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Input Path: $InputPath
Files Processed: $($fileSummaries.Count)
Consistency Check: $validationResult ($validationDetails)

OVERVIEW SUMMARY:
$overviewSummary

INDIVIDUAL FILE SUMMARIES:
$(foreach ($fs in $fileSummaries) {
"
FILE: $($fs.FileName) ($($fs.FileSize) bytes)
$($fs.Summary)
"
})

PROCESSING DETAILS:
- Large Model Used: $largeModel (individual analysis, validation)
- Small Model Used: $smallModel (overview summary)
- Files Analyzed: $($fileSummaries.Count)
- Total Size Processed: $(($fileSummaries | Measure-Object -Property FileSize -Sum).Sum) bytes
- Validation Result: $validationResult
- Validation Details: $validationDetails
- Validation Responses: $($validationResponses -join ', ')

FILES PROCESSED:
$(foreach ($fs in $fileSummaries) {"- $($fs.FileName) ($($fs.FileSize) bytes)"})

---
Generated by Multi-File Analyzer
"@

$report | Out-File -FilePath $reportPath -Encoding UTF8

# Copy overview to clipboard
$overviewSummary | Set-Clipboard

Write-Host ""
Write-Host "MULTI-FILE ANALYSIS COMPLETE!"
Write-Host "Report saved to: $reportPath"
Write-Host "Overview copied to clipboard"
Write-Host "Consistency Check: $validationResult - $validationDetails"
Write-Host ""
Write-Host "OVERVIEW SUMMARY:"
Write-Host $overviewSummary
Write-Host ""

Write-Host ""
Write-Host "FILES ANALYZED:"
foreach ($fs in $fileSummaries) {
    Write-Host "- $($fs.FileName) ($($fs.FileSize) bytes)"
}