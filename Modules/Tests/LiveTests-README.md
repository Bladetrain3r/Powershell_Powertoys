# LMStudio Live Tests

This directory contains live integration tests that make actual API calls to verify LMStudio functionality.

## Prerequisites

### Required Software
- **LMStudio** running and accessible
- **Models loaded** in LMStudio:
  - `gemma3-1b-it-qat` (for most tests)
  - `gemma-3-4b-it-qat` (for vision tests)
- **TTS endpoint** (optional, can be skipped)

### LMStudio Setup
1. Start LMStudio
2. Load the required models
3. Ensure API is accessible at `http://localhost:1234`
4. (Optional) Ensure TTS is accessible at `http://localhost:8880`

## Running Live Tests

### Basic Usage
```powershell
# Run all tests with default settings
.\LMStudioIntegration.LiveTests.ps1
```

### Skip Specific Tests
```powershell
# Skip TTS tests
.\LMStudioIntegration.LiveTests.ps1 -SkipTTS

# Skip Vision tests
.\LMStudioIntegration.LiveTests.ps1 -SkipVision

# Skip both TTS and Vision
.\LMStudioIntegration.LiveTests.ps1 -SkipTTS -SkipVision
```

### Custom Endpoints and Models
```powershell
# Custom API endpoint
.\LMStudioIntegration.LiveTests.ps1 -ApiEndpoint "http://192.168.1.100:1234"

# Custom models
.\LMStudioIntegration.LiveTests.ps1 -DefaultModel "llama2-7b" -VisionModel "llava-1.5-7b"

# Custom TTS endpoint
.\LMStudioIntegration.LiveTests.ps1 -TtsEndpoint "http://localhost:9000"
```

## Test Coverage

### Test 1: Connection Test
- Verifies API connectivity
- Tests TTS endpoint (if not skipped)
- Checks HTTP status codes

### Test 2: Simple Text Completion
- Basic prompt: "What is 2+2? Answer with just the number."
- Uses `gemma3-1b-it-qat` model
- Low temperature (0.1) for consistent results

### Test 3: Longer Conversation
- More complex prompt about PowerShell
- Tests longer response generation
- Uses higher token limit (200)

### Test 4: System Prompt
- Tests system prompt functionality
- Verifies model follows instructions
- Measures response adherence

### Test 5: Vision Test
- Creates a test image programmatically
- Uses `gemma-3-4b-it-qat` model
- Tests image analysis capabilities
- Automatically cleans up test files

### Test 6: TTS Test
- Tests text-to-speech functionality
- Creates audio file
- Verifies file generation
- Cleans up test files

## Expected Output

```
=====================================
LMStudio Integration Live Tests
=====================================
API Endpoint: http://localhost:1234
TTS Endpoint: http://localhost:8880
Default Model: gemma3-1b-it-qat
Vision Model: gemma-3-4b-it-qat

Test 1: Connection Test
----------------------------------------
PASS: API connection successful
  Status Code: 200

Test 2: Simple Text Completion (gemma3-1b-it-qat)
----------------------------------------
Prompt: What is 2+2? Answer with just the number.
PASS: Text completion successful
Response: 4

...

=====================================
Live Test Results Summary
=====================================
Total Tests: 6
Passed: 6
Failed: 0
Duration: 15.5s

All live tests passed! LMStudio integration is working correctly.
```

## Troubleshooting

### Common Issues

**Connection Failed**
- Verify LMStudio is running
- Check if models are loaded
- Confirm API endpoint is accessible

**Model Not Found**
- Ensure specified models are loaded in LMStudio
- Use `-DefaultModel` and `-VisionModel` parameters to specify available models

**TTS Fails**
- Check if TTS endpoint is running
- Use `-SkipTTS` to disable TTS tests
- Verify TTS endpoint URL with `-TtsEndpoint`

**Vision Fails**
- Ensure vision model supports image inputs
- Check if vision model is properly loaded
- Use `-SkipVision` to disable vision tests

### Performance Notes
- Vision tests take longer due to image processing
- TTS tests require file I/O operations
- Total test time varies based on model speed and hardware
