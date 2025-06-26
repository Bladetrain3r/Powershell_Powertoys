# Capture screenshot and send to LMStudio vision model
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

# API request body
$body = @{
    model = "gemma-3-4b-it-qat"  # Replace with your actual model name in LMStudio
    messages = @(
        @{
            role = "user"
            content = @(
                @{
                    type = "text"
                    text = "Concisely and briefly describe what you see in this screenshot. Focus on the main content, and large text. No special characters, optimise output for text to speech, keep it to the description only. Avoid counts."
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
    temperature = 0.15
} | ConvertTo-Json -Depth 5

# Send to LMStudio API
try {
    $headers = @{
        'Content-Type' = 'application/json'
    }
    
    $response = Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/chat/completions" -Method POST -Body $body -Headers $headers
    $responseData = $response.Content | ConvertFrom-Json
    $description = $responseData.choices[0].message.content
    
    # Save description to file
    $descriptionPath = "%appdata%\Local\Powertoys\description_$timestamp.txt"
    $description | Out-File -FilePath $descriptionPath -Encoding UTF8
    
    # Copy description to clipboard
    $description | Set-Clipboard
    
    Write-Host "Screenshot analyzed and saved to: $screenshotPath"
    Write-Host "Description saved to: $descriptionPath"
    Write-Host "Description copied to clipboard"
    
    # Generate TTS audio using FastKokoro API
    try {
        # Truncate description if too long for TTS
        $ttsText = if ($description.Length -gt 1000) { $description.Substring(0, 1000) + "..." } else { $description }
        
        $ttsBody = @{
            model = "kokoro"
            input = $ttsText
            voice = "af_sky"
            response_format = "mp3"
            speed = 1.0
            stream = $false
        } | ConvertTo-Json -Depth 3
        
        Write-Host "TTS Request Body: $ttsBody"
        
        $audioPath = "%appdata%\Local\Powertoys\latest_description.mp3"
        
        # Call TTS API with proper headers and encoding
        $headers = @{
            'Content-Type' = 'application/json; charset=utf-8'
            'Accept' = 'audio/mpeg'
        }
        
        # Convert body to UTF8 bytes to ensure proper encoding
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($ttsBody)
        
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:8880/v1/audio/speech" -Method POST -Body $bodyBytes -Headers $headers
        [System.IO.File]::WriteAllBytes($audioPath, $response.Content)
        
        Write-Host "Audio generated and saved to: $audioPath"

        Start-Sleep 3
        
        # Play the audio using headless VLC
        Start-Process -FilePath "C:\Program Files\VideoLAN\VLC\vlc.exe" -ArgumentList "--intf dummy --play-and-exit `"$audioPath`"" -NoNewWindow -Wait
        
        Write-Host "Playing audio description with VLC..."
        
    } catch {
        Write-Host "Error generating or playing TTS: $($_.Exception.Message)"
    }
    
} catch {
    Write-Host "Error calling vision API: $($_.Exception.Message)"
}
