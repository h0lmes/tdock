param([string]$Compiler, [string]$LazarusRoot = 'C:\lazarus',
    [string]$BuildPath)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-runner.ps1')
$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not $BuildPath) {
    $BuildPath = Join-Path $PSScriptRoot '.build\application'
}
$applicationFlags = @('-WG', '-otdock.exe')
Push-Location $projectRoot
try {
    Build-PascalProgram -Source (Join-Path $projectRoot 'terry.lpr') -BuildPath $buildPath `
        -Compiler $Compiler -LazarusRoot $LazarusRoot -Mode release -ExtraFlags $applicationFlags
    Get-Content -LiteralPath (Join-Path $buildPath 'build.log') -Tail 5
    Write-Host "Application: $(Join-Path $buildPath 'tdock.exe')"
} finally { Pop-Location }
