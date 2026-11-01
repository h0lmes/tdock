param([string]$Compiler, [string]$LazarusRoot = 'C:\lazarus',
    [string[]]$Suites = @('dropimport', 'dropownership', 'dropinsertion', 'coremigration', 'serialization'))

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-runner.ps1')
Invoke-TestSuites -Suites $Suites -Compiler $Compiler -LazarusRoot $LazarusRoot -BuildPrefix 'drop-import-'
