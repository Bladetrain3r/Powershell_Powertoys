# LMStudio Core API Module
# Simple, reusable functions for LMStudio API calls

param(
    [string]$ApiEndpoint = "http://localhost:1234",
    [string]$TtsEndpoint = "http://localhost:8880"
)

# Clean text for API - used everywhere
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

# Basic LMStudio API call
function Invoke-LMStudioAPI {
    param(
        [string]$Model = "gemma-3-4b-it-qat",
        [string]$Prompt,
        [int]$MaxTokens = 1000,
        [float]$Temperature = 0.3,
        [int]$RetryCount = 3
    )
    
    for ($i = 0; $i -lt $RetryCount; $i++) {
        try {
            $body = @{
                model = $Model
                messages = @(
                    @{
                        role = "user"
                        content = $Prompt
                    }
                )
                max_tokens = $MaxTokens
                temperature = $Temperature
            } | ConvertTo-Json -Depth 5
            
            $headers = @{
                'Content-Type' = 'application/json; charset=utf-8'
            }
            
            $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
            $response = Invoke-WebRequest -Uri "$ApiEndpoint/v1/chat/completions" -Method POST -Body $bodyBytes -Headers $headers -TimeoutSec 120
            $responseData = $response.Content | ConvertFrom-Json
            
            return $responseData.choices[0].message.content.Trim()
            
        } catch {
            Write-Host "API attempt $($i + 1)/$RetryCount failed: $($_.Exception.Message)" -ForegroundColor Yellow
            
            if ($i -eq $RetryCount - 1) {
                return "ERROR: API failed after $RetryCount attempts - $($_.Exception.Message)"
            }
            
            Start-Sleep -Seconds ([math]::Pow(2, $i))
        }
    }
}

# Vision/Screenshot API call
function Invoke-LMStudioVision {
    param(
        [string]$Model = "gemma-3-4b-it-qat",
        [string]$Prompt,
        [string]$Base64Image,
        [int]$MaxTokens = 1000,
        [float]$Temperature = 0.2
    )
    
    try {
        $body = @{
            model = $Model
            messages = @(
                @{
                    role = "user"
                    content = @(
                        @{
                            type = "text"
                            text = $Prompt
                        },
                        @{
                            type = "image_url"
                            image_url = @{
                                url = "data:image/png;base64,$Base64Image"
                            }
                        }
                    )
                }
            )
            max_tokens = $MaxTokens
            temperature = $Temperature
        } | ConvertTo-Json -Depth 5
        
        $headers = @{
            'Content-Type' = 'application/json; charset=utf-8'
        }
        
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $response = Invoke-WebRequest -Uri "$ApiEndpoint/v1/chat/completions" -Method POST -Body $bodyBytes -Headers $headers -TimeoutSec 120
        $responseData = $response.Content | ConvertFrom-Json
        
        return $responseData.choices[0].message.content.Trim()
        
    } catch {
        return "ERROR: Vision API failed - $($_.Exception.Message)"
    }
}

# TTS Generation
function Invoke-LMStudioTTS {
    param(
        [string]$Text,
        [string]$Voice = "af_sky",
        [string]$Model = "kokoro",
        [float]$Speed = 1.0,
        [string]$OutputPath = $null,
        [switch]$PlayAudio
    )
    
    try {
        # Truncate if too long
        $ttsText = if ($Text.Length -gt 2000) { 
            $Text.Substring(0, 2000) + "..." 
        } else { 
            $Text 
        }
        
        $body = @{
            model = $Model
            input = $ttsText
            voice = $Voice
            response_format = "mp3"
            speed = $Speed
            stream = $false
        } | ConvertTo-Json -Depth 3
        
        $headers = @{
            'Content-Type' = 'application/json; charset=utf-8'
            'Accept' = 'audio/mpeg'
        }
        
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $response = Invoke-WebRequest -Uri "$TtsEndpoint/v1/audio/speech" -Method POST -Body $bodyBytes -Headers $headers -TimeoutSec 60
        
        if (!$OutputPath) {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $OutputPath = ".\outputs\audio_$timestamp.mp3"
        }
        
        [System.IO.File]::WriteAllBytes($OutputPath, $response.Content)
        
        if ($PlayAudio) {
            $vlcPath = "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"
            if (Test-Path $vlcPath) {
                Start-Sleep -Milliseconds 500
                Start-Process -FilePath $vlcPath -ArgumentList "--intf dummy --play-and-exit `"$OutputPath`"" -NoNewWindow -Wait
            }
        }
        
        return $OutputPath
        
    } catch {
        Write-Host "TTS Error: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Export the core functions
Export-ModuleMember -Function @(
    'Clean-TextForAPI',
    'Invoke-LMStudioAPI',
    'Invoke-LMStudioVision',
    'Invoke-LMStudioTTS'
)

# Usage:
<#
Import-Module .\LMStudioCore.psm1

# Simple text prompt
$response = Invoke-LMStudioAPI -Prompt "Summarize this text: $content" -MaxTokens 500

# Vision analysis
$analysis = Invoke-LMStudioVision -Prompt "Describe this screenshot" -Base64Image $base64

# Generate and play audio
$audioPath = Invoke-LMStudioTTS -Text "Hello world" -PlayAudio

# Clean text before sending
$clean = Clean-TextForAPI -Text $dirtyText -MaxLength 8000
$response = Invoke-LMStudioAPI -Prompt $clean
#>