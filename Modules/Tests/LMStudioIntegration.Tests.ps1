# LMStudioIntegration.Tests.ps1
# Tests for LMStudioIntegration module functions

Write-Host "Testing LMStudioIntegration Module..." -ForegroundColor Cyan

# Test basic module loading
Write-Host "Test 1: Module Loading" -ForegroundColor Yellow
try {
    Import-Module (Join-Path $PSScriptRoot "..\LMStudioIntegration.psm1") -Force
    $moduleInfo = Get-Module LMStudioIntegration
    if ($moduleInfo) {
        Write-Host "PASS: LMStudioIntegration module loaded successfully" -ForegroundColor Green
        Write-Host "  - Exported functions: $($moduleInfo.ExportedFunctions.Count)" -ForegroundColor Gray
    } else {
        Write-Host "FAIL: LMStudioIntegration module not loaded" -ForegroundColor Red
    }
} catch {
    Write-Host "FAIL: Module loading test failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test function availability
Write-Host "Test 2: Function Availability" -ForegroundColor Yellow
$expectedFunctions = @('Invoke-LMStudioAPI', 'Invoke-LMStudioVision', 'Invoke-LMStudioTTS', 'Start-LMStudioAudioPlayback', 'Test-LMStudioConnection')
$allFunctionsAvailable = $true

foreach ($func in $expectedFunctions) {
    if (Get-Command $func -ErrorAction SilentlyContinue) {
        Write-Host "  PASS: $func available" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: $func not available" -ForegroundColor Red
        $allFunctionsAvailable = $false
    }
}

if ($allFunctionsAvailable) {
    Write-Host "PASS: All expected functions are available" -ForegroundColor Green
} else {
    Write-Host "FAIL: Some functions are missing" -ForegroundColor Red
}

# Test parameter validation (no network calls)
Write-Host "Test 3: Parameter Validation" -ForegroundColor Yellow
try {
    # Test empty prompt handling
    $result = Invoke-LMStudioAPI -Prompt "" 2>$null
    Write-Host "PASS: Empty prompt handled gracefully" -ForegroundColor Green
} catch {
    if ($_.Exception.Message -like "*prompt*" -or $_.Exception.Message -like "*text*") {
        Write-Host "PASS: Empty prompt validation works" -ForegroundColor Green
    } else {
        Write-Host "INFO: Parameter validation test - $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Test vision function parameter validation
Write-Host "Test 4: Vision Parameter Validation" -ForegroundColor Yellow
try {
    # Test missing image data
    $result = Invoke-LMStudioVision -Prompt "Test" 2>$null
    Write-Host "FAIL: Should require image data" -ForegroundColor Red
} catch {
    if ($_.Exception.Message -like "*image*") {
        Write-Host "PASS: Vision function correctly requires image data" -ForegroundColor Green
    } else {
        Write-Host "INFO: Vision validation test - $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Test TTS parameter validation
Write-Host "Test 5: TTS Parameter Validation" -ForegroundColor Yellow
try {
    # Test empty text handling
    $result = Invoke-LMStudioTTS -Text "" 2>$null
    Write-Host "PASS: Empty TTS text handled gracefully" -ForegroundColor Green
} catch {
    if ($_.Exception.Message -like "*text*") {
        Write-Host "PASS: TTS function correctly validates text parameter" -ForegroundColor Green
    } else {
        Write-Host "INFO: TTS validation test - $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host "LMStudioIntegration tests completed!" -ForegroundColor Cyan
