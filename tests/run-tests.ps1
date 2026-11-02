param([string]$Compiler, [string]$LazarusRoot = 'C:\lazarus')

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-runner.ps1')
$suites = @('itemmodel', 'itemcollection', 'itemidentity', 'itemmanager', 'propertylifetime',
    'runthread', 'coremigration', 'itemregistry', 'itemhost', 'subitemlifetime', 'settingssave',
    'docklayout', 'tasksync', 'windowlayout', 'nativeinput', 'pluginhost', 'serialization',
    'docktiming', 'framepacing', 'animationcurve', 'hotkey', 'animationtiming', 'itemtiming',
    'shelltiming', 'dropownership', 'appmetadata', 'iconservice', 'asyncwindowicon', 'apptarget',
    'launchservice', 'dropimport', 'targetpreservation', 'launchfailure', 'variableexpansion', 'activation', 'taskbarimport',
    'stackrunning', 'shortcutactivation')
Invoke-TestSuites -Suites $suites -Compiler $Compiler -LazarusRoot $LazarusRoot

Write-Host 'Running Windows interaction smoke tests with application build flags.'
& (Join-Path $PSScriptRoot 'run-interaction-smoke.ps1') -Compiler $Compiler -LazarusRoot $LazarusRoot
