# Comprehensive Visual Analysis - Scene + Text + Summary + TTS
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$screenshotPath = "%appdata%\Local\Powertoys\screenshot_$timestamp.png"

# Ensure directory exists
if (!(Test-Path "%appdata%\Local\Powertoys")) {
    New-Item -ItemType Directory -Path "%appdata%\Local\Powertoys" -Force
}

# Capture screenshot using .NET
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
$bitmap.Save($screenshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()

# Convert image to base64
$imageBytes = [System.IO.File]::ReadAllBytes($screenshotPath)
$base64Image = [System.Convert]::ToBase64String($imageBytes)

Write-Host "Screenshot captured: $screenshotPath"

# PHASE 1: Scene Description
try {
    Write-Host "Phase 1: Analyzing scene content..."
    
    $sceneBody = @{
        model = "gemma-3-12b-it-qat"
        messages = @(
            @{
                role = "user"
                content = @(
                    @{
                        type = "text"
                        text = "Describe the overall content and context of this screenshot. What type of application or website is this? What is the main subject or activity? Focus on the visual layout, interface elements, and general purpose. Keep it concise."
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
        max_tokens = 1000
        temperature = 0.4
    } | ConvertTo-Json -Depth 5
    
    $headers = @{
        'Content-Type' = 'application/json; charset=utf-8'
    }
    
    $sceneBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($sceneBody)
    $sceneResponse = Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/chat/completions" -Method POST -Body $sceneBodyBytes -Headers $headers
    $sceneData = $sceneResponse.Content | ConvertFrom-Json
    $sceneDescription = $sceneData.choices[0].message.content
    
    Write-Host "Scene analysis complete"
    
} catch {
    Write-Host "Error in scene analysis: $($_.Exception.Message)"
    $sceneDescription = "Unable to analyze scene content"
}

# PHASE 2: Text Extraction
try {
    Write-Host "Phase 2: Extracting visible text..."
    
    $ocrBody = @{
        model = "gemma-3-12b-it-qat"
        messages = @(
            @{
                role = "user"
                content = @(
                    @{
                        type = "text"
                        text = "Extract all visible text from this image. Include headings, paragraphs, buttons, labels, and any other readable text. Flatten as necessary but keep structure and order if possible. If there's minimal text, just state what you can see."
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
        max_tokens = 1000
        temperature = 0.1
    } | ConvertTo-Json -Depth 5
    
    $ocrBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($ocrBody)
    $ocrResponse = Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/chat/completions" -Method POST -Body $ocrBodyBytes -Headers $headers
    $ocrData = $ocrResponse.Content | ConvertFrom-Json
    $extractedText = $ocrData.choices[0].message.content
    
    Write-Host "Text extraction complete"
    
} catch {
    Write-Host "Error in text extraction: $($_.Exception.Message)"
    $extractedText = "Unable to extract text content"
}

# Save individual analyses
$scenePathOutput = "%appdata%\Local\Powertoys\scene_analysis_$timestamp.txt"
$ocrPathOutput = "%appdata%\Local\Powertoys\text_extraction_$timestamp.txt"

$sceneDescription | Out-File -FilePath $scenePathOutput -Encoding UTF8
$extractedText | Out-File -FilePath $ocrPathOutput -Encoding UTF8

Write-Host "Individual analyses saved"

# PHASE 3: Comprehensive Summary
try {
    Write-Host "Phase 3: Creating comprehensive summary..."
    
    # Combine both analyses for summarization
    $combinedAnalysis = "SCENE CONTEXT: $sceneDescription`n`nTEXT CONTENT: $extractedText"
    
    # Clean and prepare for summarization
    $cleanAnalysis = $combinedAnalysis -replace '[\x00-\x1F\x7F]', ' '
    $cleanAnalysis = $cleanAnalysis -replace '\\', '\\'
    $cleanAnalysis = $cleanAnalysis -replace '"', '\"'
    $cleanAnalysis = $cleanAnalysis -replace "`t", ' '
    $cleanAnalysis = $cleanAnalysis -replace "`r`n", ' '
    $cleanAnalysis = $cleanAnalysis -replace "`n", ' '
    $cleanAnalysis = $cleanAnalysis -replace '\s+', ' '
    $cleanAnalysis = $cleanAnalysis.Trim()
    
    # Truncate if needed
    $maxInputLength = 6000
    if ($cleanAnalysis.Length -gt $maxInputLength) {
        $cleanAnalysis = $cleanAnalysis.Substring(0, $maxInputLength) + "... [analysis truncated]"
    }
    
    $summaryBody = @{
        model = "gemma-3-12b-it-qat"
        messages = @(
            @{
                role = "user"
                content = "Concisely summarize this text. Focus on key points and main ideas. Optimize for text-to-speech delivery, no special characters (correct spoken english only), keep it brief and clear:`n`n$cleanAnalysis"
            }
        )
        max_tokens = 1000
        temperature = 0.2
    } | ConvertTo-Json -Depth 5
    
    $summaryBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($summaryBody)
    $summaryResponse = Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/chat/completions" -Method POST -Body $summaryBodyBytes -Headers $headers
    $summaryData = $summaryResponse.Content | ConvertFrom-Json
    $finalSummary = $summaryData.choices[0].message.content
    
    # Save final summary and copy to clipboard
    $summaryPathOutput = "%appdata%\Local\Powertoys\visual_summary_$timestamp.txt"
    $finalSummary | Out-File -FilePath $summaryPathOutput -Encoding UTF8
    $finalSummary | Set-Clipboard
    
    Write-Host "Summary saved to: $summaryPathOutput"
    Write-Host "Summary copied to clipboard"
    Write-Host "Final Summary: $finalSummary"
    
} catch {
    Write-Host "Error in summarization: $($_.Exception.Message)"
    $finalSummary = "Unable to create comprehensive summary"
}

# PHASE 4: Generate and Play TTS
try {
    Write-Host "Phase 4: Generating audio summary..."
    
    # Prepare text for TTS
    $ttsText = if ($finalSummary.Length -gt 2000) { $finalSummary.Substring(0, 2000) + "..." } else { $finalSummary }
    
    $ttsBody = @{
        model = "kokoro"
        input = $ttsText
        voice = "af_sky"
        response_format = "mp3"
        speed = 1.0
        stream = $false
    } | ConvertTo-Json -Depth 3
    
    $audioPath = "%appdata%\Local\Powertoys\latest_visual_analysis.mp3"
    
    # Call TTS API
    $ttsHeaders = @{
        'Content-Type' = 'application/json; charset=utf-8'
        'Accept' = 'audio/mpeg'
    }
    
    $ttsBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($ttsBody)
    $ttsResponse = Invoke-WebRequest -Uri "http://127.0.0.1:8880/v1/audio/speech" -Method POST -Body $ttsBodyBytes -Headers $ttsHeaders
    [System.IO.File]::WriteAllBytes($audioPath, $ttsResponse.Content)
    
    Write-Host "Audio generated and saved to: $audioPath"

    Start-Sleep 2
    
    # Play the audio using headless VLC
    Start-Process -FilePath "C:\Program Files\VideoLAN\VLC\vlc.exe" -ArgumentList "--intf dummy --play-and-exit `"$audioPath`"" -NoNewWindow -Wait
    
    Write-Host "Playing comprehensive visual analysis..."
    
} catch {
    Write-Host "Error generating or playing TTS: $($_.Exception.Message)"
}

Write-Host "Visual analysis complete!"
Write-Host "Files generated:"
Write-Host "- Screenshot: $screenshotPath"
Write-Host "- Scene Analysis: $scenePathOutput"
Write-Host "- Text Extraction: $ocrPathOutput"
Write-Host "- Final Summary: $summaryPathOutput"
Write-Host "- Audio: $audioPath"
