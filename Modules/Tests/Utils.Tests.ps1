# Utils.Tests.ps1
# Tests for Utils module functions

# Load the module being tested
Import-Module (Join-Path $PSScriptRoot "..\Utils.psm1") -Force

Write-Host "Testing Utils Module..." -ForegroundColor Cyan

# Test Clean-TextForAPI
$dirtyText = "Hello`nWorld`tWith`rSpecial   Chars"
$cleanText = Clean-TextForAPI -Text $dirtyText
Write-Host "Test-CleanText: '$cleanText'" -ForegroundColor Green

# Test Test-BinaryContent
$normalText = "This is normal text"
$isBinary = Test-BinaryContent -Text $normalText
Write-Host "Test-BinaryContent (normal): $isBinary" -ForegroundColor Green

# Test with binary-like content
$binaryText = "Hello" + [char]0 + "World"
$isBinary = Test-BinaryContent -Text $binaryText
if ($isBinary) {
    Write-Host "Test-BinaryContent (binary): $isBinary - PASS" -ForegroundColor Green
} else {
    Write-Host "Test-BinaryContent (binary): $isBinary - Should detect binary content" -ForegroundColor Yellow
}

# Test Get-TimestampedFilename
$filename = Get-TimestampedFilename -Prefix "test" -Extension "txt"
Write-Host "Test-TimestampedFilename: $filename" -ForegroundColor Green

# Test ConvertTo-SafeJson
$testObject = @{
    name = "test"
    value = 123
    array = @(1,2,3)
}
$json = ConvertTo-SafeJson -InputObject $testObject
Write-Host "Test-SafeJson: $json" -ForegroundColor Green

# Test Write-ModuleLog
Write-ModuleLog -Message "Test log message" -Level "Info" -ModuleName "TestModule"

# Test New-OutputDirectory (create a test directory)
$testDir = Join-Path $env:TEMP "UtilsTest"
$createdDir = New-OutputDirectory -Path $testDir
Write-Host "Test-OutputDirectory: $createdDir" -ForegroundColor Green

# Clean up test directory
if (Test-Path $testDir) {
    Remove-Item $testDir -Force -ErrorAction SilentlyContinue
}

Write-Host "Utils tests completed!" -ForegroundColor Cyan
