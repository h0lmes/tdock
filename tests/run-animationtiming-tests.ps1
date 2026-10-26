param([string]$Compiler = 'C:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe',
      [string]$LazarusRoot = 'C:\lazarus',
      [ValidateSet('checked', 'release')][string]$Mode = 'checked')

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$buildPath = Join-Path $PSScriptRoot ".build\animationtiming-$Mode"
New-Item -ItemType Directory -Path $buildPath -Force | Out-Null
$flags = @('-B', '-Mdelphi', '-dANIMATION_TIMING_TESTS', "-Fu$projectRoot", "-FU$buildPath", "-FE$buildPath",
    "-Fu$LazarusRoot\lcl\units\x86_64-win64",
    "-Fu$LazarusRoot\lcl\units\x86_64-win64\win32",
    "-Fu$LazarusRoot\components\lazutils\lib\x86_64-win64",
    "-Fu$LazarusRoot\components\lazcontrols\lib\x86_64-win64\win32")
if ($Mode -eq 'checked') { $flags += @('-Cr', '-Co', '-gl') }
else { $flags += @('-Cr-', '-Co-', '-O3') }
$logPath = Join-Path $buildPath 'build.log'
& $Compiler @flags (Join-Path $PSScriptRoot 'animationtiming_tests.lpr') *> $logPath
if ($LASTEXITCODE -ne 0) {
    Get-Content -LiteralPath $logPath -Tail 35
    throw 'Animation timing compilation failed.'
}
& (Join-Path $buildPath 'animationtiming_tests.exe')
if ($LASTEXITCODE -ne 0) { throw 'Animation timing tests failed.' }
