# Code Analyzer - Iteration 2 of self-improvement
param(
    [ValidateScript({
        if (!(Test-Path $_ -PathType Container)) {
            throw "Input path '$_' does not exist or is not a directory"
        }
        $true
    })]
    [string]$InputPath = ".",
    
    [ValidateNotNullOrEmpty()]
    [string[]]$FileExtensions = @("*.ps1", "*.py", "*.js", "*.ts", "*.java", "*.cs", "*.cpp", "*.c", "*.php", "*.rb", "*.go", "*.sql", "*.bat", "*.cmd"),
    
    [ValidateRange(1, 250)]
    [int]$MaxFiles = 25,
    
    [ValidateRange(1KB, 50MB)]
    [int]$MaxFileSize = 2MB,
    
    [switch]$Recursive,
    [string]$OutputDirectory = "%appdata%\Local\Powertoys\CodeAnalysis",
    [switch]$SkipAudio,
    [switch]$IncludeSelfAnalysis,
    
    [ValidateNotNullOrEmpty()]
    [string]$ApiEndpoint = "http://127.0.0.1:1234",
    
    [ValidateNotNullOrEmpty()]
    [string]$ModelName = "gemma-3-12b-it-qat",
    
    [ValidateRange(30, 600)]
    [int]$ApiTimeout = 300
)

# Initialize core variables
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$scriptName = Split-Path -Leaf $MyInvocation.MyCommand.Name

# Validate and create output directory
if (!(Test-Path $OutputDirectory -PathType Container)) {
    try {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
        Write-Host "Created output directory: $OutputDirectory" -ForegroundColor Green
    } catch {
        throw "Cannot create output directory '$OutputDirectory': $($_.Exception.Message)"
    }
}

Write-Host "Code Analyzer v1.4 - Second iteration..." -ForegroundColor Green
Write-Host "Input Path: $InputPath | API: $ApiEndpoint | Model: $ModelName"

# Streamlined logging with better performance
$logPath = Join-Path $OutputDirectory "analyzer_log_$timestamp.txt"
function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message, 
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    # IMPROVEMENT: Only log important events to reduce verbosity
    if ($Level -in @("ERROR", "WARN", "SUCCESS")) {
        $timestamp = Get-Date -Format "HH:mm:ss"
        $logMessage = "[$timestamp] [$Level] $Message"
        
        $color = switch ($Level) {
            "ERROR" { "Red" }
            "WARN" { "Yellow" }
            "SUCCESS" { "Green" }
            default { "White" }
        }
        Write-Host $logMessage -ForegroundColor $color
        
        # Write to log file silently
        try {
            $logMessage | Out-File -FilePath $logPath -Append -Encoding UTF8 -ErrorAction SilentlyContinue
        } catch {
            # Silent failure for logging
        }
    }
}

# IMPROVEMENT: Enhanced circuit breaker with better state management
class RobustCircuitBreaker {
    [int]$FailureCount = 0
    [int]$MaxFailures = 3
    [datetime]$LastFailureTime = [datetime]::MinValue
    [int]$BackoffSeconds = 1
    [bool]$IsOpen = $false
    [int]$HalfOpenAttempts = 0
    [int]$MaxHalfOpenAttempts = 1
    
    [bool] ShouldAttempt() {
        if (!$this.IsOpen) { return $true }
        
        # Half-open state: allow limited attempts after cooldown
        $timeSinceFailure = (Get-Date) - $this.LastFailureTime
        if ($timeSinceFailure.TotalSeconds -gt $this.BackoffSeconds) {
            if ($this.HalfOpenAttempts -lt $this.MaxHalfOpenAttempts) {
                $this.HalfOpenAttempts++
                return $true
            }
        }
        return $false
    }
    
    [void] RecordSuccess() {
        $this.FailureCount = 0
        $this.BackoffSeconds = 1
        $this.IsOpen = $false
        $this.HalfOpenAttempts = 0
    }
    
    [void] RecordFailure() {
        $this.FailureCount++
        $this.LastFailureTime = Get-Date
        
        if ($this.FailureCount -ge $this.MaxFailures) {
            $this.IsOpen = $true
            $this.HalfOpenAttempts = 0
            # Exponential backoff with cap
            $this.BackoffSeconds = [math]::Min(300, [math]::Pow(2, $this.FailureCount) + (Get-Random -Min 1 -Max 5))
        }
    }
    
