# Activity Chronicler - Process multiple screenshot descriptions into timeline summary
param(
    [string]$InputFolder = "outputs",
    [string]$FilePattern = "description_*.txt",
    [int]$MaxFiles = 50,
    [switch]$TodayOnly
)

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# Ensure output directory exists
if (!(Test-Path $InputFolder)) {
    Write-Host "Input folder does not exist: $InputFolder"
    exit
}

# Get description files, optionally filtered by today's date
try {
    if ($TodayOnly) {
        $todayPattern = "description_$(Get-Date -Format 'yyyyMMdd')_*.txt"
        $descriptionFiles = Get-ChildItem -Path $InputFolder -Name $todayPattern | Sort-Object Name
        Write-Host "Processing today's files with pattern: $todayPattern"
    } else {
        $descriptionFiles = Get-ChildItem -Path $InputFolder -Name $FilePattern | Sort-Object Name
        Write-Host "Processing files with pattern: $FilePattern"
    }
    
    if ($descriptionFiles.Count -eq 0) {
        Write-Host "No description files found matching pattern"
        exit
    }
    
    # Limit number of files if specified
    if ($MaxFiles -gt 0 -and $descriptionFiles.Count -gt $MaxFiles) {
        $descriptionFiles = $descriptionFiles | Select-Object -Last $MaxFiles
        Write-Host "Limited to most recent $MaxFiles files"
    }
    
    Write-Host "Found $($descriptionFiles.Count) description files to process"
    
} catch {
    Write-Host "Error finding description files: $($_.Exception.Message)"
    exit
}

# Process each file and create individual summaries
$activities = @()
$processedCount = 0

foreach ($file in $descriptionFiles) {
    try {
        $filePath = Join-Path $InputFolder $file
        $content = Get-Content -Path $filePath -Raw -Encoding UTF8
        
        # Extract timestamp from filename (format: description_YYYYMMDD_HHMMSS.txt)
        if ($file -match "description_(\d{8})_(\d{6})\.txt") {
            $dateStr = $matches[1]
            $timeStr = $matches[2]
            $fileDateTime = [DateTime]::ParseExact("$dateStr$timeStr", "yyyyMMddHHmmss", $null)
            $timeDisplay = $fileDateTime.ToString("HH:mm")
        } else {
            $timeDisplay = "Unknown"
        }
        
        # Skip if content is too short or empty
        if ([string]::IsNullOrWhiteSpace($content) -or $content.Length -lt 20) {
            continue
        }
        
        # Clean content for API processing
        $cleanContent = $content -replace '[\x00-\x1F\x7F]', ' '
        $cleanContent = $cleanContent -replace '\\', '\\'
        $cleanContent = $cleanContent -replace '"', '\"'
        $cleanContent = $cleanContent -replace "`t", ' '
        $cleanContent = $cleanContent -replace "`r`n", ' '
        $cleanContent = $cleanContent -replace "`n", ' '
        $cleanContent = $cleanContent -replace '\s+', ' '
        $cleanContent = $cleanContent.Trim()
        
        # Truncate if too long
        if ($cleanContent.Length -gt 1000) {
            $cleanContent = $cleanContent.Substring(0, 1000) + "..."
        }
        
        # Generate summary for this activity
        $summaryBody = @{
            model = "gemma-3-4b-it-qat"
            messages = @(
                @{
                    role = "user"
                    content = "Summarize this activity in 1-2 concise sentences. Focus on what the user was doing or viewing. Be specific about applications, content, or tasks:`n`n$cleanContent"
                }
            )
            max_tokens = 100
            temperature = 0.2
        } | ConvertTo-Json -Depth 5
        
        $headers = @{
            'Content-Type' = 'application/json; charset=utf-8'
        }
        
        $summaryBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($summaryBody)
        $summaryResponse = Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/chat/completions" -Method POST -Body $summaryBodyBytes -Headers $headers
        $summaryData = $summaryResponse.Content | ConvertFrom-Json
        $activitySummary = $summaryData.choices[0].message.content
        
        # Add to activities collection
        $activities += [PSCustomObject]@{
            Time = $timeDisplay
            DateTime = $fileDateTime
            Summary = $activitySummary.Trim()
            FileName = $file
        }
        
        $processedCount++
        Write-Host "[$processedCount/$($descriptionFiles.Count)] $timeDisplay - Processed"
        
        # Small delay to avoid overwhelming the API
        Start-Sleep -Milliseconds 500
        
    } catch {
        Write-Host "Error processing $file`: $($_.Exception.Message)"
        continue
    }
}

# Generate final chronicle summary
try {
    Write-Host "Creating comprehensive chronicle..."
    
    # Build timeline text
    $timelineText = ""
    foreach ($activity in $activities | Sort-Object DateTime) {
        $timelineText += "$($activity.Time): $($activity.Summary)`n"
    }
    
    # Create meta-summary of the entire session
    $chronicleBody = @{
        model = "gemma-3-4b-it-qat"
        messages = @(
            @{
                role = "user"
                content = "Create a brief overview of this user activity timeline. Identify main themes, productivity patterns, or notable activities. Keep it concise and insightful:`n`n$timelineText"
            }
        )
        max_tokens = 200
        temperature = 0.3
    } | ConvertTo-Json -Depth 5
    
    $chronicleBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($chronicleBody)
    $chronicleResponse = Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/chat/completions" -Method POST -Body $chronicleBodyBytes -Headers $headers
    $chronicleData = $chronicleResponse.Content | ConvertFrom-Json
    $overallSummary = $chronicleData.choices[0].message.content
    
} catch {
    Write-Host "Error creating chronicle summary: $($_.Exception.Message)"
    $overallSummary = "Unable to generate overview summary"
}

# Create final chronicle document
$chroniclePath = "$InputFolder\chronicle_$timestamp.txt"
$chronicleContent = @"
ACTIVITY CHRONICLE - $(Get-Date -Format "yyyy-MM-dd HH:mm")
Generated from $($activities.Count) activities

OVERVIEW:
$overallSummary

TIMELINE:
$timelineText

---
Files processed: $($activities.Count)
Source folder: $InputFolder
Generated: $(Get-Date)
"@

$chronicleContent | Out-File -FilePath $chroniclePath -Encoding UTF8

# Copy timeline to clipboard for easy sharing
$timelineText | Set-Clipboard

Write-Host ""
Write-Host "Chronicle complete!"
Write-Host "Processed: $($activities.Count) activities"
Write-Host "Chronicle saved to: $chroniclePath"
Write-Host "Timeline copied to clipboard"
Write-Host ""
Write-Host "OVERVIEW:"
Write-Host $overallSummary
Write-Host ""
Write-Host "RECENT ACTIVITIES:"
$activities | Sort-Object DateTime | Select-Object -Last 5 | ForEach-Object {
    Write-Host "$($_.Time): $($_.Summary)"
}
