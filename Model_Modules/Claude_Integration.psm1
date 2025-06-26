# Claude Core API Module
# Simple, reusable functions for Claude API calls

param(
    [Parameter(Mandatory)]
    [string]$ApiKey,
    [string]$Model = "claude-3-5-sonnet-20241022",
    [string]$ApiEndpoint = "https://api.anthropic.com/v1/messages"
)

# Basic Claude API call
function Invoke-ClaudeAPI {
    param(
        [string]$Prompt,
        [string]$SystemPrompt = $null,
        [int]$MaxTokens = 4096,
        [float]$Temperature = 0.3,
        [int]$RetryCount = 3
    )
    
    for ($i = 0; $i -lt $RetryCount; $i++) {
        try {
            # Build request
            $requestBody = @{
                model = $Model
                max_tokens = $MaxTokens
                temperature = $Temperature
                messages = @(
                    @{
                        role = "user"
                        content = $Prompt
                    }
                )
            }
            
            # Add system prompt if provided
            if ($SystemPrompt) {
                $requestBody.system = $SystemPrompt
            }
            
            $jsonBody = $requestBody | ConvertTo-Json -Depth 10 -Compress
            $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
            
            $headers = @{
                'Content-Type' = 'application/json'
                'x-api-key' = $ApiKey
                'anthropic-version' = '2023-06-01'
            }
            
            $response = Invoke-WebRequest -Uri $ApiEndpoint -Method POST -Body $bodyBytes -Headers $headers -TimeoutSec 120
            
            if ($response.StatusCode -ne 200) {
                throw "Claude API returned status $($response.StatusCode)"
            }
            
            $responseData = $response.Content | ConvertFrom-Json
            return $responseData.content[0].text.Trim()
            
        } catch {
            Write-Host "Claude API attempt $($i + 1)/$RetryCount failed: $($_.Exception.Message)" -ForegroundColor Yellow
            
            if ($i -eq $RetryCount - 1) {
                return "ERROR: Claude API failed after $RetryCount attempts - $($_.Exception.Message)"
            }
            
            Start-Sleep -Seconds ([math]::Pow(2, $i))
        }
    }
}

# Claude Vision API call
function Invoke-ClaudeVision {
    param(
        [string]$Prompt,
        [string]$Base64Image,
        [string]$SystemPrompt = $null,
        [int]$MaxTokens = 4096,
        [float]$Temperature = 0.3
    )
    
    try {
        # Build request with image
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
                            text = $Prompt
                        },
                        @{
                            type = "image"
                            source = @{
                                type = "base64"
                                media_type = "image/png"
                                data = $Base64Image
                            }
                        }
                    )
                }
            )
        }
        
        if ($SystemPrompt) {
            $requestBody.system = $SystemPrompt
        }
        
        $jsonBody = $requestBody | ConvertTo-Json -Depth 10 -Compress
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
        
        $headers = @{
            'Content-Type' = 'application/json'
            'x-api-key' = $ApiKey
            'anthropic-version' = '2023-06-01'
        }
        
        $response = Invoke-WebRequest -Uri $ApiEndpoint -Method POST -Body $bodyBytes -Headers $headers -TimeoutSec 120
        $responseData = $response.Content | ConvertFrom-Json
        
        return $responseData.content[0].text.Trim()
        
    } catch {
        return "ERROR: Claude Vision API failed - $($_.Exception.Message)"
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Invoke-ClaudeAPI',
    'Invoke-ClaudeVision'
)

# Usage:
<#
# Import with your API key
Import-Module .\ClaudeCore.psm1 -ArgumentList "your-api-key-here"

# Simple text prompt
$response = Invoke-ClaudeAPI -Prompt "Explain quantum computing" -MaxTokens 1000

# With system prompt
$analysis = Invoke-ClaudeAPI -Prompt $codeContent -SystemPrompt "You are a code security expert. Analyze for vulnerabilities."

# Vision analysis
$description = Invoke-ClaudeVision -Prompt "Describe this screenshot" -Base64Image $base64Image

# Custom model (e.g., for Haiku)
Import-Module .\ClaudeCore.psm1 -ArgumentList @{
    ApiKey = "your-key"
    Model = "claude-3-haiku-20240307"
}
#>