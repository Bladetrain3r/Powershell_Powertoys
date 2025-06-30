# Module Tests

This directory contains test scripts for all PowerShell modules with simulated endpoints.

## Test Files

- `Utils.Tests.ps1` - Tests for the Utils module functions
- `ClaudeIntegration.Tests.ps1` - Tests for Claude API integration with mocked endpoints
- `LMStudioIntegration.Tests.ps1` - Tests for LMStudio integration with mocked endpoints
- `Run-AllTests.ps1` - Test runner that executes all tests

## Running Tests

### Run All Tests
```powershell
.\Run-AllTests.ps1
```

### Run Specific Test
```powershell
.\Utils.Tests.ps1
.\ClaudeIntegration.Tests.ps1
.\LMStudioIntegration.Tests.ps1
```

### Run Tests with Filter
```powershell
# Run only Claude tests
.\Run-AllTests.ps1 -TestFilter "Claude*"

# Run only Utils tests
.\Run-AllTests.ps1 -TestFilter "Utils*"
```

## Test Features

### Mocked Endpoints
- All tests use simulated API endpoints
- No actual network calls are made
- Tests are completely self-contained

### Function Coverage
- **Utils**: Text processing, file operations, logging, JSON conversion
- **ClaudeIntegration**: API calls, vision processing, connection testing
- **LMStudioIntegration**: Chat completions, vision, TTS, connection testing

### Test Output
- Color-coded results (Green = Pass, Red = Fail, Yellow = Info)
- Execution timing
- Detailed error reporting
- Summary statistics

## Example Output
```
=====================================
PowerShell Module Test Runner
Started at: 06/30/2025 20:03:06
=====================================

Running test: ClaudeIntegration.Tests.ps1
----------------------------------------
Testing ClaudeIntegration Module...
Test 1: API Key Management
PASS: API Key management works correctly
Test 2: Module Loading
PASS: ClaudeIntegration module loaded successfully
  - Exported functions: 6
Test 3: Function Availability
  PASS: Set-ClaudeApiKey available
  PASS: Get-ClaudeApiKey available
  ...
PASS: All expected functions are available
PASSED: ClaudeIntegration.Tests.ps1 (Duration: 0.064s)

=====================================
Test Summary
=====================================
Total Tests: 3
Passed: 3
Failed: 0
Total Duration: 0.135s

All tests passed!
```

## Adding New Tests

1. Create a new `.Tests.ps1` file in this directory
2. Import the module being tested
3. Mock any external dependencies
4. Write test cases with descriptive output
5. The test runner will automatically discover and execute the new test file
