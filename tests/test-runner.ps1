function Resolve-PascalCompiler {
    param([string]$Compiler, [string]$LazarusRoot = 'C:\lazarus')

    if ($Compiler) { return $Compiler }
    $command = Get-Command fpc.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $Compiler = Get-ChildItem (Join-Path $LazarusRoot 'fpc\*\bin\x86_64-win64\fpc.exe') -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
    if (-not $Compiler) { throw 'Specify the Free Pascal compiler with -Compiler.' }
    return $Compiler
}

function Build-PascalProgram {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$BuildPath,
        [string]$Compiler,
        [string]$LazarusRoot = 'C:\lazarus',
        [ValidateSet('checked', 'release')][string]$Mode = 'checked',
        [string[]]$ExtraFlags = @(),
        [string]$LogName = 'build.log'
    )

    $ErrorActionPreference = 'Stop'
    $Compiler = Resolve-PascalCompiler -Compiler $Compiler -LazarusRoot $LazarusRoot
    $projectRoot = Split-Path $PSScriptRoot -Parent
    New-Item -ItemType Directory -Path $BuildPath -Force | Out-Null
    $flags = @('-B', '-Mdelphi', "-Fu$projectRoot", "-FU$BuildPath", "-FE$BuildPath",
        "-Fu$LazarusRoot\lcl\units\x86_64-win64",
        "-Fu$LazarusRoot\lcl\units\x86_64-win64\win32",
        "-Fu$LazarusRoot\components\lazutils\lib\x86_64-win64",
        "-Fu$LazarusRoot\components\lazcontrols\lib\x86_64-win64\win32")
    if ($Mode -eq 'checked') { $flags += @('-Cr', '-Co', '-gl') }
    else { $flags += @('-Cr-', '-Co-', '-O3') }
    $flags += $ExtraFlags
    if (-not [System.IO.Path]::IsPathRooted($Source)) { $Source = Join-Path $PSScriptRoot $Source }
    $buildLog = Join-Path $BuildPath $LogName
    & $Compiler @flags $Source *> $buildLog
    if ($LASTEXITCODE -ne 0) {
        Get-Content -LiteralPath $buildLog -Tail 35
        throw "Compilation failed for $Source in $Mode mode."
    }
}

function Invoke-TestSuites {
    param(
        [Parameter(Mandatory)][string[]]$Suites,
        [string]$Compiler,
        [string]$LazarusRoot = 'C:\lazarus',
        [ValidateSet('checked', 'release')][string[]]$Modes = @('checked', 'release'),
        [string]$BuildPrefix = ''
    )

    $ErrorActionPreference = 'Stop'
    $Compiler = Resolve-PascalCompiler -Compiler $Compiler -LazarusRoot $LazarusRoot
    foreach ($mode in $Modes) {
        foreach ($suite in $Suites) {
            $buildPath = Join-Path $PSScriptRoot ".build\${BuildPrefix}$suite-$mode"
            $extraFlags = @(switch ($suite) {
                { $_ -in @('runthread', 'launchfailure') } { '-dRUNTHREAD_TESTS' }
                'apptarget' { '-dPACKAGEDAPP_TESTS' }
                'stackrunning' { '-dRUNNING_BADGE_TESTS' }
                { $_ -in @('appmetadata', 'iconservice', 'dropvisual') } { '-dICONSERVICE_TESTS' }
                'asyncwindowicon' { '-dWINDOW_ICON_TESTS'; '-dANIMATION_TIMING_TESTS' }
                { $_ -in @('animationtiming', 'documentdrop') } { '-dANIMATION_TIMING_TESTS' }
            })
            Build-PascalProgram -Source "${suite}_tests.lpr" -BuildPath $buildPath `
                -Compiler $Compiler -LazarusRoot $LazarusRoot -Mode $mode -ExtraFlags @($extraFlags)
            Write-Host "Running $suite tests in $mode mode."
            $testLog = Join-Path $buildPath 'test.log'
            & (Join-Path $buildPath "${suite}_tests.exe") *> $testLog
            $testExitCode = $LASTEXITCODE
            Get-Content -LiteralPath $testLog
            if ($testExitCode -ne 0) { throw "Tests failed for $suite in $mode mode. See $testLog." }
        }
    }
}
