# System Monitor AI - Comprehensive system analysis with AI insights
param(
    [string]$OutputDirectory = "%appdata%\Local\Powertoys\System",
    [switch]$SkipAudio
)

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputDir = Join-Path $OutputDirectory "System"

# Ensure output directory exists with proper error handling
try {
    if (!(Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    
    # Verify we can write to the directory
    $testFile = Join-Path $outputDir "test_$timestamp.tmp"
    "test" | Out-File -FilePath $testFile -ErrorAction Stop
    Remove-Item -Path $testFile -Force -ErrorAction SilentlyContinue
    
} catch {
    Write-Error "Cannot create or write to output directory: $outputDir. Error: $($_.Exception.Message)"
    exit 1
}

Write-Host "System Monitor AI - Starting comprehensive system analysis..."

# PHASE 1: System Specifications
Write-Host "`nPHASE 1: Gathering system specifications..."

try {
    # Get basic system info
    $computerInfo = Get-ComputerInfo
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    $cpuInfo = Get-CimInstance -ClassName Win32_Processor
    $memoryInfo = Get-CimInstance -ClassName Win32_PhysicalMemory
    $diskInfo = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
    $gpuInfo = Get-CimInstance -ClassName Win32_VideoController
    $networkInfo = Get-CimInstance -ClassName Win32_NetworkAdapter | Where-Object { $_.NetEnabled -eq $true }
    
    # Calculate total memory more efficiently
    $totalMemoryBytes = ($memoryInfo | Measure-Object -Property Capacity -Sum).Sum
    $totalMemoryGB = [math]::Round($totalMemoryBytes / 1GB, 2)
    $availableMemoryGB = [math]::Round($osInfo.FreePhysicalMemory / 1MB, 2)
    $usedMemoryGB = [math]::Round($totalMemoryGB - $availableMemoryGB, 2)
    
    # Build system specs report
    $systemSpecs = @"
SYSTEM SPECIFICATIONS - $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

COMPUTER:
- Name: $($computerInfo.CsName)
- Domain: $($computerInfo.CsDomain)
- Manufacturer: $($computerInfo.CsManufacturer)
- Model: $($computerInfo.CsModel)

OPERATING SYSTEM:
- OS: $($osInfo.Caption) $($osInfo.Version)
- Architecture: $($osInfo.OSArchitecture)
- Install Date: $($osInfo.InstallDate)
- Last Boot: $($osInfo.LastBootUpTime)
- Uptime: $((Get-Date) - $osInfo.LastBootUpTime)

CPU:
- Name: $($cpuInfo.Name)
- Cores: $($cpuInfo.NumberOfCores)
- Logical Processors: $($cpuInfo.NumberOfLogicalProcessors)
- Max Clock Speed: $($cpuInfo.MaxClockSpeed) MHz
- Current Load: $($cpuInfo.LoadPercentage)%

MEMORY:
- Total RAM: $totalMemoryGB GB
- Available: $availableMemoryGB GB
- Used: $usedMemoryGB GB
- Usage: $([math]::Round(($usedMemoryGB / $totalMemoryGB) * 100, 1))%

STORAGE:
$(foreach ($disk in $diskInfo) {
    $freeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)
    $totalSpaceGB = [math]::Round($disk.Size / 1GB, 2)
    $usedSpaceGB = $totalSpaceGB - $freeSpaceGB
    $usagePercent = [math]::Round(($usedSpaceGB / $totalSpaceGB) * 100, 1)
    "- Drive $($disk.DeviceID) $totalSpaceGB GB total, $freeSpaceGB GB free ($usagePercent% used)"
})

GPU:
$(foreach ($gpu in $gpuInfo) {
    if ($gpu.Name -notlike "*Basic*" -and $gpu.Name -notlike "*Generic*") {
        "- $($gpu.Name)"
        if ($gpu.AdapterRAM) {
            "  VRAM: $([math]::Round($gpu.AdapterRAM / 1GB, 2)) GB"
        }
    }
})

NETWORK:
$(foreach ($adapter in $networkInfo) {
    if ($adapter.Name -notlike "*Loopback*" -and $adapter.Name -notlike "*Teredo*") {
        "- $($adapter.Name) ($($adapter.AdapterType))"
    }
})
"@

    $systemSpecsPath = Join-Path $outputDir "system_specs_$timestamp.txt"
    $systemSpecs | Out-File -FilePath $systemSpecsPath -Encoding UTF8
    Write-Host "System specs saved to: $systemSpecsPath"
    
} catch {
    Write-Host "Error gathering system specs: $($_.Exception.Message)"
    $systemSpecs = "Error gathering system specifications"
}

# PHASE 2: Process Analysis
Write-Host "`nPHASE 2: Analyzing running processes..."

try {
    # Get detailed process information
    $processes = Get-Process | Where-Object { $_.ProcessName -ne "Idle" } | Sort-Object CPU -Descending
    
    # Get additional process details
    $processDetails = @()
    $totalCPU = 0
    $totalMemoryMB = 0
    
    foreach ($proc in $processes) {
        try {
            # Get additional WMI info for the process
            $wmiProc = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction SilentlyContinue
            
            $memoryMB = [math]::Round($proc.WorkingSet64 / 1MB, 2)
            $totalMemoryMB += $memoryMB
            
            # CPU usage (note: this is cumulative CPU time, not current %)
            $cpuTime = if ($proc.CPU) { [math]::Round($proc.CPU, 2) } else { 0 }
            $totalCPU += $cpuTime
            
            $processDetails += [PSCustomObject]@{
                Name = $proc.ProcessName
                PID = $proc.Id
                MemoryMB = $memoryMB
                CPUTime = $cpuTime
                StartTime = if ($proc.StartTime) { $proc.StartTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "Unknown" }
                Path = if ($wmiProc) { $wmiProc.ExecutablePath } else { "Unknown" }
                CommandLine = if ($wmiProc) { $wmiProc.CommandLine } else { "Unknown" }
                Threads = $proc.Threads.Count
                Handles = $proc.HandleCount
            }
        } catch {
            # Skip processes we can't access
            continue
        }
    }
    
    # Sort by memory usage for the report
    $processDetails = $processDetails | Sort-Object MemoryMB -Descending
    
    # Build process report
    $processReport = @"
PROCESS ANALYSIS - $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Total Processes: $($processDetails.Count)
Total Memory Used: $([math]::Round($totalMemoryMB / 1024, 2)) GB
Total CPU Time: $([math]::Round($totalCPU, 2)) seconds

TOP PROCESSES BY MEMORY USAGE:
$(foreach ($proc in ($processDetails | Select-Object -First 20)) {
"$($proc.Name) (PID: $($proc.PID))
  Memory: $($proc.MemoryMB) MB
  CPU Time: $($proc.CPUTime)s
  Threads: $($proc.Threads)
  Start: $($proc.StartTime)
  Path: $($proc.Path)
"
})

TOP PROCESSES BY CPU TIME:
$(foreach ($proc in ($processDetails | Sort-Object CPUTime -Descending | Select-Object -First 15)) {
"$($proc.Name) (PID: $($proc.PID))
  CPU Time: $($proc.CPUTime)s
  Memory: $($proc.MemoryMB) MB
  Threads: $($proc.Threads)
"
})

ALL PROCESSES (SUMMARY):
$(foreach ($proc in $processDetails) {
"$($proc.Name),$($proc.PID),$($proc.MemoryMB),$($proc.CPUTime),$($proc.Threads),$($proc.Handles)"
})
"@

    $processAnalysisPath = Join-Path $outputDir "process_analysis_$timestamp.txt"
    $processReport | Out-File -FilePath $processAnalysisPath -Encoding UTF8
    Write-Host "Process analysis saved to: $processAnalysisPath"
    
} catch {
    Write-Host "Error analyzing processes: $($_.Exception.Message)"
    $processReport = "Error gathering process information"
}

# PHASE 3: Performance Counters
Write-Host "`nPHASE 3: Gathering performance metrics..."

try {
    # Get current performance metrics
    $cpuUsage = (Get-Counter "\Processor(_Total)\% Processor Time" -SampleInterval 1 -MaxSamples 3 | 
                 Select-Object -ExpandProperty CounterSamples | 
                 Measure-Object -Property CookedValue -Average).Average
    
    $memoryUsage = Get-Counter "\Memory\Available MBytes"
    $diskUsage = Get-Counter "\PhysicalDisk(_Total)\% Disk Time" -ErrorAction SilentlyContinue
    
    $perfMetrics = @"
PERFORMANCE METRICS - $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

CPU Usage: $([math]::Round($cpuUsage, 1))%
Available Memory: $([math]::Round($memoryUsage.CounterSamples[0].CookedValue, 0)) MB
$(if ($diskUsage) { "Disk Activity: $([math]::Round($diskUsage.CounterSamples[0].CookedValue, 1))%" })

RESOURCE SUMMARY:
- CPU Load: $(if ($cpuUsage -gt 80) { "HIGH" } elseif ($cpuUsage -gt 50) { "MODERATE" } else { "NORMAL" })
- Memory Pressure: $(if ($availableMemoryGB -lt 2) { "HIGH" } elseif ($availableMemoryGB -lt 4) { "MODERATE" } else { "NORMAL" })
- System Health: $(if ($cpuUsage -gt 80 -or $availableMemoryGB -lt 2) { "STRESSED" } elseif ($cpuUsage -gt 50 -or $availableMemoryGB -lt 4) { "MODERATE LOAD" } else { "HEALTHY" })
"@

    $performanceMetricsPath = Join-Path $outputDir "performance_metrics_$timestamp.txt"
    $perfMetrics | Out-File -FilePath $performanceMetricsPath -Encoding UTF8
    Write-Host "Performance metrics saved to: $performanceMetricsPath"
    
} catch {
    Write-Host "Error gathering performance metrics: $($_.Exception.Message)"
    $perfMetrics = "Error gathering performance metrics"
}

# PHASE 4: AI Analysis of Big Eaters
Write-Host "`nPHASE 4: AI analysis of resource usage..."

try {
    # Combine all data for AI analysis
    $combinedData = @"
$systemSpecs

$perfMetrics

$processReport
"@

    # Sanitize data for API (prevent injection)
    $cleanData = $combinedData -replace '[\x00-\x1F\x7F]', ' '
    $cleanData = $cleanData -replace '[\\""]', '\"'
    $cleanData = $cleanData -replace '\s+', ' '
    $cleanData = $cleanData.Trim()
    
    # Truncate if too long to prevent oversized requests
    $maxDataLength = 12000
    if ($cleanData.Length -gt $maxDataLength) {
        $cleanData = $cleanData.Substring(0, $maxDataLength) + "... [data truncated for processing]"
        Write-Host "Data truncated to $maxDataLength characters for AI analysis"
    }
    
    $analysisPrompt = @"
Analyze this system monitoring data and provide insights about resource usage. Focus on:

â€¢ RESOURCE HOG IDENTIFICATION - Which processes are consuming the most CPU/memory and why
â€¢ SYSTEM HEALTH ASSESSMENT - Overall system performance and any concerns
â€¢ OPTIMIZATION OPPORTUNITIES - What could be improved or investigated
â€¢ UNUSUAL ACTIVITY - Any processes or patterns that seem abnormal
â€¢ RECOMMENDATIONS - Specific actions to improve performance

System Data:
$cleanData
"@

    # Validate API endpoint is reachable before attempting
    try {
        $testResponse = Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/models" -Method GET -TimeoutSec 5 -ErrorAction Stop
    } catch {
        throw "AI service not available at 127.0.0.1:1234. Please ensure LMStudio is running."
    }
    
    # Call AI for analysis with error handling
    $aiBody = @{
        model = "gemma-3-4b-it-qat"
        messages = @(
            @{
                role = "user"
                content = $analysisPrompt
            }
        )
        max_tokens = 1500
        temperature = 0.3
    } | ConvertTo-Json -Depth 5
    
    $headers = @{
        'Content-Type' = 'application/json; charset=utf-8'
    }
    
    $aiBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($aiBody)
    $aiResponse = Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/chat/completions" -Method POST -Body $aiBodyBytes -Headers $headers -TimeoutSec 300
    $aiData = $aiResponse.Content | ConvertFrom-Json
    $aiAnalysis = $aiData.choices[0].message.content
    
    Write-Host "AI analysis complete"
    
} catch {
    Write-Host "Error in AI analysis: $($_.Exception.Message)"
    $aiAnalysis = "Unable to perform AI analysis of system data"
}

# Create comprehensive system report
$finalReportPath = "$outputDir\system_monitor_report_$timestamp.txt"
$finalReport = @"
SYSTEM MONITOR AI REPORT
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

AI ANALYSIS & RECOMMENDATIONS:
$aiAnalysis

$systemSpecs

$perfMetrics

$processReport

---
Files Generated:
- System Specs: $systemSpecsPath
- Process Analysis: $processAnalysisPath  
- Performance Metrics: $performanceMetricsPath
- Complete Report: $finalReportPath
"@

$finalReport | Out-File -FilePath $finalReportPath -Encoding UTF8

# Copy AI analysis to clipboard
$aiAnalysis | Set-Clipboard

Write-Host ""
Write-Host "SYSTEM MONITOR AI COMPLETE!"
Write-Host "Complete report saved to: $finalReportPath"
Write-Host "AI analysis copied to clipboard"
Write-Host ""
Write-Host "AI ANALYSIS SUMMARY:"
Write-Host $aiAnalysis.Substring(0, [Math]::Min(800, $aiAnalysis.Length))
if ($aiAnalysis.Length -gt 800) { Write-Host "..." }

# Generate audio summary (optional)
if (!$SkipAudio) {
    Write-Host "`nGenerating audio summary..."
    try {
        # Create concise summary for TTS
        $summaryPrompt = "Create a 2-3 sentence audio summary of this system analysis.
        Focus on key findings and main recommendations.
        Only the summary, no additional context or statements.
        Make it suitable for text-to-speech:`n`n$aiAnalysis"
        
        $summaryBody = @{
            model = "gemma-3-4b-it-qat"
            messages = @(
                @{
                    role = "user"
                    content = $summaryPrompt
                }
            )
            max_tokens = 200
            temperature = 0.2
        } | ConvertTo-Json -Depth 5
        
        $summaryBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($summaryBody)
        $summaryResponse = Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/chat/completions" -Method POST -Body $summaryBodyBytes -Headers $headers -TimeoutSec 300
        $summaryData = $summaryResponse.Content | ConvertFrom-Json
        $audioSummary = $summaryData.choices[0].message.content
        
        # Test TTS service availability
        try {
            $ttsTestResponse = Invoke-WebRequest -Uri "http://127.0.0.1:8880/v1/models" -Method GET -TimeoutSec 5 -ErrorAction Stop
        } catch {
            throw "TTS service not available at 127.0.0.1:8880"
        }
        
        $ttsBody = @{
            model = "kokoro"
            input = "System Monitor Analysis: $audioSummary"
            voice = "af_sky"
            response_format = "mp3"
            speed = 1.0
            stream = $false
        } | ConvertTo-Json -Depth 3
        
        $audioPath = Join-Path $outputDir "system_monitor_$timestamp.mp3"
        
        $ttsHeaders = @{
            'Content-Type' = 'application/json; charset=utf-8'
            'Accept' = 'audio/mpeg'
        }
        
        $ttsBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($ttsBody)
        $ttsResponse = Invoke-WebRequest -Uri "http://127.0.0.1:8880/v1/audio/speech" -Method POST -Body $ttsBodyBytes -Headers $ttsHeaders -TimeoutSec 300
        [System.IO.File]::WriteAllBytes($audioPath, $ttsResponse.Content)
        
        # Check if VLC exists before trying to use it
        $vlcPath = "C:\Program Files\VideoLAN\VLC\vlc.exe"
        if (Test-Path $vlcPath) {
            Start-Sleep 1
            Start-Process -FilePath $vlcPath -ArgumentList "--intf dummy --play-and-exit `"$audioPath`"" -NoNewWindow -Wait
            Write-Host "Audio summary played!"
        } else {
            Write-Host "Audio generated but VLC not found at expected path. Audio saved to: $audioPath"
        }
        
    } catch {
        Write-Warning "Audio generation failed: $($_.Exception.Message)"
    }
} else {
    Write-Host "Audio generation skipped (use -SkipAudio parameter to control this)"
}

Write-Host ""
Write-Host "System analysis complete - check the full report for detailed insights!"
