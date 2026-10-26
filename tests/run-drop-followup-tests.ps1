param([string]$Compiler = 'C:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe',
      [string]$LazarusRoot = 'C:\lazarus',
      [string[]]$Suites = @('dropvisual', 'appmetadata'))

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
foreach ($mode in @('checked', 'release')) {
    foreach ($suite in $Suites) {
        $buildPath = Join-Path $PSScriptRoot ".build\$suite-$mode"
        New-Item -ItemType Directory -Path $buildPath -Force | Out-Null
        $flags = @('-B', '-Mdelphi', '-dICONSERVICE_TESTS', "-Fu$projectRoot", "-FU$buildPath", "-FE$buildPath",
            "-Fu$LazarusRoot\lcl\units\x86_64-win64",
            "-Fu$LazarusRoot\lcl\units\x86_64-win64\win32",
            "-Fu$LazarusRoot\components\lazutils\lib\x86_64-win64",
            "-Fu$LazarusRoot\components\lazcontrols\lib\x86_64-win64\win32")
        if ($mode -eq 'checked') { $flags += @('-Cr', '-Co', '-gl') }
        else { $flags += @('-Cr-', '-Co-', '-O3') }
        $logPath = Join-Path $buildPath 'build.log'
        & $Compiler @flags (Join-Path $PSScriptRoot "${suite}_tests.lpr") *> $logPath
        if ($LASTEXITCODE -ne 0) {
            Get-Content -LiteralPath $logPath -Tail 30
            throw "Compilation failed for $suite in $mode mode."
        }
        Write-Host "Running $suite tests in $mode mode."
        & (Join-Path $buildPath "${suite}_tests.exe")
        if ($LASTEXITCODE -ne 0) { throw "Tests failed for $suite in $mode mode." }
    }
}
