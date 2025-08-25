# Usage/Overview:
# 1. Run this script first to fetch the latest ChromeDriver.
# 2. Other scripts (e.g., SSO.ps1, autoBook.ps1) rely on this updated driver for automation.

# Detect platform
$platform = if ([Environment]::Is64BitOperatingSystem) { 'win64' } else { 'win32' }

# Get latest Stable version (e.g. "135.0.7049.95")
$versionUrl = 'https://googlechromelabs.github.io/chrome-for-testing/LATEST_RELEASE_STABLE'
try {
    $version = (Invoke-RestMethod -Uri $versionUrl -ErrorAction Stop).Trim()
    Write-Host "Latest Stable version is $version" -ForegroundColor Green

} catch {
    Write-Error "Failed to fetch latest version from $versionUrl :`n$_"
    exit 1
}

$outFile = "..\chromeDriver-$version.zip"
$destFile = "..\chromeDriver-$version"
$chromeDir = Get-ChildItem -Path (Split-Path -Path "$PSScriptRoot") | Where-Object { $_ -like "*chromeDriver-*" }

# Check if a Chrome Driver folder exists and stop any old processes
if ($null -ne $chromeDir) {
    $proc = Get-Process "chromedriver" -ErrorAction SilentlyContinue
    if ($version -eq $chromeDir.Name.Split('-')[1]) {
        Write-Host "Already on the latest version!" -ForegroundColor Green
        exit 1
    }
    if ($proc) {
        Stop-Process -Name "chromedriver" -Force
    }
    Remove-Item -Path $chromeDir -Recurse -Force
}

# Build download URL
$downloadUrl = "https://storage.googleapis.com/chrome-for-testing-public/$version/$platform/chromedriver-$platform.zip"
Write-Host "Downloading ChromeDriver from $downloadUrl" -ForegroundColor Cyan

# Download latest Chrome Driver, extract, and delete zip
try {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $outFile -UseBasicParsing -ErrorAction Stop
    Expand-Archive -Path $outFile -DestinationPath $destFile
    Remove-Item -Path $outFile
    Write-Host "`nSaved to $destFile" -ForegroundColor Green
} catch {
    Write-Error "`nDownload failed:`n$_"
    exit 1
}