# Enhanced Visual Analysis - Context + Windows OCR + Scene Analysis + TTS
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$screenshotPath = ".\outputs\screenshot_$timestamp.png"

# Ensure directory exists
if (!(Test-Path ".\outputs")) {
    New-Item -ItemType Directory -Path ".\outputs" -Force
}

Write-Host "Screenshot capture in 5 seconds..."
Start-Sleep -Seconds 1
Write-Host "4..."
Start-Sleep -Seconds 1
Write-Host "3..."
Start-Sleep -Seconds 1
Write-Host "2..."
Start-Sleep -Seconds 1
Write-Host "1..."
Start-Sleep -Seconds 1
Write-Host "0 - Capturing screenshot now!"

Write-Host "Starting enhanced visual analysis..."

# CONTEXT GATHERING PHASE
Write-Host "Gathering system context..."

# Get active window information
Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    using System.Text;
    public class Win32 {
        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")]
        public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    }
"@

try {
    $hwnd = [Win32]::GetForegroundWindow()
    $windowTitle = New-Object System.Text.StringBuilder(256)
    [Win32]::GetWindowText($hwnd, $windowTitle, 256)
    $processId = 0
    [Win32]::GetWindowThreadProcessId($hwnd, [ref]$processId)
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    
    $activeWindow = $windowTitle.ToString()
    $activeProcess = if ($process) { $process.ProcessName } else { "Unknown" }
    
    Write-Host "Active window: $activeWindow ($activeProcess)"
} catch {
    $activeWindow = "Unable to detect"
    $activeProcess = "Unknown"
    Write-Host "Could not get active window info: $($_.Exception.Message)"
}

# Get current time context
$currentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss (dddd)"

# Capture screenshot using .NET
Write-Host "Capturing screenshot..."
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
$bitmap.Save($screenshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()

Write-Host "Screenshot captured: $screenshotPath"

# WINDOWS OCR PHASE
Write-Host "Running Windows OCR on screenshot..."
try {
    # Load Windows Runtime assemblies
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    
    # Load WinRT types
    $null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
    $null = [Windows.Media.Ocr.OcrEngine, Windows.Media.Ocr, ContentType = WindowsRuntime]
    $null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
    $null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
    
    # Helper function for async operations
    $AsTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' }[0]
    
    # Create OCR engine
    $ocrEngine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
    
    if ($ocrEngine) {
        Write-Host "OCR Engine created successfully"
        
        # Load image file
        $getFileTask = [Windows.Storage.StorageFile]::GetFileFromPathAsync($screenshotPath)
        $storageFile = $AsTask.MakeGenericMethod([Windows.Storage.StorageFile]).Invoke($null, @($getFileTask)).Result
        
        # Open file stream
        $openTask = $storageFile.OpenAsync([Windows.Storage.FileAccessMode]::Read)
        $stream = $AsTask.MakeGenericMethod([Windows.Storage.Streams.IRandomAccessStream]).Invoke($null, @($openTask)).Result
        
        # Create bitmap decoder
        $decoderTask = [Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)
        $decoder = $AsTask.MakeGenericMethod([Windows.Graphics.Imaging.BitmapDecoder]).Invoke($null, @($decoderTask)).Result
        
        # Get software bitmap
        $bitmapTask = $decoder.GetSoftwareBitmapAsync()
        $softwareBitmap = $AsTask.MakeGenericMethod([Windows.Graphics.Imaging.SoftwareBitmap]).Invoke($null, @($bitmapTask)).Result
        
        # Perform OCR
        $ocrTask = $ocrEngine.RecognizeAsync($softwareBitmap)
        $ocrResult = $AsTask.MakeGenericMethod([Windows.Media.Ocr.OcrResult]).Invoke($null, @($ocrTask)).Result
        
        # Extract text
        $extractedText = $ocrResult.Text
        if ([string]::IsNullOrWhiteSpace($extractedText)) {
            $extractedText = "No text detected by Windows OCR"
        }
        
        Write-Host "Windows OCR completed - extracted $($extractedText.Length) characters"
        
        # Clean up
        $stream.Dispose()
        $softwareBitmap.Dispose()
        
    } else {
        throw "Could not create OCR engine - language pack may not be installed"
    }
    
} catch {
    Write-Host "Windows OCR failed: $($_.Exception.Message)"
    Write-Host "Falling back to vision model for text extraction"
    $extractedText = "Windows OCR unavailable - will rely on vision model for text"
}

# Convert image to base64 for API
$imageBytes = [System.IO.File]::ReadAllBytes($screenshotPath)
$base64Image = [System.Convert]::ToBase64String($imageBytes)

# CONTEXTUAL SCENE ANALYSIS
Write-Host "Performing contextual scene analysis..."

# Build comprehensive context prompt
$contextPrompt = @"
SYSTEM CONTEXT:
- Active Window: "$activeWindow" (Process: $activeProcess)

EXTRACTED TEXT (Windows OCR):
$extractedText

TASK: Analyze this screenshot with the above context. Focus on the content on the screen, the active application, and any relevant text. Avoid speculation about the user's intent or actions.
"@

try {
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
        max_tokens = 2500
        temperature = 0.2
    } | ConvertTo-Json -Depth 5
    
    $headers = @{
        'Content-Type' = 'application/json; charset=utf-8'
    }
    
    $analysisBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($analysisBody)
    $analysisResponse = Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/chat/completions" -Method POST -Body $analysisBodyBytes -Headers $headers
    $analysisData = $analysisResponse.Content | ConvertFrom-Json
    $fullAnalysis = $analysisData.choices[0].message.content
    
    Write-Host "Contextual analysis complete"
    
} catch {
    Write-Host "Error in contextual analysis: $($_.Exception.Message)"
    $fullAnalysis = "Unable to perform contextual analysis"
}

