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
$buildPath = Join-Path $PSScriptRoot '.build\application'
New-Item -ItemType Directory -Path $buildPath -Force | Out-Null
$flags = @('-B', '-Mdelphi', '-O3', '-WG', '-otdock.exe', "-Fu$projectRoot",
    "-FU$buildPath", "-FE$buildPath",
    "-Fu$LazarusRoot\lcl\units\x86_64-win64",
    "-Fu$LazarusRoot\lcl\units\x86_64-win64\win32",
    "-Fu$LazarusRoot\components\lazutils\lib\x86_64-win64",
    "-Fu$LazarusRoot\components\lazcontrols\lib\x86_64-win64\win32")
$logPath = Join-Path $buildPath 'build.log'
Push-Location $projectRoot
try {
    & $Compiler @flags (Join-Path $projectRoot 'terry.lpr') *> $logPath
    if ($LASTEXITCODE -ne 0) {
        Get-Content -LiteralPath $logPath -Tail 40
        throw 'Application compilation failed.'
    }
    Get-Content -LiteralPath $logPath -Tail 5
    Write-Host "Application: $(Join-Path $buildPath 'tdock.exe')"
} finally { Pop-Location }
