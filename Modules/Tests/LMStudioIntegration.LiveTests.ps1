# LMStudioIntegration.LiveTests.ps1
# Live tests for LMStudio integration using real API calls
# Requires LMStudio to be running with the specified models

param(
    [string]$ApiEndpoint = "http://localhost:1234",
    [string]$TtsEndpoint = "http://localhost:8880",
    [string]$DefaultModel = "gemma3-1b-it-qat",
    [string]$VisionModel = "gemma-3-4b-it-qat",
    [switch]$SkipTTS,
    [switch]$SkipVision
)

# Import the module
Import-Module (Join-Path $PSScriptRoot "..\LMStudioIntegration.psm1") -Force

Write-Host "=====================================" -ForegroundColor Magenta
Write-Host "LMStudio Integration Live Tests" -ForegroundColor Magenta
Write-Host "=====================================" -ForegroundColor Magenta
Write-Host "API Endpoint: $ApiEndpoint" -ForegroundColor Gray
Write-Host "TTS Endpoint: $TtsEndpoint" -ForegroundColor Gray
Write-Host "Default Model: $DefaultModel" -ForegroundColor Gray
Write-Host "Vision Model: $VisionModel" -ForegroundColor Gray
Write-Host ""

$testResults = @()
$testStartTime = Get-Date

# Test 1: Connection Test
Write-Host "Test 1: Connection Test" -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Yellow
try {
    $connectionTest = Test-LMStudioConnection -IncludeTTS:(-not $SkipTTS)
    
    if ($connectionTest.API.Status -eq "Connected") {
        Write-Host "PASS: API connection successful" -ForegroundColor Green
        Write-Host "  Status Code: $($connectionTest.API.StatusCode)" -ForegroundColor Gray
        $testResults += [PSCustomObject]@{ Test = "API Connection"; Status = "PASS"; Details = "Connected" }
    } else {
        Write-Host "FAIL: API connection failed" -ForegroundColor Red
        Write-Host "  Error: $($connectionTest.API.Error)" -ForegroundColor Red
        $testResults += [PSCustomObject]@{ Test = "API Connection"; Status = "FAIL"; Details = $connectionTest.API.Error }
    }
    
    if (-not $SkipTTS -and $connectionTest.TTS) {
        if ($connectionTest.TTS.Status -eq "Connected") {
            Write-Host "PASS: TTS connection successful" -ForegroundColor Green
            $testResults += [PSCustomObject]@{ Test = "TTS Connection"; Status = "PASS"; Details = "Connected" }
        } else {
            Write-Host "FAIL: TTS connection failed" -ForegroundColor Red
            Write-Host "  Error: $($connectionTest.TTS.Error)" -ForegroundColor Red
            $testResults += [PSCustomObject]@{ Test = "TTS Connection"; Status = "FAIL"; Details = $connectionTest.TTS.Error }
        }
    }
} catch {
    Write-Host "FAIL: Connection test failed: $($_.Exception.Message)" -ForegroundColor Red
    $testResults += [PSCustomObject]@{ Test = "Connection Test"; Status = "FAIL"; Details = $_.Exception.Message }
}
Write-Host ""

# Test 2: Simple Text Completion
Write-Host "Test 2: Simple Text Completion ($DefaultModel)" -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Yellow
try {
    $prompt = "What is 2+2? Answer with just the number."
    Write-Host "Prompt: $prompt" -ForegroundColor Gray
    
    $response = Invoke-LMStudioAPI -Prompt $prompt -Model $DefaultModel -MaxTokens 50 -Temperature 0.1
    
    if ($response -and $response.Trim().Length -gt 0) {
        Write-Host "PASS: Text completion successful" -ForegroundColor Green
        Write-Host "Response: $($response.Trim())" -ForegroundColor Gray
        $testResults += [PSCustomObject]@{ Test = "Text Completion"; Status = "PASS"; Details = "Response: $($response.Trim())" }
    } else {
        Write-Host "FAIL: Empty or null response" -ForegroundColor Red
        $testResults += [PSCustomObject]@{ Test = "Text Completion"; Status = "FAIL"; Details = "Empty response" }
    }
} catch {
    Write-Host "FAIL: Text completion failed: $($_.Exception.Message)" -ForegroundColor Red
    $testResults += [PSCustomObject]@{ Test = "Text Completion"; Status = "FAIL"; Details = $_.Exception.Message }
}
Write-Host ""

