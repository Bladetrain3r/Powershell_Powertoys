# C++ Architecture Optimizer - System-aware compile-time optimization analyzer
param(
    [string]$CppSourcePath = ".",
    [string]$OutputDirectory = ".\outputs\CppOptimizer",
    [int]$MaxFiles = 500,
    [switch]$IncludeHeaders,
    [switch]$Recursive,
    [switch]$SkipAudio,
    [string]$CompilerType = "auto", # auto, gcc, clang, msvc
    [string]$TargetArchitecture = "auto" # auto, x64, arm64, x86
)

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# Ensure output directory exists
if (!(Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

Write-Host "C++ Architecture Optimizer - System-aware compile-time analysis" -ForegroundColor Green
Write-Host "Source Path: $CppSourcePath"
Write-Host "Target: $TargetArchitecture architecture with $CompilerType compiler"

# PHASE 1: System Architecture Detection
Write-Host "`nPHASE 1: Analyzing system architecture..."

try {
    # Get detailed CPU information
    $cpuInfo = Get-CimInstance -ClassName Win32_Processor
    $computerInfo = Get-ComputerInfo
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    
    # Detect CPU features
    $cpuFeatures = @()
    $cpuName = $cpuInfo.Name
    $cpuArchitecture = $cpuInfo.Architecture
    $cpuCores = $cpuInfo.NumberOfCores
    $cpuLogicalProcessors = $cpuInfo.NumberOfLogicalProcessors
    $cpuMaxClock = $cpuInfo.MaxClockSpeed
    
    # Memory information
    $totalMemoryGB = [math]::Round($computerInfo.TotalPhysicalMemory / 1GB, 2)
    $cacheL2 = if ($cpuInfo.L2CacheSize) { $cpuInfo.L2CacheSize } else { "Unknown" }
    $cacheL3 = if ($cpuInfo.L3CacheSize) { $cpuInfo.L3CacheSize } else { "Unknown" }
    
    # Detect CPU vendor and features
    $cpuVendor = "Unknown"
    $supportedInstructions = @()
    
    if ($cpuName -match "Intel") {
        $cpuVendor = "Intel"
        # Intel-specific features detection
        if ($cpuName -match "i[3579]") {
            $supportedInstructions += @("SSE", "SSE2", "SSE3", "SSSE3", "SSE4.1", "SSE4.2")
        }
        if ($cpuName -match "(i[57]|Xeon|Core.*[mi][3579])") {
            $supportedInstructions += @("AVX", "AVX2")
        }
        if ($cpuName -match "(i[79].*[0-9]{4}|Xeon.*v[4-9])") {
            $supportedInstructions += @("AVX-512")
        }
    } elseif ($cpuName -match "AMD") {
        $cpuVendor = "AMD"
        # AMD-specific features
        if ($cpuName -match "(Ryzen|EPYC|Threadripper)") {
            $supportedInstructions += @("SSE", "SSE2", "SSE3", "SSSE3", "SSE4.1", "SSE4.2", "AVX", "AVX2")
        }
        if ($cpuName -match "(Ryzen.*[3-9]|EPYC|Threadripper)") {
            $supportedInstructions += @("BMI1", "BMI2", "FMA3")
        }
    } elseif ($cpuName -match "ARM") {
        $cpuVendor = "ARM"
        $supportedInstructions += @("NEON", "AES", "SHA")
    }
    
    # Auto-detect architecture if not specified
    if ($TargetArchitecture -eq "auto") {
        $TargetArchitecture = switch ($cpuArchitecture) {
            0 { "x86" }      # x86
            9 { "x64" }      # x64
            12 { "arm64" }   # ARM64
            default { "x64" }
        }
    }
    
    $systemAnalysis = @"
SYSTEM ARCHITECTURE ANALYSIS
CPU: $cpuName
Vendor: $cpuVendor
Architecture: $TargetArchitecture
Cores: $cpuCores physical, $cpuLogicalProcessors logical
Max Clock: $cpuMaxClock MHz
L2 Cache: $cacheL2 KB
L3 Cache: $cacheL3 KB
Total RAM: $totalMemoryGB GB
Supported Instructions: $($supportedInstructions -join ', ')
"@

    Write-Host "System analysis complete: $cpuVendor $TargetArchitecture with $cpuCores cores"
    
} catch {
    Write-Host "Error analyzing system: $($_.Exception.Message)" -ForegroundColor Red
    $systemAnalysis = "System analysis failed"
    $cpuVendor = "Unknown"
    $supportedInstructions = @()
}

# PHASE 2: C++ Source Code Discovery and Analysis
Write-Host "`nPHASE 2: Discovering C++ source files..."

try {
    # File extensions to analyze
    $cppExtensions = @("*.cpp", "*.cc", "*.cxx", "*.c++")
    if ($IncludeHeaders) {
        $cppExtensions += @("*.h", "*.hpp", "*.hxx", "*.h++")
    }
    
    $allFiles = @()
    foreach ($ext in $cppExtensions) {
        if ($Recursive) {
            $files = Get-ChildItem -Path $CppSourcePath -Filter $ext -Recurse -File -ErrorAction SilentlyContinue
        } else {
            $files = Get-ChildItem -Path $CppSourcePath -Filter $ext -File -ErrorAction SilentlyContinue
        }
        if ($files) { $allFiles += $files }
    }
    
    # Filter and limit files
    $validFiles = $allFiles | Where-Object { $_.Length -le 10MB } | Sort-Object Name
    
    if ($MaxFiles -gt 0 -and $validFiles.Count -gt $MaxFiles) {
        $validFiles = $validFiles | Select-Object -First $MaxFiles
        Write-Host "Limited to first $MaxFiles files"
    }
    
    if ($validFiles.Count -eq 0) {
        Write-Host "No C++ files found to analyze" -ForegroundColor Yellow
        exit
    }
    
    Write-Host "Found $($validFiles.Count) C++ files to analyze"
    
} catch {
    Write-Host "Error discovering files: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# PHASE 3: Code Pattern Analysis
Write-Host "`nPHASE 3: Analyzing code patterns for optimization opportunities..."

$codeAnalysis = @{
    TotalFiles = $validFiles.Count
    TotalLines = 0
    TemplateUsage = 0
    LoopPatterns = @()
    MemoryPatterns = @()
    MathOperations = @()
    ConcurrencyPatterns = @()
    CompilerDirectives = @()
    LibraryUsage = @()
    OptimizationOpportunities = @()
}

$processedCount = 0

foreach ($file in $validFiles) {
    try {
        $processedCount++
        Write-Host "[$processedCount/$($validFiles.Count)] Analyzing: $($file.Name)"
        
        $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($content)) { continue }
        
        $lines = ($content -split "`n").Count
        $codeAnalysis.TotalLines += $lines
        
        # Template usage detection
        if ($content -match "template\s*<") {
            $codeAnalysis.TemplateUsage++
        }
        
        # Loop patterns
        $loopMatches = [regex]::Matches($content, "for\s*\([^)]+\)|while\s*\([^)]+\)")
        if ($loopMatches.Count -gt 0) {
            $codeAnalysis.LoopPatterns += "$($file.Name): $($loopMatches.Count) loops detected"
        }
        
        # Memory patterns
        if ($content -match "new\s+|\bmalloc\b|\bcalloc\b|\brealloc\b") {
            $codeAnalysis.MemoryPatterns += "$($file.Name): Dynamic allocation detected"
        }
        if ($content -match "std::vector|std::array|std::unique_ptr|std::shared_ptr") {
            $codeAnalysis.MemoryPatterns += "$($file.Name): STL container usage"
        }
        
        # Math operations
        if ($content -match "sin\(|cos\(|tan\(|sqrt\(|pow\(|exp\(|log\(") {
            $codeAnalysis.MathOperations += "$($file.Name): Mathematical functions"
        }
        if ($content -match "\*|\+|-|/|%") {
            $mathOps = [regex]::Matches($content, "[\+\-\*/]").Count
            if ($mathOps -gt 10) {
                $codeAnalysis.MathOperations += "$($file.Name): Heavy arithmetic ($mathOps operations)"
            }
        }
        
        # Concurrency patterns
        if ($content -match "std::thread|std::mutex|std::async|#pragma omp|pthread") {
            $codeAnalysis.ConcurrencyPatterns += "$($file.Name): Concurrency detected"
        }
        
        # Compiler directives
        $pragmas = [regex]::Matches($content, "#pragma\s+\w+")
        foreach ($pragma in $pragmas) {
            $codeAnalysis.CompilerDirectives += "$($file.Name): $($pragma.Value)"
        }
        
        # Library usage
        $includes = [regex]::Matches($content, '#include\s*[<"]([^>"]+)[>"]')
        foreach ($include in $includes) {
            $codeAnalysis.LibraryUsage += $include.Groups[1].Value
        }
        
    } catch {
        Write-Host "  Error analyzing $($file.Name): $($_.Exception.Message)" -ForegroundColor Yellow
        continue
    }
}

# Analyze library usage patterns
$libraryStats = $codeAnalysis.LibraryUsage | Group-Object | Sort-Object Count -Descending | Select-Object -First 10

Write-Host "Code analysis complete: $($codeAnalysis.TotalLines) lines in $($codeAnalysis.TotalFiles) files"

# PHASE 4: AI-Powered Optimization Analysis
Write-Host "`nPHASE 4: Generating system-specific optimization recommendations..."

# Prepare comprehensive data for AI analysis
$analysisData = @"
SYSTEM ARCHITECTURE:
$systemAnalysis

CODE ANALYSIS SUMMARY:
Total Files: $($codeAnalysis.TotalFiles)
Total Lines: $($codeAnalysis.TotalLines)
Template Usage: $($codeAnalysis.TemplateUsage) files
Loop Patterns: $($codeAnalysis.LoopPatterns.Count) files with loops
Memory Allocations: $($codeAnalysis.MemoryPatterns.Count) patterns
Math Operations: $($codeAnalysis.MathOperations.Count) files with heavy math
Concurrency: $($codeAnalysis.ConcurrencyPatterns.Count) files
Compiler Directives: $($codeAnalysis.CompilerDirectives.Count) existing pragmas

TOP LIBRARIES USED:
$(foreach ($lib in $libraryStats) { "$($lib.Name): $($lib.Count) includes" })

SPECIFIC PATTERNS FOUND:
Loop Patterns: $($codeAnalysis.LoopPatterns -join "; ")
Memory Patterns: $($codeAnalysis.MemoryPatterns -join "; ")
Math Operations: $($codeAnalysis.MathOperations -join "; ")
Concurrency: $($codeAnalysis.ConcurrencyPatterns -join "; ")

TARGET COMPILATION:
Architecture: $TargetArchitecture
Compiler: $CompilerType
"@

# Clean data for API
$cleanData = $analysisData -replace '[\x00-\x1F\x7F]', ' '
$cleanData = $cleanData -replace '\\', '\\'
$cleanData = $cleanData -replace '"', '\"'
$cleanData = $cleanData -replace '\s+', ' '
$cleanData = $cleanData.Trim()

if ($cleanData.Length -gt 15000) {
    $cleanData = $cleanData.Substring(0, 15000) + "... [truncated for analysis]"
}

$optimizationPrompt = @"
Analyze this C++ codebase and system architecture to provide specific compile-time optimization recommendations.

FOCUS AREAS:
• COMPILER FLAGS - Specific flags for the detected CPU and architecture
• VECTORIZATION - SIMD optimization opportunities based on supported instructions
• MEMORY OPTIMIZATION - Cache-friendly compilation strategies
• TEMPLATE OPTIMIZATION - Template instantiation and compile-time improvements
• LINK-TIME OPTIMIZATION - LTO and whole-program optimization suggestions
• ARCHITECTURE-SPECIFIC - CPU-specific optimizations for the detected hardware
• BUILD SYSTEM - CMake/Makefile optimization suggestions
• PROFILE-GUIDED OPTIMIZATION - PGO recommendations based on code patterns

Provide practical, actionable recommendations with specific compiler flags and techniques.

System and Code Analysis:
$cleanData
"@

try {
    $optimizationBody = @{
        model = 'gemma-3-4b-it-qat'
        messages = @(
            @{
                role = 'user'
                content = $optimizationPrompt
            }
        )
        max_tokens = 3000
        temperature = 0.2
    } | ConvertTo-Json -Depth 5
    
    $headers = @{
        'Content-Type' = 'application/json; charset=utf-8'
    }
    
    $optimizationBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($optimizationBody)
    $optimizationResponse = Invoke-WebRequest -Uri "http://localhost:1234/v1/chat/completions" -Method POST -Body $optimizationBodyBytes -Headers $headers -TimeoutSec 300
    $optimizationData = $optimizationResponse.Content | ConvertFrom-Json
    $aiRecommendations = $optimizationData.choices[0].message.content
    
    Write-Host "AI optimization analysis complete"
    
} catch {
    Write-Host "Error getting AI recommendations: $($_.Exception.Message)" -ForegroundColor Red
    $aiRecommendations = "Unable to generate AI recommendations - check LMStudio connection"
}

# PHASE 5: Generate Specific Compiler Configurations
Write-Host "`nPHASE 5: Generating compiler-specific configurations..."

# Generate architecture-specific flags
$archFlags = switch ($TargetArchitecture) {
    "x64" { 
        if ($cpuVendor -eq "Intel") {
            "-march=native -mtune=native"
        } elseif ($cpuVendor -eq "AMD") {
            "-march=native -mtune=native"
        } else {
            "-march=x86-64 -mtune=generic"
        }
    }
    "arm64" { "-march=armv8-a+crypto" }
    "x86" { "-march=i686 -mtune=generic" }
    default { "-march=native" }
}

# Vector instruction flags
$vectorFlags = ""
if ($supportedInstructions -contains "AVX-512") {
    $vectorFlags = "-mavx512f -mavx512cd"
} elseif ($supportedInstructions -contains "AVX2") {
    $vectorFlags = "-mavx2 -mfma"
} elseif ($supportedInstructions -contains "AVX") {
    $vectorFlags = "-mavx"
} elseif ($supportedInstructions -contains "SSE4.2") {
    $vectorFlags = "-msse4.2"
}

# Generate compiler configurations
$compilerConfigs = @"
COMPILER CONFIGURATION RECOMMENDATIONS

=== GCC Configuration ===
# Release build with aggressive optimization
CXXFLAGS = -O3 -DNDEBUG $archFlags $vectorFlags -flto -ffast-math
CXXFLAGS += -funroll-loops -finline-functions -fprefetch-loop-arrays
CXXFLAGS += -fomit-frame-pointer -fno-exceptions -fno-rtti
$(if ($cpuCores -gt 4) { "CXXFLAGS += -fopenmp" })

# Cache and memory optimization
CXXFLAGS += -falign-functions=32 -falign-loops=32
$(if ($cacheL3 -ne "Unknown") { "CXXFLAGS += --param l1-cache-size=$($cacheL2) --param l2-cache-size=$($cacheL3)" })

=== Clang Configuration ===
CXXFLAGS = -O3 -DNDEBUG $archFlags $vectorFlags -flto -ffast-math
CXXFLAGS += -funroll-loops -finline-functions -fvectorize
CXXFLAGS += -fomit-frame-pointer -fno-exceptions -fno-rtti
$(if ($cpuCores -gt 4) { "CXXFLAGS += -fopenmp" })

# Clang-specific optimizations
CXXFLAGS += -mllvm -polly -mllvm -polly-vectorizer=stripmine

=== MSVC Configuration ===
# Visual Studio flags
/O2 /Oi /Ot /Oy /GL /DNDEBUG
$(if ($TargetArchitecture -eq "x64") { "/favor:INTEL64" })
$(if ($supportedInstructions -contains "AVX2") { "/arch:AVX2" })
/fp:fast /Qpar

=== CMake Configuration ===
cmake_minimum_required(VERSION 3.15)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Release configuration
set(CMAKE_CXX_FLAGS_RELEASE "-O3 -DNDEBUG $archFlags $vectorFlags")
set(CMAKE_BUILD_TYPE Release)

# Enable IPO/LTO if supported
include(CheckIPOSupported)
check_ipo_supported(RESULT ipo_supported OUTPUT ipo_error)
if(ipo_supported)
    set(CMAKE_INTERPROCEDURAL_OPTIMIZATION TRUE)
endif()

# CPU-specific settings
set(CMAKE_CXX_FLAGS "`${CMAKE_CXX_FLAGS} -march=native -mtune=native")
$(if ($cpuCores -gt 4) { 
"find_package(OpenMP)
if(OpenMP_CXX_FOUND)
    target_link_libraries(your_target PUBLIC OpenMP::OpenMP_CXX)
endif()" })

=== Profile-Guided Optimization ===
# Step 1: Build with profiling
g++ -O2 -fprofile-generate $archFlags -o program_instrumented source.cpp

# Step 2: Run typical workload
./program_instrumented [with typical input]

# Step 3: Build optimized version
g++ -O3 -fprofile-use $archFlags $vectorFlags -flto -o program_optimized source.cpp
"@

# Create comprehensive report
$reportPath = Join-Path $OutputDirectory "cpp_optimization_report_$timestamp.txt"
$fullReport = @"
C++ ARCHITECTURE OPTIMIZER REPORT
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

$systemAnalysis

CODE ANALYSIS RESULTS:
$($analysisData)

AI OPTIMIZATION RECOMMENDATIONS:
$aiRecommendations

SYSTEM-SPECIFIC COMPILER CONFIGURATIONS:
$compilerConfigs

IMPLEMENTATION CHECKLIST:
□ Update build system with recommended flags
□ Test performance with different optimization levels
□ Implement Profile-Guided Optimization workflow
□ Consider memory alignment for cache optimization
□ Enable vectorization where appropriate
□ Profile actual performance improvements

ESTIMATED PERFORMANCE GAINS:
- Vectorization: 2-8x for applicable algorithms
- Cache optimization: 10-30% overall improvement
- LTO/IPO: 5-15% binary size and speed improvement
- PGO: 10-20% for hot code paths
- Architecture tuning: 5-10% baseline improvement

NEXT STEPS:
1. Apply recommended compiler flags incrementally
2. Benchmark before and after changes
3. Use profiling tools (perf, vtune, etc.)
4. Consider loop unrolling and template specialization
5. Implement SIMD intrinsics for critical paths

---
Generated by C++ Architecture Optimizer
Based on: $cpuVendor $TargetArchitecture, $cpuCores cores, $($supportedInstructions -join '+')
"@

$fullReport | Out-File -FilePath $reportPath -Encoding UTF8

# Save individual components
$systemAnalysisPath = Join-Path $OutputDirectory "system_analysis_$timestamp.txt"
$codeAnalysisPath = Join-Path $OutputDirectory "code_analysis_$timestamp.txt"
$compilerConfigsPath = Join-Path $OutputDirectory "compiler_configs_$timestamp.txt"

$systemAnalysis | Out-File -FilePath $systemAnalysisPath -Encoding UTF8
$analysisData | Out-File -FilePath $codeAnalysisPath -Encoding UTF8
$compilerConfigs | Out-File -FilePath $compilerConfigsPath -Encoding UTF8

# Copy key recommendations to clipboard
$clipboardText = @"
C++ Optimization Summary for $cpuVendor ${TargetArchitecture}:

Quick Start Flags:
GCC/Clang: -O3 -march=native -mtune=native $vectorFlags -flto
MSVC: /O2 /Oi /Ot $(if ($supportedInstructions -contains "AVX2") { "/arch:AVX2" })

Key Findings: $($codeAnalysis.TotalFiles) files, $($codeAnalysis.TotalLines) lines
- Templates: $($codeAnalysis.TemplateUsage) files
- Math-heavy: $($codeAnalysis.MathOperations.Count) files  
- Vectorizable: $($supportedInstructions -join '+') available

Estimated gains: 2-8x vectorization, 10-30% cache optimization
"@

$clipboardText | Set-Clipboard

Write-Host ""
Write-Host "C++ ARCHITECTURE OPTIMIZER COMPLETE!" -ForegroundColor Green
Write-Host "Target: $cpuVendor $TargetArchitecture with $($supportedInstructions -join '+')" -ForegroundColor Cyan
Write-Host "Analyzed: $($codeAnalysis.TotalFiles) files, $($codeAnalysis.TotalLines) lines" -ForegroundColor Cyan
Write-Host ""
Write-Host "Generated files:" -ForegroundColor Yellow
Write-Host "- Complete Report: $reportPath"
Write-Host "- System Analysis: $systemAnalysisPath"
Write-Host "- Code Analysis: $codeAnalysisPath"
Write-Host "- Compiler Configs: $compilerConfigsPath"
Write-Host ""
Write-Host "Quick start copied to clipboard" -ForegroundColor Green

# Generate and play audio summary
if (!$SkipAudio) {
    Write-Host "`nGenerating audio summary..."
    try {
        $audioSummary = @"
C++ Architecture Optimizer complete. Analyzed $($codeAnalysis.TotalFiles) files for $cpuVendor $TargetArchitecture architecture. 
Key findings: $($codeAnalysis.TemplateUsage) template files, $($codeAnalysis.MathOperations.Count) math-heavy files. 
Vectorization available: $($supportedInstructions -join ', '). 
Recommended flags: O3, march native, $vectorFlags.
Estimated performance gains: 2 to 8 times for vectorization, 10 to 30 percent cache improvement.
Profile-guided optimization recommended for additional 10 to 20 percent gains.
"@
        
        $ttsBody = @{
            model = 'kokoro'
            input = $audioSummary
            voice = 'af_sky'
            response_format = 'mp3'
            speed = 1.0
            stream = $false
        } | ConvertTo-Json -Depth 3
        
        $audioPath = Join-Path $OutputDirectory "cpp_optimizer_$timestamp.mp3"
        
        $ttsHeaders = @{
            'Content-Type' = 'application/json; charset=utf-8'
            'Accept' = 'audio/mpeg'
        }
        
        $ttsBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($ttsBody)
        $ttsResponse = Invoke-WebRequest -Uri "http://localhost:8880/v1/audio/speech" -Method POST -Body $ttsBodyBytes -Headers $ttsHeaders -TimeoutSec 60
        [System.IO.File]::WriteAllBytes($audioPath, $ttsResponse.Content)
        
        $vlcPath = "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"
        if (Test-Path $vlcPath) {
            Start-Sleep 1
            Start-Process -FilePath $vlcPath -ArgumentList "--intf dummy --play-and-exit `"$audioPath`"" -NoNewWindow -Wait
            Write-Host "Audio summary played!" -ForegroundColor Green
        } else {
            Write-Host "Audio saved to: $audioPath" -ForegroundColor Green
        }
        
    } catch {
        Write-Host "Audio generation failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "QUICK START RECOMMENDATIONS:" -ForegroundColor Cyan
Write-Host "1. Try: g++ -O3 -march=native $vectorFlags -flto yourfile.cpp" -ForegroundColor White
Write-Host "2. Measure baseline performance first" -ForegroundColor White
Write-Host "3. Apply flags incrementally and benchmark" -ForegroundColor White
Write-Host "4. Consider Profile-Guided Optimization for hot paths" -ForegroundColor White
Write-Host ""
Write-Host "Expected gains: $(if ($supportedInstructions -contains 'AVX') { '2-8x vectorization, ' })10-30% cache optimization" -ForegroundColor Green