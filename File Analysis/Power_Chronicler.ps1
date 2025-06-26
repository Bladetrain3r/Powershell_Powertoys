# Enhanced Activity Chronicler - Process screenshots directly with OCR and analysis
param(
    [string]$InputFolder = "outputs",
    [string]$FilePattern = "screenshot_*.png",
    [int]$MaxFiles = 30,
    [switch]$TodayOnly,
    [switch]$SkipExisting  # Skip screenshots that already have description files
)

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# Ensure output directory exists
if (!(Test-Path $InputFolder)) {
    Write-Host "Input folder does not exist: $InputFolder"
    exit
}

Write-Host "Starting Enhanced Activity Chronicler..."

# Load Windows OCR components
try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
    $null = [Windows.Media.Ocr.OcrEngine, Windows.Media.Ocr, ContentType = WindowsRuntime]
    $null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
    $null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
    
    $AsTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' }[0]
    $ocrEngine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
    
    $ocrAvailable = $ocrEngine -ne $null
    Write-Host "Windows OCR: $(if($ocrAvailable){'Available'}else{'Unavailable'})"
} catch {
    $ocrAvailable = $false
    Write-Host "Windows OCR initialization failed: $($_.Exception.Message)"
}

# Get screenshot files, optionally filtered by today's date
try {
    if ($TodayOnly) {
        $todayPattern = "screenshot_$(Get-Date -Format 'yyyyMMdd')_*.png"
        $screenshotFiles = Get-ChildItem -Path $InputFolder -Name $todayPattern | Sort-Object Name
        Write-Host "Processing today's files with pattern: $todayPattern"
    } else {
        $screenshotFiles = Get-ChildItem -Path $InputFolder -Name $FilePattern | Sort-Object Name
        Write-Host "Processing files with pattern: $FilePattern"
    }
    
    if ($screenshotFiles.Count -eq 0) {
        Write-Host "No screenshot files found matching pattern"
        exit
    }
    
    # Filter out screenshots that already have descriptions if requested
    if ($SkipExisting) {
        $filteredFiles = @()
        foreach ($file in $screenshotFiles) {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file)
            $descFile = $baseName -replace '^screenshot_', 'description_'
            $descPath = Join-Path $InputFolder "$descFile.txt"
            if (!(Test-Path $descPath)) {
                $filteredFiles += $file
            }
        }
        $screenshotFiles = $filteredFiles
        Write-Host "After filtering existing: $($screenshotFiles.Count) files to process"
    }
    
    # Limit number of files if specified
    if ($MaxFiles -gt 0 -and $screenshotFiles.Count -gt $MaxFiles) {
        $screenshotFiles = $screenshotFiles | Select-Object -Last $MaxFiles
        Write-Host "Limited to most recent $MaxFiles files"
    }
    
    Write-Host "Found $($screenshotFiles.Count) screenshot files to process"
    
} catch {
    Write-Host "Error finding screenshot files: $($_.Exception.Message)"
    exit
}

# Function to perform OCR on a screenshot
function Get-ScreenshotOCR {
    param([string]$ImagePath)
    
    if (!$ocrAvailable) {
        return "Windows OCR not available"
    }
    
    try {
        $getFileTask = [Windows.Storage.StorageFile]::GetFileFromPathAsync($ImagePath)
        $storageFile = $AsTask.MakeGenericMethod([Windows.Storage.StorageFile]).Invoke($null, @($getFileTask)).Result
        
        $openTask = $storageFile.OpenAsync([Windows.Storage.FileAccessMode]::Read)
        $stream = $AsTask.MakeGenericMethod([Windows.Storage.Streams.IRandomAccessStream]).Invoke($null, @($openTask)).Result
        
        $decoderTask = [Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)
        $decoder = $AsTask.MakeGenericMethod([Windows.Graphics.Imaging.BitmapDecoder]).Invoke($null, @($decoderTask)).Result
        
        $bitmapTask = $decoder.GetSoftwareBitmapAsync()
        $softwareBitmap = $AsTask.MakeGenericMethod([Windows.Graphics.Imaging.SoftwareBitmap]).Invoke($null, @($bitmapTask)).Result
        
        $ocrTask = $ocrEngine.RecognizeAsync($softwareBitmap)
        $ocrResult = $AsTask.MakeGenericMethod([Windows.Media.Ocr.OcrResult]).Invoke($null, @($ocrTask)).Result
        
        $extractedText = $ocrResult.Text
        
        $stream.Dispose()
        $softwareBitmap.Dispose()
        
        return if ([string]::IsNullOrWhiteSpace($extractedText)) { "No text detected" } else { $extractedText }
        
    } catch {
        return "OCR failed: $($_.Exception.Message)"
    }
}