# SUMMARY GENERATION
Write-Host "Generating final summary..."
try {
    # Create clean summary optimized for TTS
    $summaryPrompt = "Create a concise, natural summary suitable for text-to-speech. ONLY output the final summary text. Focus on the key points from this analysis. Use simple, spoken English without special characters or complex formatting:`n`n$fullAnalysis"
    
    $summaryBody = @{
        model = "gemma-3-4b-it-qat"
        messages = @(
            @{
                role = "user"
                content = $summaryPrompt
            }
        )
        max_tokens = 800
        temperature = 0.2
    } | ConvertTo-Json -Depth 3
    
    $summaryBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($summaryBody)
    $summaryResponse = Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/chat/completions" -Method POST -Body $summaryBodyBytes -Headers $headers
    $summaryData = $summaryResponse.Content | ConvertFrom-Json
    $finalSummary = $summaryData.choices[0].message.content
    
} catch {
    Write-Host "Error generating summary: $($_.Exception.Message)"
    $finalSummary = $fullAnalysis
}

# Save all outputs
$contextPath = ".\outputs\context_$timestamp.txt"
$ocrPath = ".\outputs\ocr_$timestamp.txt"
$analysisPath = ".\outputs\analysis_$timestamp.txt"
$summaryPath = ".\outputs\summary_$timestamp.txt"

@"
CONTEXT INFORMATION - $currentTime
Active Window: $activeWindow ($activeProcess)
Clipboard: $clipboardPreview
"@ | Out-File -FilePath $contextPath -Encoding UTF8

$extractedText | Out-File -FilePath $ocrPath -Encoding UTF8
$fullAnalysis | Out-File -FilePath $analysisPath -Encoding UTF8
$finalSummary | Out-File -FilePath $summaryPath -Encoding UTF8

# Copy summary to clipboard
$finalSummary | Set-Clipboard

Write-Host "Analysis saved and copied to clipboard"
Write-Host "Summary: $finalSummary"

# TTS GENERATION AND PLAYBACK
Write-Host "Generating and playing audio summary..."
try {
    $ttsText = if ($finalSummary.Length -gt 2000) { $finalSummary.Substring(0, 2000) + "..." } else { $finalSummary }
    
    $ttsBody = @{
        model = "kokoro"
        input = $ttsText
        voice = "af_sky"
        response_format = "mp3"
        speed = 1.0
        stream = $false
    } | ConvertTo-Json -Depth 3
    
    $audioPath = ".\outputs\latest_enhanced_analysis.mp3"
    
    $ttsHeaders = @{
        'Content-Type' = 'application/json; charset=utf-8'
        'Accept' = 'audio/mpeg'
    }
    
    $ttsBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($ttsBody)
    $ttsResponse = Invoke-WebRequest -Uri "http://127.0.0.1:8880/v1/audio/speech" -Method POST -Body $ttsBodyBytes -Headers $ttsHeaders
    [System.IO.File]::WriteAllBytes($audioPath, $ttsResponse.Content)
    
    Start-Sleep 1
    Start-Process -FilePath "C:\Program Files\VideoLAN\VLC\vlc.exe" -ArgumentList "--intf dummy --play-and-exit `"$audioPath`"" -NoNewWindow -Wait
    
    Write-Host "Audio analysis complete!"
    
} catch {
    Write-Host "TTS Error: $($_.Exception.Message)"
}

Write-Host "`nEnhanced Visual Analysis Complete!"
Write-Host "Generated files:"
Write-Host "- Screenshot: $screenshotPath"
Write-Host "- Context: $contextPath" 
Write-Host "- OCR Text: $ocrPath"
Write-Host "- Full Analysis: $analysisPath"
Write-Host "- Summary: $summaryPath"
Write-Host "- Audio: $audioPath"
