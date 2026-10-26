param([string]$Compiler = 'C:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe',
      [string]$LazarusRoot = 'C:\lazarus',
      [string[]]$Suites = @('dropimport', 'dropownership', 'dropinsertion', 'coremigration', 'serialization'))

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
foreach ($mode in @('checked', 'release')) {
    foreach ($suite in $Suites) {
        $buildPath = Join-Path $PSScriptRoot ".build\drop-import-$suite-$mode"
        New-Item -ItemType Directory -Path $buildPath -Force | Out-Null
        $flags = @('-B', '-Mdelphi', "-Fu$projectRoot", "-FU$buildPath", "-FE$buildPath",
            "-Fu$LazarusRoot\lcl\units\x86_64-win64",
            "-Fu$LazarusRoot\lcl\units\x86_64-win64\win32",
            "-Fu$LazarusRoot\components\lazutils\lib\x86_64-win64",
            "-Fu$LazarusRoot\components\lazcontrols\lib\x86_64-win64\win32")
        if ($mode -eq 'checked') { $flags += @('-Cr', '-Co', '-gl') }
        else { $flags += @('-Cr-', '-Co-', '-O3') }
        & $Compiler @flags (Join-Path $PSScriptRoot "${suite}_tests.lpr") *> (Join-Path $buildPath 'build.log')
        if ($LASTEXITCODE -ne 0) {
            Get-Content -LiteralPath (Join-Path $buildPath 'build.log') -Tail 25
            throw "Compilation failed for $suite in $mode mode."
        }
        Write-Host "Running $suite tests in $mode mode."
        & (Join-Path $buildPath "${suite}_tests.exe") | Tee-Object -FilePath (Join-Path $buildPath 'test.log')
        if ($LASTEXITCODE -ne 0) { throw "Tests failed for $suite in $mode mode." }
    }
}
