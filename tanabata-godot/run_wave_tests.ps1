# run_wave_tests.ps1
# Headless wave testing across ALL snapshot folders in snapshots/run_*/.
# Each game over creates snapshots/run_YYYYMMDD_HHMM_wN/snapshot.json.
# This script runs headless tests for every such folder, then combines results.
#
# Usage: .\run_wave_tests.ps1
# Delete any run_* folder you don't want tested.

# ============ SETTINGS (edit these) ============
$runsPerWave  = 300       # runs per wave per snapshot
$waveMax      = 15        # max wave to test (1..N)
$parallelJobs = 3         # parallel Godot processes per snapshot
# ===============================================

$godotSteam = "${env:ProgramFiles(x86)}\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$godotExe = if ($env:GODOT_PATH) { $env:GODOT_PATH } elseif (Test-Path $godotSteam) { $godotSteam } else { "godot" }
$snapshotsBase = Join-Path $projectRoot "snapshots"

# Find all snapshot folders
$runDirs = Get-ChildItem $snapshotsBase -Directory -Filter "run_*" |
    Where-Object { Test-Path (Join-Path $_.FullName "snapshot.json") } |
    Sort-Object Name
if ($runDirs.Count -eq 0) {
    Write-Host "No snapshot folders found in $snapshotsBase"
    Write-Host "Play until game over -- a run_YYYYMMDD_HHMM_wN/ folder will be created."
    exit 1
}

Write-Host "Found $($runDirs.Count) snapshot folder(s):"
foreach ($d in $runDirs) { Write-Host "  $($d.Name)" }
Write-Host ""
Write-Host "Settings: $runsPerWave runs/wave, waves 1..$waveMax, $parallelJobs parallel jobs"
Write-Host ""

# Process each snapshot folder
foreach ($runDir in $runDirs) {
    $snapPath = Join-Path $runDir.FullName "snapshot.json"
    $outDir = $runDir.FullName -replace '\\', '/'

    # Check if already done
    $existingCsvs = @(Get-ChildItem $runDir.FullName -Filter "wave_*.csv" -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -gt 3000 }).Count
    if ($existingCsvs -ge $waveMax) {
        Write-Host "[$($runDir.Name)] Already has $existingCsvs CSVs, skipping."
        continue
    }

    # Clean old partial results
    Get-ChildItem $runDir.FullName -Filter "wave_*.csv" -ErrorAction SilentlyContinue | Remove-Item
    $marker = Join-Path $runDir.FullName "batch_done.txt"
    if (Test-Path $marker) { Remove-Item $marker }

    Write-Host "[$($runDir.Name)] Starting $runsPerWave runs x $waveMax waves..."

    # Launch parallel chunks
    $totalWaves = $waveMax
    $chunkSize = [math]::Ceiling($totalWaves / $parallelJobs)
    for ($i = 0; $i -lt $parallelJobs; $i++) {
        $cMin = 1 + $i * $chunkSize
        $cMax = [math]::Min(1 + ($i + 1) * $chunkSize - 1, $waveMax)
        if ($cMin -gt $waveMax) { break }
        & $godotExe --headless --path $projectRoot -- --snapshot $snapPath --out-dir $outDir --wave $cMin --wave-max $cMax --runs $runsPerWave --seed 0
    }

    # Poll until done
    $startTime = Get-Date
    while ($true) {
        Start-Sleep -Seconds 10
        $goodCsvs = @(Get-ChildItem $runDir.FullName -Filter "wave_*.csv" -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -gt 3000 }).Count
        $elapsed = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
        Write-Host "  $($runDir.Name): $elapsed min, $goodCsvs / $totalWaves waves..."
        if ($goodCsvs -ge $totalWaves) { break }
        if ($elapsed -gt 240) { Write-Host "  Timeout!"; break }
    }
    Write-Host "[$($runDir.Name)] Done."
    Write-Host ""
}

# Combine results from all snapshots into combined/ folder
$combinedDir = Join-Path $snapshotsBase "combined"
if (-not (Test-Path $combinedDir)) { New-Item -ItemType Directory -Path $combinedDir | Out-Null }
Get-ChildItem $combinedDir -Filter "*.csv" -ErrorAction SilentlyContinue | Remove-Item
Get-ChildItem $combinedDir -Filter "*.png" -ErrorAction SilentlyContinue | Remove-Item

Write-Host "Combining results from $($runDirs.Count) snapshots into combined/..."

for ($w = 1; $w -le $waveMax; $w++) {
    $outFile = Join-Path $combinedDir "wave_$w.csv"
    $headerWritten = $false
    foreach ($runDir in $runDirs) {
        $csvPath = Join-Path $runDir.FullName "wave_$w.csv"
        if (-not (Test-Path $csvPath)) { continue }
        $lines = Get-Content $csvPath -Encoding UTF8
        if ($lines.Count -le 1) { continue }
        if (-not $headerWritten) {
            # Add snapshot_id column to header
            ($lines[0] + ",snapshot_id") | Out-File $outFile -Encoding UTF8
            $headerWritten = $true
        }
        $snapId = $runDir.Name
        for ($li = 1; $li -lt $lines.Count; $li++) {
            if ($lines[$li].Trim()) {
                ($lines[$li] + ",$snapId") | Out-File $outFile -Encoding UTF8 -Append
            }
        }
    }
}

$combinedCsvs = @(Get-ChildItem $combinedDir -Filter "wave_*.csv" -ErrorAction SilentlyContinue).Count
Write-Host "Combined: $combinedCsvs CSVs in $combinedDir"
Write-Host ""
Write-Host "Run plots: py -3 scripts\plot_wave_runs.py snapshots\combined"
Write-Host "Or per-snapshot: py -3 scripts\plot_wave_runs.py snapshots\run_YYYYMMDD_HHMM_wN"