    [string] GetState() {
        if ($this.IsOpen) { return "OPEN" }
        elseif ($this.HalfOpenAttempts -gt 0) { return "HALF-OPEN" }
        else { return "CLOSED" }
    }
}

$script:circuitBreaker = [RobustCircuitBreaker]::new()

# IMPROVEMENT: Enhanced file discovery with better symbolic link handling
try {
    Write-Log "Discovering files to analyze..." "INFO"
    $allFiles = @()
    
    foreach ($ext in $FileExtensions) {
        try {
            $searchParams = @{
                Path = $InputPath
                Filter = $ext
                File = $true
                ErrorAction = 'SilentlyContinue'
            }
            
            if ($Recursive) {
                $searchParams.Recurse = $true
            }
            
            $files = Get-ChildItem @searchParams | Where-Object { 
                # IMPROVEMENT: More robust symbolic link and junction detection
                -not (
                    ($_.LinkType -eq "SymbolicLink") -or 
                    ($_.LinkType -eq "Junction") -or 
                    ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
                )
            }
            
            if ($null -ne $files) {
                $allFiles += $files
            }
        } catch {
            Write-Log "Could not search for $ext files: $($_.Exception.Message)" "WARN"
        }
    }
    
    # IMPROVEMENT: Better file filtering with access checks
    $validFiles = @()
    foreach ($file in $allFiles) {
        try {
            # IMPROVEMENT: Check both existence and readability
            if ((Test-Path $file.FullName -PathType Leaf) -and 
                ($file.Length -le $MaxFileSize) -and
                ($IncludeSelfAnalysis -or $file.Name -ne $scriptName)) {
                
                # IMPROVEMENT: Test actual file access
                try {
                    $null = [System.IO.File]::OpenRead($file.FullName).Dispose()
                    $validFiles += $file
                } catch {
                    Write-Log "Cannot read file $($file.Name): $($_.Exception.Message)" "WARN"
                }
            }
        } catch {
            Write-Log "Error evaluating file $($file.Name): $($_.Exception.Message)" "WARN"
        }
    }
    
    $validFiles = $validFiles | Sort-Object Name
    
    # IMPROVEMENT: Enforce MaxFiles limit properly as recommended
    if ($MaxFiles -gt 0 -and $validFiles.Count -gt $MaxFiles) {
        Write-Log "Limiting analysis to first $MaxFiles of $($validFiles.Count) files" "INFO"
        $validFiles = $validFiles | Select-Object -First $MaxFiles
    }
    
    # IMPROVEMENT: Better error handling for no files found
    if ($validFiles.Count -eq 0) {
        Write-Log "No valid files found to analyze" "ERROR"
        Write-Host ""
        Write-Host "No files found matching criteria:" -ForegroundColor Yellow
        Write-Host "- Path: $InputPath" -ForegroundColor Yellow
        Write-Host "- Extensions: $($FileExtensions -join ', ')" -ForegroundColor Yellow
        Write-Host "- Max size: $([math]::Round($MaxFileSize / 1MB, 1)) MB" -ForegroundColor Yellow
        Write-Host "- Recursive: $Recursive" -ForegroundColor Yellow
        Write-Host "- Include self: $IncludeSelfAnalysis" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Suggestions:" -ForegroundColor Green
        Write-Host "- Verify the input path contains code files" -ForegroundColor Green
        Write-Host "- Check file permissions" -ForegroundColor Green
        Write-Host "- Try increasing MaxFileSize if files are large" -ForegroundColor Green
        Write-Host "- Use -Recursive switch for subdirectories" -ForegroundColor Green
        exit 1
    }
    
    Write-Log "Found $($validFiles.Count) valid files to analyze" "SUCCESS"
    
} catch {
    Write-Log "Critical error during file discovery: $($_.Exception.Message)" "ERROR"
    exit 1
}

