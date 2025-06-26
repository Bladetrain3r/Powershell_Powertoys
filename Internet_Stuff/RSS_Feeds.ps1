# RSS News Analyzer - Automated daily news summary with audio briefing
param(
    [string[]]$RSSFeeds = @(),
    [string]$FeedsConfigFile = "",
    [string]$OutputDirectory = "%appdata%\Local\Powertoys\News",
    [int]$MaxArticles = 50,
    [switch]$AudioOnly,
    [switch]$SkipAudio,
    [string]$Categories = "all" # all, tech, politics, business, etc.
)

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$dateString = Get-Date -Format "yyyy-MM-dd"

# Ensure output directory exists
if (!(Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

Write-Host "RSS News Analyzer - Daily News Summary Generator"
Write-Host "Date: $dateString"

# Default RSS feeds if none provided
$defaultFeeds = @(
    "http://feeds.news24.com/articles/news24/TopStories/rss",
    "https://feeds.bbci.co.uk/news/rss.xml", # BBC
    "https://www.theverge.com/rss/index.xml", # The Verge
    "https://feeds.arstechnica.com/arstechnica/index" # Ars Technica
)

# Load RSS feeds configuration
$feedsToProcess = @()

if ($FeedsConfigFile -and (Test-Path $FeedsConfigFile)) {
    try {
        $feedsConfig = Get-Content -Path $FeedsConfigFile -Raw | ConvertFrom-Json
        $feedsToProcess = $feedsConfig.feeds
        Write-Host "Loaded $($feedsToProcess.Count) feeds from config file"
    } catch {
        Write-Host "Error loading feeds config: $($_.Exception.Message)"
        $feedsToProcess = $defaultFeeds
    }
} elseif ($RSSFeeds.Count -gt 0) {
    $feedsToProcess = $RSSFeeds
    Write-Host "Using $($feedsToProcess.Count) provided RSS feeds"
} else {
    $feedsToProcess = $defaultFeeds
    Write-Host "Using $($feedsToProcess.Count) default RSS feeds"
}

# Function to fetch RSS feed
function Get-RSSFeed {
    param([string]$FeedUrl)
    
    try {
        Write-Host "  Fetching: $FeedUrl"
        $response = Invoke-WebRequest -Uri $FeedUrl -TimeoutSec 30 -ErrorAction Stop
        [xml]$rssXml = $response.Content
        
        $articles = @()
        
        # Handle different RSS formats
        if ($rssXml.rss) {
            # Standard RSS format
            $channelTitle = if ($rssXml.rss.channel.title) { $rssXml.rss.channel.title.ToString() } else { "Unknown Source" }
            
            foreach ($item in $rssXml.rss.channel.item) {
                $title = if ($item.title) { $item.title.ToString() } else { "No Title" }
                $description = if ($item.description) { 
                    ($item.description.ToString() -replace '<[^>]+>', '').Trim() 
                } else { "" }
                $link = if ($item.link) { $item.link.ToString() } else { "" }
                $pubDate = if ($item.pubDate) { $item.pubDate.ToString() } else { "" }
                $category = if ($item.category) { $item.category.ToString() } else { "General" }
                
                $articles += [PSCustomObject]@{
                    Title = $title
                    Description = $description
                    Link = $link
                    PubDate = $pubDate
                    Source = $channelTitle
                    Category = $category
                }
            }
        } elseif ($rssXml.feed) {
            # Atom format
            $feedTitle = if ($rssXml.feed.title) { 
                if ($rssXml.feed.title.'#text') { 
                    $rssXml.feed.title.'#text'.ToString() 
                } else { 
                    $rssXml.feed.title.ToString() 
                }
            } else { "Unknown Source" }
            
            foreach ($entry in $rssXml.feed.entry) {
                $title = if ($entry.title) {
                    if ($entry.title.'#text') { 
                        $entry.title.'#text'.ToString() 
                    } else { 
                        $entry.title.ToString() 
                    }
                } else { "No Title" }
                
                $description = if ($entry.summary) {
                    if ($entry.summary.'#text') { 
                        ($entry.summary.'#text'.ToString() -replace '<[^>]+>', '').Trim() 
                    } else { 
                        ($entry.summary.ToString() -replace '<[^>]+>', '').Trim() 
                    }
                } else { "" }
                
                $link = if ($entry.link -and $entry.link.href) { 
                    $entry.link.href.ToString() 
                } else { "" }
                
                $pubDate = if ($entry.published) { 
                    $entry.published.ToString() 
                } else { "" }
                
                $category = if ($entry.category -and $entry.category.term) { 
                    $entry.category.term.ToString() 
                } else { "General" }
                
                $articles += [PSCustomObject]@{
                    Title = $title
                    Description = $description
                    Link = $link
                    PubDate = $pubDate
                    Source = $feedTitle
                    Category = $category
                }
            }
        }
        
        Write-Host "    Found $($articles.Count) articles"
        return $articles
        
    } catch {
        Write-Host "    Error fetching feed: $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

# Function to filter articles by category
function Filter-ArticlesByCategory {
    param($Articles, [string]$CategoryFilter)
    
    if ($CategoryFilter -eq "all") {
        return $Articles
    }
    
    $filtered = $Articles | Where-Object { 
        $_.Category -like "*$CategoryFilter*" -or 
        $_.Title -like "*$CategoryFilter*" -or 
        $_.Description -like "*$CategoryFilter*"
    }
    
    return $filtered
}

# Function to clean text for API processing
function Clean-TextForAPI {
    param([string]$Text, [int]$MaxLength = 8000)
    
    $clean = $Text -replace '[\x00-\x1F\x7F]', ' '
    $clean = $clean -replace '\\', '\\'
    $clean = $clean -replace '"', '\"'
    $clean = $clean -replace "`t", ' '
    $clean = $clean -replace "`r`n", ' '
    $clean = $clean -replace "`n", ' '
    $clean = $clean -replace '\s+', ' '
    $clean = $clean.Trim()
    
    if ($clean.Length -gt $MaxLength) {
        $clean = $clean.Substring(0, $MaxLength) + "... [truncated]"
    }
    
    return $clean
}

# Function to call AI for analysis
function Invoke-NewsAPI {
    param(
        [string]$Prompt,
        [int]$MaxTokens = 1000,
        [float]$Temperature = 0.3
    )
    
    try {
        $body = @{
            model = "gemma-3-4b-it-qat"
            messages = @(
                @{
                    role = "user"
                    content = $Prompt
                }
            )
            max_tokens = $MaxTokens
            temperature = $Temperature
        } | ConvertTo-Json -Depth 5
        
        $headers = @{
            'Content-Type' = 'application/json; charset=utf-8'
        }
        
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:1234/v1/chat/completions" -Method POST -Body $bodyBytes -Headers $headers -TimeoutSec 30
        $responseData = $response.Content | ConvertFrom-Json
        
        return $responseData.choices[0].message.content.Trim()
        
    } catch {
        return "ERROR: API call failed - $($_.Exception.Message)"
    }
}

# PHASE 1: Fetch RSS Feeds
Write-Host "`nPHASE 1: Fetching RSS feeds..."

$allArticles = @()
$feedCount = 0

foreach ($feed in $feedsToProcess) {
    $feedCount++
    Write-Host "[$feedCount/$($feedsToProcess.Count)] Processing feed..."
    
    $articles = Get-RSSFeed -FeedUrl $feed
    $allArticles += $articles
    
    # Small delay between feeds to be respectful
    Start-Sleep -Milliseconds 500
}

Write-Host "Total articles fetched: $($allArticles.Count)"

# Filter by category if specified
if ($Categories -ne "all") {
    $filteredArticles = Filter-ArticlesByCategory -Articles $allArticles -CategoryFilter $Categories
    Write-Host "Articles after category filter ($Categories): $($filteredArticles.Count)"
    $allArticles = $filteredArticles
}

# Limit articles if specified
if ($MaxArticles -gt 0 -and $allArticles.Count -gt $MaxArticles) {
    # Sort by publication date (newest first) if possible, otherwise take first N
    try {
        $allArticles = $allArticles | Sort-Object { [DateTime]$_.PubDate } -Descending | Select-Object -First $MaxArticles
    } catch {
        $allArticles = $allArticles | Select-Object -First $MaxArticles
    }
    Write-Host "Limited to $MaxArticles most recent articles"
}

if ($allArticles.Count -eq 0) {
    Write-Host "No articles found to process"
    exit
}

# PHASE 2: Analyze Headlines and Generate Summary
Write-Host "`nPHASE 2: Analyzing headlines and generating summary..."

# Group articles by source for better organization
$articlesBySource = $allArticles | Group-Object -Property Source

# Build headlines text for analysis
$headlinesText = ""
foreach ($sourceGroup in $articlesBySource) {
    $headlinesText += "SOURCE: $($sourceGroup.Name)`n"
    foreach ($article in $sourceGroup.Group) {
        $headlinesText += "- $($article.Title)"
        if ($article.Description -and $article.Description.Length -gt 0) {
            $shortDesc = $article.Description.Substring(0, [Math]::Min(150, $article.Description.Length))
            $headlinesText += " | $shortDesc"
        }
        $headlinesText += "`n"
    }
    $headlinesText += "`n"
}

$cleanHeadlines = Clean-TextForAPI -Text $headlinesText -MaxLength 12000

# Generate comprehensive news analysis
$analysisPrompt = @"
Analyze these news headlines and create a comprehensive daily briefing. Structure your response as:

TOP_STORIES: [3-5 most important stories of the day with brief explanations]
TRENDING_TOPICS: [Common themes and topics appearing across multiple sources]
TECHNOLOGY_NEWS: [Key technology and innovation stories]
BUSINESS_ECONOMIC: [Major business and economic developments]
POLITICS_GOVERNANCE: [Political and policy developments]
INTERNATIONAL: [Global and international news]
OTHER_NOTABLE: [Other significant stories worth mentioning]
SUMMARY: [2-3 sentence overall summary of the day's news]

DO NOT use special characters or complex formatting. Purely simple text.
No intro music or other bullshit. No superfluous additions. Just. The. Feed. Summarised.

Today's Headlines ($dateString):
$cleanHeadlines
"@

$newsAnalysis = Invoke-NewsAPI -Prompt $analysisPrompt -MaxTokens 1500 -Temperature 0.3

Write-Host "News analysis complete"

# PHASE 3: Generate Audio Briefing Summary
Write-Host "`nPHASE 3: Creating audio briefing..."

$briefingPrompt = @"
Summarise the feeds in brief. Plaintext only.

Requirements:
- Start with date and brief overview
- Cover the most important stories clearly
- Cover key topics like technology, business, politics, and international news
- Use simple, clear language suitable for text-to-speech

News Analysis:
$newsAnalysis
"@

$audioBriefing = Invoke-NewsAPI -Prompt $briefingPrompt -MaxTokens 800 -Temperature 0.2

Write-Host "Audio briefing script created"

# Save comprehensive news report
if (!$AudioOnly) {
    $reportPath = Join-Path $OutputDirectory "news_report_$timestamp.txt"
    $fullReport = @"
DAILY NEWS REPORT - $dateString
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Articles Analyzed: $($allArticles.Count)
Sources: $($articlesBySource.Count)

COMPREHENSIVE ANALYSIS:
$newsAnalysis

AUDIO BRIEFING SCRIPT:
$audioBriefing

HEADLINES BY SOURCE:
$headlinesText

SOURCES PROCESSED:
$(foreach ($sg in $articlesBySource) { "- $($sg.Name): $($sg.Count) articles" })

---
Generated by RSS News Analyzer
"@

    $fullReport | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Host "Full report saved to: $reportPath"
}

# Save individual components
$analysisPath = Join-Path $OutputDirectory "news_analysis_$timestamp.txt"
$briefingPath = Join-Path $OutputDirectory "audio_briefing_$timestamp.txt"
$headlinesPath = Join-Path $OutputDirectory "headlines_$timestamp.txt"

$newsAnalysis | Out-File -FilePath $analysisPath -Encoding UTF8
$audioBriefing | Out-File -FilePath $briefingPath -Encoding UTF8
$headlinesText | Out-File -FilePath $headlinesPath -Encoding UTF8

# Copy audio briefing to clipboard
$audioBriefing | Set-Clipboard

Write-Host ""
Write-Host "NEWS ANALYSIS COMPLETE!"
Write-Host "Date: $dateString"
Write-Host "Articles processed: $($allArticles.Count)"
Write-Host "Sources: $($articlesBySource.Count)"
Write-Host ""
if (!$AudioOnly) {
    Write-Host "Files generated:"
    Write-Host "- Complete Report: $reportPath"
    Write-Host "- Analysis: $analysisPath"
    Write-Host "- Audio Script: $briefingPath"
    Write-Host "- Headlines: $headlinesPath"
    Write-Host ""
}
Write-Host "Audio briefing copied to clipboard"

# Generate and play audio briefing
if (!$SkipAudio) {
    Write-Host "`nGenerating audio briefing..."
    try {
        $ttsText = $audioBriefing
        
        $ttsBody = @{
            model = "kokoro"
            input = $ttsText
            voice = "af_sky"
            response_format = "mp3"
            speed = 1.0
            stream = $false
        } | ConvertTo-Json -Depth 3
        
        $audioPath = Join-Path $OutputDirectory "daily_briefing_$timestamp.mp3"
        
        $ttsHeaders = @{
            'Content-Type' = 'application/json; charset=utf-8'
            'Accept' = 'audio/mpeg'
        }
        
        $ttsBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($ttsBody)
        $ttsResponse = Invoke-WebRequest -Uri "http://127.0.0.1:8880/v1/audio/speech" -Method POST -Body $ttsBodyBytes -Headers $ttsHeaders -TimeoutSec 60
        [System.IO.File]::WriteAllBytes($audioPath, $ttsResponse.Content)
        
        Write-Host "Audio briefing saved to: $audioPath"
        
        # Check if VLC exists before trying to use it
        $vlcPath = "C:\Program Files\VideoLAN\VLC\vlc.exe"
        if (Test-Path $vlcPath) {
            Start-Sleep 1
            Start-Process -FilePath $vlcPath -ArgumentList "--intf dummy --play-and-exit `"$audioPath`"" -NoNewWindow -Wait
            Write-Host "Audio briefing played!"
        } else {
            Write-Host "Audio generated but VLC not found. Audio saved to: $audioPath"
        }
        
    } catch {
        Write-Host "Audio generation failed: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "Audio generation skipped"
}

Write-Host ""
Write-Host "DAILY NEWS BRIEFING:"
Write-Host $audioBriefing.Substring(0, [Math]::Min(600, $audioBriefing.Length))
if ($audioBriefing.Length -gt 600) { Write-Host "..." }
Write-Host ""
Write-Host "Daily news analysis complete - stay informed!"
