param([string]$Compiler = 'C:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe',
      [string]$LazarusRoot = 'C:\lazarus',
      [string[]]$Suites = @('objectactivation', 'activation', 'launchservice', 'apptarget', 'documentdrop', 'dropinsertion'))
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
foreach ($mode in @('checked', 'release')) {
    foreach ($suite in $Suites) {
        $buildPath = Join-Path $PSScriptRoot ".build\wo13-17-$suite-$mode"
        New-Item -ItemType Directory -Path $buildPath -Force | Out-Null
        $flags = @('-B', '-Mdelphi', "-Fu$projectRoot", "-FU$buildPath", "-FE$buildPath",
            "-Fu$LazarusRoot\lcl\units\x86_64-win64", "-Fu$LazarusRoot\lcl\units\x86_64-win64\win32",
            "-Fu$LazarusRoot\components\lazutils\lib\x86_64-win64",
            "-Fu$LazarusRoot\components\lazcontrols\lib\x86_64-win64\win32")
        if ($mode -eq 'checked') { $flags += @('-Cr', '-Co', '-gl') }
        else { $flags += @('-Cr-', '-Co-', '-O3') }
        if ($suite -eq 'apptarget') { $flags += '-dPACKAGEDAPP_TESTS' }
        if ($suite -eq 'documentdrop') { $flags += '-dANIMATION_TIMING_TESTS' }
        & $Compiler @flags (Join-Path $PSScriptRoot "${suite}_tests.lpr") *> (Join-Path $buildPath 'build.log')
        if ($LASTEXITCODE -ne 0) { Get-Content (Join-Path $buildPath 'build.log') -Tail 18; throw "$suite compilation failed." }
        & (Join-Path $buildPath "${suite}_tests.exe") *> (Join-Path $buildPath 'test.log')
        $testExit = $LASTEXITCODE
        Get-Content (Join-Path $buildPath 'test.log') | Select-String 'Number of|Time:|ERROR|FAIL|Error:|Failure:'
        if ($testExit -ne 0) { Get-Content (Join-Path $buildPath 'test.log') -Tail 40; throw "$suite failed in $mode mode." }
        Write-Host "$suite passed in $mode mode."
    }
}
