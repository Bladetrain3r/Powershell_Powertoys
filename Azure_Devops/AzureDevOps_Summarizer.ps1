# Azure DevOps Status Summarizer - AI-powered project insights
param(
    [Parameter(Mandatory)]
    [string]$Organization,
    
    [Parameter(Mandatory)]
    [string]$Project,
    
    [string]$PAT = $env:AZDO_PAT,
    [int]$RecentBuilds = 10,
    [int]$RecentCommits = 20,
    [int]$DaysBack = 7,
    
    # Output options
    [string]$OutputPath = ".\DevOpsStatus",
    [switch]$GenerateReport,
    [switch]$TeamsSummary,
    
    # AI options
    [string]$LMStudioEndpoint = "http://localhost:1234",
    [string]$Model = "gemma-3-4b-it-qat",
    [switch]$SkipAI
)

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# Ensure output directory exists
if (!(Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

Write-Host "Azure DevOps Status Summarizer" -ForegroundColor Cyan
Write-Host "Organization: $Organization | Project: $Project" -ForegroundColor Gray
Write-Host "Analyzing last $DaysBack days..." -ForegroundColor Gray
Write-Host ""

# Setup auth header
$base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PAT"))
$headers = @{
    Authorization = "Basic $base64Auth"
    'Content-Type' = 'application/json'
}

# API base URL
$baseUrl = "https://dev.azure.com/$Organization/$Project"

# Helper function for API calls
function Invoke-AzDoAPI {
    param(
        [string]$Endpoint,
        [string]$Method = "GET",
        [object]$Body = $null
    )
    
    try {
        $uri = "$baseUrl/_apis/$Endpoint"
        $params = @{
            Uri = $uri
            Method = $Method
            Headers = $headers
        }
        
        if ($Body) {
            $params.Body = ($Body | ConvertTo-Json -Depth 10)
        }
        
        $response = Invoke-RestMethod @params
        return $response
    } catch {
        Write-Warning "API call failed: $Endpoint"
        Write-Warning $_.Exception.Message
        return $null
    }
}

# Get recent builds
Write-Host "Fetching recent builds..." -ForegroundColor Yellow
$sinceDate = (Get-Date).AddDays(-$DaysBack).ToString("yyyy-MM-dd")
$buildsResponse = Invoke-AzDoAPI -Endpoint "build/builds?api-version=7.0&`$top=$RecentBuilds&minTime=$sinceDate"

$builds = @()
if ($buildsResponse -and $buildsResponse.value) {
    $builds = $buildsResponse.value | ForEach-Object {
        [PSCustomObject]@{
            Id = $_.id
            BuildNumber = $_.buildNumber
            Status = $_.status
            Result = $_.result
            SourceBranch = $_.sourceBranch -replace 'refs/heads/', ''
            QueueTime = [DateTime]$_.queueTime
            StartTime = if($_.startTime) { [DateTime]$_.startTime } else { $null }
            FinishTime = if($_.finishTime) { [DateTime]$_.finishTime } else { $null }
            Duration = if($_.startTime -and $_.finishTime) { 
                [math]::Round(([DateTime]$_.finishTime - [DateTime]$_.startTime).TotalMinutes, 1)
            } else { 0 }
            RequestedBy = $_.requestedBy.displayName
            Reason = $_.reason
        }
    }
    Write-Host "Found $($builds.Count) builds" -ForegroundColor Green
} else {
    Write-Host "No builds found" -ForegroundColor Red
}

# Get repositories
Write-Host "Fetching repositories..." -ForegroundColor Yellow
$reposResponse = Invoke-AzDoAPI -Endpoint "git/repositories?api-version=7.0"
$repos = @()
if ($reposResponse -and $reposResponse.value) {
    $repos = $reposResponse.value
    Write-Host "Found $($repos.Count) repositories" -ForegroundColor Green
}

# Get recent commits from ALL repos
$commits = @()
$allCommitsFound = 0
if ($repos.Count -gt 0) {
    Write-Host "Fetching recent commits from all repositories..." -ForegroundColor Yellow
    
    foreach ($repo in $repos) {
        Write-Host "  Checking $($repo.name)..." -ForegroundColor Gray
        
        # Try with date filter first
        $commitsResponse = Invoke-AzDoAPI -Endpoint "git/repositories/$($repo.id)/commits?api-version=7.0&`$top=$RecentCommits&searchCriteria.fromDate=$sinceDate"
        
        # If no results with date filter, try without
        if (!$commitsResponse -or !$commitsResponse.value -or $commitsResponse.value.Count -eq 0) {
            $commitsResponse = Invoke-AzDoAPI -Endpoint "git/repositories/$($repo.id)/commits?api-version=7.0&`$top=$RecentCommits"
        }
        
        if ($commitsResponse -and $commitsResponse.value) {
            # Only include commits from the specified date range
            $repoCommits = $commitsResponse.value | Where-Object {
                [DateTime]$_.author.date -ge (Get-Date).AddDays(-$DaysBack)
            } | ForEach-Object {
                [PSCustomObject]@{
                    CommitId = $_.commitId.Substring(0, 8)
                    Author = $_.author.name
                    Date = [DateTime]$_.author.date
                    Comment = $_.comment -split "`n" | Select-Object -First 1  # First line only
                    FullComment = $_.comment
                    Repository = $repo.name
                }
            }
            
            if ($repoCommits) {
                $commits += $repoCommits
                $allCommitsFound += $repoCommits.Count
                Write-Host "    Found $($repoCommits.Count) commits" -ForegroundColor Green
            }
        }
    }
    
    # Sort all commits by date
    $commits = $commits | Sort-Object Date -Descending | Select-Object -First $RecentCommits
    Write-Host "Total commits found: $allCommitsFound (showing top $($commits.Count))" -ForegroundColor Green
}

# Get active pull requests with contributor info
Write-Host "Fetching active pull requests..." -ForegroundColor Yellow
$prsResponse = Invoke-AzDoAPI -Endpoint "git/pullrequests?api-version=7.0&status=active"
$activePRs = @()
$prContributors = @{}

if ($prsResponse -and $prsResponse.value) {
    $activePRs = $prsResponse.value | ForEach-Object {
        # Track PR creator
        $prContributors[$_.createdBy.displayName] = $true
        
        # Try to get commits for this PR to find more contributors
        $prCommitsResponse = Invoke-AzDoAPI -Endpoint "git/repositories/$($_.repository.id)/pullRequests/$($_.pullRequestId)/commits?api-version=7.0"
        if ($prCommitsResponse -and $prCommitsResponse.value) {
            foreach ($commit in $prCommitsResponse.value) {
                if ($commit.author.name) {
                    $prContributors[$commit.author.name] = $true
                }
            }
        }
        
        [PSCustomObject]@{
            Id = $_.pullRequestId
            Title = $_.title
            SourceBranch = $_.sourceRefName -replace 'refs/heads/', ''
            TargetBranch = $_.targetRefName -replace 'refs/heads/', ''
            CreatedBy = $_.createdBy.displayName
            CreationDate = [DateTime]$_.creationDate
            Status = $_.status
        }
    }
    Write-Host "Found $($activePRs.Count) active PRs with $($prContributors.Count) contributors" -ForegroundColor Green
}

# Analyze build health
$buildStats = @{
    Total = $builds.Count
    Succeeded = ($builds | Where-Object { $_.Result -eq 'succeeded' }).Count
    Failed = ($builds | Where-Object { $_.Result -eq 'failed' }).Count
    InProgress = ($builds | Where-Object { $_.Status -eq 'inProgress' }).Count
    SuccessRate = if ($builds.Count -gt 0) { 
        [math]::Round((($builds | Where-Object { $_.Result -eq 'succeeded' }).Count / $builds.Count) * 100, 1)
    } else { 0 }
    AverageDuration = if (($builds | Where-Object { $_.Duration -gt 0 }).Count -gt 0) {
        [math]::Round((($builds | Where-Object { $_.Duration -gt 0 }).Duration | Measure-Object -Average).Average, 1)
    } else { 0 }
}

# Extract JIRA tickets from commits and branches
$jiraPattern = '([A-Z]{2,10}-\d{1,6})'
$jiraTickets = @()

# From commit messages
$commits | ForEach-Object {
    if ($_.FullComment -match $jiraPattern) {
        $jiraTickets += $matches[0]
    }
}

# From branch names
$builds | ForEach-Object {
    if ($_.SourceBranch -match $jiraPattern) {
        $jiraTickets += $matches[0]
    }
}

$activePRs | ForEach-Object {
    if ($_.SourceBranch -match $jiraPattern) {
        $jiraTickets += $matches[0]
    }
}

$jiraTickets = $jiraTickets | Select-Object -Unique | Sort-Object

# Create status summary
$statusSummary = @"
AZURE DEVOPS STATUS SUMMARY
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Organization: $Organization
Project: $Project
Period: Last $DaysBack days

BUILD HEALTH:
- Total Builds: $($buildStats.Total)
- Success Rate: $($buildStats.SuccessRate)%
- Failed: $($buildStats.Failed)
- In Progress: $($buildStats.InProgress)
- Average Duration: $($buildStats.AverageDuration) minutes

RECENT ACTIVITY:
- Commits: $($commits.Count)
- Active PRs: $($activePRs.Count)
- Unique Contributors (commits): $(($commits.Author | Select-Object -Unique).Count)
- Unique Contributors (PRs): $($prContributors.Count)
- JIRA Tickets Referenced: $($jiraTickets.Count)

TOP CONTRIBUTORS (from commits):
$(($commits | Group-Object Author | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object {
"- $($_.Name): $($_.Count) commits"
}) -join "`n")

CONTRIBUTORS FROM PULL REQUESTS:
$(($prContributors.Keys | Sort-Object | ForEach-Object { "- $_" }) -join "`n")

RECENT BUILD FAILURES:
$(($builds | Where-Object { $_.Result -eq 'failed' } | Select-Object -First 5 | ForEach-Object {
"- Build $($_.BuildNumber) on $($_.SourceBranch) by $($_.RequestedBy)"
}) -join "`n")

ACTIVE PULL REQUESTS:
$(($activePRs | Select-Object -First 5 | ForEach-Object {
"- PR #$($_.Id): $($_.Title) ($($_.SourceBranch) -> $($_.TargetBranch))"
}) -join "`n")

JIRA TICKETS IN PROGRESS:
$(if ($jiraTickets.Count -gt 0) {
($jiraTickets | ForEach-Object { "- $_" }) -join "`n"
} else {
"- No JIRA tickets found in recent activity"
})

REPOSITORY ACTIVITY:
$(($commits | Group-Object Repository | Sort-Object Count -Descending | ForEach-Object {
"- $($_.Name): $($_.Count) commits"
}) -join "`n")
"@

# Save raw summary
$summaryPath = Join-Path $OutputPath "status_summary_$timestamp.txt"
$statusSummary | Out-File -FilePath $summaryPath -Encoding UTF8
Write-Host "`nStatus summary saved to: $summaryPath" -ForegroundColor Green

# Generate AI insights
if (!$SkipAI) {
    Write-Host "`nGenerating AI insights..." -ForegroundColor Yellow
    
    try {
        $aiPrompt = @"
Analyze this Azure DevOps project status and provide insights:

$statusSummary

Please provide:
1. HEALTH ASSESSMENT - Overall project health (Excellent/Good/Fair/Poor)
2. KEY CONCERNS - What needs immediate attention?
3. POSITIVE TRENDS - What's working well?
4. BOTTLENECKS - Where are the slowdowns?
5. RECOMMENDATIONS - 3-5 specific actions to improve

Focus on actionable insights that a development team can use immediately.
"@

        $body = @{
            model = $Model
            messages = @(
                @{
                    role = "user"
                    content = $aiPrompt
                }
            )
            max_tokens = 1500
            temperature = 0.3
        } | ConvertTo-Json -Depth 5

        $aiResponse = Invoke-WebRequest -Uri "$LMStudioEndpoint/v1/chat/completions" `
            -Method POST `
            -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
            -Headers @{ 'Content-Type' = 'application/json' }
            
        $aiInsights = ($aiResponse.Content | ConvertFrom-Json).choices[0].message.content
        
        # Save AI insights
        $aiPath = Join-Path $OutputPath "ai_insights_$timestamp.txt"
        $aiInsights | Out-File -FilePath $aiPath -Encoding UTF8
        
        Write-Host "AI insights generated!" -ForegroundColor Green
        Write-Host "`n$aiInsights" -ForegroundColor Cyan
        
    } catch {
        Write-Warning "AI analysis failed: $($_.Exception.Message)"
        $aiInsights = "AI analysis unavailable"
    }
}

# Generate full report if requested
if ($GenerateReport) {
    Write-Host "`nGenerating detailed report..." -ForegroundColor Yellow
    
    $reportPath = Join-Path $OutputPath "detailed_report_$timestamp.html"
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Azure DevOps Status Report - $Project</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #0078d4; }
        h2 { color: #323130; margin-top: 30px; }
        .metric { display: inline-block; margin: 10px 20px 10px 0; }
        .metric-value { font-size: 24px; font-weight: bold; color: #0078d4; }
        .metric-label { font-size: 14px; color: #605e5c; }
        .success { color: #107c10; }
        .failure { color: #d13438; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        th, td { padding: 8px; text-align: left; border-bottom: 1px solid #edebe9; }
        th { background: #f3f2f1; }
        .ai-insights { background: #e1dfdd; padding: 15px; border-radius: 4px; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Azure DevOps Status Report</h1>
        <p><strong>Project:</strong> $Organization/$Project | <strong>Generated:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
        
        <h2>Build Metrics</h2>
        <div class="metrics">
            <div class="metric">
                <div class="metric-value">$($buildStats.Total)</div>
                <div class="metric-label">Total Builds</div>
            </div>
            <div class="metric">
                <div class="metric-value $( if ($buildStats.SuccessRate -ge 80) { "success" } else { "failure" } )">$($buildStats.SuccessRate)%</div>
                <div class="metric-label">Success Rate</div>
            </div>
            <div class="metric">
                <div class="metric-value">$($buildStats.AverageDuration) min</div>
                <div class="metric-label">Avg Duration</div>
            </div>
        </div>
        
        <h2>Recent Builds</h2>
        <table>
            <tr>
                <th>Build</th>
                <th>Branch</th>
                <th>Status</th>
                <th>Duration</th>
                <th>Requested By</th>
                <th>Time</th>
            </tr>
            $(($builds | Select-Object -First 10 | ForEach-Object {
                "<tr>
                    <td>$($_.BuildNumber)</td>
                    <td>$($_.SourceBranch)</td>
                    <td class='$(if ($_.Result -eq "succeeded") { "success" } else { "failure" })'>$($_.Result)</td>
                    <td>$($_.Duration) min</td>
                    <td>$($_.RequestedBy)</td>
                    <td>$($_.QueueTime.ToString("MM/dd HH:mm"))</td>
                </tr>"
            }) -join "`n")
        </table>
        
        <h2>Active Pull Requests</h2>
        $(if ($activePRs.Count -gt 0) {
            "<table>
                <tr>
                    <th>PR</th>
                    <th>Title</th>
                    <th>Source → Target</th>
                    <th>Author</th>
                    <th>Created</th>
                </tr>
                $(($activePRs | ForEach-Object {
                    "<tr>
                        <td>#$($_.Id)</td>
                        <td>$($_.Title)</td>
                        <td>$($_.SourceBranch) → $($_.TargetBranch)</td>
                        <td>$($_.CreatedBy)</td>
                        <td>$($_.CreationDate.ToString("MM/dd"))</td>
                    </tr>"
                }) -join "`n")
            </table>"
        } else {
            "<p>No active pull requests</p>"
        })
        
        $(if (!$SkipAI -and $aiInsights -ne "AI analysis unavailable") {
            "<h2>AI Insights</h2>
            <div class='ai-insights'>
                <pre>$aiInsights</pre>
            </div>"
        })
    </div>
</body>
</html>
"@
    
    $html | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Host "Detailed report saved to: $reportPath" -ForegroundColor Green
    
    # Open in browser
    Start-Process $reportPath
}

# Output summary to console
Write-Host "`n$statusSummary" -ForegroundColor White

# Copy key insights to clipboard
$clipboardSummary = @"
DevOps Status ($Project): $($buildStats.Total) builds, $($buildStats.SuccessRate)% success rate, $($commits.Count) commits, $($activePRs.Count) active PRs
$(if (!$SkipAI -and $aiInsights -ne "AI analysis unavailable") { "`nKey Insight: " + ($aiInsights -split "`n" | Select-Object -First 3 | Where-Object { $_ -match '\S' } | Select-Object -First 1) })
"@
$clipboardSummary | Set-Clipboard

Write-Host "`nSummary copied to clipboard!" -ForegroundColor Green