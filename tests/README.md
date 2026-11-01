# Regression tests

Run the tests from the workspace:

```powershell
.\tests\run-tests.ps1
```

The script runs all regression suites in two modes:

- Checked mode enables range and overflow checks.
- Release mode disables those checks and enables optimization.

Animation tests cover pixel settling and failed drawing, upload, movement, and batch retries.
Frame tests cover native cancellation, monitor migration, rational rates, and monotonic fallback slots.
Async icon tests cover slow windows, bounded caching, obsolete owners, shutdown, and denied window properties.
The canonical runner includes these suites in both modes.

Taskbar import tests cover shortcut copies, Unicode names, Store targets, duplicates, order, failures, and saved settings.
They also cover original shortcut references, copy migration, retained settings, separate commands, and default copying.
Run `.\tests\run-taskbar-import-tests.ps1` for this suite.

All runners share compiler discovery, dependency paths, build modes, and suite defines through `test-runner.ps1`.
Focused runners keep their existing commands and suite selections.
Each unit suite saves `build.log` and `test.log` in its build folder.
Use `-Compiler` to select a compiler explicitly.
Without that option, runners check PATH before searching the supplied `-LazarusRoot`.

Run the desktop presentation probe at the current 60 Hz mode:

```powershell
.\tests\run-animation-presentation-probe.ps1 -Rates 60
```

The probe uses the production item renderer and frame scheduler.
It captures encoded frame identifiers from a small test window.
It saves timestamps without saving desktop images.
The default run includes a slow window icon fixture.
Submitted frames and captured desktop frames remain separate measurements.
The requested rate must match the physical display mode.
Select the display rate manually before each 60 Hz or 120 Hz run.
Tests only read display parameters. They never change them.
The native GDI control excludes tdock's renderer and scheduler:

```powershell
.\tests\run-animation-presentation-probe.ps1 -Rates 60 -NativeControl
```

Use `-Rates 120 -NativeControl` when the display already runs at 120 Hz.
`-TimerControl`, `-GdiFlushControl`, and `-FlushControl` provide diagnostic comparisons.
`-WithoutIconStress` disables the slow-window fixture.
Results remain in `tests/.build/animation-present/`.
Actual desktop capture can show compositor or capture stalls despite regular frame submission.

Manager tests create hidden Windows item windows.
The tests cover creation, insertion, previews, dragging, deletion, undo, and settings restoration.
Allocation failure tests verify that insertion, dropping, and undo preserve ownership.
Detached launch tests verify parameter ownership, creation failure, immediate completion, and worker exceptions.
They check `SEE_MASK_NOASYNC`, Unicode arguments, text limits, and stable Windows handle counts.
The suite records actual handle closures because Windows can reuse a closed handle value.
A delayed worker finishes after its host window closes, without message processing.
The launch suite enables heap tracing and replaces Shell calls with controlled test functions.
Run WO-12, WO-19, and WO-20 checks with `.\tests\run-launch-preparation-tests.ps1`.
This runner includes worker ownership, launch failures, activation HRESULTs, variable expansion, routing, target preservation, and serialization.
It runs related suites in checked and release modes.
Worker tests cover concurrent failures, COM initialization, immediate completion, closed result queues, and service destruction.
Text checks include 1,023, 1,024, 32,765, 32,766, and 32,767 UTF-16 units.
Expansion checks cover Unicode, unknown names, tdock priority, literal paths, and output limits.
Activation checks use a native COM interface layout and an actual missing-application request.
Logs remain in `tests/.build/launch-preparation-{suite}-{mode}/`.
Installed handler acceptance and final application readiness still require desktop verification.
Drop ownership tests cover borrowed handles, both OLE ownership cases, insertion failures, and repeated Windows Shell imports.
Both modes check Shell-ID fallback, This PC, and Recycle Bin without skips.
Packaged-app metadata tests verify AppsFolder lookup, automatic icons, overrides, missing applications, retries, and saved settings.
They supply a real filesystem Shell item through a controlled parser instead of requiring Calculator installation.
Renderer tests cover drop completion, drag cancellation, and failed cleanup-frame retries with unchanged geometry.
Run only these rendering and metadata checks with `.\tests\run-drop-followup-tests.ps1`.
Icon service tests cover app IDs, Shell names, PIDLs, package artwork, alpha, sizing, overrides, and native cleanup.
They also cover borrowed window icons, task fallback, resource indices, independent results, and property previews.
Run only icon and metadata checks with `.\tests\run-icon-tests.ps1`.
This focused runner executes 24 icon tests and 19 metadata tests in both modes.
It saves each suite's output in its build folder's `test.log`.
The icon and metadata suites enable `ICONSERVICE_TESTS` for controlled native seams.
Native file extraction also runs without the factory seam.
Native Calculator and Calendar artwork checks require the user's installed packages.
Packaged application tests cover identity validation, AppsFolder normalization, and launch routing.
Run these checks with `.\tests\run-app-target-tests.ps1`.
This runner executes the related suites in checked and release modes.
It includes the metadata and icon checks above.
Logs stay in `tests/.build/app-target-{suite}-{mode}/`.

