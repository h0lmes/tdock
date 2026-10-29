param([string]$Compiler, [string]$LazarusRoot = 'C:\lazarus')

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
foreach ($mode in @('checked', 'release')) {
    $buildPath = Join-Path $PSScriptRoot ".build\windowlayout-$mode"
    New-Item -ItemType Directory -Path $buildPath -Force | Out-Null
    $flags = @('-B', '-Mdelphi', "-Fu$projectRoot", "-FU$buildPath", "-FE$buildPath")
    if ($mode -eq 'checked') { $flags += @('-Cr', '-Co', '-gl') }
    else { $flags += @('-Cr-', '-Co-', '-O3') }
    $buildLog = Join-Path $buildPath 'build.log'
    & $Compiler @flags (Join-Path $PSScriptRoot 'windowlayout_tests.lpr') *> $buildLog
    if ($LASTEXITCODE -ne 0) {
        Get-Content -LiteralPath $buildLog -Tail 35
        throw "Window layout compilation failed in $mode mode."
    }
    $testLog = Join-Path $buildPath 'test.log'
    & (Join-Path $buildPath 'windowlayout_tests.exe') *> $testLog
    $testExitCode = $LASTEXITCODE
    Get-Content -LiteralPath $testLog
    if ($testExitCode -ne 0) { throw "Window layout tests failed in $mode mode." }
}
