
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

# Build download URL
$downloadUrl = "https://storage.googleapis.com/chrome-for-testing-public/$version/$platform/chromedriver-$platform.zip"
Write-Host "Downloading ChromeDriver from $downloadUrl" -ForegroundColor Cyan

# Download the ZIP
$outFile = "../chromeDriver.zip"
try {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $outFile -UseBasicParsing -ErrorAction Stop
    Write-Host "`nSaved to $outFile" -ForegroundColor Green
} catch {
    Write-Error "`nDownload failed:`n$_"
    exit 1
}
