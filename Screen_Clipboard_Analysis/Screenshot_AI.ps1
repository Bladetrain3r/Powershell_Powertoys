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
                    text = "Describe what you see in this screenshot. Focus on the main content, any text visible, and what the user might be working on. Avoid superfluous language."
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
    max_tokens = 300
    temperature = 0.5
} | ConvertTo-Json -Depth 5

# Send to LMStudio API
try {
    $response = Invoke-RestMethod -Uri "http://127.0.0.1:1234/v1/chat/completions" -Method POST -Body $body -ContentType "application/json"
    $description = $response.choices[0].message.content
    
    # Save description to file
    $descriptionPath = "%appdata%\Local\Powertoys\description_$timestamp.txt"
    $description | Out-File -FilePath $descriptionPath -Encoding UTF8
    
    # Optional: Copy description to clipboard
    $description | Set-Clipboard
    
    Write-Host "Screenshot analyzed and saved to: $screenshotPath"
    Write-Host "Description saved to: $descriptionPath"
    Write-Host "Description copied to clipboard"
    
} catch {
    Write-Host "Error calling API: $($_.Exception.Message)"
}
