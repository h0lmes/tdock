param([string]$Compiler, [string]$LazarusRoot = 'C:\lazarus',
    [string[]]$Suites = @('dropvisual', 'appmetadata'))

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-runner.ps1')
Invoke-TestSuites -Suites $Suites -Compiler $Compiler -LazarusRoot $LazarusRoot
