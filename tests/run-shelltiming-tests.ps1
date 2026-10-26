param([string]$Compiler, [string]$LazarusRoot = 'C:\lazarus',
    [ValidateSet('checked', 'release')][string]$Mode = 'checked')

$ErrorActionPreference = 'Stop'
if (-not $Compiler) {
    $command = Get-Command fpc.exe -ErrorAction SilentlyContinue
    if ($command) { $Compiler = $command.Source }
    else {
        $Compiler = Get-ChildItem "$LazarusRoot\fpc\*\bin\x86_64-win64\fpc.exe" |
            Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
}
if (-not $Compiler) { throw 'Specify the Free Pascal compiler with -Compiler.' }
$projectRoot = Split-Path $PSScriptRoot -Parent
$buildPath = Join-Path $PSScriptRoot ".build\shelltiming-$Mode"
New-Item -ItemType Directory -Path $buildPath -Force | Out-Null
$flags = @('-B', '-Mdelphi', "-Fu$projectRoot", "-FU$buildPath", "-FE$buildPath",
    "-Fu$LazarusRoot\lcl\units\x86_64-win64",
    "-Fu$LazarusRoot\lcl\units\x86_64-win64\win32",
    "-Fu$LazarusRoot\components\lazutils\lib\x86_64-win64",
    "-Fu$LazarusRoot\components\lazcontrols\lib\x86_64-win64\win32")
if ($Mode -eq 'checked') { $flags += @('-Cr', '-Co', '-gl') }
else { $flags += @('-Cr-', '-Co-', '-O3') }
& $Compiler @flags (Join-Path $PSScriptRoot 'shelltiming_tests.lpr') *> (Join-Path $buildPath 'build.log')
if ($LASTEXITCODE -ne 0) {
    Get-Content -LiteralPath (Join-Path $buildPath 'build.log') -Tail 35
    throw 'Shell timing test compilation failed.'
}
& (Join-Path $buildPath 'shelltiming_tests.exe')
if ($LASTEXITCODE -ne 0) { throw 'Shell timing tests failed.' }
