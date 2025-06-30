# ClaudeIntegration.psm1
# Enhanced Claude API integration module using Utils

# Import required Utils module
Import-Module (Join-Path $PSScriptRoot "Utils.psm1") -Force

# Module configuration
$ModuleName = "Claude"
$DefaultConfig = @{
    ApiEndpoint = "https://api.anthropic.com/v1/messages"
    DefaultModel = "claude-3-5-sonnet-20241022"
    DefaultMaxTokens = 4096
    DefaultTemperature = 0.3
    ApiVersion = "2023-06-01"
    OutputDirectory = ".\outputs"
}

# Load configuration or use defaults
$Config = Get-ModuleConfig -ModuleName $ModuleName
if (-not $Config) {
    $Config = $DefaultConfig
    Write-ModuleLog -Message "Using default configuration" -Level 'Info' -ModuleName $ModuleName
}

# Store the API key if provided during import
$script:ApiKey = $null

function Set-ClaudeApiKey {
    <#
    .SYNOPSIS
        Sets the Claude API key for the session
    .PARAMETER ApiKey
        The Claude API key
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ApiKey
    )
    
    $script:ApiKey = $ApiKey
    Write-ModuleLog -Message "Claude API key configured" -Level 'Info' -ModuleName $ModuleName
}

function Get-ClaudeApiKey {
    <#
    .SYNOPSIS
        Gets the current Claude API key
    #>
    return $script:ApiKey
}

function Invoke-ClaudeAPI {
    <#
    .SYNOPSIS
        Makes a text completion request to Claude API
    .PARAMETER Prompt
        The prompt text to send to Claude
    .PARAMETER SystemPrompt
        Optional system prompt for context
    .PARAMETER Model
        Claude model to use (optional, uses config default)
    .PARAMETER MaxTokens
        Maximum tokens in response
    .PARAMETER Temperature
        Temperature for response generation (0.0 to 1.0)
    .PARAMETER ApiKey
        Claude API key (optional if already set via Set-ClaudeApiKey)
    .PARAMETER RetryCount
        Number of retry attempts
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,
        [string]$SystemPrompt = $null,
        [string]$Model = $Config.DefaultModel,
        [int]$MaxTokens = $Config.DefaultMaxTokens,
        [float]$Temperature = $Config.DefaultTemperature,
        [string]$ApiKey = $script:ApiKey,
        [int]$RetryCount = 3
    )
    
    Write-ModuleLog -Message "Starting Claude API request" -Level 'Info' -ModuleName $ModuleName
    
    # Validate API key
    if (-not $ApiKey) {
        Write-ModuleLog -Message "Claude API key not provided" -Level 'Error' -ModuleName $ModuleName
        throw "Claude API key is required. Use Set-ClaudeApiKey or provide -ApiKey parameter"
    }
    
    # Validate and clean input
    if (Test-BinaryContent -Text $Prompt) {
        Write-ModuleLog -Message "Binary content detected in prompt" -Level 'Error' -ModuleName $ModuleName
        throw "Prompt contains binary data"
    }
    
    $cleanPrompt = Clean-TextForAPI -Text $Prompt -MaxLength 100000
    
    # Build request body
    $requestBody = @{
        model = $Model
        max_tokens = $MaxTokens
        temperature = $Temperature
        messages = @(
            @{
                role = "user"
                content = $cleanPrompt
            }
        )
    }
    
    # Add system prompt if provided
    if ($SystemPrompt) {
        $cleanSystemPrompt = Clean-TextForAPI -Text $SystemPrompt -MaxLength 10000
        $requestBody.system = $cleanSystemPrompt
    }
    
    try {
        $headers = @{
            'Content-Type' = 'application/json'
            'x-api-key' = $ApiKey
            'anthropic-version' = $Config.ApiVersion
        }
        
        $response = Invoke-ApiRequest -Uri $Config.ApiEndpoint -Body $requestBody -Headers $headers -RetryCount $RetryCount -TimeoutSec 120
        $responseData = $response.Content | ConvertFrom-Json
        
        if (-not $responseData.content -or -not $responseData.content[0] -or -not $responseData.content[0].text) {
            Write-ModuleLog -Message "Invalid response structure from Claude API" -Level 'Error' -ModuleName $ModuleName
            throw "Invalid response structure from Claude API"
        }
        
        $result = $responseData.content[0].text.Trim()
        Write-ModuleLog -Message "Claude API request completed successfully" -Level 'Info' -ModuleName $ModuleName
        
        return $result
        
    } catch {
        Write-ModuleLog -Message "Claude API request failed: $($_.Exception.Message)" -Level 'Error' -ModuleName $ModuleName
        throw
    }
}

