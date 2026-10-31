param([string]$Compiler = 'C:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe')

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$buildPath = Join-Path $PSScriptRoot '.build\animation-pacing'
New-Item -ItemType Directory -Path $buildPath -Force | Out-Null
$flags = @('-B', '-Mdelphi', '-Cr-', '-Co-', '-O3', "-Fu$projectRoot",
    "-FU$buildPath", "-FE$buildPath")
& $Compiler @flags (Join-Path $PSScriptRoot 'animation_pacing_probe.lpr') *> (Join-Path $buildPath 'build.log')
if ($LASTEXITCODE -ne 0) {
    Get-Content -LiteralPath (Join-Path $buildPath 'build.log') -Tail 25
    throw 'Frame pacing probe compilation failed.'
}
& (Join-Path $buildPath 'animation_pacing_probe.exe') |
    Tee-Object -FilePath (Join-Path $buildPath 'results.csv')
if ($LASTEXITCODE -ne 0) { throw 'Frame pacing probe failed.' }
