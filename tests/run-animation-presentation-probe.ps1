param(
    [ValidateSet(60, 120)][int[]]$Rates = @(60),
    [switch]$SkipBuild,
    [switch]$BuildOnly,
    [switch]$WithoutIconStress,
    [switch]$TimerControl,
    [switch]$FlushControl,
    [switch]$GdiFlushControl,
    [switch]$NativeControl,
    [string]$Compiler,
    [string]$CppCompiler = 'C:\Code\mingw64\bin\g++.exe',
    [string]$LazarusRoot = 'C:\lazarus'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-runner.ps1')
$buildPath = Join-Path $PSScriptRoot '.build\animation-present'
New-Item -ItemType Directory -Path $buildPath -Force | Out-Null
$captureExe = Join-Path $buildPath 'animation_present_capture.exe'
$probeExe = Join-Path $buildPath 'animation_present_probe.exe'
if (-not $SkipBuild) {
    & $CppCompiler '-std=c++17' '-O2' '-Wall' '-Wextra' '-static' `
        (Join-Path $PSScriptRoot 'animation_present_capture.cpp') '-o' $captureExe `
        '-ld3d11' '-ldxgi' '-lgdi32' '-luser32' '-luuid' *> (Join-Path $buildPath 'capture-build.log')
    if ($LASTEXITCODE -ne 0) { throw 'Desktop capture compilation failed.' }
    Build-PascalProgram -Source 'animation_present_probe.lpr' -BuildPath $buildPath `
        -Compiler $Compiler -LazarusRoot $LazarusRoot -Mode release -LogName 'probe-build.log'
}
if ($BuildOnly) { Write-Host "Presentation tools: $buildPath"; return }

foreach ($hz in $Rates) {
    $prefix = Join-Path $buildPath "${hz}hz"
    if ($NativeControl) { $prefix += '-native-control' }
    $ready = "$prefix.ready"
    $submitted = "$prefix-submitted.csv"
    $presented = "$prefix-presented.csv"
    if (Test-Path -LiteralPath $ready) { Remove-Item -LiteralPath $ready }
    $probe = $null
    $capture = $null
    try {
        $probeArguments = @($hz, "`"$ready`"", "`"$submitted`"")
        $selectedProbe = $probeExe
        if ($NativeControl) { $selectedProbe = $captureExe; $probeArguments = @('control', $hz, "`"$ready`"", "`"$submitted`"") }
        if ($NativeControl) { }
        elseif ($GdiFlushControl) { $probeArguments += 'gdi' }
        elseif ($FlushControl) { $probeArguments += 'flush' }
        elseif ($TimerControl) { $probeArguments += 'timer' }
        elseif (-not $WithoutIconStress) { $probeArguments += 'stress' }
        $probe = Start-Process -FilePath $selectedProbe -ArgumentList $probeArguments `
            -PassThru -WindowStyle Hidden -RedirectStandardOutput "$prefix-probe.log" -RedirectStandardError "$prefix-probe.err"
        $null = $probe.Handle
        $capture = Start-Process -FilePath $captureExe -ArgumentList @('capture', $probe.Id, "`"$presented`"", "`"$ready`"") `
            -PassThru -WindowStyle Hidden -RedirectStandardOutput "$prefix-capture.log" -RedirectStandardError "$prefix-capture.err"
        $null = $capture.Handle
        if (-not $probe.WaitForExit(22000)) { throw 'Presentation probe timed out.' }
        $probe.Refresh()
        if ($probe.ExitCode -ne 0) {
            Get-Content -LiteralPath "$prefix-probe.err"
            throw "Presentation probe failed at $hz Hz (exit $($probe.ExitCode))."
        }
        if (-not $capture.WaitForExit(5000)) { throw 'Desktop capture timed out.' }
        $capture.Refresh()
        if ($capture.ExitCode -ne 0) {
            Get-Content -LiteralPath "$prefix-capture.err"
            throw "Desktop capture failed at $hz Hz."
        }
        $send = @(Import-Csv -LiteralPath $submitted)
        $seen = @(Import-Csv -LiteralPath $presented)
        if ($send.Count -ne 240) { throw 'The probe did not submit all 240 frames.' }
        $actual = [double]$send[-1].display_hz
        $effective = [double]$send[-1].effective_hz
        if ([Math]::Abs($actual - $hz) -gt 1) { throw "Physical display is $actual Hz; requested $hz Hz." }
        $frequency = [Diagnostics.Stopwatch]::Frequency
        $intervals = @()
        $submissionIntervals = @()
        $drawDurations = @()
        $sequenceGaps = [int]$seen[0].sequence - 1
        $overruns = 0
        for ($index = 1; $index -lt $seen.Count; $index++) {
            $intervals += 1000 * ([double]$seen[$index].present_qpc - [double]$seen[$index - 1].present_qpc) / $frequency
            $sequenceGaps += [int]$seen[$index].sequence - [int]$seen[$index - 1].sequence - 1
        }
        $sequenceGaps += 240 - [int]$seen[-1].sequence
        foreach ($entry in $seen) { if ([int]$entry.accumulated_frames -gt 1) { $overruns++ } }
        for ($index = 0; $index -lt $send.Count; $index++) {
            $drawDurations += 1000 * ([double]$send[$index].submit_qpc - [double]$send[$index].sample_qpc) / $frequency
            if ($index -gt 0) {
                $submissionIntervals += 1000 * ([double]$send[$index].sample_qpc - [double]$send[$index - 1].sample_qpc) / $frequency
            }
        }
        $submissionSorted = @($submissionIntervals | Sort-Object)
        $submissionMeasure = $submissionIntervals | Measure-Object -Average -Maximum -Minimum
        $drawMeasure = $drawDurations | Measure-Object -Average -Maximum
        $sorted = @($intervals | Sort-Object)
        $measure = $intervals | Measure-Object -Average -Maximum
        $result = [pscustomobject]@{
            requested_hz = $hz; display_hz = $actual; effective_hz = $effective
            clock_source = $send[-1].clock_source; submitted = $send.Count; captured = $seen.Count
            missing_sequences = $sequenceGaps; capture_overruns = $overruns
            mean_ms = [Math]::Round($measure.Average, 3)
            p95_ms = [Math]::Round($sorted[[Math]::Ceiling($sorted.Count * 0.95) - 1], 3)
            max_ms = [Math]::Round($measure.Maximum, 3)
            submission_mean_ms = [Math]::Round($submissionMeasure.Average, 3)
            submission_p95_ms = [Math]::Round($submissionSorted[[Math]::Ceiling($submissionSorted.Count * 0.95) - 1], 3)
            submission_max_ms = [Math]::Round($submissionMeasure.Maximum, 3)
            submission_min_ms = [Math]::Round($submissionMeasure.Minimum, 3)
            draw_mean_ms = [Math]::Round($drawMeasure.Average, 3)
            draw_max_ms = [Math]::Round($drawMeasure.Maximum, 3)
        }
        $result | Export-Csv -LiteralPath "$prefix-results.csv" -NoTypeInformation
        $result | Format-List
        Get-Content -LiteralPath "$prefix-probe.log"
        Get-Content -LiteralPath "$prefix-capture.log"
    }
    finally {
        foreach ($process in @($capture, $probe)) {
            if ($null -ne $process) {
                $process.Refresh()
                if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
                $process.Dispose()
            }
        }
    }
}