# Test 3: Longer Conversation
Write-Host "Test 3: Longer Conversation ($DefaultModel)" -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Yellow
try {
    $prompt = "Explain what PowerShell is in exactly one sentence."
    Write-Host "Prompt: $prompt" -ForegroundColor Gray
    
    $response = Invoke-LMStudioAPI -Prompt $prompt -Model $DefaultModel -MaxTokens 200 -Temperature 0.3
    
    if ($response -and $response.Trim().Length -gt 20) {
        Write-Host "PASS: Longer conversation successful" -ForegroundColor Green
        Write-Host "Response: $($response.Trim())" -ForegroundColor Gray
        $testResults += [PSCustomObject]@{ Test = "Longer Conversation"; Status = "PASS"; Details = "Length: $($response.Length) chars" }
    } else {
        Write-Host "FAIL: Response too short or empty" -ForegroundColor Red
        $testResults += [PSCustomObject]@{ Test = "Longer Conversation"; Status = "FAIL"; Details = "Response too short" }
    }
} catch {
    Write-Host "FAIL: Longer conversation failed: $($_.Exception.Message)" -ForegroundColor Red
    $testResults += [PSCustomObject]@{ Test = "Longer Conversation"; Status = "FAIL"; Details = $_.Exception.Message }
}
Write-Host ""

# Test 4: System Prompt
Write-Host "Test 4: System Prompt Test ($DefaultModel)" -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Yellow
try {
    $systemPrompt = "You are a helpful assistant that always responds in exactly 3 words."
    $prompt = "What is the weather like?"
    Write-Host "System: $systemPrompt" -ForegroundColor Gray
    Write-Host "Prompt: $prompt" -ForegroundColor Gray
    
    $response = Invoke-LMStudioAPI -Prompt $prompt -SystemPrompt $systemPrompt -Model $DefaultModel -MaxTokens 50 -Temperature 0.1
    
    if ($response -and $response.Trim().Length -gt 0) {
        $wordCount = ($response.Trim() -split '\s+').Count
        Write-Host "PASS: System prompt response received" -ForegroundColor Green
        Write-Host "Response: $($response.Trim()) (Words: $wordCount)" -ForegroundColor Gray
        $testResults += [PSCustomObject]@{ Test = "System Prompt"; Status = "PASS"; Details = "Words: $wordCount" }
    } else {
        Write-Host "FAIL: No response with system prompt" -ForegroundColor Red
        $testResults += [PSCustomObject]@{ Test = "System Prompt"; Status = "FAIL"; Details = "No response" }
    }
} catch {
    Write-Host "FAIL: System prompt test failed: $($_.Exception.Message)" -ForegroundColor Red
    $testResults += [PSCustomObject]@{ Test = "System Prompt"; Status = "FAIL"; Details = $_.Exception.Message }
}
Write-Host ""

