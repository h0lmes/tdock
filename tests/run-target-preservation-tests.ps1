param([string]$Compiler, [string]$LazarusRoot = 'C:\lazarus',
    [string[]]$Suites = @('targetpreservation', 'dropownership', 'dropimport', 'serialization', 'launchservice', 'appmetadata', 'iconservice', 'propertylifetime', 'pluginhost', 'coremigration', 'settingssave'))

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-runner.ps1')
Invoke-TestSuites -Suites $Suites -Compiler $Compiler -LazarusRoot $LazarusRoot -BuildPrefix 'target-preservation-'
