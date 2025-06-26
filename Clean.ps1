# Default Values Replacer - Update hardcoded paths and URLs in PowerShell scripts
param(
    [string]$SearchPath = ".",
    [string]$FilePattern = "*.ps1",
    [switch]$Recursive,
    [switch]$Preview,  # Just show what would be changed without actually changing
    [switch]$BackupOriginals,
    
    # Replacement values - modify these as needed
    [string]$NewScreenshotPath = "outputs",
    [string]$NewLMStudioEndpoint = "http://127.0.0.1:1234",
    [string]$NewTTSEndpoint = "http://127.0.0.1:8880",
    [string]$NewVLCPath = "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe",
    
    # Or use a config file
    [string]$ConfigFile = ""
)

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Host "Default Values Replacer - Starting..." -ForegroundColor Green
Write-Host "Mode: $(if ($Preview) {'PREVIEW ONLY'} else {'LIVE REPLACEMENT'})" -ForegroundColor $(if ($Preview) {'Yellow'} else {'Red'})

# Default replacement mappings
$replacements = @{
    # Paths
    'C:\\Screenshots' = $NewScreenshotPath -replace '\\', '\\\\'
    '.\outputs' = $NewScreenshotPath
    
    # API Endpoints
    'http://localhost:1234' = $NewLMStudioEndpoint
    'localhost:1234' = $NewLMStudioEndpoint -replace 'http://', ''
    'http://localhost:8880' = $NewTTSEndpoint
    'localhost:8880' = $NewTTSEndpoint -replace 'http://', ''
    
    # VLC Path variations
    'C:\\Program Files\\VideoLAN\\VLC\\vlc.exe' = $NewVLCPath -replace '\\', '\\\\'
    'C:\Program Files\VideoLAN\VLC\vlc.exe' = $NewVLCPath
}

# Load config file if specified
if ($ConfigFile -and (Test-Path $ConfigFile)) {
    try {
        Write-Host "Loading configuration from: $ConfigFile"
        $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        
        # Override replacements with config values
        if ($config.ScreenshotPath) {
            $replacements['C:\\Screenshots'] = $config.ScreenshotPath -replace '\\', '\\\\'
            $replacements['.\outputs'] = $config.ScreenshotPath
        }
        if ($config.LMStudioEndpoint) {
            $replacements['http://localhost:1234'] = $config.LMStudioEndpoint
            $replacements['localhost:1234'] = $config.LMStudioEndpoint -replace 'http://', ''
        }
        if ($config.TTSEndpoint) {
            $replacements['http://localhost:8880'] = $config.TTSEndpoint
            $replacements['localhost:8880'] = $config.TTSEndpoint -replace 'http://', ''
        }
        if ($config.VLCPath) {
            $replacements['C:\\Program Files (x86)\\VideoLAN\\VLC\\vlc.exe'] = $config.VLCPath -replace '\\', '\\\\'
            $replacements['C:\Program Files (x86)\VideoLAN\VLC\vlc.exe'] = $config.VLCPath
        }
        
        Write-Host "Configuration loaded successfully" -ForegroundColor Green
    } catch {
        Write-Host "Error loading config file: $_" -ForegroundColor Red
        exit 1
    }
}

# Display replacement mappings
Write-Host "`nReplacement mappings:" -ForegroundColor Cyan
foreach ($key in $replacements.Keys) {
    Write-Host "  '$key' → '$($replacements[$key])'" -ForegroundColor Gray
}

# Get files to process
Write-Host "`nSearching for files..." -ForegroundColor Cyan
$searchParams = @{
    Path = $SearchPath
    Filter = $FilePattern
    File = $true
    ErrorAction = 'SilentlyContinue'
}

if ($Recursive) {
    $searchParams.Recurse = $true
}

$files = Get-ChildItem @searchParams
Write-Host "Found $($files.Count) files to process"

if ($files.Count -eq 0) {
    Write-Host "No files found matching pattern '$FilePattern' in '$SearchPath'" -ForegroundColor Yellow
    exit
}

# Process each file
$changedFiles = @()

# Handle exclusion of Clean.ps1 itself
$currentScriptName = "Clean.ps1"
$files = $files | Where-Object { $_.Name -ne $currentScriptName }
Write-Host "Excluded self ($currentScriptName) from processing" -ForegroundColor Yellow

$totalReplacements = 0