# IMPROVEMENT: More secure and robust text cleaning
function Clean-TextForAPI {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text, 
        [ValidateRange(100, 50000)]
        [int]$MaxLength = 8000
    )
    
    try {
        if ([string]::IsNullOrEmpty($Text)) {
            return ""
        }
        
        # IMPROVEMENT: More comprehensive sanitization
        $clean = $Text
        
        # Remove control characters except tabs, newlines, carriage returns
        $clean = $clean -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]', ' '
        
        # Escape potentially dangerous characters for JSON
        $clean = $clean -replace '\\', '\\\\'     # Backslashes
        $clean = $clean -replace '"', '\"'        # Double quotes
        $clean = $clean -replace "`r`n", ' '      # CRLF
        $clean = $clean -replace "`n", ' '        # LF
        $clean = $clean -replace "`t", ' '        # Tabs
        
        # Collapse multiple whitespace
        $clean = $clean -replace '\s+', ' '
        $clean = $clean.Trim()
        
        # IMPROVEMENT: Better truncation with word boundaries
        if ($clean.Length -gt $MaxLength) {
            $truncateAt = $MaxLength - 50
            $lastSpace = $clean.LastIndexOf(' ', $truncateAt)
            if ($lastSpace -gt $truncateAt - 100) {
                $clean = $clean.Substring(0, $lastSpace) + " [truncated at word boundary]"
            } else {
                $clean = $clean.Substring(0, $truncateAt) + " [truncated]"
            }
        }
        
        return $clean
        
    } catch {
        Write-Log "Error cleaning text: $($_.Exception.Message)" "ERROR"
        return "ERROR: Text cleaning failed - $($_.Exception.Message)"
    }
}

# IMPROVEMENT: More robust API calling with better error handling
function Invoke-ModelAPI {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Prompt,
        [ValidateRange(10, 4000)]
        [int]$MaxTokens = 1500,
        [ValidateRange(0.0, 2.0)]
        [float]$Temperature = 0.3,
        [ValidateRange(1, 5)]
        [int]$RetryCount = 3
    )
    
    # Check circuit breaker state
    if (!$script:circuitBreaker.ShouldAttempt()) {
        $state = $script:circuitBreaker.GetState()
        return "ERROR: API circuit breaker is $state - waiting for cooldown ($($script:circuitBreaker.BackoffSeconds)s)"
    }
    
    for ($i = 0; $i -lt $RetryCount; $i++) {
        try {
            # IMPROVEMENT: Only do health check on first attempt and after circuit breaker opens
            if ($i -eq 0 -or $script:circuitBreaker.GetState() -eq "HALF-OPEN") {
                try {
                    $healthCheck = Invoke-WebRequest -Uri "$ApiEndpoint/v1/models" -Method GET -TimeoutSec 5 -ErrorAction Stop
                    if ($healthCheck.StatusCode -ne 200) {
                        throw "API health check failed with status $($healthCheck.StatusCode)"
                    }
                } catch {
                    throw "API endpoint $ApiEndpoint is not accessible: $($_.Exception.Message)"
                }
            }
            
            # Prepare request with validation
            $requestBody = @{
                model = $ModelName
                messages = @(@{
                    role = "user"
                    content = $Prompt
                })
                max_tokens = $MaxTokens
                temperature = $Temperature
            }
            
            $jsonBody = $requestBody | ConvertTo-Json -Depth 5 -Compress
            $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
            
            $headers = @{
                'Content-Type' = 'application/json; charset=utf-8'
                'User-Agent' = 'PowerShell-CodeAnalyzer/1.4'
                'Accept' = 'application/json'
            }
            
            # Make API call with proper timeout
            $response = Invoke-WebRequest -Uri "$ApiEndpoint/v1/chat/completions" -Method POST -Body $bodyBytes -Headers $headers -TimeoutSec $ApiTimeout
            
            # IMPROVEMENT: Better response validation
            if ($response.StatusCode -ne 200) {
                throw "API returned status $($response.StatusCode): $($response.StatusDescription)"
            }
            
            if ([string]::IsNullOrWhiteSpace($response.Content)) {
                throw "API returned empty response"
            }
            
            # Parse and validate JSON response
            try {
                $responseData = $response.Content | ConvertFrom-Json
            } catch {
                throw "Invalid JSON response from API: $($_.Exception.Message)"
            }
            
            if (-not $responseData.choices -or $responseData.choices.Count -eq 0) {
                throw "API response missing choices array"
            }
            
            $content = $responseData.choices[0].message.content
            if ([string]::IsNullOrWhiteSpace($content)) {
                throw "API returned empty content in response"
            }
            
            # Success - update circuit breaker
            $script:circuitBreaker.RecordSuccess()
            return $content.Trim()
            
        } catch {
            $errorMsg = "API attempt $($i + 1)/$RetryCount failed: $($_.Exception.Message)"
            Write-Log $errorMsg "WARN"
            
            if ($i -eq $RetryCount - 1) {
                # Final failure - update circuit breaker
                $script:circuitBreaker.RecordFailure()
                return "ERROR: API failed after $RetryCount attempts. Last error: $($_.Exception.Message)"
            }
            
            # IMPROVEMENT: Smarter backoff strategy
            $baseDelay = [math]::Pow(2, $i)
            $jitter = Get-Random -Min 0.5 -Max 1.5
            $delay = [int]($baseDelay * $jitter)
            
            Write-Log "Retrying in $delay seconds..." "INFO"
            Start-Sleep -Seconds $delay
        }
    }
}

