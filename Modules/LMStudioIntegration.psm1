# LMStudioIntegration.psm1
# Enhanced LMStudio integration module using Utils

# Import required Utils module
Import-Module (Join-Path $PSScriptRoot "Utils.psm1") -Force

# Module configuration
$ModuleName = "LMStudio"
$DefaultConfig = @{
    ApiEndpoint = "http://localhost:1234"
    TtsEndpoint = "http://localhost:8880"
    DefaultModel = "gemma-3-4b-it-qat"
    DefaultTTSVoice = "af_sky"
    DefaultMaxTokens = 1000
    DefaultTemperature = 0.3
    OutputDirectory = ".\outputs"
}

# Load configuration or use defaults
$Config = Get-ModuleConfig -ModuleName $ModuleName
if (-not $Config) {
    $Config = $DefaultConfig
    Write-ModuleLog -Message "Using default configuration" -Level 'Info' -ModuleName $ModuleName
}

# Core LMStudio API Functions
function Invoke-LMStudioAPI {
    <#
    .SYNOPSIS
        Makes a text completion request to LMStudio
    .PARAMETER Prompt
        The prompt text to send
    .PARAMETER Model
        Model name (optional, uses config default)
    .PARAMETER MaxTokens
        Maximum tokens in response
    .PARAMETER Temperature
        Temperature for response generation
    .PARAMETER SystemPrompt
        System prompt for context
    .PARAMETER RetryCount
        Number of retry attempts
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,
        [string]$Model = $Config.DefaultModel,
        [int]$MaxTokens = $Config.DefaultMaxTokens,
        [float]$Temperature = $Config.DefaultTemperature,
        [string]$SystemPrompt = $null,
        [int]$RetryCount = 3
    )
    
    Write-ModuleLog -Message "Starting LMStudio API request" -Level 'Info' -ModuleName $ModuleName
    
    # Validate and clean input
    if (Test-BinaryContent -Text $Prompt) {
        Write-ModuleLog -Message "Binary content detected in prompt" -Level 'Error' -ModuleName $ModuleName
        throw "Prompt contains binary data"
    }
    
    $cleanPrompt = Clean-TextForAPI -Text $Prompt -MaxLength 8000
    
    # Build request body
    $messages = @(
        @{
            role = "user"
            content = $cleanPrompt
        }
    )
    
    # Add system prompt if provided
    if ($SystemPrompt) {
        $cleanSystemPrompt = Clean-TextForAPI -Text $SystemPrompt -MaxLength 2000
        $messages = @(
            @{
                role = "system"
                content = $cleanSystemPrompt
            }
        ) + $messages
    }
    
    $requestBody = @{
        model = $Model
        messages = $messages
        max_tokens = $MaxTokens
        temperature = $Temperature
    }
    
    try {
        $headers = @{
            'Content-Type' = 'application/json; charset=utf-8'
        }
        
        $response = Invoke-ApiRequest -Uri "$($Config.ApiEndpoint)/v1/chat/completions" -Body $requestBody -Headers $headers -RetryCount $RetryCount
        $responseData = $response.Content | ConvertFrom-Json
        
        $result = $responseData.choices[0].message.content.Trim()
        Write-ModuleLog -Message "API request completed successfully" -Level 'Info' -ModuleName $ModuleName
        
        return $result
        
    } catch {
        Write-ModuleLog -Message "API request failed: $($_.Exception.Message)" -Level 'Error' -ModuleName $ModuleName
        throw
    }
}

