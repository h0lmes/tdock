param([string]$Compiler, [string]$LazarusRoot = 'C:\lazarus')

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-runner.ps1')
$buildPath = Join-Path $PSScriptRoot '.build\interaction-smoke'
Build-PascalProgram -Source 'interaction_smoke.lpr' -BuildPath $buildPath -Compiler $Compiler -LazarusRoot $LazarusRoot -Mode release
& (Join-Path $buildPath 'interaction_smoke.exe')
if ($LASTEXITCODE -ne 0) { throw 'Interaction smoke tests failed.' }