# Function to analyze screenshot with vision model
function Get-ScreenshotAnalysis {
    param([string]$ImagePath, [string]$OcrText)
    
    try {
        # Convert image to base64
        $imageBytes = [System.IO.File]::ReadAllBytes($ImagePath)
        $base64Image = [System.Convert]::ToBase64String($imageBytes)
        
        # Build context prompt
        $contextPrompt = if ($OcrText -and $OcrText -ne "No text detected" -and $OcrText -ne "Windows OCR not available") {
            @"
EXTRACTED TEXT (OCR):
$OcrText

TASK: Analyze this screenshot and describe the main activity, application, and content. Avoid speculation and focus on content over guessed activity.
"@
        } else {
            "Analyze this screenshot and describe the main application, and content. Be concise and specific."
        }
        
        $analysisBody = @{
            model = "gemma-3-4b-it-qat"
            messages = @(
                @{
                    role = "user"
                    content = @(
                        @{
                            type = "text"
                            text = $contextPrompt
                        },
                        @{
                            type = "image_url"
                            image_url = @{
                                url = "data:image/png;base64,$base64Image"
                            }
                        }
                    )
                }
            )
            max_tokens = 500
            temperature = 0.2
        } | ConvertTo-Json -Depth 5
        
        $headers = @{
            'Content-Type' = 'application/json; charset=utf-8'
        }
        
        $analysisBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($analysisBody)
        $analysisResponse = Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/chat/completions" -Method POST -Body $analysisBodyBytes -Headers $headers
        $analysisData = $analysisResponse.Content | ConvertFrom-Json
        
        return $analysisData.choices[0].message.content
        
    } catch {
        return "Vision analysis failed: $($_.Exception.Message)"
    }
}

# Process each screenshot file
$activities = @()
$processedCount = 0

