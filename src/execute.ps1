param(
    [String]$WSID = "$PSScriptRoot\..\res\WSID.txt",
    [int]   $Throttle = 10
)
$modelsFile = "$PSScriptRoot\..\res\newModels.csv"
$localLogFile = "$PSScriptRoot\..\Updates.log"

if (-not (Test-Path $modelsFile)) {
    Write-Error "No models file found at '$modelsFile'"
    exit 1
}

if (-not (Test-Path $WSID)) {
    Write-Error "No WSID file found at '$WSID'"
    exit 1
}

if (-not (Test-Path $localLogFile)) {
    New-Item -Path $localLogFile -ItemType File -Force | Out-Null;
}

$hostNames = Get-Content -Path $WSID | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
Write-Host "Starting processing for $($hostNames.Count) computers."

$processComputer = {
    $computer = $_
    $modelsFile = $using:modelsFile
    $localLogFile = $using:localLogFile
    $parsedIP = $null
    
    if ([System.Net.IPAddress]::TryParse($computer, [ref]$parsedIP)) {
        $ip = $parsedIP
    }

    else {
        # Try to resolve a single IP
        try {
            $ip = [System.Net.Dns]::GetHostAddresses("$computer")[0]
        }
        catch {
            Write-Error "[$computer] DNS lookup failed: $_"
            Add-Content -Path $using:localLogFile -Value "[$computer] DNS lookup failed: $_"
            return
        }
    
        # Reverse-DNS lookup + name check
        try {
            $hostEntry = [System.Net.Dns]::GetHostEntry($ip)
            $resolvedName = $hostEntry.HostName.Split('.')[0]
        
            if ($resolvedName -ne $computer) {
                Write-Warning "[$computer] Reverse-DNS returned '$resolvedName' (expected '$computer'), skipping..."
                Add-Content -Path $using:localLogFile -Value "[$computer] Incorrect reverse-DNS: $resolvedName"
                return
            }
        }
        catch [System.Net.Sockets.SocketException] {
            # 1722 is RPC_S_SERVER_UNAVAILABLE
            if ($_.Exception.ErrorCode -eq 1722) {
                Write-Warning "[$computer] RPC Server unavailable, skipping..."
                Add-Content -Path $using:localLogFile -Value "[$computer] RPC server unavailable"
                return
            }
            else { 
                Write-Error "[$computer] SocketException during reverse-DNS: $_"
                Add-Content -Path $using:localLogFile -Value "[$computer] SocketException: $_"
                return
            }
        }
        catch {
            Write-Error "[$computer] Unexpected error during reverse-DNS: $_"
            Add-Content -Path $using:localLogFile -Value "[$computer] Reverse-DNS error: $_"
            return
        }
    }
    
    # Get system model and convert spaces to underscores (e.g., "Latitude 5320" to "Latitude_5320")
    try {
        $model = (systeminfo /s $ip | Where-Object { $_ -like "*System Model*" }).Split(":")[1].Trim()
        $modelType = $model.Split(' ')[0]
        $modelNum = $model.Split(' ')[1]
    }
    catch {
        Write-Error "PsExec failed to retrieve model: $_"
        return
    }
    
    # Import CSV
    $rows = Import-Csv -Path $modelsFile
    
    # Match CSV row with model
    $match = $rows | Where-Object {
        $_.Product -like "*$modelType*" -and $_.Product -like "*$modelNum*" 
    }
    
    if ($match) {
        Write-Host "Found match in CSV: $($match.Product)" -ForegroundColor Green
        
        $url = $match.URL
        $fileName = "$($modelType)_$($modelNum)_$($match.Version).exe"
        $dest = "C:\temp\biosUpdates\$fileName"
    }
    
    else {
        Write-Error "Failed to find a match for model: $model"
        return
    }
    
    $headers
    $local = $true
    $biosCmd = "C:\temp\biosUpdates\$fileName /f /l=`"update.log`" /p=`"biospwd`" /bls"
    $psCmd = "Invoke-WebRequest ``
    -Uri '$url' ``
    -Method GET ``
    -Headers @{ ``
    'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36'; ``
    'Referer'= 'https://www.dell.com/' ``
    } ``
    -OutFile '$dest' ``
    -ErrorAction Stop"
    
    if ($computer -eq $env:COMPUTERNAME) {
        Invoke-Expression $psCmd
        Invoke-Expression $biosCmd
        Write-Host "Local Detected!" -ForegroundColor Green
    }
    else {
        $local = $false
        if (-not (Test-Path "\\$ip\C$\temp\biosUpdates")) {
            New-Item -ItemType Directory -Force -Path "\\$ip\C$\temp\biosUpdates"
            Write-Host "`n"
        }
        & psexec -accepteula -nobanner -s -h -i \\$ip pwsh -c "$psCmd; & $biosCmd"
    }
    Write-Host "`n✅ Copying Complete!" -ForegroundColor Green

    $Attempt       = 0
    $MaxAttempts   = 10
    $SleepSeconds  = 60

        while ($true) {
        $log = if ($local) {
            "C:\temp\biosUpdates\update.log"
        } else {
            "\\$ip\C$\temp\biosUpdates\update.log"
        }

        # 1) If the file doesn't exist yet, wait and retry
        if (-not (Test-Path $log)) {
            $Attempt++
            if ($Attempt -ge $MaxAttempts) {
                Write-Warning "[$computer] Log never appeared after $MaxAttempts attempts – skipping."
                return
            }
            Write-Host "[$computer] Log not found (attempt $Attempt/$MaxAttempts), sleeping $SleepSeconds s…" -ForegroundColor Yellow
            Start-Sleep -Seconds $SleepSeconds
            continue
        }

        try {
            # 2) Now attempt to read it
            $Lines = Get-Content -Path $log -ErrorAction Stop
            Write-Host "[$computer] Log read successfully." -ForegroundColor Green
            break
        }
        catch [System.IO.IOException] {
            # sharing violation?
            $win32Code = $_.Exception.HResult -band 0x0000FFFF
            if ($win32Code -eq 32) {
                $Attempt++
                if ($Attempt -ge $MaxAttempts) {
                    Write-Warning "[$computer] Log still locked after $MaxAttempts attempts – skipping."
                    return
                }
                Write-Host "[$computer] Log locked (attempt $Attempt/$MaxAttempts), sleeping $SleepSeconds s…" -ForegroundColor Yellow
                Start-Sleep -Seconds $SleepSeconds
                continue
            }
            throw
        }
    }

    $Lines | Out-File $using:localLogFile -Append
}   

$hostNames | ForEach-Object -Parallel $processComputer -ThrottleLimit $Throttle 