# IMPROVEMENT: More focused analysis functions with better error handling
function Get-RiskAnalysis {
    param(
        [Parameter(Mandatory)]
        [string]$FileName, 
        [Parameter(Mandatory)]
        [string]$Content
    )
    
    try {
        $cleanContent = Clean-TextForAPI -Text $Content -MaxLength 8000
        if ($cleanContent -like "ERROR:*") { 
            return $cleanContent 
        }
        
        $prompt = @"
Analyze this code for security and quality risks. Respond in exactly this format:

RISK_LEVEL: [LOW/MEDIUM/HIGH/CRITICAL]
SECURITY_ISSUES: [Specific security concerns or "None identified"]
QUALITY_ISSUES: [Code quality problems or "None identified"]
BEST_PRACTICE_VIOLATIONS: [Best practice issues or "None identified"]

Focus on actual issues, not theoretical problems.

File: $FileName
Code: $cleanContent
"@
        
        return Invoke-ModelAPI -Prompt $prompt -MaxTokens 800 -Temperature 0.1
    } catch {
        return "ERROR: Risk analysis failed for $FileName - $($_.Exception.Message)"
    }
}

function Get-TestCases {
    param(
        [Parameter(Mandatory)]
        [string]$FileName, 
        [Parameter(Mandatory)]
        [string]$Content
    )
    
    try {
        $cleanContent = Clean-TextForAPI -Text $Content -MaxLength 8000
        if ($cleanContent -like "ERROR:*") { 
            return $cleanContent 
        }
        
        $prompt = @"
Generate practical test cases for this code:

UNIT TESTS: [Test individual functions with specific inputs/outputs]
EDGE CASES: [Boundary conditions, null/empty inputs, invalid data]
ERROR HANDLING: [Exception scenarios and error conditions]
INTEGRATION TESTS: [Component interactions if applicable]
VALIDATION TESTS: [Input validation and data integrity]

Focus on realistic test scenarios that would actually be implemented.

File: $FileName
Code: $cleanContent
"@
        
        return Invoke-ModelAPI -Prompt $prompt -MaxTokens 1500 -Temperature 0.3
    } catch {
        return "ERROR: Test case generation failed for $FileName - $($_.Exception.Message)"
    }
}

function Get-ErrorAnalysis {
    param(
        [Parameter(Mandatory)]
        [string]$FileName, 
        [Parameter(Mandatory)]
        [string]$Content
    )
    
    try {
        $cleanContent = Clean-TextForAPI -Text $Content -MaxLength 8000
        if ($cleanContent -like "ERROR:*") { 
            return $cleanContent 
        }
        
        $prompt = @"
Analyze potential errors in this code:

SYNTAX ERRORS: [Compilation/parsing issues]
RUNTIME ERRORS: [Execution exceptions and failure points]
LOGIC ERRORS: [Incorrect behavior or flawed algorithms]
RESOURCE ERRORS: [File/memory/network/permission issues]
INPUT VALIDATION: [Unhandled user input scenarios]

Focus on likely failure scenarios rather than theoretical edge cases.

File: $FileName
Code: $cleanContent
"@
        
        return Invoke-ModelAPI -Prompt $prompt -MaxTokens 1500 -Temperature 0.2
    } catch {
        return "ERROR: Error analysis failed for $FileName - $($_.Exception.Message)"
    }
}