`IsPackagedApp` replaces the old suffix predicate.
`TryNormalizeAppTarget` returns a bare packaged AUMID for activation.
The normalizer accepts bare identities and these case-insensitive prefixes:

- `shell:AppsFolder\`
- `shell:::{4234d49b-0245-4df3-b780-3893943456e1}\`
- `::{4234d49b-0245-4df3-b780-3893943456e1}\`

Windows validates the package-family portion through its dynamically loaded Windows 8 API.
Application IDs allow 1–64 ASCII letters, digits, or periods.
Other endings receive the same activation route as `!App`.
Existing files and directories take priority over matching bare identities.
Normalization preserves saved commands and application-ID spelling.
Ordinary paths, URIs, shortcuts, Shell roots, and serialized PIDLs retain their launch routes.
The tests capture launch calls with threaded execution enabled and disabled.
Native activation checks require installed applications and run separately from the regression runner.

Run WO-09 through WO-11 checks with `.\tests\run-target-preservation-tests.ps1`.
The runner includes bounded Shell readers, selective Unicode persistence, properties, launch routing, and plugin compatibility.
The new suite verifies malformed counts, offsets, lengths, terminators, partial streams, and 2,000 malformed CIDA samples.
It also checks long native paths, long link metadata, Unicode images, and exact buffer boundaries.
Shared-save checks invoke an ObjectDock-style callback using ANSI profile functions.
ASCII item text and existing semicolon lists retain their original representation.
Non-ASCII built-in items use tagged hexadecimal UTF-8 fields.
Tests change Pascal conversion defaults to CP1251 and CP1252 without changing Windows system settings.
These checks do not replace testing actual non-UTF-8 Windows locales.
Logs remain in `tests/.build/target-preservation-{suite}-{mode}/`.
The native Settings check opens Windows Settings.

Docking tests use controlled cursor coordinates.
They cover redocking, stack creation, drag deletion, and failed cursor reads.

Use these parameters for other compiler installations:

```powershell
.\tests\run-tests.ps1 -Compiler 'C:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe' -LazarusRoot 'C:\lazarus'
```

Build files and test fixtures stay in `tests\.build`.

The item collection stores active, dragged, and deleted records separately.
`Count` reports active records.
`ViewCount` adds the optional drag preview.
`SaveCount` includes the dragged record and excludes the preview.

The migration also adds these regression suites:

- Core state, commands, settings, lifecycle, and rendering.
- Item registry identities, callback pins, and host bindings.
- Stable model ownership, creation scopes, retirement, and independent model leases.
- Native window loss, view replacement, timers, locks, and deletion cleanup.
- Property form handlers after deletion, retirement, window loss, and view replacement.
- Subitem construction rollback, stack ownership, drag handoff, and deletion visibility.
- Legacy plugin routing and versioned opaque-ID exports.
- Pure dock geometry and task reconciliation.
- Native raw input validation and plugin SDK routing.
- Atomic settings checkpoints and interrupted saves.

Build the application without deployment:

```powershell
.\tests\build-application.ps1
```

This script compiles `terry.lpr` into `tests\.build\application\tdock.exe`.
It does not run the Lazarus post-build `copy.bat` command.
See `ARCHITECTURE.md` for service ownership and compatibility rules.

The canonical runner includes 35 suites.
The migration baseline passed 377 tests in checked and release modes.
The canonical runner also runs ten Windows interaction smoke checks.
These checks create the real form and process Windows messages.
They cover startup observation, hover hints, stack animation, zoom geometry, and hidden-window hotkey delivery.
They also cover copied-file insertion, URL stack insertion, and drag-state clearing through the real form.
WO-18 adds rejected-entry cleanup, consumer failure propagation, and native Shell transfer through the real form.
The smoke executable uses the application build flags.
It disables taskbar changes, screen reservation, fullscreen hiding, and process integration.
The hotkey check uses real registration and synthetic `WM_HOTKEY` messages.
Physical keyboard delivery and Explorer popup placement require desktop acceptance.

Timing suites cover pure reveal policy, global hotkey bindings, animations, item deadlines, and shell recovery.
They use controlled clocks and native-effect seams.
Tests cover reversal continuity, stale callbacks, view replacement, deletion, undo, and failed shell writes.

Spring tests compare matched timestamps at 60 Hz and 120 Hz.
They cover velocity preservation, settling, delayed frames, and release velocity.
Click tests retain all animation choices and verify continuous phases and smooth endpoints.
Drawing tests cover reusable surfaces, failed presentations, and native resource cleanup.
Frame scheduler tests cover pending-message bounds, rate changes, stopping, and fallback resolution cleanup.

Measure native frame-message delivery:

```powershell
.\tests\run-animation-pacing-probe.ps1
```

The probe measures 240 intervals at each requested rate.
It reports averages and interval percentiles.
Results stay in `tests/.build/animation-pacing/results.csv`.
This probe measures message delivery, not compositor presentation or complete dock rendering.

Run these checks separately:

```powershell
.\tests\run-interaction-smoke.ps1
```

Visual checks for themes, task previews, and monitor movement remain manual.

Run the focused drag-data checks with `tests/run-drop-import-tests.ps1`.
The runner covers import decoding, ownership, insertion, renderer state, lifecycle, and serialization.
It runs checked and release builds.
The import suite covers URL, text, filename, and descriptor/content formats.
It verifies indexed contents, Unicode names, ANSI locale decoding, partial reads, collisions, cleanup, and persistence.
Real compound-storage files verify the IStorage path.
The insertion runner selects seven related manager checks.
Browser and email source acceptance remains a separate desktop check.
The canonical regression runner also includes the import suite.

The serialization suite checks the existing INI keys and item text syntax.
It covers all settings bindings, text bounds, normalization, colors, booleans, and internal DTO versions.
It also checks long values, unknown settings, factory registration, stack modes, and sparse child keys.
Manager tests cover unknown item retention, full stack drops, and stack merge capacity.
Child lifetime tests verify insertion results and rollback after a later child fails.

Run target-preservation checks with `tests/run-target-preservation-tests.ps1`.
The runner checks long targets, bounded Shell data, Unicode persistence, and ANSI plugin writes.
Folder regressions cover commands saved relative to tdock's executable directory.
They verify short and long folder restoration, native icons, and both launch settings.
Native icon checks disable the default icon fallback.
Unicode persistence checks verify individual `UTF-8''` prefixes and unchanged neighboring ASCII values.
They cover literal prefixes, percent signs, plus signs, malformed escapes, invalid UTF-8, and size limits.
ANSI plugin callbacks preserve their own literal prefix values through shared settings saves.

# WO-13 through WO-17 focused checks

Run `./tests/run-object-activation-tests.ps1` for this remediation group.
The runner selects activation contracts, PIDL options, Shell identities, document drops, and destination routing.
It runs these checks in checked and release modes.
It does not run the full regression suite.

`objectactivation_native.lpr` provides opt-in checks under the desktop user's account.
Its `inspect` mode reads Shell identities and registered application contracts.
Its `roots` mode submits the six standard Shell-root activation requests.
Its `pidl` mode launches a capture helper for arguments and the working directory.
Its `document` mode tests real dock and stack callbacks with the installed Paint 3D package.
Pass another packaged identity as its second argument to check that application's contract.
Its `provider` mode invokes the Wi-Fi provider's default status action.
These native modes do not establish physical Explorer drag acceptance.

# WO-18 feedback and WO-21 acceptance

Run `./tests/run-drop-import-tests.ps1` for the focused import, ownership, insertion, renderer, and persistence checks.
The import suite now contains 57 tests.
Feedback checks cover COPY, LINK, modifiers, unsupported formats, empty data, and unavailable format advertisements.
They verify that hover never retrieves contents and never controls final extraction eligibility.
Failure checks cover complete rejection, partial acceptance, exceptions, uncertain outcomes, and feedback cleanup.
Retention checks preserve missing executable targets and unknown URI schemes through insertion and settings reload.
Run `./tests/run-object-activation-tests.ps1 -Suites documentdrop` for existing icon and stack-child preservation checks.
Those checks verify destination-based rejection and preserved PNG/ICO image replacement.
Run `./tests/run-interaction-smoke.ps1` for ten real-form checks.
The native Shell transfer obtains a real data object through `IShellFolder.GetUIObjectOf`.
It exercises the production drop manager, form callback, insertion, effect negotiation, and cleanup.
These automated checks do not establish physical Explorer or source-application dragging.
Record source versions, process elevation levels, target type, visible application results, and restart results separately.
WO-21 remains pending where the desktop acceptance matrix lacks that evidence.

The approved desktop follow-up uses only these related selections:

```powershell
.\tests\run-object-activation-tests.ps1 -Suites documentdrop,dropinsertion
.\tests\run-drop-followup-tests.ps1 -Suites appmetadata
```

The document suite contains 12 checks, including native Shell transfers through the production drop manager.
It verifies NONE after icon or stack-child rejection and successful insertion of the same file into empty space.
The insertion suite contains eight checks, including stack-capacity rejection and unlaunchable-target persistence.
The metadata suite contains 19 checks for dock and stack captions, icons, overrides, retries, and saved fields.
It exercises a real stack drop with controlled metadata supplied by a real filesystem Shell item.
These three suites total 78 executions across checked and release modes.
No broad regression or interaction-smoke run is required for this follow-up.

Window layout tests run in checked and release modes:

```powershell
.\tests\run-windowlayout-tests.ps1
```

They cover saved geometry, window states, lifetime markers, display checks, partial failures, and repeated restoration.
Diagnostic checks cover window names, native errors, exceptions, and missing reasons.
Native checks use hidden windows and an isolated desktop.
They leave the user's application windows unchanged.
The main runner also checks command routing and application service ownership.
Logs stay in `tests/.build/windowlayout-{checked,release}/`.
