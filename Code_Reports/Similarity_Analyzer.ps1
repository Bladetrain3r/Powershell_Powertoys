# Code Similarity Analyzer - PowerShell wrapper for neural network analysis
param(
    [Parameter(Mandatory)]
    [string]$InputPath,
    [string[]]$FileExtensions = @("*.ps1", "*.py", "*.js", "*.cs", "*.java"),
    [int]$MinFunctionSize = 5,
    [float]$SimilarityThreshold = 0.7,
    [string]$OutputDirectory = "C:\tmp\CodeSimilarity",
    [int]$TrainingEpochs = 2000,
    [switch]$SkipVenvSetup,
    [switch]$Recursive
)

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# Ensure output directory exists
if (!(Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

# Import LMStudio module
try {
    Import-Module G:\Doom\Zerofuchs_Software\Powershell\Model_Modules\LMStudio_Integration.psm1 -Force -ErrorAction Stop
    Write-Host "LMStudio module loaded" -ForegroundColor Green
} catch {
    Write-Host "Warning: LMStudio module not found. LLM analysis will be skipped." -ForegroundColor Yellow
    $skipLLM = $true
}

Write-Host "Code Similarity Analyzer - Neural Network Pattern Detection" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# Check Python availability
try {
    $pythonVersion = python --version 2>&1
    if ($pythonVersion -match "Python (\d+)\.(\d+)") {
        $majorVersion = [int]$matches[1]
        $minorVersion = [int]$matches[2]
        if ($majorVersion -lt 3 -or ($majorVersion -eq 3 -and $minorVersion -lt 7)) {
            throw "Python 3.7+ required, found $pythonVersion"
        }
    }
    Write-Host "Python detected: $pythonVersion" -ForegroundColor Green
} catch {
    Write-Host "Error: Python 3.7+ is required but not found" -ForegroundColor Red
    Write-Host "Please install Python from https://python.org" -ForegroundColor Yellow
    exit 1
}

# Set up virtual environment
$venvPath = Join-Path $OutputDirectory "similarity_venv"
$venvPython = Join-Path $venvPath "Scripts\python.exe"
$venvPip = Join-Path $venvPath "Scripts\pip.exe"

if (!$SkipVenvSetup -or !(Test-Path $venvPath)) {
    Write-Host "`nSetting up Python virtual environment..." -ForegroundColor Cyan
    
    try {
        # Create venv
        Write-Host "Creating virtual environment at $venvPath" -ForegroundColor Gray
        python -m venv $venvPath 2>&1 | Out-Null
        
        if (!(Test-Path $venvPython)) {
            throw "Virtual environment creation failed"
        }
        
        # Upgrade pip
        Write-Host "Upgrading pip..." -ForegroundColor Gray
        & $venvPython -m pip install --upgrade pip 2>&1 | Out-Null
        
        # Install required packages
        Write-Host "Installing required packages..." -ForegroundColor Gray
        $packages = @(
            "numpy>=1.21.0",
            "scikit-learn>=1.0.0",
            "torch>=1.9.0",
            "pandas>=1.3.0"
        )
        
        foreach ($package in $packages) {
            Write-Host "  Installing $package" -ForegroundColor Gray
            & $venvPip install $package 2>&1 | Out-Null
        }
        
        Write-Host "Virtual environment setup complete" -ForegroundColor Green
        
    } catch {
        Write-Host "Error setting up virtual environment: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Using existing virtual environment at $venvPath" -ForegroundColor Green
}

# Copy Python script to output directory
$pythonScriptSource = Join-Path $PSScriptRoot "code_vectorizer.py"
$pythonScriptDest = Join-Path $OutputDirectory "code_vectorizer.py"

if (Test-Path $pythonScriptSource) {
    Copy-Item $pythonScriptSource $pythonScriptDest -Force
    Write-Host "Python script copied to $pythonScriptDest" -ForegroundColor Green
} else {
    Write-Host "Warning: code_vectorizer.py not found in script directory" -ForegroundColor Yellow
    Write-Host "Please ensure code_vectorizer.py is in the same directory as this script" -ForegroundColor Yellow
    exit 1
}

# Run Python analysis
Write-Host "`nPhase 1: Running neural network analysis..." -ForegroundColor Cyan

$pythonArgs = @(
    $pythonScriptDest,
    $InputPath,
    "--min-lines", $MinFunctionSize,
    "--threshold", $SimilarityThreshold,
    "--output-dir", $OutputDirectory,
    "--timestamp", $timestamp,
    "--epochs", $TrainingEpochs
)

try {
    Write-Host "Executing Python analysis with:" -ForegroundColor Gray
    Write-Host "  Input path: $InputPath" -ForegroundColor Gray
    Write-Host "  Min function size: $MinFunctionSize lines" -ForegroundColor Gray
    Write-Host "  Similarity threshold: $SimilarityThreshold" -ForegroundColor Gray
    Write-Host "  Training epochs: $TrainingEpochs" -ForegroundColor Gray
    Write-Host ""
    
    $process = Start-Process -FilePath $venvPython -ArgumentList $pythonArgs -NoNewWindow -PassThru -Wait -RedirectStandardOutput "$OutputDirectory\python_output.txt" -RedirectStandardError "$OutputDirectory\python_error.txt"
    
    # Display Python output
    if (Test-Path "$OutputDirectory\python_output.txt") {
        Get-Content "$OutputDirectory\python_output.txt" | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    }
    
    if ($process.ExitCode -ne 0) {
        if (Test-Path "$OutputDirectory\python_error.txt") {
            $errorContent = Get-Content "$OutputDirectory\python_error.txt" -Raw
            throw "Python analysis failed: $errorContent"
        }
        throw "Python analysis failed with exit code $($process.ExitCode)"
    }
    
    Write-Host "`nNeural network analysis complete" -ForegroundColor Green
    
} catch {
    Write-Host "Error during Python analysis: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Load results
Write-Host "`nPhase 2: Loading analysis results..." -ForegroundColor Cyan

$resultsPath = Join-Path $OutputDirectory "similarity_analysis_$timestamp.json"
$tablePath = Join-Path $OutputDirectory "similarity_table_$timestamp.csv"
$embeddingsPath = Join-Path $OutputDirectory "embeddings_$timestamp.npy"

if (!(Test-Path $resultsPath)) {
    Write-Host "Analysis results not found at $resultsPath" -ForegroundColor Red
    exit 1
}

try {
    $results = Get-Content $resultsPath -Raw | ConvertFrom-Json
    $csvData = Import-Csv $tablePath
    
    Write-Host "Analysis results loaded:" -ForegroundColor Green
    Write-Host "- Total functions analyzed: $($results.total_functions)"
    Write-Host "- Similar pairs found: $($results.similar_pairs)"
    Write-Host "- Pattern clusters: $($results.clusters)"
    Write-Host "- Embedding dimensions: $($results.embedding_dim)"
    Write-Host "- Features extracted: $($results.feature_count)"
    
} catch {
    Write-Host "Error loading results: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Phase 3: LLM Analysis (if available)
if (!$skipLLM -and $results.similar_pairs -gt 0) {
    Write-Host "`nPhase 3: Generating LLM insights..." -ForegroundColor Cyan
    
    # Prepare summary data
    $topSimilarities = $csvData | Sort-Object -Property Similarity -Descending | Select-Object -First 20
    
    $summaryData = @"
Code Similarity Analysis Results:
- Total functions: $($results.total_functions)
- Similar pairs: $($results.similar_pairs)
- Pattern clusters: $($results.clusters)
- Neural network embedding dimensions: $($results.embedding_dim)
- Features per function: $($results.feature_count)

TOP SIMILAR FUNCTIONS (Neural Network Similarity):
$(foreach ($item in $topSimilarities) {
    "$($item.Function1) ($($item.Lines1) lines) <-> $($item.Function2) ($($item.Lines2) lines) = $($item.Similarity)"
})

PATTERN CLUSTERS:
$(if ($results.clusters_detail) {
    $clusterNum = 1
    foreach ($cluster in $results.clusters_detail) {
        "Cluster $clusterNum`: $($cluster.Count) similar functions"
        $clusterNum++
    }
})

TOP FEATURES ANALYZED:
$(if ($results.feature_importance.top_features) {
    $results.feature_importance.top_features -join ", "
})
"@

    $llmPrompt = @"
Analyze this code similarity report from neural network analysis:

$summaryData

The analysis used:
- Structural features (lines, complexity, indentation)
- AST features (for Python code)
- Semantic features (token patterns)
- Neural network embeddings for similarity

Provide insights on:
1. DUPLICATION PATTERNS - What types of code duplication are evident?
2. REFACTORING OPPORTUNITIES - Which similar functions could be consolidated?
3. CODE SMELL INDICATORS - What do these patterns suggest about code quality?
4. ARCHITECTURE INSIGHTS - What does this reveal about the codebase structure?
5. PRIORITY ACTIONS - What should be addressed first to improve maintainability?

Focus on actionable recommendations.
"@

    try {
        $cleanPrompt = Clean-TextForAPI -Text $llmPrompt -MaxLength 8000
        $llmSummary = Invoke-LMStudioAPI -Model "gemma-3-12b-it-qat" -Prompt $cleanPrompt -MaxTokens 1500 -Temperature 0.3
        
        if ($llmSummary -notlike "ERROR:*") {
            Write-Host "LLM analysis complete" -ForegroundColor Green
        } else {
            Write-Host "LLM analysis failed: $llmSummary" -ForegroundColor Yellow
            $llmSummary = "LLM analysis unavailable"
        }
        
    } catch {
        Write-Host "LLM analysis error: $($_.Exception.Message)" -ForegroundColor Yellow
        $llmSummary = "LLM analysis unavailable"
    }
} else {
    $llmSummary = if ($skipLLM) { "LLM analysis skipped (module not loaded)" } else { "No similar pairs found to analyze" }
}

# Generate final report
$finalReportPath = Join-Path $OutputDirectory "similarity_report_$timestamp.txt"
$finalReport = @"
CODE SIMILARITY ANALYSIS REPORT (Neural Network Analysis)
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Codebase: $InputPath

=== NEURAL NETWORK CONFIGURATION ===
Training Epochs: $TrainingEpochs
Embedding Dimensions: $($results.embedding_dim)
Features Extracted: $($results.feature_count)
Similarity Threshold: $SimilarityThreshold

=== SUMMARY STATISTICS ===
Total Functions Analyzed: $($results.total_functions)
Similar Pairs Found: $($results.similar_pairs)
Pattern Clusters: $($results.clusters)

=== TOP SIMILARITIES (Neural Network) ===
$(foreach ($item in ($csvData | Sort-Object -Property Similarity -Descending | Select-Object -First 10)) {
    "Score: $($item.Similarity)"
    "  Function 1: $($item.Function1) ($($item.Lines1) lines) in $($item.File1)"
    "  Function 2: $($item.Function2) ($($item.Lines2) lines) in $($item.File2)"
    ""
})

=== LLM ANALYSIS ===
$llmSummary

=== PATTERN CLUSTERS ===
$(if ($results.clusters_detail -and $results.clusters_detail.Count -gt 0) {
    $clusterNum = 1
    foreach ($cluster in $results.clusters_detail) {
        "Cluster $clusterNum ($($cluster.Count) functions):"
        foreach ($idx in $cluster) {
            $func = $results.functions[$idx]
            "  - $($func.name) ($($func.lines) lines) in $(Split-Path -Leaf $func.file)"
        }
        ""
        $clusterNum++
    }
} else {
    "No significant clusters found"
})

=== FEATURE IMPORTANCE ===
Top analyzed features: $(if ($results.feature_importance.top_features) { $results.feature_importance.top_features -join ", " } else { "N/A" })

=== FILES GENERATED ===
- Neural Network Results: $resultsPath
- Similarity Table (CSV): $tablePath
- Embeddings (NumPy): $embeddingsPath
- This Report: $finalReportPath
"@

$finalReport | Out-File -FilePath $finalReportPath -Encoding UTF8

# Display summary
Write-Host "`n=== ANALYSIS COMPLETE ===" -ForegroundColor Green
Write-Host "Neural network trained with $TrainingEpochs epochs"
Write-Host "Analyzed $($results.total_functions) functions"
Write-Host "Found $($results.similar_pairs) similar pairs (threshold: $SimilarityThreshold)"
Write-Host "Identified $($results.clusters) pattern clusters"

if ($csvData.Count -gt 0) {
    Write-Host "`nTop 5 most similar function pairs:" -ForegroundColor Yellow
    $csvData | Sort-Object -Property Similarity -Descending | Select-Object -First 5 | ForEach-Object {
        Write-Host "  $($_.Similarity): $($_.Function1) <-> $($_.Function2)" -ForegroundColor Cyan
    }
}

Write-Host "`nFiles generated:" -ForegroundColor Gray
Write-Host "- Full report: $finalReportPath"
Write-Host "- Similarity CSV: $tablePath"
Write-Host "- Raw JSON data: $resultsPath"
Write-Host "- Embeddings: $embeddingsPath"

# Copy summary to clipboard
if ($llmSummary -ne "LLM analysis unavailable") {
    $llmSummary | Set-Clipboard
    Write-Host "`nLLM insights copied to clipboard" -ForegroundColor Green
}