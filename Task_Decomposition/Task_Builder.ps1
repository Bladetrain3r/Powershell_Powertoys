# Task Decomposition Engine - Recursive breakdown with model routing
param(
    [string]$InitialPrompt,
    [int]$MaxDepth = 5,
    [int]$MaxSubtasks = 10,
    [string]$OutputPath = ".\outputs\TaskDecomp"
)

# Model hierarchy - simplest to most complex
$ModelHierarchy = @(
    @{ Name = "REGEX"; Type = "code"; Capabilities = @("pattern_matching", "text_extraction") },
    @{ Name = "SCRIPT"; Type = "code"; Capabilities = @("file_ops", "data_transform", "calculation") },
    @{ Name = "gemma-3-1b-it-qat"; Type = "ai"; Capabilities = @("simple_summary", "basic_classification") },
    @{ Name = "gemma-3-4b-it-qat"; Type = "ai"; Capabilities = @("analysis", "code_review", "complex_summary") },
    @{ Name = "gemma-3-12b-it-qat"; Type = "ai"; Capabilities = @("reasoning", "planning", "creative_tasks") }
)

# Task queue structure
$script:TaskQueue = [System.Collections.Queue]::new()
$script:CompletedTasks = @()
$script:TaskTree = @{}

# Function to decompose a task
function Decompose-Task {
    param(
        [string]$TaskDescription,
        [int]$CurrentDepth = 0,
        [string]$ParentId = "root"
    )
    
    $taskId = [guid]::NewGuid().ToString().Substring(0, 8)
    Write-Host "[$CurrentDepth] Decomposing: $($TaskDescription.Substring(0, [Math]::Min(50, $TaskDescription.Length)))..." -ForegroundColor Cyan
    
    # Check if we've hit max depth or task is atomic enough
    if ($CurrentDepth -ge $MaxDepth) {
        Write-Host "  Max depth reached, queuing as-is" -ForegroundColor Yellow
        Queue-AtomicTask -Task $TaskDescription -Id $taskId -ParentId $ParentId
        return
    }
    
    # Try simple pattern matching first
    if (Test-AtomicTask -Task $TaskDescription) {
        Write-Host "  Task is atomic, queuing directly" -ForegroundColor Green
        Queue-AtomicTask -Task $TaskDescription -Id $taskId -ParentId $ParentId
        return
    }
    
    # Use smallest capable model for decomposition
    $decompositionPrompt = @"
Break down this task into at most $MaxSubtasks atomic subtasks. Each subtask should be:
- Self-contained and independently executable
- Clear and specific
- As simple as possible

Return ONLY a numbered list, nothing else:

Task: $TaskDescription
"@
    
    $subtasks = Invoke-LMStudioAPI -Model "gemma-3-4b-it-qat" -Prompt $decompositionPrompt -MaxTokens 1000 -Temperature 0.2
    
    if ($subtasks -like "ERROR:*") {
        Write-Host "  Decomposition failed, queuing as-is" -ForegroundColor Red
        Queue-AtomicTask -Task $TaskDescription -Id $taskId -ParentId $ParentId
        return
    }
    
    # Parse subtasks
    $subtaskList = $subtasks -split "`n" | Where-Object { $_ -match '^\d+\.' } | ForEach-Object {
        $_ -replace '^\d+\.\s*', ''
    }
    
    Write-Host "  Decomposed into $($subtaskList.Count) subtasks" -ForegroundColor Green
    
    # Record in task tree
    $script:TaskTree[$taskId] = @{
        Description = $TaskDescription
        Parent = $ParentId
        Subtasks = @()
        Depth = $CurrentDepth
    }
    
    # Recursively decompose each subtask
    foreach ($subtask in $subtaskList) {
        if (![string]::IsNullOrWhiteSpace($subtask)) {
            $subtaskId = Decompose-Task -TaskDescription $subtask -CurrentDepth ($CurrentDepth + 1) -ParentId $taskId
            $script:TaskTree[$taskId].Subtasks += $subtaskId
        }
    }
    
    return $taskId
}

