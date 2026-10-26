param([string]$Compiler = 'C:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe',
      [string]$LazarusRoot = 'C:\lazarus')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
foreach ($mode in @('checked', 'release')) {
    $buildPath = Join-Path $PSScriptRoot ".build\$mode"
    New-Item -ItemType Directory -Path $buildPath -Force | Out-Null
    $flags = @('-B', '-Mdelphi', "-Fu$PSScriptRoot", "-Fu$projectRoot", "-FU$buildPath", "-FE$buildPath",
        "-Fu$LazarusRoot\lcl\units\x86_64-win64",
        "-Fu$LazarusRoot\lcl\units\x86_64-win64\win32",
        "-Fu$LazarusRoot\components\lazutils\lib\x86_64-win64")
    if ($mode -eq 'checked') { $flags += @('-Cr', '-Co', '-gl') }
    else { $flags += @('-Cr-', '-Co-', '-O2') }
    & $Compiler @flags (Join-Path $PSScriptRoot 'check_source.lpr') *> (Join-Path $buildPath 'build.log')
    if ($LASTEXITCODE -ne 0) {
        Get-Content -LiteralPath (Join-Path $buildPath 'build.log') -Tail 25
        throw "Source check compilation failed: $mode"
    }
    & (Join-Path $buildPath 'check_source.exe') | Tee-Object -FilePath (Join-Path $buildPath 'test.log')
    if ($LASTEXITCODE -ne 0) { throw "Source checks failed: $mode" }
}
