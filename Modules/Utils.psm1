# Utils.psm1
# Core utility functions for common operations across all modules

# Text Processing Utilities
function Clean-TextForAPI {
    <#
    .SYNOPSIS
        Cleans and validates text for API consumption
    .PARAMETER Text
        The text to clean
    .PARAMETER MaxLength
        Maximum length allowed (default: 8000)
    #>
    param(
        [string]$Text, 
        [int]$MaxLength = 8000
    )
    
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }
    
    # Remove control characters and normalize whitespace
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

function Test-BinaryContent {
    <#
    .SYNOPSIS
        Checks if text contains binary data
    .PARAMETER Text
        The text to check
    .PARAMETER Threshold
        Percentage threshold for binary detection (default: 0.1)
    #>
    param(
        [string]$Text,
        [double]$Threshold = 0.1
    )
    
    if ([string]::IsNullOrEmpty($Text)) {
        return $false
    }
    
    $badChars = ($Text.ToCharArray() | Where-Object { 
        [int]$_ -eq 0 -or ([int]$_ -lt 32 -and $_ -notin "`t", "`n", "`r") 
    }).Count
    
    return ($badChars / $Text.Length) -gt $Threshold
}

# Network Utilities
function Invoke-ApiRequest {
    <#
    .SYNOPSIS
        Standard API request wrapper with retry logic
    .PARAMETER Uri
        The API endpoint URI
    .PARAMETER Method
        HTTP method (default: POST)
    .PARAMETER Body
        Request body (will be UTF8 encoded)
    .PARAMETER Headers
        Request headers
    .PARAMETER TimeoutSec
        Timeout in seconds (default: 120)
    .PARAMETER RetryCount
        Number of retry attempts (default: 3)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Uri,
        [string]$Method = 'POST',
        [object]$Body,
        [hashtable]$Headers = @{},
        [int]$TimeoutSec = 120,
        [int]$RetryCount = 3
    )
    
    for ($i = 0; $i -lt $RetryCount; $i++) {
        try {
            $requestParams = @{
                Uri = $Uri
                Method = $Method
                Headers = $Headers
                TimeoutSec = $TimeoutSec
            }
            
            if ($Body) {
                if ($Body -is [string]) {
                    $requestParams.Body = [System.Text.Encoding]::UTF8.GetBytes($Body)
                } elseif ($Body -is [hashtable] -or $Body -is [PSCustomObject]) {
                    $jsonBody = $Body | ConvertTo-Json -Depth 10 -Compress
                    $requestParams.Body = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
                } else {
                    $requestParams.Body = $Body
                }
            }
            
            $response = Invoke-WebRequest @requestParams
            return $response
            
        } catch {
            Write-Warning "API request attempt $($i + 1)/$RetryCount failed: $($_.Exception.Message)"
            
            if ($i -eq $RetryCount - 1) {
                throw "API request failed after $RetryCount attempts: $($_.Exception.Message)"
            }
            
            # Exponential backoff
            Start-Sleep -Seconds ([math]::Pow(2, $i))
        }
    }
}

# File System Utilities
function New-OutputDirectory {
    <#
    .SYNOPSIS
        Creates output directory if it doesn't exist
    .PARAMETER Path
        The directory path to create
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Verbose "Created directory: $Path"
    }
    
    return $Path
}

function Get-TimestampedFilename {
    <#
    .SYNOPSIS
        Generates a timestamped filename
    .PARAMETER Prefix
        Filename prefix
    .PARAMETER Extension
        File extension (with or without dot)
    .PARAMETER Directory
        Directory path (optional)
    #>
    param(
        [string]$Prefix = "file",
        [string]$Extension = "txt",
        [string]$Directory = ""
    )
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $extension = if ($Extension.StartsWith(".")) { $Extension } else { ".$Extension" }
    $filename = "${Prefix}_${timestamp}${extension}"
    
    if ($Directory) {
        return Join-Path $Directory $filename
    }
    
    return $filename
}

# Error Handling and Logging
function Write-ModuleLog {
    <#
    .SYNOPSIS
        Standardized logging for modules
    .PARAMETER Message
        Log message
    .PARAMETER Level
        Log level (Info, Warning, Error)
    .PARAMETER ModuleName
        Name of the calling module
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info',
        [string]$ModuleName = 'Unknown'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$ModuleName] [$Level] $Message"
    
    switch ($Level) {
        'Info' { Write-Host $logMessage -ForegroundColor Green }
        'Warning' { Write-Warning $logMessage }
        'Error' { Write-Error $logMessage }
    }
}

function ConvertTo-SafeJson {
    <#
    .SYNOPSIS
        Safely converts objects to JSON with error handling
    .PARAMETER InputObject
        Object to convert
    .PARAMETER Depth
        JSON depth (default: 10)
    #>
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,
        [int]$Depth = 10
    )
    
    try {
        return $InputObject | ConvertTo-Json -Depth $Depth -Compress
    } catch {
        Write-ModuleLog -Message "JSON conversion failed: $($_.Exception.Message)" -Level 'Error' -ModuleName 'Utils'
        throw
    }
}

# Configuration Utilities
function Get-ModuleConfig {
    <#
    .SYNOPSIS
        Loads configuration for a module
    .PARAMETER ModuleName
        Name of the module
    .PARAMETER ConfigPath
        Path to config file (optional)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,
        [string]$ConfigPath = ""
    )
    
    if (-not $ConfigPath) {
        $ConfigPath = Join-Path (Split-Path $PSScriptRoot) "config.json"
    }
    
    if (Test-Path $ConfigPath) {
        try {
            $config = Get-Content $ConfigPath | ConvertFrom-Json
            return $config.$ModuleName
        } catch {
            Write-ModuleLog -Message "Failed to load config: $($_.Exception.Message)" -Level 'Warning' -ModuleName 'Utils'
        }
    }
    
    return $null
}

# Export all functions
Export-ModuleMember -Function @(
    'Clean-TextForAPI',
    'Test-BinaryContent',
    'Invoke-ApiRequest',
    'New-OutputDirectory',
    'Get-TimestampedFilename',
    'Write-ModuleLog',
    'ConvertTo-SafeJson',
    'Get-ModuleConfig'
)
