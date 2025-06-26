# Music Collection Analyzer - Simple metadata analysis and reporting
param(
    [string]$MediaPath = "G:\zmusic\Various Artists",
    [string]$OutputPath = ".\outputs\MusicAnalysis",
    [string[]]$Extensions = @("*.mp3", "*.flac", "*.wav", "*.m4a", "*.ogg", "*.wma"),
    [switch]$Recursive = $true,
    [switch]$Detailed,
    [switch]$SkipAudio
)

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# Ensure output directory exists
if (!(Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

Write-Host "Music Collection Analyzer - Local Metadata Analysis" -ForegroundColor Green
Write-Host "Scanning: $MediaPath"

# Extract metadata using Windows Shell COM
function Get-TrackMetadata {
    param([string]$FilePath)
    
    try {
        # Get basic file info first (always works)
        $fileInfo = Get-Item $FilePath -ErrorAction Stop
        
        # Initialize metadata with guaranteed properties
        $metadata = @{
            FilePath = $FilePath
            FileName = $fileInfo.Name
            Title = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
            Artist = "Unknown"
            Album = "Unknown"
            Genre = "Unknown"
            Year = "Unknown"
            Duration = "Unknown"
            BitRate = "Unknown"
            Size = $fileInfo.Length
            Extension = $fileInfo.Extension.ToLower()
            LastModified = $fileInfo.LastWriteTime
        }
        
        # Try to get enhanced metadata via COM (with extensive null checking)
        try {
            $shell = New-Object -ComObject Shell.Application -ErrorAction Stop
            if ($shell -ne $null) {
                $folder = $shell.Namespace($fileInfo.DirectoryName)
                if ($folder -ne $null) {
                    $file = $folder.ParseName($fileInfo.Name)
                    if ($file -ne $null) {
                        # Extract metadata with extensive null/error checking
                        try { $title = $folder.GetDetailsOf($file, 21); if ($title) { $title = ($title -replace '\x00', '').Trim(); if (![string]::IsNullOrWhiteSpace($title)) { $metadata.Title = $title } } } catch { }
                        try { $artist = $folder.GetDetailsOf($file, 13); if ($artist) { $artist = ($artist -replace '\x00', '').Trim(); if (![string]::IsNullOrWhiteSpace($artist)) { $metadata.Artist = $artist } } } catch { }
                        try { $album = $folder.GetDetailsOf($file, 14); if ($album) { $album = ($album -replace '\x00', '').Trim(); if (![string]::IsNullOrWhiteSpace($album)) { $metadata.Album = $album } } } catch { }
                        try { $genre = $folder.GetDetailsOf($file, 16); if ($genre) { $genre = ($genre -replace '\x00', '').Trim(); if (![string]::IsNullOrWhiteSpace($genre)) { $metadata.Genre = $genre } } } catch { }
                        try { $year = $folder.GetDetailsOf($file, 15); if ($year) { $year = ($year -replace '\x00', '').Trim(); if (![string]::IsNullOrWhiteSpace($year)) { $metadata.Year = $year } } } catch { }
                        try { $duration = $folder.GetDetailsOf($file, 27); if ($duration) { $duration = ($duration -replace '\x00', '').Trim(); if (![string]::IsNullOrWhiteSpace($duration)) { $metadata.Duration = $duration } } } catch { }
                        try { $bitrate = $folder.GetDetailsOf($file, 28); if ($bitrate) { $bitrate = ($bitrate -replace '\x00', '').Trim(); if (![string]::IsNullOrWhiteSpace($bitrate)) { $metadata.BitRate = $bitrate } } } catch { }
                    }
                }
            }
        } catch {
            # COM extraction completely failed - silently continue with basic info
        } finally {
            # Clean up COM objects
            try { if ($shell) { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null } } catch { }
        }
        
        return $metadata
        
    } catch {
        Write-Host "Error reading file $FilePath`: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Scan all music files
Write-Host "`nScanning for music files..." -ForegroundColor Cyan

$allFiles = @()
foreach ($ext in $Extensions) {
    $files = Get-ChildItem -Path $MediaPath -Filter $ext -Recurse:$Recursive -File -ErrorAction SilentlyContinue
    $allFiles += $files
}

if ($allFiles.Count -eq 0) {
    Write-Host "No music files found in $MediaPath" -ForegroundColor Yellow
    exit
}

Write-Host "Found $($allFiles.Count) music files. Extracting metadata..." -ForegroundColor Green

# Extract metadata from all files
$tracks = @()
$processedCount = 0

foreach ($file in $allFiles) {
    $processedCount++
    $progressPercent = [math]::Round(($processedCount / $allFiles.Count) * 100)
    
    if ($processedCount % 50 -eq 0 -or $processedCount -eq $allFiles.Count) {
        Write-Host "[$processedCount/$($allFiles.Count) - $progressPercent%] Processing..."
    }
    
    $metadata = Get-TrackMetadata -FilePath $file.FullName
    if ($metadata) {
        $tracks += $metadata
    }
}

Write-Host "Metadata extraction complete! Analyzing $($tracks.Count) tracks..." -ForegroundColor Green

# Calculate total size safely
$totalSizeBytes = 0
foreach ($track in $tracks) {
    if ($track.Size -and $track.Size -is [long]) {
        $totalSizeBytes += $track.Size
    }
}

# Clean text function for grouping operations
function Clean-GroupingText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return "Unknown" }
    
    # Remove unicode escapes, control characters, and trim
    $clean = $Text -replace '\\u[0-9A-Fa-f]{4}', ''
    $clean = $clean -replace '[\x00-\x1F\x7F]', ''
    $clean = $clean.Trim()
    
    if ([string]::IsNullOrWhiteSpace($clean)) { return "Unknown" }
    return $clean
}

# Generate collection analysis with safer grouping
$analysis = @{
    ScanDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    TotalTracks = $tracks.Count
    TotalSizeGB = [math]::Round($totalSizeBytes / 1GB, 2)
    
    # Completeness ratios
    UnknownTitles = ($tracks | Where-Object { $_.Title -eq "Unknown" -or $_.Title -like "*$($_.FileName)*" }).Count
    UnknownArtists = ($tracks | Where-Object { $_.Artist -eq "Unknown" }).Count
    UnknownAlbums = ($tracks | Where-Object { $_.Album -eq "Unknown" }).Count
    UnknownGenres = ($tracks | Where-Object { $_.Genre -eq "Unknown" }).Count
    UnknownYears = ($tracks | Where-Object { $_.Year -eq "Unknown" }).Count
}

# Safer file format analysis
$formatGroups = @{}
foreach ($track in $tracks) {
    $ext = Clean-GroupingText -Text $track.Extension
    if ($formatGroups.ContainsKey($ext)) {
        $formatGroups[$ext]++
    } else {
        $formatGroups[$ext] = 1
    }
}
$analysis.FormatCounts = $formatGroups.GetEnumerator() | Sort-Object Value -Descending

# Safer artist analysis
$artistGroups = @{}
foreach ($track in $tracks) {
    $artist = Clean-GroupingText -Text $track.Artist
    if ($artist -ne "Unknown") {
        if ($artistGroups.ContainsKey($artist)) {
            $artistGroups[$artist]++
        } else {
            $artistGroups[$artist] = 1
        }
    }
}
$analysis.TopArtists = $artistGroups.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10

# Safer album analysis
$albumGroups = @{}
foreach ($track in $tracks) {
    $album = Clean-GroupingText -Text $track.Album
    if ($album -ne "Unknown") {
        if ($albumGroups.ContainsKey($album)) {
            $albumGroups[$album]++
        } else {
            $albumGroups[$album] = 1
        }
    }
}
$analysis.TopAlbums = $albumGroups.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10

# Safer genre analysis
$genreGroups = @{}
foreach ($track in $tracks) {
    $genre = Clean-GroupingText -Text $track.Genre
    if ($genre -ne "Unknown") {
        if ($genreGroups.ContainsKey($genre)) {
            $genreGroups[$genre]++
        } else {
            $genreGroups[$genre] = 1
        }
    }
}
$analysis.TopGenres = $genreGroups.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10

# Safer year analysis
$yearGroups = @{}
foreach ($track in $tracks) {
    $year = Clean-GroupingText -Text $track.Year
    if ($year -ne "Unknown" -and $year -match '^\d{4}

# Calculate completion percentages
$completionStats = @{
    TitleCompletion = [math]::Round((($analysis.TotalTracks - $analysis.UnknownTitles) / $analysis.TotalTracks) * 100, 1)
    ArtistCompletion = [math]::Round((($analysis.TotalTracks - $analysis.UnknownArtists) / $analysis.TotalTracks) * 100, 1)
    AlbumCompletion = [math]::Round((($analysis.TotalTracks - $analysis.UnknownAlbums) / $analysis.TotalTracks) * 100, 1)
    GenreCompletion = [math]::Round((($analysis.TotalTracks - $analysis.UnknownGenres) / $analysis.TotalTracks) * 100, 1)
    YearCompletion = [math]::Round((($analysis.TotalTracks - $analysis.UnknownYears) / $analysis.TotalTracks) * 100, 1)
}

# Generate AI analysis of collection
Write-Host "`nGenerating AI insights..." -ForegroundColor Cyan

$collectionSummary = @"
COLLECTION OVERVIEW:
- Total tracks: $($analysis.TotalTracks)
- Total size: $($analysis.TotalSizeGB) GB
- Metadata completion: $($completionStats.ArtistCompletion)% artists, $($completionStats.AlbumCompletion)% albums, $($completionStats.GenreCompletion)% genres

TOP ARTISTS: $(if ($analysis.TopArtists.Count -gt 0) { ($analysis.TopArtists | Select-Object -First 5 | ForEach-Object { "$($_.Name) ($($_.Value))" }) -join ', ' } else { "None available" })
TOP GENRES: $(if ($analysis.TopGenres.Count -gt 0) { ($analysis.TopGenres | Select-Object -First 5 | ForEach-Object { "$($_.Name) ($($_.Value))" }) -join ', ' } else { "None available" })
FORMATS: $(($analysis.FormatCounts | ForEach-Object { "$($_.Name) ($($_.Value))" }) -join ', ')
"@

try {
    $aiPrompt = @"
Analyze this music collection and provide insights:

COLLECTION_HEALTH: [Overall metadata quality assessment]
MUSIC_TASTE_PROFILE: [What this collection says about the owner's music preferences]
ORGANIZATION_SUGGESTIONS: [How to improve metadata completeness]
DISCOVERY_OPPORTUNITIES: [Gaps or areas for music discovery]
CURATION_NOTES: [Quality of collection, diversity, etc.]

Collection Data:
$collectionSummary
"@

    $body = @{
        model = "llama-3.2-1b-instruct"
        messages = @(
            @{
                role = "user"
                content = $aiPrompt
            }
        )
        max_tokens = 1000
        temperature = 0.4
    } | ConvertTo-Json -Depth 5
    
    $headers = @{
        'Content-Type' = 'application/json; charset=utf-8'
    }
    
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $response = Invoke-WebRequest -Uri "http://localhost:1234/v1/chat/completions" -Method POST -Body $bodyBytes -Headers $headers -TimeoutSec 30
    $responseData = $response.Content | ConvertFrom-Json
    $aiInsights = $responseData.choices[0].message.content.Trim()
    
} catch {
    $aiInsights = "AI analysis unavailable: $($_.Exception.Message)"
}

# Create comprehensive report
$reportPath = Join-Path $OutputPath "music_analysis_$timestamp.txt"
$report = @"
MUSIC COLLECTION ANALYSIS REPORT
Generated: $($analysis.ScanDate)
Source: $MediaPath

===== COLLECTION OVERVIEW =====
Total Tracks: $($analysis.TotalTracks)
Total Size: $($analysis.TotalSizeGB) GB
Average File Size: $(if ($analysis.TotalTracks -gt 0 -and $analysis.TotalSizeGB -gt 0) { [math]::Round($analysis.TotalSizeGB * 1024 / $analysis.TotalTracks, 1) } else { 0 }) MB

===== METADATA COMPLETENESS =====
Titles: $($completionStats.TitleCompletion)% complete ($($analysis.UnknownTitles) unknown)
Artists: $($completionStats.ArtistCompletion)% complete ($($analysis.UnknownArtists) unknown)
Albums: $($completionStats.AlbumCompletion)% complete ($($analysis.UnknownAlbums) unknown)
Genres: $($completionStats.GenreCompletion)% complete ($($analysis.UnknownGenres) unknown)
Years: $($completionStats.YearCompletion)% complete ($($analysis.UnknownYears) unknown)

===== FILE FORMATS =====
$(foreach ($format in $analysis.FormatCounts) {
"$($format.Name): $($format.Value) files ($([math]::Round(($format.Value / $analysis.TotalTracks) * 100, 1))%)"
})

===== TOP ARTISTS =====
$(if ($analysis.TopArtists.Count -eq 0) {
"No artist information available"
} else {
foreach ($artist in $analysis.TopArtists) {
"$($artist.Name): $($artist.Value) tracks"
}
})

===== TOP ALBUMS =====
$(if ($analysis.TopAlbums.Count -eq 0) {
"No album information available" 
} else {
foreach ($album in $analysis.TopAlbums) {
"$($album.Name): $($album.Value) tracks"
}
})

===== TOP GENRES =====
$(if ($analysis.TopGenres.Count -eq 0) {
"No genre information available"
} else {
foreach ($genre in $analysis.TopGenres) {
"$($genre.Name): $($genre.Value) tracks"
}
})

===== YEAR DISTRIBUTION =====
$(if ($analysis.YearCounts.Count -gt 0) {
    # Group years by decade
    $decades = @{}
    foreach ($yearEntry in $analysis.YearCounts) {
        $year = [int]$yearEntry.Name
        $decade = [math]::Floor($year / 10) * 10
        if ($decades.ContainsKey($decade)) {
            $decades[$decade] += $yearEntry.Value
        } else {
            $decades[$decade] = $yearEntry.Value
        }
    }
    foreach ($decade in ($decades.GetEnumerator() | Sort-Object Name)) {
        "$($decade.Name)s: $($decade.Value) tracks"
    }
} else {
    "No year information available"
})

===== AI INSIGHTS =====
$aiInsights

$(if ($Detailed) {
"
===== DETAILED TRACK LISTING =====
$(foreach ($track in ($tracks | Sort-Object Artist, Album, Title)) {
"$($track.Artist) - $($track.Title) [$($track.Album)] ($($track.Year)) - $([math]::Round($track.Size / 1MB, 1)) MB"
})"
})

---
Generated by Music Collection Analyzer
"@

$report | Out-File -FilePath $reportPath -Encoding UTF8

# Save raw data as JSON for further processing
$dataPath = Join-Path $OutputPath "music_data_$timestamp.json"
@{
    Analysis = $analysis
    CompletionStats = $completionStats
    Tracks = $tracks
} | ConvertTo-Json -Depth 10 | Out-File -FilePath $dataPath -Encoding UTF8

# Copy summary to clipboard
$clipboardSummary = "Music collection analyzed: $($analysis.TotalTracks) tracks, $($analysis.TotalSizeGB) GB. Metadata completion: $($completionStats.ArtistCompletion)% artists, $($completionStats.AlbumCompletion)% albums, $($completionStats.GenreCompletion)% genres. Top artists: $(($analysis.TopArtists | Select-Object -First 3 | ForEach-Object { $_.Name }) -join ', ')"
$clipboardSummary | Set-Clipboard

# Display results
Write-Host ""
Write-Host "MUSIC COLLECTION ANALYSIS COMPLETE!" -ForegroundColor Green
Write-Host "Report saved: $reportPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "QUICK STATS:" -ForegroundColor Yellow
Write-Host "- Total tracks: $($analysis.TotalTracks)"
Write-Host "- Collection size: $($analysis.TotalSizeGB) GB"
Write-Host "- Artist metadata: $($completionStats.ArtistCompletion)% complete"
Write-Host "- Album metadata: $($completionStats.AlbumCompletion)% complete"
Write-Host "- Genre metadata: $($completionStats.GenreCompletion)% complete"
Write-Host ""
Write-Host "TOP ARTISTS:" -ForegroundColor Cyan
if ($analysis.TopArtists.Count -gt 0) {
    $analysis.TopArtists | Select-Object -First 5 | ForEach-Object {
        Write-Host "- $($_.Name): $($_.Value) tracks" -ForegroundColor White
    }
} else {
    Write-Host "- No artist information available" -ForegroundColor Gray
}
Write-Host ""
Write-Host "Summary copied to clipboard" -ForegroundColor Green

# Generate audio summary
if (!$SkipAudio) {
    Write-Host "`nGenerating audio summary..." -ForegroundColor Cyan
    try {
        $audioSummary = "Music collection analysis complete. Found $($analysis.TotalTracks) tracks totaling $($analysis.TotalSizeGB) gigabytes. Artist metadata is $($completionStats.ArtistCompletion) percent complete. $(if ($analysis.TopArtists.Count -gt 0) { "Top artists include $(($analysis.TopArtists | Select-Object -First 3 | ForEach-Object { $_.Name }) -join ', ')." } else { "No artist information available." }) $(if ($analysis.TopGenres.Count -gt 0) { "Collection appears to favor $(($analysis.TopGenres | Select-Object -First 2 | ForEach-Object { $_.Name }) -join ' and ') music." } else { "No genre information available for analysis." })"
        
        $ttsBody = @{
            model = "kokoro"
            input = $audioSummary
            voice = "af_sky"
            response_format = "mp3"
            speed = 1.0
            stream = $false
        } | ConvertTo-Json -Depth 3
        
        $audioPath = Join-Path $OutputPath "music_analysis_$timestamp.mp3"
        
        $ttsHeaders = @{
            'Content-Type' = 'application/json; charset=utf-8'
            'Accept' = 'audio/mpeg'
        }
        
        $ttsBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($ttsBody)
        $ttsResponse = Invoke-WebRequest -Uri "http://localhost:8880/v1/audio/speech" -Method POST -Body $ttsBodyBytes -Headers $ttsHeaders
        [System.IO.File]::WriteAllBytes($audioPath, $ttsResponse.Content)
        
        $vlcPath = "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"
        if (Test-Path $vlcPath) {
            Start-Sleep 1
            Start-Process -FilePath $vlcPath -ArgumentList "--intf dummy --play-and-exit `"$audioPath`"" -NoNewWindow -Wait
            Write-Host "Audio summary complete!" -ForegroundColor Green
        }
        
    } catch {
        Write-Host "Audio generation failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Use -Detailed for full track listings" -ForegroundColor Gray) {
        if ($yearGroups.ContainsKey($year)) {
            $yearGroups[$year]++
        } else {
            $yearGroups[$year] = 1
        }
    }
}
$analysis.YearCounts = $yearGroups.GetEnumerator() | Sort-Object Name

# Calculate completion percentages
$completionStats = @{
    TitleCompletion = [math]::Round((($analysis.TotalTracks - $analysis.UnknownTitles) / $analysis.TotalTracks) * 100, 1)
    ArtistCompletion = [math]::Round((($analysis.TotalTracks - $analysis.UnknownArtists) / $analysis.TotalTracks) * 100, 1)
    AlbumCompletion = [math]::Round((($analysis.TotalTracks - $analysis.UnknownAlbums) / $analysis.TotalTracks) * 100, 1)
    GenreCompletion = [math]::Round((($analysis.TotalTracks - $analysis.UnknownGenres) / $analysis.TotalTracks) * 100, 1)
    YearCompletion = [math]::Round((($analysis.TotalTracks - $analysis.UnknownYears) / $analysis.TotalTracks) * 100, 1)
}

# Generate AI analysis of collection
Write-Host "`nGenerating AI insights..." -ForegroundColor Cyan

$collectionSummary = @"
COLLECTION OVERVIEW:
- Total tracks: $($analysis.TotalTracks)
- Total size: $($analysis.TotalSizeGB) GB
- Metadata completion: $($completionStats.ArtistCompletion)% artists, $($completionStats.AlbumCompletion)% albums, $($completionStats.GenreCompletion)% genres

TOP ARTISTS: $(($analysis.TopArtists | Select-Object -First 5 | ForEach-Object { "$($_.Name) ($($_.Count))" }) -join ', ')
TOP GENRES: $(($analysis.TopGenres | Select-Object -First 5 | ForEach-Object { "$($_.Name) ($($_.Count))" }) -join ', ')
FORMATS: $(($analysis.FormatCounts | ForEach-Object { "$($_.Name) ($($_.Count))" }) -join ', ')
"@

try {
    $aiPrompt = @"
Analyze this music collection and provide insights:

COLLECTION_HEALTH: [Overall metadata quality assessment]
MUSIC_TASTE_PROFILE: [What this collection says about the owner's music preferences]
ORGANIZATION_SUGGESTIONS: [How to improve metadata completeness]
DISCOVERY_OPPORTUNITIES: [Gaps or areas for music discovery]
CURATION_NOTES: [Quality of collection, diversity, etc.]

Collection Data:
$collectionSummary
"@

    $body = @{
        model = "gemma-3-4b-it-qat"
        messages = @(
            @{
                role = "user"
                content = $aiPrompt
            }
        )
        max_tokens = 1000
        temperature = 0.4
    } | ConvertTo-Json -Depth 5
    
    $headers = @{
        'Content-Type' = 'application/json; charset=utf-8'
    }
    
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $response = Invoke-WebRequest -Uri "http://localhost:1234/v1/chat/completions" -Method POST -Body $bodyBytes -Headers $headers -TimeoutSec 30
    $responseData = $response.Content | ConvertFrom-Json
    $aiInsights = $responseData.choices[0].message.content.Trim()
    
} catch {
    $aiInsights = "AI analysis unavailable: $($_.Exception.Message)"
}

# Create comprehensive report
$reportPath = Join-Path $OutputPath "music_analysis_$timestamp.txt"
$report = @"
MUSIC COLLECTION ANALYSIS REPORT
Generated: $($analysis.ScanDate)
Source: $MediaPath

===== COLLECTION OVERVIEW =====
Total Tracks: $($analysis.TotalTracks)
Total Size: $($analysis.TotalSizeGB) GB
Average File Size: $(if ($analysis.TotalTracks -gt 0 -and $analysis.TotalSizeGB -gt 0) { [math]::Round($analysis.TotalSizeGB * 1024 / $analysis.TotalTracks, 1) } else { 0 }) MB

===== METADATA COMPLETENESS =====
Titles: $($completionStats.TitleCompletion)% complete ($($analysis.UnknownTitles) unknown)
Artists: $($completionStats.ArtistCompletion)% complete ($($analysis.UnknownArtists) unknown)
Albums: $($completionStats.AlbumCompletion)% complete ($($analysis.UnknownAlbums) unknown)
Genres: $($completionStats.GenreCompletion)% complete ($($analysis.UnknownGenres) unknown)
Years: $($completionStats.YearCompletion)% complete ($($analysis.UnknownYears) unknown)

===== FILE FORMATS =====
$(foreach ($format in $analysis.FormatCounts) {
"$($format.Name): $($format.Count) files ($([math]::Round(($format.Count / $analysis.TotalTracks) * 100, 1))%)"
})

===== TOP ARTISTS =====
$(foreach ($artist in $analysis.TopArtists) {
"$($artist.Name): $($artist.Count) tracks"
})

===== TOP ALBUMS =====
$(foreach ($album in $analysis.TopAlbums) {
"$($album.Name): $($album.Count) tracks"
})

===== TOP GENRES =====
$(foreach ($genre in $analysis.TopGenres) {
"$($genre.Name): $($genre.Count) tracks"
})

===== YEAR DISTRIBUTION =====
$(if ($analysis.YearCounts.Count -gt 0) {
    $decades = $analysis.YearCounts | Group-Object { [math]::Floor([int]$_.Name / 10) * 10 } | Sort-Object Name
    foreach ($decade in $decades) {
        "$($decade.Name)s: $($decade.Group | Measure-Object -Property Count -Sum | Select-Object -ExpandProperty Sum) tracks"
    }
} else {
    "No year information available"
})

===== AI INSIGHTS =====
$aiInsights

$(if ($Detailed) {
"
===== DETAILED TRACK LISTING =====
$(foreach ($track in ($tracks | Sort-Object Artist, Album, Title)) {
"$($track.Artist) - $($track.Title) [$($track.Album)] ($($track.Year)) - $([math]::Round($track.Size / 1MB, 1)) MB"
})"
})

---
Generated by Music Collection Analyzer
"@

$report | Out-File -FilePath $reportPath -Encoding UTF8

# Save raw data as JSON for further processing
$dataPath = Join-Path $OutputPath "music_data_$timestamp.json"
@{
    Analysis = $analysis
    CompletionStats = $completionStats
    Tracks = $tracks
} | ConvertTo-Json -Depth 10 | Out-File -FilePath $dataPath -Encoding UTF8

# Copy summary to clipboard
$clipboardSummary = "Music collection analyzed: $($analysis.TotalTracks) tracks, $($analysis.TotalSizeGB) GB. Metadata completion: $($completionStats.ArtistCompletion)% artists, $($completionStats.AlbumCompletion)% albums, $($completionStats.GenreCompletion)% genres. Top artists: $(($analysis.TopArtists | Select-Object -First 3 | ForEach-Object { $_.Name }) -join ', ')"
$clipboardSummary | Set-Clipboard

# Display results
Write-Host ""
Write-Host "MUSIC COLLECTION ANALYSIS COMPLETE!" -ForegroundColor Green
Write-Host "Report saved: $reportPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "QUICK STATS:" -ForegroundColor Yellow
Write-Host "- Total tracks: $($analysis.TotalTracks)"
Write-Host "- Collection size: $($analysis.TotalSizeGB) GB"
Write-Host "- Artist metadata: $($completionStats.ArtistCompletion)% complete"
Write-Host "- Album metadata: $($completionStats.AlbumCompletion)% complete"
Write-Host "- Genre metadata: $($completionStats.GenreCompletion)% complete"
Write-Host ""
Write-Host "TOP ARTISTS:" -ForegroundColor Cyan
$analysis.TopArtists | Select-Object -First 5 | ForEach-Object {
    Write-Host "- $($_.Name): $($_.Count) tracks" -ForegroundColor White
}
Write-Host ""
Write-Host "Summary copied to clipboard" -ForegroundColor Green

# Generate audio summary
if (!$SkipAudio) {
    Write-Host "`nGenerating audio summary..." -ForegroundColor Cyan
    try {
        $audioSummary = "Music collection analysis complete. Found $($analysis.TotalTracks) tracks totaling $($analysis.TotalSizeGB) gigabytes. Artist metadata is $($completionStats.ArtistCompletion) percent complete. Top artists include $(($analysis.TopArtists | Select-Object -First 3 | ForEach-Object { $_.Name }) -join ', '). Collection appears to favor $(($analysis.TopGenres | Select-Object -First 2 | ForEach-Object { $_.Name }) -join ' and ') music."
        
        $ttsBody = @{
            model = "kokoro"
            input = $audioSummary
            voice = "af_sky"
            response_format = "mp3"
            speed = 1.0
            stream = $false
        } | ConvertTo-Json -Depth 3
        
        $audioPath = Join-Path $OutputPath "music_analysis_$timestamp.mp3"
        
        $ttsHeaders = @{
            'Content-Type' = 'application/json; charset=utf-8'
            'Accept' = 'audio/mpeg'
        }
        
        $ttsBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($ttsBody)
        $ttsResponse = Invoke-WebRequest -Uri "http://localhost:8880/v1/audio/speech" -Method POST -Body $ttsBodyBytes -Headers $ttsHeaders
        [System.IO.File]::WriteAllBytes($audioPath, $ttsResponse.Content)
        
        $vlcPath = "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"
        if (Test-Path $vlcPath) {
            Start-Sleep 1
            Start-Process -FilePath $vlcPath -ArgumentList "--intf dummy --play-and-exit `"$audioPath`"" -NoNewWindow -Wait
            Write-Host "Audio summary complete!" -ForegroundColor Green
        }
        
    } catch {
        Write-Host "Audio generation failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Use -Detailed for full track listings" -ForegroundColor Gray