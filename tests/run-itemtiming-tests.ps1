param([string]$Compiler = 'C:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe',
      [string]$LazarusRoot = 'C:\lazarus')

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$buildPath = Join-Path $PSScriptRoot '.build\itemtiming-checked'
New-Item -ItemType Directory -Path $buildPath -Force | Out-Null
$flags = @('-B', '-Mdelphi', '-Cr', '-Co', '-gl', "-Fu$projectRoot",
    "-FU$buildPath", "-FE$buildPath",
    "-Fu$LazarusRoot\lcl\units\x86_64-win64",
    "-Fu$LazarusRoot\lcl\units\x86_64-win64\win32",
    "-Fu$LazarusRoot\components\lazutils\lib\x86_64-win64",
    "-Fu$LazarusRoot\components\lazcontrols\lib\x86_64-win64\win32")
$logPath = Join-Path $buildPath 'build.log'
& $Compiler @flags (Join-Path $PSScriptRoot 'itemtiming_tests.lpr') *> $logPath
if ($LASTEXITCODE -ne 0) {
    Get-Content -LiteralPath $logPath -Tail 30
    throw 'Item timing compilation failed.'
}
& (Join-Path $buildPath 'itemtiming_tests.exe')
if ($LASTEXITCODE -ne 0) { throw 'Item timing tests failed.' }