function Invoke-ClaudeVision {
    <#
    .SYNOPSIS
        Makes a vision/image analysis request to Claude API
    .PARAMETER Prompt
        The prompt text to send to Claude
    .PARAMETER ImagePath
        Path to image file
    .PARAMETER Base64Image
        Base64 encoded image data (alternative to ImagePath)
    .PARAMETER MediaType
        Image media type (default: image/png)
    .PARAMETER SystemPrompt
        Optional system prompt for context
    .PARAMETER Model
        Claude model to use (optional, uses config default)
    .PARAMETER MaxTokens
        Maximum tokens in response
    .PARAMETER Temperature
        Temperature for response generation
    .PARAMETER ApiKey
        Claude API key (optional if already set via Set-ClaudeApiKey)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,
        [string]$ImagePath = "",
        [string]$Base64Image = "",
        [string]$MediaType = "image/png",
        [string]$SystemPrompt = $null,
        [string]$Model = $Config.DefaultModel,
        [int]$MaxTokens = $Config.DefaultMaxTokens,
        [float]$Temperature = $Config.DefaultTemperature,
        [string]$ApiKey = $script:ApiKey
    )
    
    Write-ModuleLog -Message "Starting Claude Vision API request" -Level 'Info' -ModuleName $ModuleName
    
    # Validate API key
    if (-not $ApiKey) {
        Write-ModuleLog -Message "Claude API key not provided" -Level 'Error' -ModuleName $ModuleName
        throw "Claude API key is required. Use Set-ClaudeApiKey or provide -ApiKey parameter"
    }
    
    # Handle image input
    if ($ImagePath -and (Test-Path $ImagePath)) {
        try {
            $imageBytes = [System.IO.File]::ReadAllBytes($ImagePath)
            $Base64Image = [Convert]::ToBase64String($imageBytes)
            
            # Determine media type from file extension if not specified
            if ($MediaType -eq "image/png") {
                $extension = [System.IO.Path]::GetExtension($ImagePath).ToLower()
                switch ($extension) {
                    ".jpg" { $MediaType = "image/jpeg" }
                    ".jpeg" { $MediaType = "image/jpeg" }
                    ".gif" { $MediaType = "image/gif" }
                    ".webp" { $MediaType = "image/webp" }
                    default { $MediaType = "image/png" }
                }
            }
            
            Write-ModuleLog -Message "Loaded image from path: $ImagePath (Type: $MediaType)" -Level 'Info' -ModuleName $ModuleName
        } catch {
            Write-ModuleLog -Message "Failed to load image: $($_.Exception.Message)" -Level 'Error' -ModuleName $ModuleName
            throw "Failed to load image from path: $ImagePath"
        }
    }
    
    if (-not $Base64Image) {
        throw "Either ImagePath or Base64Image must be provided"
    }
    
    # Validate and clean prompt
    if (Test-BinaryContent -Text $Prompt) {
        Write-ModuleLog -Message "Binary content detected in prompt" -Level 'Error' -ModuleName $ModuleName
        throw "Prompt contains binary data"
    }
    
    $cleanPrompt = Clean-TextForAPI -Text $Prompt -MaxLength 10000
    
    # Build request body with image
    $requestBody = @{
        model = $Model
        max_tokens = $MaxTokens
        temperature = $Temperature
        messages = @(
            @{
                role = "user"
                content = @(
                    @{
                        type = "text"
                        text = $cleanPrompt
                    },
                    @{
                        type = "image"
                        source = @{
                            type = "base64"
                            media_type = $MediaType
                            data = $Base64Image
                        }
                    }
                )
            }
        )
    }
    
    # Add system prompt if provided
    if ($SystemPrompt) {
        $cleanSystemPrompt = Clean-TextForAPI -Text $SystemPrompt -MaxLength 10000
        $requestBody.system = $cleanSystemPrompt
    }
    
    try {
        $headers = @{
            'Content-Type' = 'application/json'
            'x-api-key' = $ApiKey
            'anthropic-version' = $Config.ApiVersion
        }
        
        $response = Invoke-ApiRequest -Uri $Config.ApiEndpoint -Body $requestBody -Headers $headers -TimeoutSec 120
        $responseData = $response.Content | ConvertFrom-Json
        
        if (-not $responseData.content -or -not $responseData.content[0] -or -not $responseData.content[0].text) {
            Write-ModuleLog -Message "Invalid response structure from Claude Vision API" -Level 'Error' -ModuleName $ModuleName
            throw "Invalid response structure from Claude Vision API"
        }
        
        $result = $responseData.content[0].text.Trim()
        Write-ModuleLog -Message "Claude Vision API request completed successfully" -Level 'Info' -ModuleName $ModuleName
        
        return $result
        
    } catch {
        Write-ModuleLog -Message "Claude Vision API request failed: $($_.Exception.Message)" -Level 'Error' -ModuleName $ModuleName
        throw
    }
}

