param(
    [string]$ModelsCsv    = "..\Dell-BIOS-Search\res\models.csv",
    [int]   $JobCount      = 10,
    [int]   $InnerThrottle = 10,
    [int]   $Bump          = 100000,
    [int]   $MajorsAhead   = 1
)

#—1) Import & prep (unchanged)—
$rows = Import-Csv -Path $ModelsCsv

$modelInfo = $rows | ForEach-Object {
    $sv        = [version]$_.Version
    $startMaj  = $sv.Minor
    $endMaj    = $startMaj + $MajorsAhead

    [PSCustomObject]@{
        Model       = $_.Model
        SeedVer     = $sv
        SeedNum     = [int]$_.Num
        VersionList = foreach ($maj in $startMaj..$endMaj) {
            0..9 | ForEach-Object { "1.$maj.$_" }
        }
    }
}

$minStart = ($modelInfo | Measure-Object SeedNum -Minimum).Minimum
$maxEnd   = ($modelInfo | ForEach-Object { $_.SeedNum + $Bump } | Measure-Object -Maximum).Maximum

$chunkSize = [math]::Ceiling(( $maxEnd - $minStart + 1 ) / $JobCount)
$chunks    = for ($i = 0; $i -lt $JobCount; $i++) {
    [PSCustomObject]@{
        Start = $minStart + $i * $chunkSize
        End   = [math]::Min($minStart + ($i + 1) * $chunkSize - 1, $maxEnd)
    }
}

$Results = [System.Collections.Concurrent.ConcurrentDictionary[string,PSCustomObject]]::new()
$Pending = [System.Collections.Concurrent.ConcurrentDictionary[string,bool]]::new()

#—2) Browser‑like GET headers (added Range)—
$Headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36"
    "Referer"    = "https://www.dell.com/support/home"
    "Range"      = "bytes=0-0"
}

#—3) Chunk script with GET+Range, 200|206 check, plus random sleep—  
$chunkScript = {
    param($modelInfo, $startID, $endID, $innerTL, $bump, $headers, $results, $pending)

    foreach ($mi in $modelInfo) {
        $pending[$mi.Model] = $true
    }

    $minDelay = [int]$minDelay
    $maxDelay = [int]$maxDelay

    ($startID..$endID) |
      ForEach-Object -Parallel {
        $n        = $_
        $modelInfo = $using:modelInfo
        $bump      = $using:bump
        $headers   = $using:headers
        $results   = $using:results
        $pending   = $using:pending
        $minDelay  = 100
        $maxDelay  = 300

        if ($pending.IsEmpty) { return }

        $folder = '{0:00000000}' -f $n

        foreach ($mi in $modelInfo) {
            if (-not $pending.ContainsKey($mi.Model)) { continue }
            if ($n -lt $mi.SeedNum -or $n -gt ($mi.SeedNum + $bump)) { continue }

            foreach ($ver in $mi.VersionList) {
                if ([version]$ver -le $mi.SeedVer) { continue }

                # handle special‑case filename
                $file = "${mi.Model}_${ver}.exe"
                if ($mi.Model -eq "XPS9520_Precision5570") {
                    $file = "${mi.Model}_${ver}_QSL0.exe"
                }

                $url = "https://dl.dell.com/FOLDER${folder}M/1/$file"

                try {
                    # GET with Range: bytes=0-0
                    $r = Invoke-WebRequest `
                        -Uri $url `
                        -Method Get `
                        -Headers $headers `
                        -MaximumRedirection 5 `
                        -ErrorAction Stop

                    # treat 200 OR 206 as success
                    if ($r.StatusCode -eq 200 -or $r.StatusCode -eq 206) {
                        $results[$mi.Model] = [PSCustomObject]@{
                            Model      = $mi.Model
                            OldVersion = $mi.SeedVer.ToString()
                            OldNum     = $mi.SeedNum
                            NewVersion = $ver
                            NewNum     = $n
                            URL        = $url
                        }
                        $null = $pending.TryRemove($mi.Model,[ref]$null)
                        break
                    }
                }
                catch {
                    # swallow 403/404/etc
                }
                finally {
                    # small random delay to avoid rate‑limiting
                    Start-Sleep -Milliseconds (Get-Random -Minimum $minDelay -Maximum $maxDelay)
                }
            }
        }
      } -ThrottleLimit $innerTL
}

#—4) Launch your jobs (passing the two new delay params)—
$jobs = foreach ($c in $chunks) {
    Start-Job -ScriptBlock $chunkScript `
      -ArgumentList (
        $modelInfo,
        $c.Start,
        $c.End,
        $InnerThrottle,
        $Bump,
        $Headers,
        $Results,
        $Pending
      )
}

#—5) Wait, collect & update your CSV (unchanged)—
Receive-Job -Job $jobs -Wait -AutoRemoveJob | Out-Null

foreach ($row in $rows) {
    if ($Results.ContainsKey($row.Model)) {
        $r = $Results[$row.Model]
        $row.Version = $r.NewVersion
        $row.Num     = $r.NewNum
        $row.URL     = $r.URL
    }
}

$rows | Export-Csv -Path $ModelsCsv -NoTypeInformation
Write-Host "Process Completed! models.csv has been updated for $($Results.Count) models" -ForegroundColor Green