function Invoke-LMStudioVision {
    <#
    .SYNOPSIS
        Makes a vision/image analysis request to LMStudio
    .PARAMETER Prompt
        The prompt text to send
    .PARAMETER ImagePath
        Path to image file
    .PARAMETER Base64Image
        Base64 encoded image data (alternative to ImagePath)
    .PARAMETER Model
        Model name (optional, uses config default)
    .PARAMETER MaxTokens
        Maximum tokens in response
    .PARAMETER Temperature
        Temperature for response generation
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,
        [string]$ImagePath = "",
        [string]$Base64Image = "",
        [string]$Model = $Config.DefaultModel,
        [int]$MaxTokens = $Config.DefaultMaxTokens,
        [float]$Temperature = 0.2
    )
    
    Write-ModuleLog -Message "Starting LMStudio Vision API request" -Level 'Info' -ModuleName $ModuleName
    
    # Handle image input
    if ($ImagePath -and (Test-Path $ImagePath)) {
        try {
            $imageBytes = [System.IO.File]::ReadAllBytes($ImagePath)
            $Base64Image = [Convert]::ToBase64String($imageBytes)
            Write-ModuleLog -Message "Loaded image from path: $ImagePath" -Level 'Info' -ModuleName $ModuleName
        } catch {
            Write-ModuleLog -Message "Failed to load image: $($_.Exception.Message)" -Level 'Error' -ModuleName $ModuleName
            throw "Failed to load image from path: $ImagePath"
        }
    }
    
    if (-not $Base64Image) {
        throw "Either ImagePath or Base64Image must be provided"
    }
    
    $cleanPrompt = Clean-TextForAPI -Text $Prompt -MaxLength 2000
    
    $requestBody = @{
        model = $Model
        messages = @(
            @{
                role = "user"
                content = @(
                    @{
                        type = "text"
                        text = $cleanPrompt
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
    }
    
    try {
        $headers = @{
            'Content-Type' = 'application/json; charset=utf-8'
        }
        
        $response = Invoke-ApiRequest -Uri "$($Config.ApiEndpoint)/v1/chat/completions" -Body $requestBody -Headers $headers
        $responseData = $response.Content | ConvertFrom-Json
        
        $result = $responseData.choices[0].message.content.Trim()
        Write-ModuleLog -Message "Vision API request completed successfully" -Level 'Info' -ModuleName $ModuleName
        
        return $result
        
    } catch {
        Write-ModuleLog -Message "Vision API request failed: $($_.Exception.Message)" -Level 'Error' -ModuleName $ModuleName
        throw
    }
}

function Invoke-LMStudioTTS {
    <#
    .SYNOPSIS
        Generates speech from text using LMStudio TTS endpoint
    .PARAMETER Text
        Text to convert to speech
    .PARAMETER Voice
        Voice to use for TTS
    .PARAMETER Model
        TTS model name
    .PARAMETER Speed
        Speech speed multiplier
    .PARAMETER OutputPath
        Custom output path (optional)
    .PARAMETER PlayAudio
        Whether to play the audio after generation
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text,
        [string]$Voice = $Config.DefaultTTSVoice,
        [string]$Model = "kokoro",
        [float]$Speed = 1.0,
        [string]$OutputPath = "",
        [switch]$PlayAudio
    )
    
    Write-ModuleLog -Message "Starting TTS generation" -Level 'Info' -ModuleName $ModuleName
    
    # Validate and prepare text
    if (Test-BinaryContent -Text $Text) {
        Write-ModuleLog -Message "Binary content detected in TTS text" -Level 'Error' -ModuleName $ModuleName
        throw "TTS text contains binary data"
    }
    
    # Truncate if too long for TTS
    $ttsText = if ($Text.Length -gt 2000) { 
        $Text.Substring(0, 2000) + "..." 
        Write-ModuleLog -Message "Text truncated for TTS (length: $($Text.Length))" -Level 'Warning' -ModuleName $ModuleName
    } else { 
        $Text 
    }
    
    # Prepare output directory and filename
    $outputDir = New-OutputDirectory -Path $Config.OutputDirectory
    
    if (-not $OutputPath) {
        $OutputPath = Get-TimestampedFilename -Prefix "tts" -Extension "mp3" -Directory $outputDir
    }
    
    $requestBody = @{
        model = $Model
        input = $ttsText
        voice = $Voice
        response_format = "mp3"
        speed = $Speed
        stream = $false
    }
    
    try {
        $headers = @{
            'Content-Type' = 'application/json; charset=utf-8'
            'Accept' = 'audio/mpeg'
        }
        
        $response = Invoke-ApiRequest -Uri "$($Config.TtsEndpoint)/v1/audio/speech" -Body $requestBody -Headers $headers -TimeoutSec 60
        
        # Ensure directory exists before saving audio file
        $directory = Split-Path -Path $OutputPath -Parent
        if (-not (Test-Path $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }
        
        # Save audio file
        [System.IO.File]::WriteAllBytes($OutputPath, $response.Content)
        Write-ModuleLog -Message "TTS audio saved to: $OutputPath" -Level 'Info' -ModuleName $ModuleName
        
        # Play audio if requested
        if ($PlayAudio) {
            Start-LMStudioAudioPlayback -AudioPath $OutputPath
        }
        
        return $OutputPath
        
    } catch {
        Write-ModuleLog -Message "TTS generation failed: $($_.Exception.Message)" -Level 'Error' -ModuleName $ModuleName
        throw
    }
}

function Start-LMStudioAudioPlayback {
    <#
    .SYNOPSIS
        Plays audio file using VLC or default system player
    .PARAMETER AudioPath
        Path to audio file to play
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AudioPath
    )
    
    if (-not (Test-Path $AudioPath)) {
        Write-ModuleLog -Message "Audio file not found: $AudioPath" -Level 'Error' -ModuleName $ModuleName
        return
    }
    
    # Try to find VLC
    $vlcPaths = @(
        "C:\Program Files\VideoLAN\VLC\vlc.exe",
        "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"
    )
    
    $vlcPath = $vlcPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    
    if ($vlcPath) {
        try {
            Write-ModuleLog -Message "Playing audio with VLC: $AudioPath" -Level 'Info' -ModuleName $ModuleName
            Start-Sleep -Milliseconds 500  # Brief delay to ensure file is fully written
            Start-Process -FilePath $vlcPath -ArgumentList "--intf dummy --play-and-exit `"$AudioPath`"" -NoNewWindow -Wait
        } catch {
            Write-ModuleLog -Message "VLC playback failed: $($_.Exception.Message)" -Level 'Warning' -ModuleName $ModuleName
        }
    } else {
        try {
            Write-ModuleLog -Message "Playing audio with system default: $AudioPath" -Level 'Info' -ModuleName $ModuleName
            Start-Process -FilePath $AudioPath
        } catch {
            Write-ModuleLog -Message "Audio playback failed: $($_.Exception.Message)" -Level 'Warning' -ModuleName $ModuleName
        }
    }
}

function Test-LMStudioConnection {
    <#
    .SYNOPSIS
        Tests connectivity to LMStudio endpoints
    .PARAMETER IncludeTTS
        Whether to test TTS endpoint as well
    #>
    [CmdletBinding()]
    param(
        [switch]$IncludeTTS
    )
    
    $results = @{}
    
    # Test main API endpoint
    try {
        Write-ModuleLog -Message "Testing LMStudio API connection..." -Level 'Info' -ModuleName $ModuleName
        $response = Invoke-WebRequest -Uri "$($Config.ApiEndpoint)/v1/models" -Method GET -TimeoutSec 10
        $results.API = @{
            Status = "Connected"
            StatusCode = $response.StatusCode
        }
        Write-ModuleLog -Message "LMStudio API: Connected" -Level 'Info' -ModuleName $ModuleName
    } catch {
        $results.API = @{
            Status = "Failed"
            Error = $_.Exception.Message
        }
        Write-ModuleLog -Message "LMStudio API: Failed - $($_.Exception.Message)" -Level 'Error' -ModuleName $ModuleName
    }
    
    # Test TTS endpoint if requested
    if ($IncludeTTS) {
        try {
            Write-ModuleLog -Message "Testing TTS endpoint..." -Level 'Info' -ModuleName $ModuleName
            $response = Invoke-WebRequest -Uri "$($Config.TtsEndpoint)/v1/models" -Method GET -TimeoutSec 10
            $results.TTS = @{
                Status = "Connected"
                StatusCode = $response.StatusCode
            }
            Write-ModuleLog -Message "TTS endpoint: Connected" -Level 'Info' -ModuleName $ModuleName
        } catch {
            $results.TTS = @{
                Status = "Failed"
                Error = $_.Exception.Message
            }
            Write-ModuleLog -Message "TTS endpoint: Failed - $($_.Exception.Message)" -Level 'Error' -ModuleName $ModuleName
        }
    }
    
    return $results
}

# Export module functions
Export-ModuleMember -Function @(
    'Invoke-LMStudioAPI',
    'Invoke-LMStudioVision', 
    'Invoke-LMStudioTTS',
    'Start-LMStudioAudioPlayback',
    'Test-LMStudioConnection'
)

# Module initialization
Write-ModuleLog -Message "LMStudio Integration module loaded" -Level 'Info' -ModuleName $ModuleName
Write-ModuleLog -Message "API Endpoint: $($Config.ApiEndpoint)" -Level 'Info' -ModuleName $ModuleName
Write-ModuleLog -Message "TTS Endpoint: $($Config.TtsEndpoint)" -Level 'Info' -ModuleName $ModuleName