foreach ($file in $files) {
    try {
        Write-Host "`nProcessing: $($file.Name)" -ForegroundColor White
        
        # Read file content
        $content = Get-Content -Path $file.FullName -Raw
        $originalContent = $content
        $fileReplacements = 0
        
        # Apply each replacement
        foreach ($search in $replacements.Keys) {
            $replace = $replacements[$search]
            
            # Count occurrences
            $occurrences = ([regex]::Matches($content, [regex]::Escape($search))).Count
            
            if ($occurrences -gt 0) {
                Write-Host "  Found $occurrences occurrences of '$search'" -ForegroundColor Yellow
                
                # Perform replacement
                $content = $content -replace [regex]::Escape($search), $replace
                $fileReplacements += $occurrences
                $totalReplacements += $occurrences
            }
        }
        
        # Check if file was modified
        if ($content -ne $originalContent) {
            $changedFiles += $file
            
            if ($Preview) {
                Write-Host "  Would update file with $fileReplacements replacements" -ForegroundColor Green
                
                # Show a preview of changes
                Write-Host "  Preview of changes:" -ForegroundColor Cyan
                
                # Extract a few lines that would change
                $originalLines = $originalContent -split "`n"
                $newLines = $content -split "`n"
                
                for ($i = 0; $i -lt $originalLines.Count; $i++) {
                    if ($originalLines[$i] -ne $newLines[$i]) {
                        Write-Host "    Line $($i+1):" -ForegroundColor Gray
                        Write-Host "      - $($originalLines[$i].Trim())" -ForegroundColor Red
                        Write-Host "      + $($newLines[$i].Trim())" -ForegroundColor Green
                        
                        # Only show first 3 changed lines per file
                        if ((++$shown) -ge 3) {
                            Write-Host "    ... and more changes" -ForegroundColor Gray
                            break
                        }
                    }
                }
            } else {
                # Backup original if requested
                if ($BackupOriginals) {
                    $backupPath = "$($file.FullName).backup_$timestamp"
                    Copy-Item -Path $file.FullName -Destination $backupPath
                    Write-Host "  Backed up to: $backupPath" -ForegroundColor Gray
                }
                
                # Write updated content
                $content | Out-File -FilePath $file.FullName -Encoding UTF8
                Write-Host "  Updated file with $fileReplacements replacements" -ForegroundColor Green
            }
        } else {
            Write-Host "  No changes needed" -ForegroundColor Gray
        }
        
    } catch {
        Write-Host "  Error processing file: $_" -ForegroundColor Red
    }
}

# Generate summary report
$reportPath = "replacement_report_$timestamp.txt"
$report = @"
DEFAULT VALUES REPLACEMENT REPORT
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Mode: $(if ($Preview) {'PREVIEW'} else {'LIVE'})

FILES PROCESSED: $($files.Count)
FILES CHANGED: $($changedFiles.Count)
TOTAL REPLACEMENTS: $totalReplacements

REPLACEMENT MAPPINGS:
$(foreach ($key in $replacements.Keys) {
"  '$key' → '$($replacements[$key])'"
})

CHANGED FILES:
$(foreach ($file in $changedFiles) {
"  - $($file.Name)"
})

$(if ($BackupOriginals -and !$Preview) {
"BACKUPS:
Original files backed up with .backup_$timestamp extension"
})
"@

$report | Out-File -FilePath $reportPath -Encoding UTF8

# Display summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "SUMMARY:" -ForegroundColor Green
Write-Host "Files processed: $($files.Count)"
Write-Host "Files changed: $($changedFiles.Count)"
Write-Host "Total replacements: $totalReplacements"
Write-Host "Report saved to: $reportPath"

if ($Preview) {
    Write-Host "`nThis was a PREVIEW run. No files were actually modified." -ForegroundColor Yellow
    Write-Host "Remove the -Preview switch to perform actual replacements." -ForegroundColor Yellow
} else {
    Write-Host "`nFiles have been updated!" -ForegroundColor Green
    if ($BackupOriginals) {
        Write-Host "Original files backed up with .backup_$timestamp extension" -ForegroundColor Cyan
    }
}

# Example config file creation
if (!(Test-Path "replacement_config_example.json")) {
    $exampleConfig = @{
        ScreenshotPath = "D:\\MyData\\Screenshots"
        LMStudioEndpoint = "http://192.168.1.100:1234"
        TTSEndpoint = "http://192.168.1.100:8880"
        VLCPath = "C:\\Program Files\\VideoLAN\\VLC\\vlc.exe"
    } | ConvertTo-Json -Depth 2
    
    $exampleConfig | Out-File -FilePath "replacement_config_example.json" -Encoding UTF8
    Write-Host "`nCreated example config file: replacement_config_example.json" -ForegroundColor Cyan
}

Write-Host "`nTips:" -ForegroundColor Yellow
Write-Host "- Use -Preview to see what would change without modifying files"
Write-Host "- Use -BackupOriginals to create backups before modifying"
Write-Host "- Use -ConfigFile to load settings from a JSON file"
Write-Host "- Modify the script parameters to set your preferred paths/URLs"