# Run-AllTests.ps1
# Test runner for all module tests

param(
    [string]$TestFilter = "*"
)

$TestsPath = $PSScriptRoot
$StartTime = Get-Date

Write-Host "=====================================" -ForegroundColor Magenta
Write-Host "PowerShell Module Test Runner" -ForegroundColor Magenta
Write-Host "Started at: $StartTime" -ForegroundColor Magenta
Write-Host "=====================================" -ForegroundColor Magenta
Write-Host ""

# Find all test files
$TestFiles = Get-ChildItem -Path $TestsPath -Filter "*.Tests.ps1" | Where-Object { $_.Name -like $TestFilter }

if ($TestFiles.Count -eq 0) {
    Write-Host "No test files found matching filter: $TestFilter" -ForegroundColor Red
    exit 1
}

$PassedTests = 0
$FailedTests = 0
$TestResults = @()

foreach ($TestFile in $TestFiles) {
    Write-Host "Running test: $($TestFile.Name)" -ForegroundColor Yellow
    Write-Host "----------------------------------------" -ForegroundColor Yellow
    
    $TestStartTime = Get-Date
    try {
        # Execute the test file
        & $TestFile.FullName
        
        $TestEndTime = Get-Date
        $TestDuration = $TestEndTime - $TestStartTime
        
        $PassedTests++
        $TestResults += [PSCustomObject]@{
            TestFile = $TestFile.Name
            Status = "PASSED"
            Duration = $TestDuration.TotalSeconds
            Error = $null
        }
        
        Write-Host "PASSED: $($TestFile.Name) (Duration: $($TestDuration.TotalSeconds)s)" -ForegroundColor Green
        
    } catch {
        $TestEndTime = Get-Date
        $TestDuration = $TestEndTime - $TestStartTime
        
        $FailedTests++
        $TestResults += [PSCustomObject]@{
            TestFile = $TestFile.Name
            Status = "FAILED"
            Duration = $TestDuration.TotalSeconds
            Error = $_.Exception.Message
        }
        
        Write-Host "FAILED: $($TestFile.Name)" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host ""
}

$EndTime = Get-Date
$TotalDuration = $EndTime - $StartTime

Write-Host "=====================================" -ForegroundColor Magenta
Write-Host "Test Summary" -ForegroundColor Magenta
Write-Host "=====================================" -ForegroundColor Magenta
Write-Host "Total Tests: $($PassedTests + $FailedTests)" -ForegroundColor White
Write-Host "Passed: $PassedTests" -ForegroundColor Green
Write-Host "Failed: $FailedTests" -ForegroundColor Red
Write-Host "Total Duration: $($TotalDuration.TotalSeconds)s" -ForegroundColor White
Write-Host ""

if ($FailedTests -gt 0) {
    Write-Host "Failed Tests:" -ForegroundColor Red
    $TestResults | Where-Object { $_.Status -eq "FAILED" } | ForEach-Object {
        Write-Host "  - $($_.TestFile): $($_.Error)" -ForegroundColor Red
    }
    Write-Host ""
}

# Detailed results
Write-Host "Detailed Results:" -ForegroundColor Cyan
$TestResults | Format-Table -AutoSize

if ($FailedTests -eq 0) {
    Write-Host "All tests passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Some tests failed!" -ForegroundColor Red
    exit 1
}