# Test 5: Vision Test (if not skipped)
if (-not $SkipVision) {
    Write-Host "Test 5: Vision Test ($VisionModel)" -ForegroundColor Yellow
    Write-Host "----------------------------------------" -ForegroundColor Yellow
    try {
        # Create a simple test image (solid color)
        $testImagePath = Join-Path $env:TEMP "lmstudio_test_image.png"
        
        # Create a simple 100x100 red PNG using .NET
        Add-Type -AssemblyName System.Drawing
        $bitmap = New-Object System.Drawing.Bitmap(100, 100)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.Clear([System.Drawing.Color]::Red)
        $graphics.DrawString("TEST", (New-Object System.Drawing.Font("Arial", 20)), [System.Drawing.Brushes]::White, 10, 40)
        $graphics.Dispose()
        $bitmap.Save($testImagePath, [System.Drawing.Imaging.ImageFormat]::Png)
        $bitmap.Dispose()
        
        $prompt = "What color is this image and what text does it contain?"
        Write-Host "Prompt: $prompt" -ForegroundColor Gray
        Write-Host "Image: Test image created at $testImagePath" -ForegroundColor Gray
        
        $response = Invoke-LMStudioVision -Prompt $prompt -ImagePath $testImagePath -Model $VisionModel -MaxTokens 100
        
        if ($response -and $response.Trim().Length -gt 0) {
            Write-Host "PASS: Vision test successful" -ForegroundColor Green
            Write-Host "Response: $($response.Trim())" -ForegroundColor Gray
            $testResults += [PSCustomObject]@{ Test = "Vision"; Status = "PASS"; Details = "Response: $($response.Trim())" }
        } else {
            Write-Host "FAIL: Empty vision response" -ForegroundColor Red
            $testResults += [PSCustomObject]@{ Test = "Vision"; Status = "FAIL"; Details = "Empty response" }
        }
        
        # Clean up test image
        if (Test-Path $testImagePath) {
            Remove-Item $testImagePath -Force -ErrorAction SilentlyContinue
        }
        
    } catch {
        Write-Host "FAIL: Vision test failed: $($_.Exception.Message)" -ForegroundColor Red
        $testResults += [PSCustomObject]@{ Test = "Vision"; Status = "FAIL"; Details = $_.Exception.Message }
    }
    Write-Host ""
} else {
    Write-Host "Test 5: Vision Test - SKIPPED" -ForegroundColor Yellow
    Write-Host ""
}

# Test 6: TTS Test (if not skipped)
if (-not $SkipTTS) {
    Write-Host "Test 6: TTS Test" -ForegroundColor Yellow
    Write-Host "----------------------------------------" -ForegroundColor Yellow
    try {
        $ttsText = "This is a test of the text to speech functionality."
        Write-Host "Text: $ttsText" -ForegroundColor Gray
        
        $audioPath = Invoke-LMStudioTTS -Text $ttsText -Voice "af_sky" -OutputPath (Join-Path $env:TEMP "lmstudio_test.mp3")
        
        if (Test-Path $audioPath) {
            $fileSize = (Get-Item $audioPath).Length
            Write-Host "PASS: TTS test successful" -ForegroundColor Green
            Write-Host "Audio saved: $audioPath (Size: $fileSize bytes)" -ForegroundColor Gray
            $testResults += [PSCustomObject]@{ Test = "TTS"; Status = "PASS"; Details = "File size: $fileSize bytes" }
            
            # Clean up audio file
            Remove-Item $audioPath -Force -ErrorAction SilentlyContinue
        } else {
            Write-Host "FAIL: Audio file not created" -ForegroundColor Red
            $testResults += [PSCustomObject]@{ Test = "TTS"; Status = "FAIL"; Details = "File not created" }
        }
    } catch {
        Write-Host "FAIL: TTS test failed: $($_.Exception.Message)" -ForegroundColor Red
        $testResults += [PSCustomObject]@{ Test = "TTS"; Status = "FAIL"; Details = $_.Exception.Message }
    }
    Write-Host ""
} else {
    Write-Host "Test 6: TTS Test - SKIPPED" -ForegroundColor Yellow
    Write-Host ""
}

# Results Summary
$testEndTime = Get-Date
$totalDuration = $testEndTime - $testStartTime
$passedTests = ($testResults | Where-Object { $_.Status -eq "PASS" }).Count
$failedTests = ($testResults | Where-Object { $_.Status -eq "FAIL" }).Count

Write-Host "=====================================" -ForegroundColor Magenta
Write-Host "Live Test Results Summary" -ForegroundColor Magenta
Write-Host "=====================================" -ForegroundColor Magenta
Write-Host "Total Tests: $($passedTests + $failedTests)" -ForegroundColor White
Write-Host "Passed: $passedTests" -ForegroundColor Green
Write-Host "Failed: $failedTests" -ForegroundColor Red
Write-Host "Duration: $($totalDuration.TotalSeconds)s" -ForegroundColor White
Write-Host ""

Write-Host "Detailed Results:" -ForegroundColor Cyan
$testResults | Format-Table -AutoSize

if ($failedTests -eq 0) {
    Write-Host "All live tests passed! LMStudio integration is working correctly." -ForegroundColor Green
    exit 0
} else {
    Write-Host "Some live tests failed. Check LMStudio configuration and model availability." -ForegroundColor Red
    exit 1
}
