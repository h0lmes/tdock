param([ValidateSet('checked', 'release')][string]$Mode = 'checked',
    [string]$Compiler, [string]$LazarusRoot = 'C:\lazarus')

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-runner.ps1')
Invoke-TestSuites -Suites @('asyncwindowicon') -Compiler $Compiler -LazarusRoot $LazarusRoot -Modes @($Mode)
