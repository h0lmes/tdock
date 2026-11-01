param([string]$Compiler, [string]$LazarusRoot = 'C:\lazarus',
    [ValidateSet('apptarget', 'launchservice', 'appmetadata', 'iconservice')][string[]]$Suites = @('apptarget', 'launchservice', 'appmetadata', 'iconservice'))

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-runner.ps1')
Invoke-TestSuites -Suites $Suites -Compiler $Compiler -LazarusRoot $LazarusRoot -BuildPrefix 'app-target-'
