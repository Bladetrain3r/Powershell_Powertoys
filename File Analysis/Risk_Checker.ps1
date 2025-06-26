# File Risk Analyzer - Quick security and code quality assessment
param(
    [string]$InputPath = ".",
    [string[]]$FileExtensions = @("*.ps1", "*.py", "*.js", "*.ts", "*.java", "*.cs", "*.cpp", "*.c", "*.php", "*.rb", "*.go", "*.sql", "*.json", "*.xml", "*.yaml", "*.yml", "*.cfg", "*.conf", "*.ini"),
    [int]$MaxFiles = 100,
    [int]$MaxFileSize = 1MB,
    [switch]$Recursive
)

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputDir = "outputs\RiskAnalysis"

# Ensure output directory exists
if (!(Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force
}

Write-Host "File Risk Analyzer - Starting security and quality assessment..."
Write-Host "Input Path: $InputPath"

# Get files to analyze
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
        Write-Host "No valid files found to analyze"
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

# Function to call API for risk analysis
function Get-RiskAnalysis {
    param([string]$FileName, [string]$Content)
    
    try {
        $cleanContent = Clean-TextForAPI -Text $Content -MaxLength 6000
        
        $riskPrompt = @"
Analyze this file for security and code quality risks. Provide assessment in EXACTLY this format, nothing else, no other words, and keep each section concise:

RISK_LEVEL: [LOW/MEDIUM/HIGH/CRITICAL]
SECURITY_ISSUES: [Brief description of security concerns like hardcoded passwords, SQL injection risks, etc.]
QUALITY_ISSUES: [Brief description of code quality issues like hardcoded paths, poor variable naming, etc.]
BEST_PRACTICE_VIOLATIONS: [Brief description of best practice violations like missing error handling, poor structure, etc.]

File: $FileName
Content: $cleanContent
"@

        $riskBody = @{
            model = "gemma-3-4b-it-qat"
            messages = @(
                @{
                    role = "user"
                    content = $riskPrompt
                }
            )
            max_tokens = 500
            temperature = 0.2
        } | ConvertTo-Json -Depth 5
        
        $headers = @{
            'Content-Type' = 'application/json; charset=utf-8'
        }
        
        $riskBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($riskBody)
        $riskResponse = Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/chat/completions" -Method POST -Body $riskBodyBytes -Headers $headers
        $riskData = $riskResponse.Content | ConvertFrom-Json
        
        return $riskData.choices[0].message.content.Trim()
        
    } catch {
        return "ERROR: Unable to analyze risk for $FileName - $($_.Exception.Message)"
    }
}

# Function to parse risk analysis response
function Parse-RiskAnalysis {
    param([string]$Response)
    
    $riskLevel = "UNKNOWN"
    $securityIssues = "Not assessed"
    $qualityIssues = "Not assessed"
    $bestPracticeViolations = "Not assessed"
    
    # Extract each component using regex
    if ($Response -match "RISK_LEVEL:\s*([A-Z]+)") {
        $riskLevel = $matches[1]
    }
    if ($Response -match "SECURITY_ISSUES:\s*(.+?)(?=\n[A-Z_]+:|$)") {
        $securityIssues = $matches[1].Trim()
    }
    if ($Response -match "QUALITY_ISSUES:\s*(.+?)(?=\n[A-Z_]+:|$)") {
        $qualityIssues = $matches[1].Trim()
    }
    if ($Response -match "BEST_PRACTICE_VIOLATIONS:\s*(.+?)(?=\n[A-Z_]+:|$)") {
        $bestPracticeViolations = $matches[1].Trim()
    }
    
    return @{
        RiskLevel = $riskLevel
        SecurityIssues = $securityIssues
        QualityIssues = $qualityIssues
        BestPracticeViolations = $bestPracticeViolations
    }
}

# Analyze each file
Write-Host "`nAnalyzing files for security and quality risks..."
$riskResults = @()
$processedCount = 0

foreach ($file in $validFiles) {
    try {
        $processedCount++
        Write-Host "[$processedCount/$($validFiles.Count)] Analyzing: $($file.Name)"
        
        # Read file content
        $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop
        
        if ([string]::IsNullOrWhiteSpace($content)) {
            Write-Host "  Skipping empty file"
            continue
        }
        
        # Get risk analysis
        $riskAnalysis = Get-RiskAnalysis -FileName $file.Name -Content $content
        $parsedRisk = Parse-RiskAnalysis -Response $riskAnalysis
        
        $riskResults += [PSCustomObject]@{
            FileName = $file.Name
            FilePath = $file.FullName
            FileSize = $file.Length
            RiskLevel = $parsedRisk.RiskLevel
            SecurityIssues = $parsedRisk.SecurityIssues
            QualityIssues = $parsedRisk.QualityIssues
            BestPracticeViolations = $parsedRisk.BestPracticeViolations
            RawAnalysis = $riskAnalysis
        }
        
        # Show quick result
        $riskColor = switch ($parsedRisk.RiskLevel) {
            "CRITICAL" { "Red" }
            "HIGH" { "Yellow" }
            "MEDIUM" { "Cyan" }
            "LOW" { "Green" }
            default { "Gray" }
        }
        
        Write-Host "  Risk Level: $($parsedRisk.RiskLevel)" -ForegroundColor $riskColor
        
        # Small delay between files
        Start-Sleep -Milliseconds 300
        
    } catch {
        Write-Host "  Error analyzing $($file.Name): $($_.Exception.Message)" -ForegroundColor Red
        
        $riskResults += [PSCustomObject]@{
            FileName = $file.Name
            FilePath = $file.FullName
            FileSize = $file.Length
            RiskLevel = "ERROR"
            SecurityIssues = "Analysis failed"
            QualityIssues = "Analysis failed"
            BestPracticeViolations = "Analysis failed"
            RawAnalysis = "Error: $($_.Exception.Message)"
        }
        continue
    }
}

# Generate summary statistics
$riskCounts = $riskResults | Group-Object -Property RiskLevel | Sort-Object Name
$criticalFiles = $riskResults | Where-Object { $_.RiskLevel -eq "CRITICAL" }
$highRiskFiles = $riskResults | Where-Object { $_.RiskLevel -eq "HIGH" }
$mediumRiskFiles = $riskResults | Where-Object { $_.RiskLevel -eq "MEDIUM" }

# Create comprehensive risk report
$riskReportPath = "$outputDir\risk_analysis_report_$timestamp.txt"
$riskReport = @"
FILE RISK ANALYSIS REPORT
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Input Path: $InputPath
Files Analyzed: $($riskResults.Count)

RISK LEVEL SUMMARY:
$(foreach ($group in $riskCounts) {
"- $($group.Name): $($group.Count) files"
})

CRITICAL RISK FILES:
$(if ($criticalFiles.Count -eq 0) {
"None found"
} else {
foreach ($file in $criticalFiles) {
"
FILE: $($file.FileName)
Security Issues: $($file.SecurityIssues)
Quality Issues: $($file.QualityIssues)
Best Practice Violations: $($file.BestPracticeViolations)
"
}
})

HIGH RISK FILES:
$(if ($highRiskFiles.Count -eq 0) {
"None found"
} else {
foreach ($file in $highRiskFiles) {
"
FILE: $($file.FileName)
Security Issues: $($file.SecurityIssues)
Quality Issues: $($file.QualityIssues)
Best Practice Violations: $($file.BestPracticeViolations)
"
}
})

MEDIUM RISK FILES:
$(if ($mediumRiskFiles.Count -eq 0) {
"None found"
} else {
foreach ($file in $mediumRiskFiles) {
"
FILE: $($file.FileName)
Security Issues: $($file.SecurityIssues)
Quality Issues: $($file.QualityIssues)
Best Practice Violations: $($file.BestPracticeViolations)
"
}
})

DETAILED ANALYSIS BY FILE:
$(foreach ($result in ($riskResults | Sort-Object RiskLevel -Descending)) {
"
========================================
FILE: $($result.FileName) [$($result.RiskLevel)]
Path: $($result.FilePath)
Size: $($result.FileSize) bytes

Security Issues: $($result.SecurityIssues)
Quality Issues: $($result.QualityIssues)
Best Practice Violations: $($result.BestPracticeViolations)
"
})

---
Generated by File Risk Analyzer
"@

$riskReport | Out-File -FilePath $riskReportPath -Encoding UTF8

# Create summary for clipboard and TTS
$summaryText = @"
Risk Analysis Summary: Analyzed $($riskResults.Count) files. 
$(if ($criticalFiles.Count -gt 0) { "Found $($criticalFiles.Count) critical risk files. " })
$(if ($highRiskFiles.Count -gt 0) { "Found $($highRiskFiles.Count) high risk files. " })
$(if ($mediumRiskFiles.Count -gt 0) { "Found $($mediumRiskFiles.Count) medium risk files. " })
Main concerns include security vulnerabilities, hardcoded credentials, poor code quality, and best practice violations.
"@

$summaryText | Set-Clipboard

Write-Host ""
Write-Host "FILE RISK ANALYSIS COMPLETE!"
Write-Host "Report saved to: $riskReportPath"
Write-Host "Summary copied to clipboard"
Write-Host ""
Write-Host "RISK SUMMARY:"
foreach ($group in $riskCounts) {
    $color = switch ($group.Name) {
        "CRITICAL" { "Red" }
        "HIGH" { "Yellow" }
        "MEDIUM" { "Cyan" }
        "LOW" { "Green" }
        default { "Gray" }
    }
    Write-Host "- $($group.Name): $($group.Count) files" -ForegroundColor $color
}

# Show top concerns if any high-risk files found
if ($criticalFiles.Count -gt 0 -or $highRiskFiles.Count -gt 0) {
    Write-Host ""
    Write-Host "TOP CONCERNS:" -ForegroundColor Red
    
    $topConcerns = @()
    $topConcerns += $criticalFiles | Select-Object -First 3
    $topConcerns += $highRiskFiles | Select-Object -First 3
    
    foreach ($concern in ($topConcerns | Select-Object -First 5)) {
        Write-Host "- $($concern.FileName): $($concern.SecurityIssues)" -ForegroundColor Yellow
    }
}

# Generate audio summary
Write-Host "`nGenerating audio summary..."
try {
    $ttsText = $summaryText
    
    $ttsBody = @{
        model = "kokoro"
        input = $ttsText
        voice = "af_sky"
        response_format = "mp3"
        speed = 1.0
        stream = $false
    } | ConvertTo-Json -Depth 3
    
    $audioPath = "$outputDir\risk_analysis_$timestamp.mp3"
    
    $ttsHeaders = @{
        'Content-Type' = 'application/json; charset=utf-8'
        'Accept' = 'audio/mpeg'
    }
    
    $ttsBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($ttsBody)
    $ttsResponse = Invoke-WebRequest -Uri "http://127.0.0.1:8880/v1/audio/speech" -Method POST -Body $ttsBodyBytes -Headers $ttsHeaders
    [System.IO.File]::WriteAllBytes($audioPath, $ttsResponse.Content)
    
    Start-Sleep 1
    Start-Process -FilePath "C:\Program Files\VideoLAN\VLC\vlc.exe" -ArgumentList "--intf dummy --play-and-exit `"$audioPath`"" -NoNewWindow -Wait
    
    Write-Host "Audio summary complete!"
    
} catch {
    Write-Host "TTS Error: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "Check the full report for detailed security and quality recommendations!"
