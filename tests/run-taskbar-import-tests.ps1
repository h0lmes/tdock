param([string]$Compiler, [string]$LazarusRoot = 'C:\lazarus')

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-runner.ps1')
Invoke-TestSuites -Suites @('taskbarimport') -Compiler $Compiler -LazarusRoot $LazarusRoot