function Get-CumulativeErrorRisk {
    param(
        [Parameter(Mandatory)]
        [string]$ErrorAnalysis, 
        [Parameter(Mandatory)]
        [string]$FileName
    )
    
    try {
        if ($ErrorAnalysis -like "ERROR:*") {
            return "ERROR: Cannot assess cumulative risk - error analysis failed"
        }
        
        $prompt = @"
Assess the cumulative risk from this error analysis:

OVERALL_RISK_LEVEL: [LOW/MEDIUM/HIGH/CRITICAL]
PRODUCTION ENVIRONMENT: [Is it safe to deploy in prod? Yes/No]
DEVELOPMENT ENVIRONMENT: [Is it reasonably safe to deploy in dev? Yes/No]
LOCAL ENVIRONMENT: [Is it reasonably safe to run locally? Yes/No]
MOST_LIKELY_FAILURES: [What will probably actually break]
WORST_CASE_SCENARIO: [Realistic worst-case outcomes]
MITIGATION_PRIORITY: [Which issues to fix first]
USER_IMPACT: [How failures affect end users]
QUICK_WINS: [Easy fixes with high impact]

Be practical and focus on real-world implications.

File: $FileName
Error Analysis: $ErrorAnalysis
"@
        
        return Invoke-ModelAPI -Prompt $prompt -MaxTokens 1000 -Temperature 0.2
    } catch {
        return "ERROR: Cumulative risk assessment failed for $FileName - $($_.Exception.Message)"
    }
}

# IMPROVEMENT: More robust risk parsing with better validation
function Parse-RiskAnalysis {
    param([Parameter(Mandatory)][string]$Response)
    
    try {
        # Initialize with defaults
        $result = @{
            RiskLevel = "UNKNOWN"
            SecurityIssues = "Parse error"
            QualityIssues = "Parse error"
            BestPracticeViolations = "Parse error"
        }
        
        # IMPROVEMENT: More robust regex patterns with multiline support
        if ($Response -match "(?mi)^RISK_LEVEL:\s*([A-Z]+)") {
            $level = $matches[1].Trim().ToUpper()
            if ($level -in @("LOW", "MEDIUM", "HIGH", "CRITICAL")) {
                $result.RiskLevel = $level
            }
        }
        
        if ($Response -match "(?mis)^SECURITY_ISSUES:\s*(.+?)(?=^\s*[A-Z_]+:|$)") {
            $result.SecurityIssues = $matches[1].Trim()
        }
        
        if ($Response -match "(?mis)^QUALITY_ISSUES:\s*(.+?)(?=^\s*[A-Z_]+:|$)") {
            $result.QualityIssues = $matches[1].Trim()
        }
        
        if ($Response -match "(?mis)^BEST_PRACTICE_VIOLATIONS:\s*(.+?)(?=^\s*[A-Z_]+:|$)") {
            $result.BestPracticeViolations = $matches[1].Trim()
        }
        
        return $result
        
    } catch {
        Write-Log "Risk parsing error: $($_.Exception.Message)" "ERROR"
        return @{
            RiskLevel = "ERROR"
            SecurityIssues = "Parsing failed"
            QualityIssues = "Parsing failed"
            BestPracticeViolations = "Parsing failed"
        }
    }
}

# IMPROVEMENT: Streamlined main analysis loop with better progress tracking
Write-Log "Starting analysis of $($validFiles.Count) files..." "SUCCESS"
$analysisResults = @()
$processedCount = 0
$successCount = 0
$startTime = Get-Date

