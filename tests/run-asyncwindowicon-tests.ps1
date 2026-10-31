param([ValidateSet('checked', 'release')][string]$Mode = 'checked')
$ErrorActionPreference = 'Stop'
$compiler = 'C:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe'
$projectRoot = Split-Path $PSScriptRoot -Parent
$buildPath = Join-Path $PSScriptRoot ".build\gap-async-icons-$Mode"
New-Item -ItemType Directory -Path $buildPath -Force | Out-Null
$flags = @('-B', '-Mdelphi', '-dWINDOW_ICON_TESTS', '-dANIMATION_TIMING_TESTS', "-Fu$projectRoot", "-FU$buildPath", "-FE$buildPath",
  '-FuC:\lazarus\lcl\units\x86_64-win64',
  '-FuC:\lazarus\lcl\units\x86_64-win64\win32',
  '-FuC:\lazarus\components\lazutils\lib\x86_64-win64',
  '-FuC:\lazarus\components\lazcontrols\lib\x86_64-win64\win32')
if ($Mode -eq 'checked') { $flags += @('-Cr', '-Co', '-gl') }
else { $flags += @('-Cr-', '-Co-', '-O3') }
& $compiler @flags (Join-Path $PSScriptRoot 'asyncwindowicon_tests.lpr') *> (Join-Path $buildPath 'build.log')
if ($LASTEXITCODE -ne 0) {
  Get-Content -LiteralPath (Join-Path $buildPath 'build.log') -Tail 30
  throw 'The async icon tests did not compile.'
}
& (Join-Path $buildPath 'asyncwindowicon_tests.exe')
if ($LASTEXITCODE -ne 0) { throw 'The async icon tests failed.' }
