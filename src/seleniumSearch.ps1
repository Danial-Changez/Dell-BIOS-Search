param(
    [string]   $newModels = "$PSScriptRoot\..\res\newModels.csv",
    [string]   $oldModels = "$PSScriptRoot\..\res\oldModels.csv",
    [string[]] $Arguments = @( 
        'disable-features=LoadMetricsReporting',
        'disable-features=NetworkService,NetworkServiceInProcess',
        'log-level=3'
    )
)
Import-Module Selenium

# Load all models from CSV
$rows = Import-Csv $newModels
Write-Host "Loaded $($rows.Count) models from $newModels" -ForegroundColor Cyan

# Array to store updated output
$results = @()

# Web driver location
$chromeDriver = Get-ChildItem -Path (Split-Path -Path "$PSScriptRoot") | Where-Object { $_.Name -like "*chromeDriver-*" }
$DriverPath = "$chromeDriver\chromedriver-win64\"

# Launch browser
Write-Host "Launching headless Chrome..." -ForegroundColor Cyan
$driver = Start-SeChrome `
-WebDriverDirectory $DriverPath `
-Arguments          $Arguments

# Process each model
foreach ($row in $rows) {
    $modelID = $row.Model
    $productKey = $row.Product
    $productUrl = "https://www.dell.com/support/product-details/en-ca/product/$productKey/drivers"
    
    Write-Host "`nProcessing $modelID ($productKey)" -ForegroundColor Yellow
    
    # JS-click helper function
    function JsClick {
        param($el)
        $driver.ExecuteScript('arguments[0].click()', $el) 
    }
    
    function Clear-Tabs {
        param($driver)
        $handles = $driver.WindowHandles
        foreach ($handle in $handles) {
            if ($handle -ne $driver.CurrentWindowHandle) {
                $driver.SwitchTo().Window($handle)
                $driver.Close()
            }
        }
        $driver.SwitchTo().Window($handles[0])
    }

    # Navigate to the product page
    Write-Host "  Step 1: Navigating to $productUrl..." -ForegroundColor Cyan
    Enter-SeUrl -Driver $driver -Url $productUrl
    
    # Select Drivers
    Write-Host "  Step 2: Clicking 'Select Drivers'..." -ForegroundColor Cyan
    $el = Find-SeElement -Driver $driver -Id 'dnd-manual-drivers' -Timeout 15
    JsClick $el
    
    # Tick BIOS row checkbox
    Write-Host "  Step 3: Ticking BIOS checkbox..." -ForegroundColor Cyan
    $spanXPath = @"
    //div[contains(@class,'dds__tr') 
                      and .//span[@class='dds__table__cell' and normalize-space(.)='BIOS']]
                //label[contains(@class,'dds__checkbox__label')]/span
"@.Trim()
    $span = Find-SeElement -Driver $driver -XPath $spanXPath
    JsClick $span
            
    # Click "Selected for download"
    Write-Host "  Step 4: Clicking 'Selected for download'..." -ForegroundColor Cyan
    $el = Find-SeElement -Driver $driver -XPath "//a[@class='dds__link dnd-pointer-cursor']"
    JsClick $el

    # Follow support‑page link
    Write-Host "  Step 5: Opening driver details..." -ForegroundColor Cyan
    $el = Find-SeElement -Driver $driver -XPath "//a[contains(@class,'text-decoration-none') and contains(@href,'/drivers/driversdetails')]"
    JsClick $el

    # Extract .exe URL matching model
    Write-Host "  Step 6: Extracting .exe URL for $modelID..." -ForegroundColor Cyan
    $exe = Find-SeElement -Driver $driver -XPath "//a[contains(@href,'.exe') and contains(@href,'$modelID')]" 

    if ($exe) {
        $downloadUrl = $exe.GetAttribute('href')
        $name = $downloadUrl.Split('/')[-1]
        
        # Extract version from name
        # e.g. "XPS9520_Precision5570_1.31.0_QSL0" -> "1.31.0"
        $pattern = '(?<=_)(\d+\.\d+\.\d+)(?=_|\.exe)'
        $m = [regex]::Match($name, $pattern)
        if ($m.Success) {
            $version = $m.Groups[1].Value
        }
        else { $null }

        Write-Host "Found URL: $downloadUrl with version $version" -ForegroundColor Green
    }
    else {
        $downloadUrl = ''
        $version = ''
        Write-Warning "No .exe link found for $modelID"
    }
    
    # Store back into the row
    $row.URL = $downloadUrl
    $row.Version = $version
    $results += $row

    Clear-Tabs $driver
}

# Exit browser
Write-Host "Cleaning up browser..." -ForegroundColor Cyan
$driver.Quit()

# Overwrite $oldModels with $newModels before updating
Copy-Item -Path $newModels -Destination $oldModels -Force

# Export updated CSV
$results | Export-Csv $newModels -NoTypeInformation
Write-Host "`n✅ All done! Updated CSV saved to $newModels" -ForegroundColor Green