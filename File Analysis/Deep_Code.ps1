# Code to Natural Language Translator - Convert code logic to readable explanations
param(
    [string]$InputPath = ".",
    [string[]]$FileExtensions = @("*.ps1", "*.py", "*.js", "*.ts", "*.java", "*.cs", "*.cpp", "*.c", "*.php", "*.rb", "*.go", "*.sql", "*.bat", "*.cmd"),
    [int]$MaxFiles = 20,
    [int]$MaxFileSize = 500KB,
    [switch]$Recursive,
    [string]$OutputDirectory = "outputs\Explained"
)

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# Ensure output directory exists
if (!(Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

Write-Host "Code to Natural Language Translator - Starting..."
Write-Host "Input Path: $InputPath"
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
function Clean-CodeForAPI {
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

# Function to call API for natural language explanation
function Get-NaturalLanguageExplanation {
    param([string]$FileName, [string]$Code)
    
    try {
        $cleanCode = Clean-CodeForAPI -Code $Code -MaxLength 12000
        
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
        
        $explanationPrompt = @"
Convert this $fileType into a detailed, natural language explanation that a non-programmer can understand.

REQUIREMENTS:
- Explain what the code does in plain English
- Break down the logic step by step
- Explain any complex concepts in simple terms
- Describe the purpose and workflow
- Mention what inputs it expects and what outputs it produces
- Use everyday language, avoid technical jargon where possible
- When technical terms are necessary, explain them briefly
- Structure the explanation logically from start to finish

DO NOT:
- Include the actual code in your response
- Use programming terminology without explanation
- Assume prior coding knowledge
- Be overly brief - provide detailed explanations

File: $FileName
Code to explain:
$cleanCode
"@

        $explanationBody = @{
            model = "gemma-3-4b-it-qat"
            messages = @(
                @{
                    role = "user"
                    content = $explanationPrompt
                }
            )
            max_tokens = 2000
            temperature = 0.3
        } | ConvertTo-Json -Depth 5
        
        $headers = @{
            'Content-Type' = 'application/json; charset=utf-8'
        }
        
        $explanationBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($explanationBody)
        $explanationResponse = Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/chat/completions" -Method POST -Body $explanationBodyBytes -Headers $headers -TimeoutSec 300
        $explanationData = $explanationResponse.Content | ConvertFrom-Json
        
        return $explanationData.choices[0].message.content.Trim()
        
    } catch {
        return "ERROR: Unable to generate explanation for $FileName - $($_.Exception.Message)"
    }
}

# Process each code file
Write-Host "`nTranslating code files to natural language..."
$explanations = @()
$processedCount = 0

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
        
        # Generate natural language explanation
        $explanation = Get-NaturalLanguageExplanation -FileName $file.Name -Code $content
        
        if ($explanation -notlike "ERROR:*") {
            $explanations += [PSCustomObject]@{
                FileName = $file.Name
                FilePath = $file.FullName
                FileSize = $file.Length
                FileType = [System.IO.Path]::GetExtension($file.Name)
                Explanation = $explanation
                ProcessedTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
            
            # Save individual explanation file
            $safeFileName = $file.BaseName -replace '[^\w\-_]', '_'
            $explanationPath = Join-Path $OutputDirectory "explained_$safeFileName`_$timestamp.txt"
            
            $individualExplanation = @"
NATURAL LANGUAGE EXPLANATION - $($file.Name)
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
File Size: $($file.Length) bytes
File Type: $([System.IO.Path]::GetExtension($file.Name))
Source Path: $($file.FullName)

WHAT THIS CODE DOES:
$explanation

---
This explanation was generated automatically to help non-programmers understand the code logic.
Generated by Code to Natural Language Translator
"@
            
            $individualExplanation | Out-File -FilePath $explanationPath -Encoding UTF8
            
            Write-Host "  Explanation complete: $explanationPath"
        } else {
            Write-Host "  Failed to generate explanation: $explanation" -ForegroundColor Red
        }
        
        # Small delay between files
        Start-Sleep -Milliseconds 800
        
    } catch {
        Write-Host "  Error processing $($file.Name): $($_.Exception.Message)" -ForegroundColor Red
        continue
    }
}

if ($explanations.Count -eq 0) {
    Write-Host "No files were successfully processed"
    exit
}

# Create summary index file
$indexPath = Join-Path $OutputDirectory "explanation_index_$timestamp.txt"
$indexContent = @"
CODE EXPLANATION INDEX
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Files Processed: $($explanations.Count)

EXPLAINED FILES:
$(foreach ($exp in $explanations) {
"
FILE: $($exp.FileName) ($($exp.FileType))
Size: $($exp.FileSize) bytes
Explanation File: explained_$($exp.FileName -replace '[^\w\-_]', '_')_$timestamp.txt
Processed: $($exp.ProcessedTime)

SUMMARY: $($exp.Explanation.Substring(0, [Math]::Min(300, $exp.Explanation.Length)))...
"
})

PROCESSING SUMMARY:
- Total files translated: $($explanations.Count)
- Total code size processed: $(($explanations | Measure-Object -Property FileSize -Sum).Sum) bytes
- File types processed: $(($explanations | Group-Object -Property FileType | ForEach-Object { $_.Name }) -join ', ')
- Output directory: $OutputDirectory

---
Generated by Code to Natural Language Translator
"@

$indexContent | Out-File -FilePath $indexPath -Encoding UTF8

# Create combined explanations file for easy reading
$combinedPath = Join-Path $OutputDirectory "all_explanations_$timestamp.txt"
$combinedContent = @"
ALL CODE EXPLANATIONS - COMBINED DOCUMENT
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

$(foreach ($exp in $explanations) {
"
================================================================================
FILE: $($exp.FileName)
TYPE: $($exp.FileType) | SIZE: $($exp.FileSize) bytes
PATH: $($exp.FilePath)
PROCESSED: $($exp.ProcessedTime)
================================================================================

$($exp.Explanation)

"
})

---
Generated by Code to Natural Language Translator
Total files explained: $($explanations.Count)
"@

$combinedContent | Out-File -FilePath $combinedPath -Encoding UTF8

# Create a brief summary for clipboard
$summaryText = @"
Code Translation Complete: Processed $($explanations.Count) files and converted them to natural language explanations. 
Files types: $(($explanations | Group-Object -Property FileType | ForEach-Object { $_.Name }) -join ', ').
All explanations saved to $OutputDirectory for easy reading by non-developers.
"@

$summaryText | Set-Clipboard

Write-Host ""
Write-Host "CODE TO NATURAL LANGUAGE TRANSLATION COMPLETE!"
Write-Host "Files processed: $($explanations.Count)"
Write-Host "Output directory: $OutputDirectory"
Write-Host ""
Write-Host "Generated files:"
Write-Host "- Index: $indexPath"
Write-Host "- Combined explanations: $combinedPath"
Write-Host "- Individual explanation files: $($explanations.Count) files"
Write-Host ""
Write-Host "Summary copied to clipboard"

# Show sample of explanations
Write-Host ""
Write-Host "SAMPLE EXPLANATIONS:"
$explanations | Select-Object -First 3 | ForEach-Object {
    Write-Host ""
    Write-Host "FILE: $($_.FileName)" -ForegroundColor Cyan
    $preview = $_.Explanation.Substring(0, [Math]::Min(400, $_.Explanation.Length))
    Write-Host $preview
    if ($_.Explanation.Length -gt 400) { Write-Host "..." }
}

# Generate audio summary if requested
Write-Host "`nGenerating audio summary..."
try {
    $audioText = "Code translation complete. Processed $($explanations.Count) files and converted programming logic into natural language explanations that non-developers can understand. All explanations have been saved as individual text files for easy reading."
    
    $ttsBody = @{
        model = "kokoro"
        input = $audioText
        voice = "af_sky"
        response_format = "mp3"
        speed = 1.0
        stream = $false
    } | ConvertTo-Json -Depth 3
    
    $audioPath = Join-Path $OutputDirectory "translation_summary_$timestamp.mp3"
    
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
Write-Host "Translation complete! Check the output directory for all natural language explanations."
