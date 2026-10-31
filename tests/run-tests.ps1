param([string]$Compiler, [string]$LazarusRoot = 'C:\lazarus')

$ErrorActionPreference = 'Stop'
if (-not $Compiler) {
    $command = Get-Command fpc.exe -ErrorAction SilentlyContinue
    if ($command) {
        $Compiler = $command.Source
    } else {
        $Compiler = Get-ChildItem 'C:\lazarus\fpc\*\bin\x86_64-win64\fpc.exe' |
            Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
}
if (-not $Compiler) { throw 'Specify the Free Pascal compiler with -Compiler.' }

$projectRoot = Split-Path $PSScriptRoot -Parent
foreach ($mode in @('checked', 'release')) {
    foreach ($suite in @('itemmodel', 'itemcollection', 'itemidentity', 'itemmanager', 'propertylifetime', 'runthread', 'coremigration', 'itemregistry', 'itemhost', 'subitemlifetime', 'settingssave', 'docklayout', 'tasksync', 'windowlayout', 'nativeinput', 'pluginhost', 'serialization', 'docktiming', 'framepacing', 'animationcurve', 'hotkey', 'animationtiming', 'itemtiming', 'shelltiming', 'dropownership', 'appmetadata', 'iconservice', 'asyncwindowicon', 'apptarget', 'launchservice', 'dropimport', 'targetpreservation', 'launchfailure', 'variableexpansion', 'activation')) {
        $buildPath = Join-Path $PSScriptRoot ".build\$suite-$mode"
        New-Item -ItemType Directory -Path $buildPath -Force | Out-Null
        $flags = @('-B', '-Mdelphi', "-Fu$projectRoot", "-FU$buildPath", "-FE$buildPath")
        if ($mode -eq 'checked') { $flags += @('-Cr', '-Co', '-gl') }
        else { $flags += @('-Cr-', '-Co-', '-O3') }
        if ($suite -in @('runthread', 'launchfailure')) { $flags += '-dRUNTHREAD_TESTS' }
        if ($suite -eq 'apptarget') { $flags += '-dPACKAGEDAPP_TESTS' }
        if ($suite -in @('appmetadata', 'iconservice')) { $flags += '-dICONSERVICE_TESTS' }
        if ($suite -eq 'asyncwindowicon') { $flags += @('-dWINDOW_ICON_TESTS', '-dANIMATION_TIMING_TESTS') }
        if ($suite -eq 'animationtiming') { $flags += '-dANIMATION_TIMING_TESTS' }
        if ($suite -in @('itemmanager', 'itemidentity', 'propertylifetime', 'coremigration', 'pluginhost', 'nativeinput', 'subitemlifetime', 'serialization', 'docklayout', 'animationtiming', 'itemtiming', 'shelltiming', 'dropownership', 'appmetadata', 'iconservice', 'asyncwindowicon', 'apptarget', 'launchservice', 'dropimport', 'targetpreservation', 'launchfailure', 'variableexpansion')) {
            $flags += @(
                "-Fu$LazarusRoot\lcl\units\x86_64-win64",
                "-Fu$LazarusRoot\lcl\units\x86_64-win64\win32",
                "-Fu$LazarusRoot\components\lazutils\lib\x86_64-win64",
                "-Fu$LazarusRoot\components\lazcontrols\lib\x86_64-win64\win32"
            )
        }
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

Write-Host 'Running Windows interaction smoke tests with application build flags.'
& (Join-Path $PSScriptRoot 'run-interaction-smoke.ps1') -Compiler $Compiler -LazarusRoot $LazarusRoot
