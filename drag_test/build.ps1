param([string]$Compiler = 'C:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe',
      [string]$LazarusRoot = 'C:\lazarus')
$ErrorActionPreference = 'Stop'
$buildPath = Join-Path $PSScriptRoot '.build'
New-Item -ItemType Directory -Path $buildPath -Force | Out-Null
$flags = @('-B', '-Mdelphi', '-O2', '-WG', '-oDragTest.exe', "-Fu$PSScriptRoot",
    "-FU$buildPath", "-FE$PSScriptRoot",
    "-Fu$LazarusRoot\lcl\units\x86_64-win64",
    "-Fu$LazarusRoot\lcl\units\x86_64-win64\win32",
    "-Fu$LazarusRoot\components\lazutils\lib\x86_64-win64")
& $Compiler @flags (Join-Path $PSScriptRoot 'drag_test.lpr') *> (Join-Path $buildPath 'build.log')
if ($LASTEXITCODE -ne 0) {
    Get-Content -LiteralPath (Join-Path $buildPath 'build.log') -Tail 30
    throw 'Drag test application build failed.'
}
Get-Content -LiteralPath (Join-Path $buildPath 'build.log') -Tail 4
Write-Host "Application: $(Join-Path $PSScriptRoot 'DragTest.exe')"
