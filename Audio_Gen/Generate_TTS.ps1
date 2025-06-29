[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Text,
    
    [int]$MaxLength = 2000
)

$ErrorActionPreference = 'Stop'

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$OutputDir = Join-Path $ScriptDir "outputs"
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

# Check for binary
$badChars = ($Text.ToCharArray() | Where-Object { [int]$_ -eq 0 -or ([int]$_ -lt 32 -and $_ -notin "`t","`n","`r") }).Count
if ($badChars / $Text.Length -gt 0.1) {
    Write-Error "Binary data detected"
    exit 1
}

# Truncate if needed
$ttsText = if ($Text.Length -gt $MaxLength) {
    $Text.Substring(0, $MaxLength) + "..."
} else {
    $Text
}

# Generate TTS
Write-Host "Generating audio..."
$body = @{
    model = "kokoro"
    input = $ttsText
    voice = "af_sky"
    response_format = "mp3"
    speed = 1.0
    stream = $false
} | ConvertTo-Json

$response = Invoke-WebRequest -Uri "http://127.0.0.1:8880/v1/audio/speech" `
    -Method POST `
    -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
    -Headers @{'Content-Type'='application/json; charset=utf-8'; 'Accept'='audio/mpeg'}

# Save audio
$audioPath = Join-Path $OutputDir "tts_$(Get-Date -Format 'yyyyMMdd_HHmmss').mp3"
[System.IO.File]::WriteAllBytes($audioPath, $response.Content)

# Play with VLC if found
$vlc = @("C:\Program Files\VideoLAN\VLC\vlc.exe", "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($vlc) {
    Write-Host "Playing audio..."
    Start-Process -FilePath $vlc -ArgumentList "--intf dummy --play-and-exit `"$audioPath`"" -NoNewWindow -Wait
}

Write-Host "Done: $audioPath"