param([string]$Compiler, [string]$LazarusRoot = 'C:\lazarus')

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-runner.ps1')
$buildPath = Join-Path $PSScriptRoot '.build\animation-pacing'
Build-PascalProgram -Source 'animation_pacing_probe.lpr' -BuildPath $buildPath -Compiler $Compiler -LazarusRoot $LazarusRoot -Mode release
& (Join-Path $buildPath 'animation_pacing_probe.exe') |
    Tee-Object -FilePath (Join-Path $buildPath 'results.csv')
if ($LASTEXITCODE -ne 0) { throw 'Frame pacing probe failed.' }