# Test if task is atomic enough
function Test-AtomicTask {
    param([string]$Task)
    
    # Simple heuristics for atomic tasks
    $atomicPatterns = @(
        '^(Read|Write|Save|Load|Get|Set|Extract|Count|Calculate|Find|Check|Validate)',
        '(file|text|number|list|data|value|string|path|url|pattern)',
        '^(Compare|Match|Replace|Filter|Sort|Group|Sum|Average)',
        'from .* to .*',
        'between .* and .*'
    )
    
    foreach ($pattern in $atomicPatterns) {
        if ($Task -match $pattern) {
            return $true
        }
    }
    
    # Length heuristic - very short tasks are likely atomic
    if ($Task.Length -lt 50 -and ($Task -split ' ').Count -lt 10) {
        return $true
    }
    
    return $false
}

# Queue an atomic task
function Queue-AtomicTask {
    param(
        [string]$Task,
        [string]$Id,
        [string]$ParentId
    )
    
    $atomicTask = [PSCustomObject]@{
        Id = $Id
        ParentId = $ParentId
        Description = $Task
        AssignedModel = $null
        Status = "Queued"
        Result = $null
        Timestamp = Get-Date
    }
    
    $script:TaskQueue.Enqueue($atomicTask)
}

# Determine simplest capable model/method
function Get-OptimalSolver {
    param([string]$Task)
    
    # Pattern-based routing
    $routingRules = @(
        @{ Pattern = 'count.*files|list.*directory|get.*size'; Solver = "SCRIPT" },
        @{ Pattern = 'extract.*from|match.*pattern|find.*text'; Solver = "REGEX" },
        @{ Pattern = 'summarize.*briefly|classify.*simple'; Solver = "gemma-3-1b-it-qat" },
        @{ Pattern = 'analyze|review|explain|describe'; Solver = "gemma-3-4b-it-qat" },
        @{ Pattern = 'design|create.*complex|plan|strategize'; Solver = "gemma-3-12b-it-qat" }
    )
    
    foreach ($rule in $routingRules) {
        if ($Task -match $rule.Pattern) {
            return $rule.Solver
        }
    }
    
    # Default based on complexity
    $wordCount = ($Task -split ' ').Count
    if ($wordCount -lt 10) { return "gemma-3-1b-it-qat" }
    elseif ($wordCount -lt 25) { return "gemma-3-4b-it-qat" }
    else { return "gemma-3-12b-it-qat" }
}

# Execute atomic task with assigned solver
function Execute-AtomicTask {
    param([PSCustomObject]$Task)
    
    $solver = Get-OptimalSolver -Task $Task.Description
    $Task.AssignedModel = $solver
    
    Write-Host "Executing with $solver`: $($Task.Description.Substring(0, [Math]::Min(50, $Task.Description.Length)))..." -ForegroundColor Gray
    
    try {
        switch ($solver) {
            "REGEX" {
                # Handle with regex
                $Task.Result = Invoke-RegexSolver -Task $Task.Description
            }
            "SCRIPT" {
                # Handle with PowerShell
                $Task.Result = Invoke-ScriptSolver -Task $Task.Description
            }
            default {
                # Handle with AI model
                $Task.Result = Invoke-LMStudioAPI -Model $solver -Prompt $Task.Description -MaxTokens 500
            }
        }
        
        $Task.Status = if ($Task.Result -like "ERROR:*") { "Failed" } else { "Completed" }
        
    } catch {
        $Task.Status = "Failed"
        $Task.Result = "ERROR: $($_.Exception.Message)"
    }
    
    return $Task
}

# Simple regex solver for pattern tasks
function Invoke-RegexSolver {
    param([string]$Task)
    
    # Very basic implementation - would expand with actual patterns
    if ($Task -match 'extract.*email') {
        return "Regex pattern: \b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b"
    }
    elseif ($Task -match 'extract.*url') {
        return "Regex pattern: https?://[^\s]+"
    }
    else {
        return "ERROR: No regex pattern available for this task"
    }
}