function Test-ClaudeConnection {
    <#
    .SYNOPSIS
        Tests connectivity to Claude API
    .PARAMETER ApiKey
        Claude API key (optional if already set via Set-ClaudeApiKey)
    #>
    [CmdletBinding()]
    param(
        [string]$ApiKey = $script:ApiKey
    )
    
    $results = @{}
    
    if (-not $ApiKey) {
        $results.Status = "Failed"
        $results.Error = "API key not provided"
        Write-ModuleLog -Message "Claude API: Failed - No API key provided" -Level 'Error' -ModuleName $ModuleName
        return $results
    }
    
    try {
        Write-ModuleLog -Message "Testing Claude API connection..." -Level 'Info' -ModuleName $ModuleName
        
        # Make a simple test request
        $testPrompt = "Hello, respond with just 'OK' to confirm connection."
        $response = Invoke-ClaudeAPI -Prompt $testPrompt -MaxTokens 10 -ApiKey $ApiKey
        
        $results.Status = "Connected"
        $results.Response = $response
        $results.Model = $Config.DefaultModel
        $results.Endpoint = $Config.ApiEndpoint
        
        Write-ModuleLog -Message "Claude API: Connected successfully" -Level 'Info' -ModuleName $ModuleName
        
    } catch {
        $results.Status = "Failed"
        $results.Error = $_.Exception.Message
        Write-ModuleLog -Message "Claude API: Failed - $($_.Exception.Message)" -Level 'Error' -ModuleName $ModuleName
    }
    
    return $results
}

function Save-ClaudeResponse {
    <#
    .SYNOPSIS
        Saves Claude API response to a file
    .PARAMETER Response
        The response text to save
    .PARAMETER OutputPath
        Custom output path (optional)
    .PARAMETER Prefix
        Filename prefix (default: "claude")
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Response,
        [string]$OutputPath = "",
        [string]$Prefix = "claude"
    )

    try {
        if (-not $Response) {
            throw "Response cannot be empty."
        }

        # If no custom output path is provided, generate one
        if (-not $OutputPath) {
            $targetDir = $Config.OutputDirectory
            # If no directory is configured, use the current working directory
            if (-not $targetDir) {
                $targetDir = "."
            }

            # Ensure the output directory exists
            if (-not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }
            
            $OutputPath = Get-TimestampedFilename -Prefix $Prefix -Extension "txt" -Directory $targetDir
        }
        
        # Save response to file
        $Response | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-ModuleLog -Message "Claude response saved to: $OutputPath" -Level 'Info' -ModuleName $ModuleName
        
        return $OutputPath
        
    } catch {
        Write-ModuleLog -Message "Failed to save response: $($_.Exception.Message)" -Level 'Error' -ModuleName $ModuleName
        throw
    }
}

# Export module functions
Export-ModuleMember -Function @(
    'Set-ClaudeApiKey',
    'Get-ClaudeApiKey',
    'Invoke-ClaudeAPI',
    'Invoke-ClaudeVision',
    'Test-ClaudeConnection',
    'Save-ClaudeResponse'
)

# Module initialization
Write-ModuleLog -Message "Claude Integration module loaded" -Level 'Info' -ModuleName $ModuleName
Write-ModuleLog -Message "API Endpoint: $($Config.ApiEndpoint)" -Level 'Info' -ModuleName $ModuleName
Write-ModuleLog -Message "Default Model: $($Config.DefaultModel)" -Level 'Info' -ModuleName $ModuleName

<#
.NOTES
Usage Examples:

# Set API key for the session
Set-ClaudeApiKey -ApiKey "your-api-key-here"

# Simple text completion
$response = Invoke-ClaudeAPI -Prompt "Explain quantum computing"

# With system prompt
$analysis = Invoke-ClaudeAPI -Prompt $codeContent -SystemPrompt "You are a code security expert. Analyze for vulnerabilities."

# Vision analysis
$description = Invoke-ClaudeVision -Prompt "Describe this image" -ImagePath "C:\path\to\image.png"

# With base64 image
$description = Invoke-ClaudeVision -Prompt "Analyze this screenshot" -Base64Image $base64Data

# Test connection
$connectionTest = Test-ClaudeConnection

# Save response to file  
$savedPath = Save-ClaudeResponse -Response $response

# Custom configuration via config.json:
{
    "Claude": {
        "ApiEndpoint": "https://api.anthropic.com/v1/messages",
        "DefaultModel": "claude-3-haiku-20240307",
        "DefaultMaxTokens": 2048,
        "DefaultTemperature": 0.5,
        "OutputDirectory": "C:\MyOutputs"
    }
}
#>
