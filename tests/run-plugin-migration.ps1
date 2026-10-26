param([string]$Compiler = 'C:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe',
      [string]$LazarusRoot = 'C:\lazarus',
      [string[]]$Suites = @('nativeinput', 'pluginhost'))

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
foreach ($mode in @('checked', 'release')) {
    $buildPath = Join-Path $PSScriptRoot ".build\plugin-migration\$mode"
    New-Item -ItemType Directory -Path $buildPath -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $buildPath 'fixtures') -Force | Out-Null
    $flags = @('-B', '-Mdelphi', "-Fu$projectRoot", "-FU$buildPath", "-FE$buildPath",
        "-Fu$LazarusRoot\lcl\units\x86_64-win64",
        "-Fu$LazarusRoot\lcl\units\x86_64-win64\win32",
        "-Fu$LazarusRoot\components\lazutils\lib\x86_64-win64",
        "-Fu$LazarusRoot\components\lazcontrols\lib\x86_64-win64\win32")
    if ($mode -eq 'checked') { $flags += @('-Cr', '-Co', '-gl') }
    else { $flags += @('-Cr-', '-Co-', '-O3') }
    foreach ($suite in $Suites) {
        $logPath = Join-Path $buildPath "$suite-build.log"
        & $Compiler @flags (Join-Path $PSScriptRoot "${suite}_tests.lpr") *> $logPath
        if ($LASTEXITCODE -ne 0) {
            Get-Content -LiteralPath $logPath -Tail 35
            throw "Compilation failed for $suite in $mode mode."
        }
        & (Join-Path $buildPath "${suite}_tests.exe")
        if ($LASTEXITCODE -ne 0) { throw "Tests failed for $suite in $mode mode." }
    }
}
