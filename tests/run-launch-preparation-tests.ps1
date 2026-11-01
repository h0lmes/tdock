param([string]$Compiler, [string]$LazarusRoot = 'C:\lazarus',
    [string[]]$Suites = @('runthread', 'launchfailure', 'variableexpansion', 'activation', 'launchservice', 'apptarget', 'targetpreservation', 'serialization'))

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-runner.ps1')
Invoke-TestSuites -Suites $Suites -Compiler $Compiler -LazarusRoot $LazarusRoot -BuildPrefix 'launch-preparation-'
