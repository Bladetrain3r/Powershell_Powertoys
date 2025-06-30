# demo_lmstudio.ps1
# Demonstration script for the new LMStudio Integration module

[CmdletBinding()]
param(
    [switch]$SkipTTS,
    [switch]$SkipVision,
    [switch]$Interactive
)

# Clear screen for demo
Clear-Host

Write-Host "=== LMStudio Integration Module Demo ===" -ForegroundColor Cyan
Write-Host "This demo showcases the enhanced LMStudio module functionality`n" -ForegroundColor Yellow

# Import the new module
try {
    Import-Module ".\Modules\LMStudioIntegration.psm1" -Force
    Write-Host "✓ LMStudio Integration module loaded successfully`n" -ForegroundColor Green
} catch {
    Write-Error "Failed to load LMStudio module: $($_.Exception.Message)"
    exit 1
}

# Function to pause between demos
function Wait-ForUser {
    param([string]$Message = "Press Enter to continue...")
    if ($Interactive) {
        Read-Host $Message
    } else {
        Start-Sleep -Seconds 2
    }
}

# Demo 1: Connection Test
Write-Host "=== Demo 1: Connection Testing ===" -ForegroundColor Magenta
Write-Host "Testing connectivity to LMStudio endpoints...`n"

$connectionResults = Test-LMStudioConnection -IncludeTTS
$connectionResults | Format-Table -AutoSize

if ($connectionResults.API.Status -eq "Connected") {
    Write-Host "✓ LMStudio API is available" -ForegroundColor Green
} finally {
    Write-Host "✗ LMStudio API is not available" -ForegroundColor Red
    Write-Host "Please ensure LMStudio is running on localhost:1234" -ForegroundColor Yellow
}

if ($connectionResults.TTS.Status -eq "Connected") {
    Write-Host "✓ TTS endpoint is available" -ForegroundColor Green
} else {
    Write-Host "✗ TTS endpoint is not available" -ForegroundColor Red
    Write-Host "Please ensure Kokoro TTS is running on localhost:8880" -ForegroundColor Yellow
}

Wait-ForUser

# Demo 2: Basic Text Generation
Write-Host "`n=== Demo 2: Basic Text Generation ===" -ForegroundColor Magenta
Write-Host "Generating a response about PowerShell modules...`n"

try {
    $prompt = "Explain the benefits of using PowerShell modules in 3 sentences."
    Write-Host "Prompt: $prompt" -ForegroundColor Cyan
    
    $response = Invoke-LMStudioAPI -Prompt $prompt -MaxTokens 200 -Temperature 0.7
    Write-Host "`nResponse:" -ForegroundColor Green
    Write-Host $response -ForegroundColor White
} catch {
    Write-Host "Text generation failed: $($_.Exception.Message)" -ForegroundColor Red
}

Wait-ForUser

# Demo 3: System Prompt Usage
Write-Host "`n=== Demo 3: System Prompt Usage ===" -ForegroundColor Magenta
Write-Host "Using a system prompt to influence response style...`n"

try {
    $systemPrompt = "You are a helpful technical documentation writer. Respond in a clear, structured format."
    $userPrompt = "How do I create a PowerShell module manifest?"
    
    Write-Host "System Prompt: $systemPrompt" -ForegroundColor Cyan
    Write-Host "User Prompt: $userPrompt" -ForegroundColor Cyan
    
    $response = Invoke-LMStudioAPI -Prompt $userPrompt -SystemPrompt $systemPrompt -MaxTokens 300
    Write-Host "`nResponse:" -ForegroundColor Green
    Write-Host $response -ForegroundColor White
} catch {
    Write-Host "System prompt demo failed: $($_.Exception.Message)" -ForegroundColor Red
}

Wait-ForUser