# Simple script solver for file/system tasks
function Invoke-ScriptSolver {
    param([string]$Task)
    
    # Very basic implementation
    if ($Task -match 'count.*files.*in\s+(.+)') {
        $path = $matches[1].Trim('"', "'")
        if (Test-Path $path) {
            $count = (Get-ChildItem -Path $path -File).Count
            return "Found $count files in $path"
        }
    }
    elseif ($Task -match 'get.*size.*of\s+(.+)') {
        $path = $matches[1].Trim('"', "'")
        if (Test-Path $path) {
            $size = Get-Item $path | Select-Object -ExpandProperty Length
            return "Size: $([math]::Round($size / 1MB, 2)) MB"
        }
    }
    
    return "ERROR: Cannot parse script task"
}

# Process the queue
function Process-TaskQueue {
    Write-Host "`nProcessing task queue ($($script:TaskQueue.Count) tasks)..." -ForegroundColor Green
    
    while ($script:TaskQueue.Count -gt 0) {
        $task = $script:TaskQueue.Dequeue()
        $completed = Execute-AtomicTask -Task $task
        $script:CompletedTasks += $completed
        
        # Brief pause between tasks
        Start-Sleep -Milliseconds 500
    }
}

# Generate execution report
function Get-ExecutionReport {
    $report = @"
TASK DECOMPOSITION REPORT
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

INITIAL PROMPT:
$InitialPrompt

DECOMPOSITION TREE:
$(Get-TaskTreeVisualization -NodeId "root" -Indent 0)

EXECUTION SUMMARY:
Total Tasks: $($script:CompletedTasks.Count)
Completed: $(($script:CompletedTasks | Where-Object { $_.Status -eq "Completed" }).Count)
Failed: $(($script:CompletedTasks | Where-Object { $_.Status -eq "Failed" }).Count)

MODEL DISTRIBUTION:
$(($script:CompletedTasks | Group-Object AssignedModel | ForEach-Object {
    "- $($_.Name): $($_.Count) tasks"
}) -join "`n")

DETAILED RESULTS:
$(foreach ($task in $script:CompletedTasks) {
"
Task: $($task.Description)
Model: $($task.AssignedModel)
Status: $($task.Status)
Result: $($task.Result)
"
})
"@
    
    return $report
}

# Visualize task tree
function Get-TaskTreeVisualization {
    param(
        [string]$NodeId,
        [int]$Indent
    )
    
    $node = $script:TaskTree[$NodeId]
    if (!$node) { return "" }
    
    $visualization = " " * $Indent + "├─ $($node.Description)`n"
    
    foreach ($subtaskId in $node.Subtasks) {
        $visualization += Get-TaskTreeVisualization -NodeId $subtaskId -Indent ($Indent + 2)
    }
    
    return $visualization
}

# Main execution
Write-Host "Task Decomposition Engine Starting..." -ForegroundColor Green
Write-Host "Initial prompt: $InitialPrompt" -ForegroundColor Cyan

# Ensure output directory
if (!(Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

# Start decomposition
$rootTaskId = Decompose-Task -TaskDescription $InitialPrompt -CurrentDepth 0

# Process all queued tasks
Process-TaskQueue

# Generate and save report
$report = Get-ExecutionReport
$reportPath = Join-Path $OutputPath "decomposition_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$report | Out-File -FilePath $reportPath -Encoding UTF8

Write-Host "`nExecution complete!" -ForegroundColor Green
Write-Host "Report saved to: $reportPath" -ForegroundColor Cyan

# Display summary
Write-Host "`nSUMMARY:" -ForegroundColor Yellow
Write-Host "- Tasks decomposed: $($script:TaskTree.Count)"
Write-Host "- Atomic tasks executed: $($script:CompletedTasks.Count)"
Write-Host "- Success rate: $(([math]::Round((($script:CompletedTasks | Where-Object { $_.Status -eq "Completed" }).Count / $script:CompletedTasks.Count) * 100, 1)))%"

# Copy summary to clipboard
$summary = "Decomposed '$InitialPrompt' into $($script:CompletedTasks.Count) atomic tasks. Success rate: $(([math]::Round((($script:CompletedTasks | Where-Object { $_.Status -eq "Completed" }).Count / $script:CompletedTasks.Count) * 100, 1)))%"
$summary | Set-Clipboard