foreach ($file in $validFiles) {
    try {
        $processedCount++
        $progressPercent = [math]::Round(($processedCount / $validFiles.Count) * 100)
        Write-Host "[$processedCount/$($validFiles.Count) - $progressPercent%] Analyzing: $($file.Name)"
        
        # IMPROVEMENT: Better file reading with encoding detection
        $content = $null
        $encodings = @('UTF8', 'Unicode', 'UTF32', 'ASCII', 'Default')
        
        foreach ($encoding in $encodings) {
            try {
                $content = Get-Content -Path $file.FullName -Raw -Encoding $encoding -ErrorAction Stop
                if (![string]::IsNullOrWhiteSpace($content)) {
                    break
                }
            } catch {
                # Try next encoding
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($content)) {
            Write-Log "Skipping empty/unreadable file: $($file.Name)" "WARN"
            continue
        }
        
        # Perform all analyses with individual error handling
        $riskAnalysis = Get-RiskAnalysis -FileName $file.Name -Content $content
        $parsedRisk = Parse-RiskAnalysis -Response $riskAnalysis
        $testCases = Get-TestCases -FileName $file.Name -Content $content
        $errorAnalysis = Get-ErrorAnalysis -FileName $file.Name -Content $content
        $cumulativeRisk = Get-CumulativeErrorRisk -ErrorAnalysis $errorAnalysis -FileName $file.Name
        
        # Determine success
        $analysisSuccess = ($riskAnalysis -notlike "ERROR:*" -and 
                           $testCases -notlike "ERROR:*" -and 
                           $errorAnalysis -notlike "ERROR:*" -and
                           $cumulativeRisk -notlike "ERROR:*")
        
        if ($analysisSuccess) { 
            $successCount++ 
        }
        
        $analysisResults += [PSCustomObject]@{
            FileName = $file.Name
            FilePath = $file.FullName
            FileSize = $file.Length
            RiskLevel = $parsedRisk.RiskLevel
            SecurityIssues = $parsedRisk.SecurityIssues
            QualityIssues = $parsedRisk.QualityIssues
            BestPracticeViolations = $parsedRisk.BestPracticeViolations
            TestCases = $testCases
            ErrorAnalysis = $errorAnalysis
            CumulativeErrorRisk = $cumulativeRisk
            Success = $analysisSuccess
            ProcessedTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        
        # Save individual analysis
        $safeFileName = $file.BaseName -replace '[^\w\-_]', '_'
        $analysisPath = Join-Path $OutputDirectory "$safeFileName`_$timestamp.txt"
        
        $analysis = @"
Code ANALYSIS - $($file.Name)
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Analyzer: Twice Self-Improved v1.4 (Second iteration of AI recommendations)

===== RISK ASSESSMENT =====
Risk Level: $($parsedRisk.RiskLevel)
Security Issues: $($parsedRisk.SecurityIssues)
Quality Issues: $($parsedRisk.QualityIssues)
Best Practice Violations: $($parsedRisk.BestPracticeViolations)

===== TEST CASES =====
$testCases

===== ERROR ANALYSIS =====
$errorAnalysis

===== CUMULATIVE ERROR RISK =====
$cumulativeRisk

---
Generated by Code Analyzer v1.4
Following second iteration of AI recommendations
"@
        
        try {
            $analysis | Out-File -FilePath $analysisPath -Encoding UTF8
        } catch {
            Write-Log "Failed to save analysis for $($file.Name): $($_.Exception.Message)" "WARN"
        }
        
        # Display status
        $color = switch ($parsedRisk.RiskLevel) {
            "CRITICAL" { "Red" }
            "HIGH" { "Yellow" }
            "MEDIUM" { "Cyan" }
            "LOW" { "Green" }
            default { "Gray" }
        }
        Write-Host "  Risk: $($parsedRisk.RiskLevel)" -ForegroundColor $color
        
        # IMPROVEMENT: Adaptive rate limiting based on circuit breaker state
        $sleepTime = switch ($script:circuitBreaker.GetState()) {
            "OPEN" { 2000 }
            "HALF-OPEN" { 1500 }
            default { 800 }
        }
        Start-Sleep -Milliseconds $sleepTime
        
    } catch {
        Write-Log "Critical error processing $($file.Name): $($_.Exception.Message)" "ERROR"
        continue
    }
}

$processingTime = (Get-Date) - $startTime
$avgTimePerFile = if ($analysisResults.Count -gt 0) { $processingTime.TotalSeconds / $analysisResults.Count } else { 0 }

# Generate improved summary report
$summaryPath = Join-Path $OutputDirectory "summary_$timestamp.txt"
$riskCounts = $analysisResults | Group-Object -Property RiskLevel | Sort-Object Name
$criticalFiles = $analysisResults | Where-Object { $_.RiskLevel -eq "CRITICAL" }
$highRiskFiles = $analysisResults | Where-Object { $_.RiskLevel -eq "HIGH" }
$failedFiles = $analysisResults | Where-Object { -not $_.Success }

$summary = @"
Code ANALYSIS SUMMARY
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Analyzer: v1.4 - Second iteration following AI recommendations

===== PROCESSING METRICS =====
Files Processed: $($analysisResults.Count)
Success Rate: $([math]::Round(($successCount / $analysisResults.Count) * 100, 1))%
Processing Time: $([math]::Round($processingTime.TotalMinutes, 2)) minutes
Average per File: $([math]::Round($avgTimePerFile, 1)) seconds
Circuit Breaker State: $($script:circuitBreaker.GetState())

===== RISK DISTRIBUTION =====
$(foreach ($group in $riskCounts) { "- $($group.Name): $($group.Count) files" })

===== HIGH PRIORITY FILES =====
$(if ($criticalFiles.Count -eq 0 -and $highRiskFiles.Count -eq 0) {
"No critical or high-risk files found - Excellent code quality!"
} else {
"Critical Files: $($criticalFiles.Count)"
foreach ($file in $criticalFiles) { "- $($file.FileName): $($file.SecurityIssues)" }
""
"High Risk Files: $($highRiskFiles.Count)"
foreach ($file in $highRiskFiles) { "- $($file.FileName): $($file.SecurityIssues)" }
})

===== ANALYSIS FAILURES =====
$(if ($failedFiles.Count -eq 0) {
"No analysis failures - Perfect processing!"
} else {
"Failed Files: $($failedFiles.Count)"
foreach ($file in $failedFiles) { "- $($file.FileName): Check individual report" }
})

===== RECOMMENDATIONS =====
$(if ($criticalFiles.Count -gt 0) {
"[CRITICAL] Address security vulnerabilities immediately"
} elseif ($highRiskFiles.Count -gt 0) {
"[HIGH] Review high-risk files within one week"
} elseif ($failedFiles.Count -gt ($analysisResults.Count * 0.2)) {
"[ATTENTION] High failure rate suggests API or infrastructure issues"
} else {
"[EXCELLENT] Code quality is good, continue best practices"
})

---
Generated by Code Analyzer v1.4
"@

$summary | Out-File -FilePath $summaryPath -Encoding UTF8

# Display results
Write-Host ""
Write-Host "ANALYSIS COMPLETE!" -ForegroundColor Green
Write-Host "Files analyzed: $($analysisResults.Count) | Success: $([math]::Round(($successCount / $analysisResults.Count) * 100, 1))%"
Write-Host "Processing time: $([math]::Round($processingTime.TotalMinutes, 2)) min | Avg: $([math]::Round($avgTimePerFile, 1))s per file"
Write-Host "Circuit breaker: $($script:circuitBreaker.GetState()) | Summary: $summaryPath"

Write-Host ""
Write-Host "RISK DISTRIBUTION:" -ForegroundColor Cyan
foreach ($group in $riskCounts) {
    $color = switch ($group.Name) {
        "CRITICAL" { "Red" }; "HIGH" { "Yellow" }; "MEDIUM" { "Cyan" }; "LOW" { "Green" }; default { "Gray" }
    }
    Write-Host "- $($group.Name): $($group.Count) files" -ForegroundColor $color
}

# Show priority items

# Create clipboard summary
$clipboardText = "Analysis complete! Processed $($analysisResults.Count) files with $([math]::Round(($successCount / $analysisResults.Count) * 100, 1))% success rate. $(if ($criticalFiles.Count -eq 0 -and $highRiskFiles.Count -eq 0) { 'No high-priority issues found - excellent code quality!' } else { "$($criticalFiles.Count + $highRiskFiles.Count) files need attention." }) Second iteration improvements include enhanced circuit breaker, better error handling, and smarter API management."
$clipboardText | Set-Clipboard

Write-Host ""
Write-Host "Summary copied to clipboard." -ForegroundColor Green
