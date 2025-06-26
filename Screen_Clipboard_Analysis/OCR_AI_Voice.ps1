# Capture screenshot and extract text using LMStudio vision model
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

# API request body for OCR
$body = @{
    model = "gemma-3-4b-it-qat"
    messages = @(
        @{
            role = "user"
            content = @(
                @{
                    type = "text"
                    text = "Extract and read all visible text from this image. Maintain the original structure and formatting where possible. Only output the text, without acknowledgement or post output note. Include headings, paragraphs, lists, and any other text content. Present it clearly for text-to-speech reading. If there are multiple columns or sections, read from left to right, top to bottom."
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
    temperature = 0.0
} | ConvertTo-Json -Depth 5

# Send to LMStudio API
try {
    $headers = @{
        'Content-Type' = 'application/json; charset=utf-8'
    }
    
    # Convert body to UTF8 bytes to ensure proper encoding
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    
    Write-Host "Extracting text from screenshot..."
    $response = Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/chat/completions" -Method POST -Body $bodyBytes -Headers $headers
    $responseData = $response.Content | ConvertFrom-Json
    $extractedText = $responseData.choices[0].message.content
    
    # Save extracted text to file
    $ocrPath = "%appdata%\Local\Powertoys\ocr_text_$timestamp.txt"
    $extractedText | Out-File -FilePath $ocrPath -Encoding UTF8
    
    # Copy extracted text to clipboard
    $extractedText | Set-Clipboard
    
    Write-Host "Screenshot saved to: $screenshotPath"
    Write-Host "Extracted text saved to: $ocrPath"
    Write-Host "Text copied to clipboard"
    Write-Host "Extracted text: $extractedText"
    
    # Pass extracted text to clipboard summarizer
    try {
        Write-Host "Passing extracted text to summarizer..."
        
        # Clean and sanitize the extracted text for summarization
        $cleanText = $extractedText -replace '[\x00-\x1F\x7F]', ' '  # Remove control characters
        $cleanText = $cleanText -replace '\\', '\\'                  # Escape backslashes
        $cleanText = $cleanText -replace '"', '\"'                   # Escape quotes
        $cleanText = $cleanText -replace "`t", ' '                   # Replace tabs with spaces
        $cleanText = $cleanText -replace "`r`n", ' '                 # Replace CRLF with space
        $cleanText = $cleanText -replace "`n", ' '                   # Replace LF with space
        $cleanText = $cleanText -replace '\s+', ' '                  # Collapse multiple spaces
        $cleanText = $cleanText.Trim()
        
        # Truncate if too long for summarization
        $maxInputLength = 8000
        if ($cleanText.Length -gt $maxInputLength) {
            $cleanText = $cleanText.Substring(0, $maxInputLength) + "... [text truncated]"
            Write-Host "Text truncated to $maxInputLength characters for summarization"
        }
        
        # API request body for summarization
        $summaryBody = @{
            model = "gemma-3-4b-it-qat"
            messages = @(
                @{
                    role = "user"
                    content = "Concisely summarize this extracted text. Focus on key points and main ideas. Optimize for text-to-speech delivery, avoid special characters, keep it brief and clear:`n`n$cleanText"
                }
            )
            max_tokens = 400
            temperature = 0.3
        } | ConvertTo-Json -Depth 5
        
        # Send summarization request
        $summaryBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($summaryBody)
        $summaryResponse = Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/chat/completions" -Method POST -Body $summaryBodyBytes -Headers $headers
        $summaryData = $summaryResponse.Content | ConvertFrom-Json
        $summary = $summaryData.choices[0].message.content
        
        # Save summary and update clipboard
        $summaryPath = "%appdata%\Local\Powertoys\ocr_summary_$timestamp.txt"
        $summary | Out-File -FilePath $summaryPath -Encoding UTF8
        $summary | Set-Clipboard
        
        Write-Host "Summary saved to: $summaryPath"
        Write-Host "Summary copied to clipboard"
        Write-Host "Summary: $summary"
    
        # Generate TTS audio from summary using FastKokoro API
        $ttsText = if ($summary.Length -gt 1000) { $summary.Substring(0, 1000) + "..." } else { $summary }
        
        $ttsBody = @{
            model = "kokoro"
            input = $ttsText
            voice = "af_sky"
            response_format = "mp3"
            speed = 1.0
            stream = $false
        } | ConvertTo-Json -Depth 3
        
        $audioPath = "%appdata%\Local\Powertoys\latest_ocr_summary.mp3"
        
        # Call TTS API with proper headers and encoding
        $ttsHeaders = @{
            'Content-Type' = 'application/json; charset=utf-8'
            'Accept' = 'audio/mpeg'
        }
        
        # Convert body to UTF8 bytes to ensure proper encoding
        $ttsBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($ttsBody)
        
        $ttsResponse = Invoke-WebRequest -Uri "http://127.0.0.1:8880/v1/audio/speech" -Method POST -Body $ttsBodyBytes -Headers $ttsHeaders
        [System.IO.File]::WriteAllBytes($audioPath, $ttsResponse.Content)
        
        Write-Host "Audio generated and saved to: $audioPath"

        Start-Sleep 2
        
        # Play the audio using headless VLC
        Start-Process -FilePath "C:\Program Files\VideoLAN\VLC\vlc.exe" -ArgumentList "--intf dummy --play-and-exit `"$audioPath`"" -NoNewWindow -Wait
        
        Write-Host "Playing summary audio with VLC..."
        
    } catch {
        Write-Host "Error in summarization process: $($_.Exception.Message)"
    }
    
} catch {
    Write-Host "Error calling vision API: $($_.Exception.Message)"
}
