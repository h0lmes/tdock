param([string]$Compiler, [string]$LazarusRoot = 'C:\lazarus',
    [ValidateSet('checked', 'release')][string]$Mode = 'checked')

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-runner.ps1')
Invoke-TestSuites -Suites @('animationtiming') -Compiler $Compiler -LazarusRoot $LazarusRoot -Modes @($Mode)