foreach ($file in $screenshotFiles) {
    try {
        $filePath = Join-Path $InputFolder $file
        
        # Extract timestamp from filename (format: screenshot_YYYYMMDD_HHMMSS.png)
        if ($file -match "screenshot_(\d{8})_(\d{6})\.png") {
            $dateStr = $matches[1]
            $timeStr = $matches[2]
            $fileDateTime = [DateTime]::ParseExact("$dateStr$timeStr", "yyyyMMddHHmmss", $null)
            $timeDisplay = $fileDateTime.ToString("HH:mm")
        } else {
            $timeDisplay = "Unknown"
            $fileDateTime = Get-Date
        }
        
        Write-Host "[$($processedCount + 1)/$($screenshotFiles.Count)] Processing $file ($timeDisplay)..."
        
        # Perform OCR
        Write-Host "  Running OCR..."
        $ocrText = Get-ScreenshotOCR -ImagePath $filePath
        
        # Perform vision analysis
        Write-Host "  Running vision analysis..."
        $visionAnalysis = Get-ScreenshotAnalysis -ImagePath $filePath -OcrText $ocrText
        
        # Generate activity summary
        Write-Host "  Generating summary..."
        $combinedContent = "VISION: $visionAnalysis`nOCR: $ocrText"
        
        # Clean content for summarization
        $cleanContent = $combinedContent -replace '[\x00-\x1F\x7F]', ' '
        $cleanContent = $cleanContent -replace '\\', '\\'
        $cleanContent = $cleanContent -replace '"', '\"'
        $cleanContent = $cleanContent -replace "`t", ' '
        $cleanContent = $cleanContent -replace "`r`n", ' '
        $cleanContent = $cleanContent -replace "`n", ' '
        $cleanContent = $cleanContent -replace '\s+', ' '
        $cleanContent = $cleanContent.Trim()
        
        if ($cleanContent.Length -gt 1500) {
            $cleanContent = $cleanContent.Substring(0, 1500) + "..."
        }
        
        # Generate concise activity summary
        $summaryBody = @{
            model = "gemma-3-4b-it-qat"
            messages = @(
                @{
                    role = "user"
                    content = "Summarize this screenshot analysis in 1-2 concise sentences. Avoid speculation:`n`n$cleanContent"
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
        $activitySummary = $summaryData.choices[0].message.content.Trim()
        
        # Save individual analysis files
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file)
        $ocrFile = Join-Path $InputFolder "$baseName`_ocr.txt"
        $analysisFile = Join-Path $InputFolder "$baseName`_analysis.txt"
        $summaryFile = Join-Path $InputFolder "$baseName`_summary.txt"
        
        $ocrText | Out-File -FilePath $ocrFile -Encoding UTF8
        $visionAnalysis | Out-File -FilePath $analysisFile -Encoding UTF8
        $activitySummary | Out-File -FilePath $summaryFile -Encoding UTF8
        
        # Add to activities collection
        $activities += [PSCustomObject]@{
            Time = $timeDisplay
            DateTime = $fileDateTime
            Summary = $activitySummary
            FileName = $file
            OcrLength = $ocrText.Length
            Analysis = $visionAnalysis.Substring(0, [Math]::Min(100, $visionAnalysis.Length)) + "..."
        }
        
        $processedCount++
        Write-Host "  Complete: $activitySummary"
        
        # Small delay to avoid overwhelming the API
        Start-Sleep -Milliseconds 800
        
    } catch {
        Write-Host "Error processing $file`: $($_.Exception.Message)"
        continue
    }
}

# Generate final chronicle summary
try {
    Write-Host "`nCreating comprehensive chronicle..."
    
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
                content = "Create a brief overview of this user activity timeline. Identify main themes, productivity patterns, applications used, or notable activities. Keep it concise and insightful:`n`n$timelineText"
            }
        )
        max_tokens = 300
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
$chroniclePath = "$InputFolder\enhanced_chronicle_$timestamp.txt"
$chronicleContent = @"
ENHANCED ACTIVITY CHRONICLE - $(Get-Date -Format "yyyy-MM-dd HH:mm")
Generated from $($activities.Count) screenshot analyses (OCR + Vision)

OVERVIEW:
$overallSummary

DETAILED TIMELINE:
$timelineText

PROCESSING SUMMARY:
- Screenshots analyzed: $($activities.Count)
- OCR extractions: $($activities | Where-Object {$_.OcrLength -gt 20} | Measure-Object).Count
- Average analysis length: $([math]::Round(($activities | Measure-Object -Property {$_.Analysis.Length} -Average).Average)) chars
- Time span: $(($activities | Sort-Object DateTime | Select-Object -First 1).Time) - $(($activities | Sort-Object DateTime | Select-Object -Last 1).Time)

---
Source folder: $InputFolder
Generated: $(Get-Date)
"@

$chronicleContent | Out-File -FilePath $chroniclePath -Encoding UTF8

# Copy timeline to clipboard for easy sharing
$timelineText | Set-Clipboard

Write-Host ""
Write-Host "Enhanced Chronicle Complete!"
Write-Host "Processed: $($activities.Count) screenshots with full OCR + vision analysis"
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

# Generate and play summary if requested
Write-Host ""
Write-Host "Generating audio summary..."
try {
    $audioSummary = "Activity Chronicle Summary: $overallSummary"
    
    $ttsBody = @{
        model = "kokoro"
        input = $audioSummary
        voice = "af_sky"
        response_format = "mp3"
        speed = 1.0
        stream = $false
    } | ConvertTo-Json -Depth 3
    
    $audioPath = "$InputFolder\chronicle_summary_$timestamp.mp3"
    
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
