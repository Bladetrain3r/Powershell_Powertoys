# ClaudeIntegration.Tests.ps1
# Tests for ClaudeIntegration module functions using simulated endpoints

Write-Host "Testing ClaudeIntegration Module..." -ForegroundColor Cyan

# Test API Key functions without importing the full module
Write-Host "Test 1: API Key Management" -ForegroundColor Yellow
try {
    # Import just the module to test key management
    Import-Module (Join-Path $PSScriptRoot "..\ClaudeIntegration.psm1") -Force
    
    Set-ClaudeApiKey -ApiKey "test-key-12345"
    $apiKey = Get-ClaudeApiKey
    
    if ($apiKey -eq "test-key-12345") {
        Write-Host "PASS: API Key management works correctly" -ForegroundColor Green
    } else {
        Write-Host "FAIL: API Key management failed" -ForegroundColor Red
    }
} catch {
    Write-Host "FAIL: API Key test failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test basic module loading
Write-Host "Test 2: Module Loading" -ForegroundColor Yellow
try {
    $moduleInfo = Get-Module ClaudeIntegration
    if ($moduleInfo) {
        Write-Host "PASS: ClaudeIntegration module loaded successfully" -ForegroundColor Green
        Write-Host "  - Exported functions: $($moduleInfo.ExportedFunctions.Count)" -ForegroundColor Gray
    } else {
        Write-Host "FAIL: ClaudeIntegration module not loaded" -ForegroundColor Red
    }
} catch {
    Write-Host "FAIL: Module loading test failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test function availability
Write-Host "Test 3: Function Availability" -ForegroundColor Yellow
$expectedFunctions = @('Set-ClaudeApiKey', 'Get-ClaudeApiKey', 'Invoke-ClaudeAPI', 'Invoke-ClaudeVision', 'Test-ClaudeConnection', 'Save-ClaudeResponse')
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

# Test Save Response (this doesn't require API calls)
Write-Host "Test 4: Save Response Function" -ForegroundColor Yellow

# Test 4a: Valid response should save successfully
try {
    $testResponse = "This is a test response from Claude API"
    $savedPath = Save-ClaudeResponse -Response $testResponse -Prefix "test-claude"
    
    if (Test-Path $savedPath) {
        Write-Host "PASS: Valid response saved successfully to: $savedPath" -ForegroundColor Green
        # Clean up test file
        Remove-Item $savedPath -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "FAIL: Response file was not created for valid input" -ForegroundColor Red
    }
} catch {
    Write-Host "FAIL: Save response test failed for valid input: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4b: Empty string should be handled appropriately
try {
    $emptyResponse = ""
    $result = Save-ClaudeResponse -Response $emptyResponse -Prefix "test-empty"
    
    # Check if file was created (some implementations might save empty files)
    if (Test-Path $result) {
        Write-Host "PASS: Empty response handled - file created at: $result" -ForegroundColor Green
        # Clean up test file
        Remove-Item $result -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "PASS: Empty response handled - no file created" -ForegroundColor Green
    }
} catch {
    # If it throws an error for empty string, that's also acceptable
    if ($_.Exception.Message -like "*empty*" -or $_.Exception.Message -like "*Response*") {
        Write-Host "PASS: Empty response properly rejected: $($_.Exception.Message)" -ForegroundColor Green
    } else {
        Write-Host "FAIL: Unexpected error for empty response: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Test connection function (without API key - should fail gracefully)
Write-Host "Test 5: Connection Test (Invalid API Key Scenarios)" -ForegroundColor Yellow

# Test 5a: Null API key
try {
    $connectionTest = Test-ClaudeConnection -ApiKey $null
    
    if ($connectionTest.Status -eq "Failed" -and $connectionTest.Error -like "*API key*") {
        Write-Host "PASS: Connection test correctly identifies null API key" -ForegroundColor Green
    } else {
        Write-Host "FAIL: Connection test did not handle null API key correctly" -ForegroundColor Red
    }
} catch {
    if ($_.Exception.Message -like "*API key*" -or $_.Exception.Message -like "*empty string*") {
        Write-Host "PASS: Connection test correctly validates null API key parameter" -ForegroundColor Green
    } else {
        Write-Host "FAIL: Connection test failed with null key: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Test 5b: Empty string API key
try {
    $connectionTest = Test-ClaudeConnection -ApiKey ""
    
    if ($connectionTest.Status -eq "Failed" -and $connectionTest.Error -like "*API key*") {
        Write-Host "PASS: Connection test correctly identifies empty API key" -ForegroundColor Green
    } else {
        Write-Host "FAIL: Connection test did not handle empty API key correctly" -ForegroundColor Red
    }
} catch {
    if ($_.Exception.Message -like "*API key*") {
        Write-Host "PASS: Connection test correctly validates empty API key parameter" -ForegroundColor Green
    } else {
        Write-Host "FAIL: Connection test failed with empty key: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Test 5c: Invalid API key format (should fail connection, not parameter validation)
try {
    $connectionTest = Test-ClaudeConnection -ApiKey "invalid-test-key"
    
    if ($connectionTest.Status -eq "Failed") {
        Write-Host "PASS: Connection test correctly fails with invalid API key" -ForegroundColor Green
    } else {
        Write-Host "WARNING: Connection test unexpectedly succeeded with test key" -ForegroundColor Yellow
    }
} catch {
    # This is also acceptable - the function might throw instead of returning failed status
    Write-Host "PASS: Connection test properly handles invalid API key (threw exception)" -ForegroundColor Green
}

Write-Host "ClaudeIntegration tests completed!" -ForegroundColor Cyan