# Demo 4: Text-to-Speech (if not skipped)
if (-not $SkipTTS -and $connectionResults.TTS.Status -eq "Connected") {
    Write-Host "`n=== Demo 4: Text-to-Speech Generation ===" -ForegroundColor Magenta
    Write-Host "Generating speech from text...`n"
    
    try {
        $ttsText = "Hello! This is a demonstration of the LMStudio integration module. The text-to-speech functionality is working correctly."
        Write-Host "Text to synthesize: $ttsText" -ForegroundColor Cyan
        
        $audioPath = Invoke-LMStudioTTS -Text $ttsText -Voice "af_sky" -Speed 1.1 -PlayAudio
        Write-Host "`n✓ Audio generated and saved to: $audioPath" -ForegroundColor Green
        Write-Host "Audio should have played automatically via VLC" -ForegroundColor Yellow
    } catch {
        Write-Host "TTS demo failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Wait-ForUser
} finally {
    Write-Host "`n=== Demo 4: Text-to-Speech (Skipped) ===" -ForegroundColor Magenta
    if ($SkipTTS) {
        Write-Host "TTS demo skipped by user request" -ForegroundColor Yellow
    } else {
        Write-Host "TTS endpoint not available, skipping demo" -ForegroundColor Yellow
    }
    Wait-ForUser
}

# Demo 5: Vision Analysis (if not skipped)
if (-not $SkipVision -and $connectionResults.API.Status -eq "Connected") {
    Write-Host "`n=== Demo 5: Vision Analysis ===" -ForegroundColor Magenta
    Write-Host "This demo would analyze an image if one was provided...`n"
    
    # Check if there's a screenshot or image file to analyze
    $imageFiles = Get-ChildItem -Path "." -Include "*.png", "*.jpg", "*.jpeg" -Recurse | Select-Object -First 1
    
    if ($imageFiles) {
        try {
            Write-Host "Found image file: $($imageFiles.FullName)" -ForegroundColor Cyan
            $prompt = "Describe what you see in this image in detail."
            
            $response = Invoke-LMStudioVision -Prompt $prompt -ImagePath $imageFiles.FullName -MaxTokens 300
            Write-Host "`nVision Analysis:" -ForegroundColor Green
            Write-Host $response -ForegroundColor White
        } catch {
            Write-Host "Vision analysis failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "No image files found for vision demo" -ForegroundColor Yellow
        Write-Host "To test vision functionality, place a .png or .jpg file in the current directory" -ForegroundColor Cyan
    }
    
    Wait-ForUser
} else {
    Write-Host "`n=== Demo 5: Vision Analysis (Skipped) ===" -ForegroundColor Magenta
    if ($SkipVision) {
        Write-Host "Vision demo skipped by user request" -ForegroundColor Yellow
    } else {
        Write-Host "API endpoint not available, skipping vision demo" -ForegroundColor Yellow
    }
    Wait-ForUser
}

# Demo 6: Error Handling and Validation
Write-Host "`n=== Demo 6: Error Handling and Input Validation ===" -ForegroundColor Magenta
Write-Host "Demonstrating how the module handles various edge cases...`n"

# Test 1: Empty prompt
try {
    Write-Host "Test 1: Empty prompt handling" -ForegroundColor Cyan
    $response = Invoke-LMStudioAPI -Prompt "" -MaxTokens 50
    Write-Host "Response to empty prompt: '$response'" -ForegroundColor White
} catch {
    Write-Host "✓ Empty prompt properly rejected: $($_.Exception.Message)" -ForegroundColor Green
}

# Test 2: Very long text (should be truncated)
try {
    Write-Host "`nTest 2: Long text truncation" -ForegroundColor Cyan
    $longText = "This is a test. " * 1000  # Very long text
    Write-Host "Original text length: $($longText.Length) characters"
    
    $response = Invoke-LMStudioAPI -Prompt $longText -MaxTokens 100
    Write-Host "✓ Long text handled successfully (truncated automatically)" -ForegroundColor Green
} catch {
    Write-Host "Long text handling failed: $($_.Exception.Message)" -ForegroundColor Red
}

Wait-ForUser

# Demo 7: Configuration Display
Write-Host "`n=== Demo 7: Module Configuration ===" -ForegroundColor Magenta
Write-Host "Current module configuration:`n"

# Display the configuration that was loaded
$configPath = ".\config.json"
if (Test-Path $configPath) {
    $config = Get-Content $configPath | ConvertFrom-Json
    $config.LMStudio | Format-List
} else {
    Write-Host "No config.json found, using default configuration" -ForegroundColor Yellow
}

Wait-ForUser

# Summary
Write-Host "`n=== Demo Complete ===" -ForegroundColor Cyan
Write-Host "Summary of demonstrated features:" -ForegroundColor Yellow
Write-Host "  ✓ Connection testing" -ForegroundColor Green
Write-Host "  ✓ Basic text generation" -ForegroundColor Green
Write-Host "  ✓ System prompt usage" -ForegroundColor Green

if (-not $SkipTTS -and $connectionResults.TTS.Status -eq "Connected") {
    Write-Host "  ✓ Text-to-speech generation" -ForegroundColor Green
} finally {
    Write-Host "  - Text-to-speech (skipped/unavailable)" -ForegroundColor Yellow
}

if (-not $SkipVision) {
    Write-Host "  ✓ Vision analysis capabilities" -ForegroundColor Green
} else {
    Write-Host "  - Vision analysis (skipped)" -ForegroundColor Yellow
}

Write-Host "  ✓ Error handling and validation" -ForegroundColor Green
Write-Host "  ✓ Configuration management" -ForegroundColor Green

Write-Host "`nThe LMStudio Integration module is ready for use!" -ForegroundColor Cyan
Write-Host "Available functions:" -ForegroundColor White
Write-Host "  - Invoke-LMStudioAPI" -ForegroundColor Gray
Write-Host "  - Invoke-LMStudioVision" -ForegroundColor Gray  
Write-Host "  - Invoke-LMStudioTTS" -ForegroundColor Gray
Write-Host "  - Test-LMStudioConnection" -ForegroundColor Gray
Write-Host "  - Start-LMStudioAudioPlayback" -ForegroundColor Gray

if ($Interactive) {
    Write-Host "`nWould you like to try any custom prompts? (y/n): " -NoNewline -ForegroundColor Cyan
    $customTest = Read-Host
    
    if ($customTest -eq 'y' -or $customTest -eq 'Y') {
        do {
            $userPrompt = Read-Host "`nEnter your prompt (or 'quit' to exit)"
            if ($userPrompt -ne 'quit' -and $userPrompt -ne '') {
                try {
                    $response = Invoke-LMStudioAPI -Prompt $userPrompt -MaxTokens 500
                    Write-Host "`nResponse:" -ForegroundColor Green
                    Write-Host $response -ForegroundColor White
                } catch {
                    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        } while ($userPrompt -ne 'quit')
    }
}

Write-Host "`nDemo completed successfully!" -ForegroundColor Green
