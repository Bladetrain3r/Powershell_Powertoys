# Critical Tool - Generate test cases from clipboard content
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# Ensure output directory exists
if (!(Test-Path "%appdata%\Local\Powertoys\Tests")) {
    New-Item -ItemType Directory -Path "%appdata%\Local\Powertoys\Tests" -Force
}

Write-Host "Critical Tool - Test Case Generator"
Write-Host "Analyzing clipboard content for test scenarios..."

try {
    # Get clipboard content
    $clipboardText = Get-Clipboard -Raw
    
    # Check if clipboard is empty or null
    if ([string]::IsNullOrWhiteSpace($clipboardText)) {
        Write-Host "Clipboard is empty or contains no text. Nothing to analyze."
        exit
    }
    
    Write-Host "Processing clipboard content ($(($clipboardText.Length)) characters)..."
    
    # Clean and sanitize the text for analysis
    $cleanText = $clipboardText -replace '[\x00-\x1F\x7F]', ' '  # Remove control characters
    $cleanText = $cleanText -replace '\\', '\\'                  # Escape backslashes
    $cleanText = $cleanText -replace '"', '\"'                   # Escape quotes
    $cleanText = $cleanText -replace "`t", ' '                   # Replace tabs with spaces
    $cleanText = $cleanText.Trim()
    
    # Truncate if too long (leaving room for prompt + JSON overhead)
    $maxInputLength = 16000
    if ($cleanText.Length -gt $maxInputLength) {
        $cleanText = $cleanText.Substring(0, $maxInputLength) + "... [content truncated for analysis]"
        Write-Host "Content truncated to $maxInputLength characters for processing"
    }
    
    # Detect content type and build appropriate prompt
    $contentType = "general"
    $analysisPrompt = ""
    
    # Code detection patterns
    if ($cleanText -match '(function|def |class |import |#include|public |private |void |int |string |bool |var |let |const |return)') {
        $contentType = "code"
        $analysisPrompt = @"
CONTENT TYPE: Programming Code
Analyze this code and generate comprehensive test cases. Include:

1. UNIT TESTS - Test individual functions/methods with various inputs
2. EDGE CASES - Boundary conditions, null/empty inputs, invalid data
3. INTEGRATION TESTS - How components work together
4. ERROR HANDLING - Expected failures and exception scenarios
5. PERFORMANCE TESTS - Load, stress, or timing considerations if relevant

For each test case, provide:
- Test name/description
- Input parameters or setup
- Expected output/behavior
- Test category (unit/integration/edge/error/performance)

CODE TO ANALYZE:
$cleanText
"@
    }
    # Mathematical content detection
    elseif ($cleanText -match '(\d+[\+\-\*\/\=]\d+|âˆ«|âˆ‘|âˆ‚|âˆš|Ï€|sin|cos|tan|log|ln|matrix|equation|theorem|proof|formula)') {
        $contentType = "mathematical"
        $analysisPrompt = @"
CONTENT TYPE: Mathematical Content
Analyze this mathematical content and generate test scenarios. Include:

1. CALCULATION VERIFICATION - Test computations with known results
2. BOUNDARY CONDITIONS - Test limits, extremes, special values
3. EDGE CASES - Zero, negative numbers, infinity, undefined conditions
4. ALTERNATIVE METHODS - Different approaches to verify results
5. ASSUMPTION VALIDATION - Test underlying mathematical assumptions

For each test case, provide:
- Test description
- Input values or conditions
- Expected mathematical result
- Method for verification
- Special considerations

MATHEMATICAL CONTENT TO ANALYZE:
$cleanText
"@
    }
    # Logical/procedural content detection
    elseif ($cleanText -match '(if |then |else |when |should |must |requires |steps|process|procedure|algorithm|logic|rule)') {
        $contentType = "logical"
        $analysisPrompt = @"
CONTENT TYPE: Logical/Procedural Content
Analyze this logical or procedural content and generate test scenarios. Include:

1. POSITIVE TESTS - Normal flow, expected conditions
2. NEGATIVE TESTS - Invalid inputs, unexpected conditions
3. BOUNDARY TESTS - Edge cases in logic or procedures
4. SEQUENCE TESTS - Order dependency, step validation
5. EXCEPTION HANDLING - What happens when things go wrong

For each test case, provide:
- Scenario description
- Preconditions/setup
- Test steps or inputs
- Expected outcome
- What this test validates

LOGICAL/PROCEDURAL CONTENT TO ANALYZE:
$cleanText
"@
    }
    # Data/specification content
    elseif ($cleanText -match '(data|table|list|specification|requirement|format|structure|schema|field|column)') {
        $contentType = "data"
        $analysisPrompt = @"
CONTENT TYPE: Data/Specification Content
Analyze this data or specification content and generate test scenarios. Include:

1. DATA VALIDATION - Format, type, range checks
2. COMPLETENESS TESTS - Required fields, missing data
3. CONSISTENCY TESTS - Cross-field validation, relationships
4. CONSTRAINT TESTS - Business rules, data limits
5. TRANSFORMATION TESTS - Data conversion, processing

For each test case, provide:
- Test objective
- Input data or conditions
- Validation criteria
- Expected result
- Type of validation (format/completeness/consistency/constraint/transformation)

DATA/SPECIFICATION TO ANALYZE:
$cleanText
"@
    }
    # General content fallback
    else {
        $analysisPrompt = @"
CONTENT TYPE: General Content
Analyze this content and generate relevant test scenarios. Include:

1. VALIDITY TESTS - Is the content accurate, complete, consistent?
2. ASSUMPTION TESTS - What assumptions does this content make?
3. SCENARIO TESTS - Different use cases or applications
4. BOUNDARY TESTS - Limits or edge cases mentioned
5. VERIFICATION TESTS - How could claims/statements be verified?

For each test case, provide:
- Test purpose
- What to examine or verify
- How to conduct the test
- Expected findings
- What this reveals about the content

CONTENT TO ANALYZE:
$cleanText
"@
    }
    
    Write-Host "Detected content type: $contentType"
    Write-Host "Generating test cases..."
    
    # API request for test case generation
    $testBody = @{
        model = "gemma-3-4b-it-qat"
        messages = @(
            @{
                role = "user"
                content = $analysisPrompt
            }
        )
        max_tokens = 2000
        temperature = 0.3
    } | ConvertTo-Json -Depth 5
    
    # Send to LMStudio API
    $headers = @{
        'Content-Type' = 'application/json; charset=utf-8'
    }
    
    $testBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($testBody)
    $testResponse = Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/chat/completions" -Method POST -Body $testBodyBytes -Headers $headers
    $testData = $testResponse.Content | ConvertFrom-Json
    $testCases = $testData.choices[0].message.content
    
    Write-Host "Test case generation complete"
    
    # Generate a concise summary for TTS
    Write-Host "Creating summary..."
    $summaryBody = @{
        model = "gemma-3-4b-it-qat"
        messages = @(
            @{
                role = "user"
                content = "Summarize these test cases in 2-3 sentences. Focus on the main types of tests suggested and key areas to validate. Make it suitable for text-to-speech:`n`n$testCases"
            }
        )
        max_tokens = 500
        temperature = 0.2
    } | ConvertTo-Json -Depth 5
    
    $summaryBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($summaryBody)
    $summaryResponse = Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/chat/completions" -Method POST -Body $summaryBodyBytes -Headers $headers
    $summaryResponseData = $summaryResponse.Content | ConvertFrom-Json
    $testSummary = $summaryResponseData.choices[0].message.content
    
    # Save outputs
    $originalPath = "%appdata%\Local\Powertoys\Tests\critical_original_$timestamp.txt"
    $testCasesPath = "%appdata%\Local\Powertoys\Tests\critical_tests_$timestamp.txt"
    $summaryPath = "%appdata%\Local\Powertoys\Tests\critical_summary_$timestamp.txt"
    
    # Create comprehensive output
    $fullOutput = @"
CRITICAL TOOL ANALYSIS - $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Content Type: $contentType
Content Length: $($clipboardText.Length) characters

GENERATED TEST CASES:
$testCases

SUMMARY:
$testSummary

---
Original content saved to: $originalPath
Generated: $(Get-Date)
"@
    
    $clipboardText | Out-File -FilePath $originalPath -Encoding UTF8
    $testCases | Out-File -FilePath $testCasesPath -Encoding UTF8
    $fullOutput | Out-File -FilePath $summaryPath -Encoding UTF8
    
    # Copy test cases to clipboard
    $testCases | Set-Clipboard
    
    Write-Host ""
    Write-Host "Critical Tool Analysis Complete!"
    Write-Host "Content Type: $contentType"
    Write-Host "Files generated:"
    Write-Host "- Original content: $originalPath"
    Write-Host "- Test cases: $testCasesPath"
    Write-Host "- Full analysis: $summaryPath"
    Write-Host "Test cases copied to clipboard"
    Write-Host ""
    Write-Host "SUMMARY:"
    Write-Host $testSummary
    Write-Host ""
    
    # Generate and play audio summary
    Write-Host "Generating audio summary..."
    try {
        $audioText = "Critical Tool Analysis: $testSummary"
        
        $ttsBody = @{
            model = "kokoro"
            input = $audioText
            voice = "af_sky"
            response_format = "mp3"
            speed = 1.0
            stream = $false
        } | ConvertTo-Json -Depth 3
        
        $audioPath = "%appdata%\Local\Powertoys\Tests\critical_summary_$timestamp.mp3"
        
        $ttsHeaders = @{
            'Content-Type' = 'application/json; charset=utf-8'
            'Accept' = 'audio/mpeg'
        }
        
        $ttsBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($ttsBody)
        $ttsResponse = Invoke-WebRequest -Uri "http://127.0.0.1:8880/v1/audio/speech" -Method POST -Body $ttsBodyBytes -Headers $ttsHeaders
        [System.IO.File]::WriteAllBytes($audioPath, $ttsResponse.Content)
        
        Start-Sleep 1
        Start-Process -FilePath "C:\Program Files\VideoLAN\VLC\vlc.exe" -ArgumentList "--intf dummy --play-and-exit `"$audioPath`"" -NoNewWindow -Wait
        
        Write-Host "Audio summary played!"
        
    } catch {
        Write-Host "TTS Error: $($_.Exception.Message)"
    }
    
    Write-Host ""
    Write-Host "TEST CASES PREVIEW:"
    Write-Host ($testCases.Substring(0, [Math]::Min(500, $testCases.Length)) + "...")
    
} catch {
    Write-Host "Error processing clipboard or calling API: $($_.Exception.Message)"
}
