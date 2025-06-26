# Azure DevOps Discovery Tool - Comprehensive project analysis and setup discovery
param(
    [Parameter(Mandatory)]
    [string]$Organization,
    
    [Parameter(Mandatory)]
    [string]$Project,
    
    [string]$PAT = $env:AZDO_PAT,
    [int]$DaysBack = 30,
    [switch]$ExportReport,
    [string]$OutputPath = ".\AzureDevOpsDiscovery"
)

$ErrorActionPreference = "Continue"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# Ensure output directory exists
if ($ExportReport -and !(Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "           Azure DevOps Discovery Tool v1.0                     " -ForegroundColor Cyan
Write-Host "                                                                " -ForegroundColor Cyan
Write-Host "  Discover repositories, pipelines, contributors, and more!     " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Organization: $Organization" -ForegroundColor White
Write-Host "Project: $Project" -ForegroundColor White
Write-Host "Analysis Period: Last $DaysBack days" -ForegroundColor White
Write-Host ""

# Setup auth
$base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PAT"))
$headers = @{
    Authorization = "Basic $base64Auth"
    'Content-Type' = 'application/json'
}

$baseUrl = "https://dev.azure.com/$Organization/$Project"
$discoveries = @{}

# Helper function for safe API calls
function Invoke-SafeAPI {
    param([string]$Uri, [string]$Description = "API call")
    
    try {
        $response = Invoke-RestMethod -Uri $Uri -Headers $headers -ErrorAction Stop
        return $response
    } catch {
        Write-Host "  X Failed: $Description" -ForegroundColor Red
        Write-Host "    $($_.Exception.Message)" -ForegroundColor DarkRed
        return $null
    }
}

# 1. PROJECT OVERVIEW
Write-Host "=== PROJECT OVERVIEW ===" -ForegroundColor Yellow
$projectUri = "https://dev.azure.com/$Organization/_apis/projects/$Project`?api-version=7.0"
$projectInfo = Invoke-SafeAPI -Uri $projectUri -Description "Project details"

if ($projectInfo) {
    Write-Host "[OK] Project Name: $($projectInfo.name)" -ForegroundColor Green
    Write-Host "  Description: $($projectInfo.description)" -ForegroundColor Gray
    Write-Host "  Created: $($projectInfo.createdDate)" -ForegroundColor Gray
    Write-Host "  Process Template: $($projectInfo.capabilities.processTemplate.templateName)" -ForegroundColor Gray
    Write-Host "  Version Control: $($projectInfo.capabilities.versioncontrol.sourceControlType)" -ForegroundColor Gray
    
    $discoveries.ProjectInfo = $projectInfo
}

Write-Host ""

# 2. REPOSITORY DISCOVERY
Write-Host "=== REPOSITORY DISCOVERY ===" -ForegroundColor Yellow
$reposUri = "$baseUrl/_apis/git/repositories?api-version=7.0"
$reposResponse = Invoke-SafeAPI -Uri $reposUri -Description "Repositories"

$repoAnalysis = @()
if ($reposResponse -and $reposResponse.value) {
    Write-Host "[OK] Found $($reposResponse.value.Count) repositories" -ForegroundColor Green
    
    foreach ($repo in $reposResponse.value) {
        Write-Host "`n  Repository: '$($repo.name)'" -ForegroundColor Cyan
        Write-Host "  |-- ID: $($repo.id)" -ForegroundColor Gray
        Write-Host "  |-- Size: $([math]::Round($repo.size / 1MB, 2)) MB" -ForegroundColor Gray
        Write-Host "  |-- Default Branch: $($repo.defaultBranch)" -ForegroundColor Gray
        Write-Host "  |-- Web URL: $($repo.webUrl)" -ForegroundColor Gray
        
        # Check for recent activity - build URI with string concatenation to avoid issues
        $commitsUri = $baseUrl + "/_apis/git/repositories/" + $repo.id + "/commits?api-version=7.0" + "&" + "`$top=1"
        $latestCommit = Invoke-SafeAPI -Uri $commitsUri -Description "Latest commit"
        
        $daysSinceCommit = 999
        if ($latestCommit -and $latestCommit.value -and $latestCommit.value.Count -gt 0) {
            $lastCommitDate = [DateTime]$latestCommit.value[0].author.date
            $daysSinceCommit = ((Get-Date) - $lastCommitDate).Days
            Write-Host "     Last Commit: $daysSinceCommit days ago" -ForegroundColor $(if($daysSinceCommit -lt 7){"Green"}elseif($daysSinceCommit -lt 30){"Yellow"}else{"Red"})
        }
        
        # Count branches
        $branchesUri = $baseUrl + "/_apis/git/repositories/" + $repo.id + "/refs?filter=heads" + "&" + "api-version=7.0"
        $branches = Invoke-SafeAPI -Uri $branchesUri -Description "Branches"
        $branchCount = if ($branches -and $branches.value) { $branches.value.Count } else { 0 }
        Write-Host "     Branches: $branchCount" -ForegroundColor Gray
        
        $repoAnalysis += [PSCustomObject]@{
            Name = $repo.name
            Id = $repo.id
            SizeMB = [math]::Round($repo.size / 1MB, 2)
            DefaultBranch = $repo.defaultBranch
            BranchCount = $branchCount
            DaysSinceLastCommit = $daysSinceCommit
            IsActive = $daysSinceCommit -lt 30
        }
    }
    
    $discoveries.Repositories = $repoAnalysis
}

Write-Host ""

# 3. BUILD PIPELINE DISCOVERY
Write-Host "=== BUILD PIPELINE DISCOVERY ===" -ForegroundColor Yellow
$pipelinesUri = "$baseUrl/_apis/build/definitions?api-version=7.0"
$pipelines = Invoke-SafeAPI -Uri $pipelinesUri -Description "Build pipelines"

$pipelineAnalysis = @()
if ($pipelines -and $pipelines.value) {
    Write-Host "[OK] Found $($pipelines.value.Count) build pipelines" -ForegroundColor Green
    
    foreach ($pipeline in $pipelines.value | Sort-Object name) {
        Write-Host "`n  Pipeline: '$($pipeline.name)'" -ForegroundColor Cyan
        Write-Host "  |-- Type: $($pipeline.type)" -ForegroundColor Gray
        Write-Host "  |-- Created: $($pipeline.createdDate)" -ForegroundColor Gray
        
        # Get recent runs
        $runsUri = $baseUrl + "/_apis/build/builds?definitions=" + $pipeline.id + "&" + "`$top=5" + "&" + "api-version=7.0"
        $runs = Invoke-SafeAPI -Uri $runsUri -Description "Recent runs"
        
        $successRate = 0
        if ($runs -and $runs.value -and $runs.value.Count -gt 0) {
            $successCount = ($runs.value | Where-Object { $_.result -eq 'succeeded' }).Count
            $successRate = [math]::Round(($successCount / $runs.value.Count) * 100, 1)
            
            Write-Host "  |-- Recent Runs: $($runs.value.Count)" -ForegroundColor Gray
            Write-Host "  |-- Success Rate: $successRate%" -ForegroundColor $(if($successRate -ge 80){"Green"}elseif($successRate -ge 50){"Yellow"}else{"Red"})
            Write-Host "  |-- Last Run: $(([DateTime]$runs.value[0].queueTime).ToString('yyyy-MM-dd HH:mm'))" -ForegroundColor Gray
        } else {
            Write-Host "  |-- No recent runs" -ForegroundColor DarkGray
        }
        
        $pipelineAnalysis += [PSCustomObject]@{
            Name = $pipeline.name
            Id = $pipeline.id
            Type = $pipeline.type
            RecentRuns = if($runs -and $runs.value) { $runs.value.Count } else { 0 }
            SuccessRate = $successRate
            LastRun = if($runs -and $runs.value -and $runs.value.Count -gt 0) { [DateTime]$runs.value[0].queueTime } else { $null }
        }
    }
    
    $discoveries.Pipelines = $pipelineAnalysis
}

Write-Host ""

# 4. CONTRIBUTOR DISCOVERY
Write-Host "=== CONTRIBUTOR DISCOVERY ===" -ForegroundColor Yellow
$contributors = @{}
$sinceDate = (Get-Date).AddDays(-$DaysBack).ToString("yyyy-MM-dd")

# Get contributors from recent commits across all repos
if ($reposResponse -and $reposResponse.value) {
    foreach ($repo in $reposResponse.value) {
        $commitsUri = $baseUrl + "/_apis/git/repositories/" + $repo.id + "/commits?api-version=7.0" + "&" + "`$top=100" + "&" + "searchCriteria.fromDate=" + $sinceDate
        $commits = Invoke-SafeAPI -Uri $commitsUri -Description "Commits from $($repo.name)"
        
        if ($commits -and $commits.value) {
            foreach ($commit in $commits.value) {
                $authorName = $commit.author.name
                if (!$contributors.ContainsKey($authorName)) {
                    $contributors[$authorName] = @{
                        CommitCount = 0
                        Repos = @{}
                        LastCommit = $commit.author.date
                    }
                }
                $contributors[$authorName].CommitCount++
                $contributors[$authorName].Repos[$repo.name] = $true
                
                # Update last commit if more recent
                if ([DateTime]$commit.author.date -gt [DateTime]$contributors[$authorName].LastCommit) {
                    $contributors[$authorName].LastCommit = $commit.author.date
                }
            }
        }
    }
}

# Get contributors from PRs
$prsUri = $baseUrl + "/_apis/git/pullrequests?api-version=7.0" + "&" + "status=all" + "&" + "`$top=100"
$allPRs = Invoke-SafeAPI -Uri $prsUri -Description "Pull requests"

if ($allPRs -and $allPRs.value) {
    foreach ($pr in $allPRs.value | Where-Object { [DateTime]$_.creationDate -ge (Get-Date).AddDays(-$DaysBack) }) {
        $creatorName = $pr.createdBy.displayName
        if (!$contributors.ContainsKey($creatorName)) {
            $contributors[$creatorName] = @{
                CommitCount = 0
                Repos = @{}
                LastCommit = $pr.creationDate
                PRCount = 0
            }
        }
        if (!$contributors[$creatorName].PRCount) {
            $contributors[$creatorName].PRCount = 0
        }
        $contributors[$creatorName].PRCount++
    }
}

Write-Host "[OK] Found $($contributors.Count) active contributors" -ForegroundColor Green
Write-Host "`nTop Contributors (by commits):" -ForegroundColor White

$topContributors = $contributors.GetEnumerator() | 
    Sort-Object { $_.Value.CommitCount } -Descending | 
    Select-Object -First 10

foreach ($contributor in $topContributors) {
    $lastActive = ((Get-Date) - [DateTime]$contributor.Value.LastCommit).Days
    Write-Host "  * $($contributor.Key)" -ForegroundColor Cyan
    Write-Host "    |-- Commits: $($contributor.Value.CommitCount)" -ForegroundColor Gray
    Write-Host "    |-- PRs: $(if($contributor.Value.PRCount){$contributor.Value.PRCount}else{0})" -ForegroundColor Gray
    Write-Host "    |-- Repos: $($contributor.Value.Repos.Keys -join ', ')" -ForegroundColor Gray
    Write-Host "    |-- Last Active: $lastActive days ago" -ForegroundColor $(if($lastActive -lt 7){"Green"}elseif($lastActive -lt 30){"Yellow"}else{"Red"})
}

$discoveries.Contributors = $contributors

Write-Host ""

# 5. WORK ITEM DISCOVERY (if available)
Write-Host "=== WORK ITEM DISCOVERY ===" -ForegroundColor Yellow
$workItemsUri = "$baseUrl/_apis/wit/wiql?api-version=7.0"
$wiql = @{
    query = "SELECT [System.Id], [System.Title], [System.State], [System.AssignedTo], [System.WorkItemType] FROM workitems WHERE [System.TeamProject] = '$Project' AND [System.ChangedDate] >= @today - $DaysBack ORDER BY [System.ChangedDate] DESC"
} | ConvertTo-Json

try {
    $workItemsResponse = Invoke-WebRequest -Uri $workItemsUri -Method POST -Body $wiql -Headers $headers -ContentType 'application/json'
    $workItems = $workItemsResponse.Content | ConvertFrom-Json
    
    if ($workItems.workItems) {
        Write-Host "[OK] Found $($workItems.workItems.Count) work items changed in last $DaysBack days" -ForegroundColor Green
        
        # Get work item details (in batches)
        $workItemIds = $workItems.workItems | Select-Object -First 200 | ForEach-Object { $_.id }
        if ($workItemIds.Count -gt 0) {
            $idsString = $workItemIds -join ','
            $detailsUri = "https://dev.azure.com/$Organization/_apis/wit/workitems?ids=" + $idsString + "&" + "api-version=7.0"
            $details = Invoke-SafeAPI -Uri $detailsUri -Description "Work item details"
            
            if ($details -and $details.value) {
                $workItemTypes = $details.value | Group-Object { $_.fields.'System.WorkItemType' }
                Write-Host "`nWork Item Types:" -ForegroundColor White
                foreach ($type in $workItemTypes | Sort-Object Count -Descending) {
                    Write-Host "  * $($type.Name): $($type.Count)" -ForegroundColor Gray
                }
                
                $states = $details.value | Group-Object { $_.fields.'System.State' }
                Write-Host "`nWork Item States:" -ForegroundColor White
                foreach ($state in $states | Sort-Object Count -Descending) {
                    Write-Host "  * $($state.Name): $($state.Count)" -ForegroundColor Gray
                }
            }
        }
    } else {
        Write-Host "X No work items found or work item tracking not enabled" -ForegroundColor Yellow
    }
} catch {
    Write-Host "X Could not access work items - may require additional permissions" -ForegroundColor Yellow
}

Write-Host ""

# 6. SECURITY AND PERMISSIONS CHECK
Write-Host "=== SECURITY AND PERMISSIONS CHECK ===" -ForegroundColor Yellow
Write-Host "Testing API access levels..." -ForegroundColor White
Write-Host "(Note: Some APIs may show as 'Not configured' if the feature isn't used in your project)" -ForegroundColor Gray
Write-Host ""

$permissionTests = @(
    @{ Name = "Read Builds"; Uri = $baseUrl + "/_apis/build/builds?`$top=1" + "&" + "api-version=7.0" },
    @{ Name = "Read Code"; Uri = $baseUrl + "/_apis/git/repositories?api-version=7.0" },
    @{ Name = "Read Work Items"; Uri = $baseUrl + "/_apis/wit/workitems?ids=1" + "&" + "api-version=7.0" },
    @{ Name = "Read Test Plans"; Uri = $baseUrl + "/_apis/test/plans?api-version=7.0" },
    @{ Name = "Read Releases"; Uri = $baseUrl + "/_apis/release/releases?api-version=7.0-preview.8" }
)

foreach ($test in $permissionTests) {
    try {
        $response = Invoke-RestMethod -Uri $test.Uri -Headers $headers -ErrorAction Stop
        Write-Host "  [OK] $($test.Name)" -ForegroundColor Green
    } catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        
        if ($statusCode -eq 404 -or $_.Exception.Message -like "*404*") {
            Write-Host "  [-] $($test.Name) - Not configured in project" -ForegroundColor Yellow
        } elseif ($statusCode -eq 403) {
            Write-Host "  [X] $($test.Name) - Access denied" -ForegroundColor Red
        } else {
            Write-Host "  [?] $($test.Name) - Error: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }
}

Write-Host ""

# 7. RECOMMENDATIONS
Write-Host "=== RECOMMENDATIONS ===" -ForegroundColor Yellow

$recommendations = @()

# Check for inactive repos
$inactiveRepos = $repoAnalysis | Where-Object { $_.DaysSinceLastCommit -gt 60 }
if ($inactiveRepos) {
    $recommendations += "Consider archiving inactive repositories: $($inactiveRepos.Name -join ', ')"
}

# Check for failing pipelines
$failingPipelines = $pipelineAnalysis | Where-Object { $_.SuccessRate -lt 50 -and $_.RecentRuns -gt 0 }
if ($failingPipelines) {
    $recommendations += "Address failing pipelines: $($failingPipelines.Name -join ', ')"
}

# Check for long-running PRs
if ($allPRs -and $allPRs.value) {
    $stalePRs = $allPRs.value | Where-Object { 
        $_.status -eq 'active' -and 
        ((Get-Date) - [DateTime]$_.creationDate).Days -gt 30 
    }
    if ($stalePRs) {
        $recommendations += "Review $($stalePRs.Count) pull requests open for 30+ days"
    }
}

# Check contributor balance
if ($topContributors -and $topContributors.Count -gt 0) {
    $topContributorCommits = ($topContributors | Select-Object -First 1).Value.CommitCount
    # Calculate total commits from all contributors
    $totalCommits = 0
    foreach ($contrib in $contributors.Values) {
        if ($contrib.CommitCount) {
            $totalCommits += $contrib.CommitCount
        }
    }
    if ($totalCommits -gt 0 -and ($topContributorCommits / $totalCommits) -gt 0.4) {
        $recommendations += "High contributor concentration - consider knowledge sharing"
    }
}

if ($recommendations.Count -gt 0) {
    foreach ($rec in $recommendations) {
        Write-Host "  * $rec" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [OK] No critical issues found!" -ForegroundColor Green
}

Write-Host ""

# EXPORT REPORT
if ($ExportReport) {
    Write-Host "=== EXPORTING REPORT ===" -ForegroundColor Yellow
    
    $reportPath = Join-Path $OutputPath "discovery_report_$timestamp.json"
    $discoveries | ConvertTo-Json -Depth 10 | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Host "[OK] JSON report saved to: $reportPath" -ForegroundColor Green
    
    # Create summary report
    $summaryPath = Join-Path $OutputPath "discovery_summary_$timestamp.txt"
    $summaryContent = @"
Azure DevOps Discovery Report
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Organization: $Organization
Project: $Project

REPOSITORIES: $($repoAnalysis.Count)
$(foreach ($repo in $repoAnalysis) {
"  - $($repo.Name) ($($repo.SizeMB) MB, $($repo.BranchCount) branches, last commit $($repo.DaysSinceLastCommit) days ago)"
})

BUILD PIPELINES: $($pipelineAnalysis.Count)
$(foreach ($pipeline in $pipelineAnalysis | Sort-Object SuccessRate) {
"  - $($pipeline.Name): $($pipeline.SuccessRate)% success rate"
})

TOP CONTRIBUTORS:
$(foreach ($contributor in $topContributors | Select-Object -First 10) {
"  - $($contributor.Key): $($contributor.Value.CommitCount) commits"
})

RECOMMENDATIONS:
$(foreach ($rec in $recommendations) {
"  - $rec"
})
"@
    
    $summaryContent | Out-File -FilePath $summaryPath -Encoding UTF8
    Write-Host "[OK] Summary report saved to: $summaryPath" -ForegroundColor Green
}

Write-Host ""
Write-Host "Discovery complete! Use -ExportReport to save detailed findings." -ForegroundColor Cyan