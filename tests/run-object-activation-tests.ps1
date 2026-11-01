param([string]$Compiler, [string]$LazarusRoot = 'C:\lazarus',
    [string[]]$Suites = @('objectactivation', 'activation', 'launchservice', 'apptarget', 'documentdrop', 'dropinsertion'))

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-runner.ps1')
Invoke-TestSuites -Suites $Suites -Compiler $Compiler -LazarusRoot $LazarusRoot -BuildPrefix 'wo13-17-'
