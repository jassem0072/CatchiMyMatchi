$jsonPath = "ai/tmp/validation_result_final_check.json"
$data = Get-Content $jsonPath -Raw | ConvertFrom-Json
$pts = @($data.positions)
$selT = 16.08
$maxNormSpeed = 0.55
$maxGapSec = 3.2
$confCutoffs = @(0.00, 0.20, 0.25, 0.28)
$relockDists = @(0.14, 0.20, 0.28, 0.35, 0.45)
$results = foreach ($confCutoff in $confCutoffs) {
    foreach ($relockDist in $relockDists) {
        $withTrack = @($pts | Where-Object { $null -ne $_.trackId })
        if ($withTrack.Count -eq 0) { continue }
        $lockedTrack = [int]($withTrack[0].trackId)
        $filtered = @($pts | Where-Object { $null -ne $_.trackId -and [int]$_.trackId -eq $lockedTrack -and ($null -eq $_.conf -or [double]$_.conf -ge $confCutoff) } | Sort-Object { [double]$_.t })
        if ($filtered.Count -eq 0) { continue }
        $startIdx = 0; $bestDt = [double]::PositiveInfinity
        for ($i=0; $i -lt $filtered.Count; $i++) {
            $dt = [math]::Abs([double]$filtered[$i].t - $selT)
            if ($dt -lt $bestDt) { $bestDt = $dt; $startIdx = $i }
        }
        $stable = New-Object System.Collections.Generic.List[object]; $stable.Add($filtered[$startIdx])
        $rejFast = 0; $rejRelock = 0
        for ($i=$startIdx+1; $i -lt $filtered.Count; $i++) {
            $prev = $stable[$stable.Count - 1]; $cur = $filtered[$i]; $dt = [double]$cur.t - [double]$prev.t
            if ($dt -le 1e-6) { continue }
            $px = if ($null -ne $prev.ncx) { [double]$prev.ncx } else { [double]$prev.cx / 1920.0 }
            $py = if ($null -ne $prev.ncy) { [double]$prev.ncy } else { [double]$prev.cy / 1080.0 }
            $cx = if ($null -ne $cur.ncx) { [double]$cur.ncx } else { [double]$cur.cx / 1920.0 }
            $cy = if ($null -ne $cur.ncy) { [double]$cur.ncy } else { [double]$cur.cy / 1080.0 }
            $dist = [math]::Sqrt([math]::Pow($cx - $px, 2) + [math]::Pow($cy - $py, 2)); $speed = $dist / $dt
            if ($dt -le $maxGapSec) { if ($speed -le $maxNormSpeed) { $stable.Add($cur) } else { $rejFast++ } }
            else { if ($dist -le $relockDist) { $stable.Add($cur) } else { $rejRelock++ } }
        }
        [pscustomobject]@{ confCutoff=$confCutoff; relockDist=$relockDist; filteredPoints=$filtered.Count; acceptedStablePoints=$stable.Count; rejectedFast=$rejFast; rejectedRelock=$rejRelock; coveragePct=[math]::Round(($stable.Count/$filtered.Count*100),2) }
    }
}
Write-Host "--- Full Sweep Results ---"
$results | Format-Table -AutoSize
Write-Host "`n--- Top 5 Combos ---"
$results | Sort-Object -Property @{Expression="acceptedStablePoints"; Descending=$true}, @{Expression="rejectedRelock"; Ascending=$true} | Select-Object -First 5 | Format-Table -AutoSize
