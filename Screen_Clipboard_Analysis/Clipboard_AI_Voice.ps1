# Get clipboard content and summarize with LMStudio
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# Ensure directory exists
if (!(Test-Path "outputs\Clipboard")) {
    New-Item -ItemType Directory -Path "outputs\Clipboard" -Force
}

try {
    # Get clipboard content
    $clipboardText = Get-Clipboard -Raw
    
    # Check if clipboard is empty or null
    if ([string]::IsNullOrWhiteSpace($clipboardText)) {
        Write-Host "Clipboard is empty or contains no text. Exiting."
        exit
    }
    
    # Check if clipboard contains non-text data (basic check)
    if ($clipboardText -match '^\s*$') {
        Write-Host "Clipboard appears to contain non-text data. Exiting."
        exit
    }
    
    Write-Host "Processing clipboard text ($(($clipboardText.Length)) characters)..."
    
    # Clean and sanitize the text
    # Remove problematic characters that break JSON
    $cleanText = $clipboardText -replace '[\x00-\x1F\x7F]', ' '  # Remove control characters
    $cleanText = $cleanText -replace '\\', '\\'                  # Escape backslashes
    $cleanText = $cleanText -replace '"', '\"'                   # Escape quotes
    $cleanText = $cleanText -replace "`t", ' '                   # Replace tabs with spaces
    $cleanText = $cleanText -replace "`r`n", ' '                 # Replace CRLF with space
    $cleanText = $cleanText -replace "`n", ' '                   # Replace LF with space
    $cleanText = $cleanText -replace '\s+', ' '                  # Collapse multiple spaces
    $cleanText = $cleanText.Trim()
    
    # Truncate if too long (leaving room for prompt + JSON overhead)
    $maxInputLength = 16000  # Conservative limit for your model's context
    if ($cleanText.Length -gt $maxInputLength) {
        $cleanText = $cleanText.Substring(0, $maxInputLength) + "... [text truncated]"
        Write-Host "Text truncated to $maxInputLength characters for processing"
    }
    
    # API request body for summarization
    $body = @{
        model = "gemma-3-12b-it-qat"
        messages = @(
            @{
                role = "user"
                content = "Concisely summarize this text. Focus on key points and main ideas. Optimize for text-to-speech delivery, no special characters (correct spoken english only), keep it brief and clear:`n`n$cleanText /no_think"
            }
        )
        max_tokens = 1000
        temperature = 0.2
    } | ConvertTo-Json -Depth 5
    
    # Send to LMStudio API
    $headers = @{
        'Content-Type' = 'application/json; charset=utf-8'
    }
    
    # Convert body to UTF8 bytes to ensure proper encoding
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    
    Write-Host "Sending request to LMStudio..."
    $response = Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/chat/completions" -Method POST -Body $bodyBytes -Headers $headers
    $responseData = $response.Content | ConvertFrom-Json
    $summary = $responseData.choices[0].message.content
    
    # Save original text and summary to files
    $originalPath = "outputs\Clipboard\clipboard_original_$timestamp.txt"
    $summaryPath = "outputs\Clipboard\clipboard_summary_$timestamp.txt"
    
    $clipboardText | Out-File -FilePath $originalPath -Encoding UTF8
    $summary | Out-File -FilePath $summaryPath -Encoding UTF8
    
    # Copy summary back to clipboard
    $summary | Set-Clipboard
    
    Write-Host "Original text saved to: $originalPath"
    Write-Host "Summary saved to: $summaryPath"
    Write-Host "Summary copied to clipboard"
    Write-Host "Summary: $summary"
    
    # Generate TTS audio using FastKokoro API
    try {
        # Truncate summary if too long for TTS
        $ttsText = if ($summary.Length -gt 2000) { $summary.Substring(0, 2000) + "..." } else { $summary }
        
        $ttsBody = @{
            model = "kokoro"
            input = $ttsText
            voice = "af_sky"
            response_format = "mp3"
            speed = 1.0
            stream = $false
        } | ConvertTo-Json -Depth 3
        
        $audioPath = "outputs\Clipboard\latest_summary.mp3"
        
        # Call TTS API with proper headers and encoding
        $ttsHeaders = @{
            'Content-Type' = 'application/json; charset=utf-8'
            'Accept' = 'audio/mpeg'
        }
        
        # Convert body to UTF8 bytes to ensure proper encoding
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($ttsBody)
        
        $ttsResponse = Invoke-WebRequest -Uri "http://127.0.0.1:8880/v1/audio/speech" -Method POST -Body $bodyBytes -Headers $ttsHeaders
        [System.IO.File]::WriteAllBytes($audioPath, $ttsResponse.Content)
        
        Write-Host "Audio generated and saved to: $audioPath"

        Start-Sleep 2
        
        # Play the audio using headless VLC
        Start-Process -FilePath "C:\Program Files\VideoLAN\VLC\vlc.exe" -ArgumentList "--intf dummy --play-and-exit `"$audioPath`"" -NoNewWindow -Wait
        
        Write-Host "Playing summary audio with VLC..."
        
    } catch {
        Write-Host "Error generating or playing TTS: $($_.Exception.Message)"
    }
    
} catch {
    Write-Host "Error processing clipboard or calling API: $($_.Exception.Message)"
}
