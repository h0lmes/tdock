# Dock architecture

The main form connects dock services to Windows events.
`TDockApplication` owns those services and controls their cleanup.

| Responsibility | Unit |
| --- | --- |
| Service ownership and shutdown | `dockapplicationu.pas`, `applifecycleu.pas` |
| Settings model and change order | `docksettingsu.pas`, `settingscoordinatoru.pas` |
| Complete settings checkpoints | `settingssaveu.pas` |
| Visibility, movement, and mouse locks | `dockstateu.pas` |
| Pure visibility and reveal transitions | `dockpolicyu.pas` |
| Logical deadlines, scalar motion, and analytical springs | `docktimingu.pas` |
| Precise animation time and shared frame timestamps | `animationclocku.pas` |
| Native frame scheduling and monitor refresh selection | `framepaceru.pas` |
| Native display waits, refresh rates, and fallback phase | `displayclocku.pas` |
| Continuous click animation curves | `animationcurveu.pas` |
| Typed commands and legacy command mapping | `dockcommandu.pas` |
| Stable item models and owning stores | `itemmodelu.pas`, `itemmgru.pas` |
| Item order, drag previews, and undo records | `itemcollectionu.pas` |
| Native item bindings, timers, and mouse locks | `itemviewu.pas` |
| Registry compatibility and host callbacks | `itemregistryu.pas`, `itemhostu.pas` |
| Layout calculations | `docklayoutu.pas` |
| Task reconciliation decisions | `tasksyncu.pas` |
| Shared application window discovery | `appwindowsu.pas` |
| Application window layout snapshots | `windowlayoutu.pas` |
| Dock background and blur rendering | `dockrendereru.pas` |
| Icon selection, extraction, sizing, and native cleanup | `iconserviceu.pas` |
| Bounded foreign-window icon worker and owner notifications | `asyncwindowiconu.pas` |
| Native window, input, and command adapters | `win32docku.pas`, `win32inputu.pas`, `win32commandu.pas` |
| Global hotkey registration and fallback selection | `win32hotkeyu.pas` |
| Launch requests and detached workers | `launchserviceu.pas`, `runthreadu.pas` |
| Plugin SDK routing | `pluginhostu.pas`, `plgitemu.pas` |

## Ownership

The application owns the settings, theme, item manager, plugin host, and native adapters.
The form borrows these objects through application properties.
Legacy `sets`, `theme`, and `PluginHost` globals remain compatibility references.
The application clears these references during cleanup.

Each model receives one nonzero, unsigned 64-bit `TItemId`.
The process never reuses a retired ID.
`itemmodelu` has no Windows dependency.
The manager's store owns pending, active, dragged, and deleted models.
Each stack owns its subitem store.
Creation scopes retain models through constructor callbacks and rollback.
Collection records, task decisions, and interaction snapshots contain stable IDs.
Native application windows in task snapshots remain borrowed Windows handles.

The view adapter owns item window bindings and their native context records.
`GWL_USERDATA` contains a view context, rather than a model pointer.
Each binding records its window, parent, model ID, and generation token.
Dispatch snapshots check the generation before acquiring a model lease.
A replaced window cannot satisfy an old dispatch snapshot.
The adapter validates native context ownership during lookup.
Invalid contexts retire their models and preserve foreign native windows.
The registry unit provides compatibility names for this adapter.

Executing callbacks retain model leases until they return.
Lease release uses the model ID and survives native window loss.
Retirement rejects new leases and removes ownership before notification.
Destruction waits for the last lease.
Native window loss retires the model and removes its collection membership.
Logical deletion hides retained windows and preserves undo ownership.
Deleted stack children reject callbacks until undo restores their parent.

Window replacement preserves model identity, child ownership, timers, rendering, and mouse locks.
Stack buckets resolve child models by ID.
Subitem insertion retains parent and child models through parsing callbacks.
Failed drag or undo handoffs preserve their source and release pending copies.
Geometry and membership snapshots precede native validation and callback dispatch.
Property forms retain an ID and acquire a short lease for each handler.
Forms reject missing, deleted, or retiring models.

Internal item callbacks use a bound host service record.
Plugin exports retain their names, calling conventions, and handle widths.
Plugin operations run on the bound UI thread.
Plugin DLLs remain loaded until process exit.
This preserves callback code pointers.
Legacy plugin HWND values remain native handles throughout each plugin instance.
Plugin window replacement fails before changing that instance.
The optional V1 API accepts opaque IDs and exposes native window conversion separately.
See [PLUGIN_API.md](PLUGIN_API.md) for signatures, encoding, ownership, and failure behavior.

## Settings and commands

`TDSets.container` remains the authoritative settings record.
The dock state borrows this record.
The item manager receives typed settings snapshots.
Restored and redocked items receive current settings and fonts.

`settingsschemau` defines settings keys, defaults, field bindings, and numeric limits once.
INI loading, saving, and parameter access use this schema.
The internal settings DTO has version 1.
The existing INI format has no new version key or syntax.
The adapter retains unknown settings keys and sections.
`Hello` remains a one-shot setting.
`DropDistance` remains derived and has no INI key.
Mouse effect locks bypass persistent settings.

`itemserializationu` owns shortcut and stack DTOs, validation, and legacy codecs.
Both INI and clipboard readers use the same numeric and boolean rules.
Unsupported delimiters and line breaks produce conversion errors before lossy text export.
Property forms validate drafts before changing live fields.
Profile reads grow their buffers instead of truncating item values.
Profile write failures propagate to the checkpoint coordinator.

`itemfactoryu` registers item classes, validators, and persistence capabilities.
The native view registry remains separate.
Plugin construction retains its virtual factory and callback ownership order.
Unknown or malformed persisted items retain their fields and relative positions during saving.
The manager does not construct native windows for those entries.
Tasks remain transient.
Stack insertion reports success explicitly.
Batch insertion rolls back its own published children after failure.
Full stacks reject drops before source deletion.
Stack visibility batches retain full-width native handles and check replacement handles.

The coordinator stores normalized values before notifying items.
It preserves the original callback order.
It reports both previous and new values for dependent zoom changes.
Theme and shell writes respect their fixed buffer sizes.
Settings cancellation restores the complete record and refreshes tasks.

The command controller converts legacy command text into typed requests.
The form handles application actions.
Native adapters handle Windows commands and launch requests.
The public command names and settings sections remain compatible.
Empty command lines return without indexing an empty string.

`/savewindows` and `/restorewindows` use one in-memory snapshot per application instance.
`TDockApplication` owns the window layout service and releases its window properties during shutdown.
Task refresh and layout capture use the same application window discovery function.
Layout capture does not change the cached task list or apply its monitor restriction.
Each saved window receives a unique lifetime property before geometry capture.
Restore validates that property, process, thread, current eligibility, and display setup before applying placement.
Failed saves preserve the previous snapshot when every window fails or the display setup changes.
Native placement uses asynchronous requests for foreign input queues.
Reported restoration counts describe accepted placement requests.
Failure results retain window descriptions and reasons alongside the existing counts.
Native calls capture error codes before cleanup can overwrite them.
The notifier displays and logs those details through its existing message path.

## Shutdown and persistence

Operations retain application services while callbacks, native drag handlers, and modal dialogs run.
A close request blocks new commands.
The application posts its deferred close after the final operation returns.
The native quit route commits that close directly.
Cleanup releases independent services after destructor failures.

Settings saving writes a unique staging file beside the destination.
Both settings and item writers must finish before replacement.
The coordinator flushes the staging file before replacement.
Failed or nested saves preserve the previous complete checkpoint.
Snapshot writers retain their original source paths.
Plugin `OnSave` receives the staging path during checkpoint creation.

Session queries preserve services.
Cancelled session shutdown preserves normal operation.
Committed session shutdown attempts saving before returning.
Active callbacks retain their objects until they return.
An active save or load uses the previous complete checkpoint.
That checkpoint can contain older plugin state.

Windows API references: [session shutdown](https://learn.microsoft.com/en-us/windows/win32/shutdown/wm-endsession),
[file replacement](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-movefileexw),
and [INI cache flushing](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-writeprivateprofilestringw).

## State and scheduling

`dockpolicyu` provides pure visibility and reveal transitions.
Transitions receive time and observation snapshots as inputs.
Native adapters apply their resulting state.
User visibility intent remains separate from fullscreen suppression.
Fullscreen suppression wins while its setting remains enabled.
Manual hiding survives fullscreen exit.
Disabling fullscreen hiding immediately removes suppression.

Reveal state owns delays, blockers, movement targets, and explicit activation requests.
Geometry changes retarget collapsed docks.
Drag completion and settings closure reevaluate blocked hiding.
Movement reversals preserve the current position.
Animations use elapsed time instead of callback counts.
`StayOnTop` retains its existing stacking behavior.
It suppresses outside click lowering and uses temporary topmost placement when raising.

Logical deadlines use absolute due times and cancellation generations.
Native timer messages must satisfy the current deadline before producing effects.
Item view replacement preserves remaining time.
Deletion cancels internal item timers and owned overlays.
Legacy plugin timers retain their native compatibility path.

The frame scheduler runs only while active work requires it.
Active work includes animations, popup discovery, and hotkey fallback.
Stable items receive no frame callbacks.
Stable hints, previews, and alerts stop their frame timers.
Application operation completion refreshes scheduling under a reentry guard.

Animation time uses `QueryPerformanceCounter` with a cached frequency.
Nested frame scopes share one precise timestamp.
Item, task, and shell deadlines retain their existing integer clocks.
Reveal delays share the animation clock with reveal motion.
This keeps reveal deadlines and movement in one time domain.

The scheduler binds to the window's monitor and reads its rational refresh rate.
Monitor-specific vertical blank waits provide the preferred clock.
Stop, wake, and watchdog events keep native waits cancellable.
Unsupported native waits use primary-monitor DWM timing or a high-resolution timer.
DWM timing advances monotonically across physical refresh slots.
The requested rate never exceeds the physical display rate.
Monitor migration and display changes refresh each active window's binding.
Older Windows versions use a scoped timer-resolution request while fallback pacing remains active.
The worker posts frame messages; drawing remains on the UI thread.
Each pacer keeps at most one pending frame message.
Rate changes, stopping, and destruction discard obsolete messages.
Generation checks reject obsolete messages already removed from the queue.

Hover magnification and drag return use analytical springs without overshoot at rest.
Retargeting preserves current position and velocity.
Drag return starts with measured release velocity.
The manager combines pointer changes, reveal offsets, layout, and click motion within one frame.
Nested frame callbacks cannot repeat item sampling or drawing.
Stable icons retain reusable drawing surfaces.
Pixel rounding preserves continuous spring position and velocity.
Failed rendering, uploads, moves, and position batches retain pending drawing work.
Only successful native presentation clears that work.
Click choices retain their settings values and use continuous curves.
Reference timing uses 15.625 milliseconds per legacy phase.

Hints and previews evaluate continuous decay instead of replaying missed steps.
Position and opacity changes reuse successfully presented pixels.
Changed pixels and failed presentations remain eligible for full rendering.
Notification entry uses an ease-out curve.
Stack closing follows each opening trajectory in reverse.

Global hotkeys use system-wide registration and `WM_HOTKEY`.
The dock can receive those messages while hidden or inactive.
Settings suspend registration and clear fallback press history.
Binding generations reject queued messages from previous registrations.
Registration conflicts retain the sampling fallback.

Window observation hooks publish coalesced events through the dock message queue.
Foreground changes update task attention immediately.
Window changes trigger bounded task refresh and fullscreen observation.
Creation bursts preserve the earliest refresh deadline.
Task changes during dragging remain pending until dragging ends.

Tray and Start-menu requests own explicit discovery and placement states.
Discovery expires after three seconds.
Controllers reacquire late or replaced windows.
Placement work continues independently from dock visibility.
Shell layout records successful effects separately from requested effects.
Failed workarea changes remain eligible for retry.
Invalid native geometry never produces workarea writes.
Monitor `-1` reservations use the monitor containing the dock rectangle center.

One-second maintenance retains cursor, shell, and deletion recovery.
Five-second maintenance audits fullscreen observations, foreground state, and screen reservation.
Plugin clocks and system meters keep their periodic sampling.

## Layout and rendering

Layout and task reconciliation use snapshots and return decisions.
The item manager applies those decisions to live windows.
Geometry tests cover each dock edge, bounds, previews, and hit tests.
Task tests cover grouping, visibility, ordering, and drag suppression.

The renderer owns its blur window and geometry cache.
It updates the cache only after successful drawing.
Failed frames remain eligible for another draw.
Native input uses the official Windows record layout and validates received sizes.
The window adapter calls the native Windows pointer functions explicitly.
This avoids JEDI wrappers that truncate callback addresses in this compiler.

## Icon loading

`iconserviceu` centralizes icon selection, extraction, sizing, and native cleanup.
Dock items, stack items, task images, previews, and property forms call this service.
`gfx` retains bitmap conversion and drawing helpers.
Custom image paths take priority over automatic icons.
Automatic targets support files, app IDs, Shell names, and serialized PIDLs.

Packaged apps use their Shell artwork properties.
The service prefers unplated assets at sufficient resolution.
Unplated assets omit the colored tile background.
Asset qualifiers follow Microsoft's [Windows app icon guide](https://learn.microsoft.com/en-us/windows/apps/design/iconography/app-icon-construction).
Missing artwork falls back to the Shell image factory, legacy icons, and optional defaults.
The factory receives the requested size and icon-only flags.
The service copies native pixels before releasing each Shell bitmap.
Resizing preserves the whole image, its aspect ratio, and its alpha channel.

Each returned GDI+ bitmap belongs to its caller.
Callers release these bitmaps with `GdipDisposeImage`.
Input PIDLs and window icons remain borrowed.
The service releases owned native bitmaps and icons exactly once.
Task and preview window requests return cached or fallback pixels immediately.
`asyncwindowiconu` queries foreign windows on a worker with 40-millisecond message timeouts.
The worker owns at most 64 cache entries and 256 subscriptions.
Window properties, process identity, and owner generations reject obsolete results.
The worker sends completion messages; the UI converts and draws copied icons.
Denied foreign properties retain readable class icons without caching an unverified window identity.
Owner destruction cancels subscriptions and queued notifications.
Application shutdown stops the worker before image-service destruction.
Task images keep large file icons before requesting window icons.

Run only icon and packaged-app metadata checks:

```powershell
.\tests\run-icon-tests.ps1
```

These 27 tests pass in checked and release modes on 2026-10-24.
Native Calculator and Calendar probes also produce transparent, full-size artwork.
The Calendar probe uses a PIDL.
Desktop acceptance still covers the actual dock and properties dialogs.

## Verification

Final verification passed on 2026-10-31.
All 808 tests passed in checked and release modes across 35 suites.
All ten native interaction checks passed.
The application build succeeded with Free Pascal 3.2.2.
The compiler reported 185 warnings and 26 notes.
Source whitespace and the Lazarus unit manifest passed their checks.
Generated build folders retained inherited permissions and normal user access.
The executable retains 31 legacy exports and adds 13 versioned exports.

The follow-up presentation probe submitted 240 frames at each physical display rate.
Average submission intervals were 16.668 milliseconds at 60 Hz and 8.341 milliseconds at 120 Hz.
The slow foreign-window fixture remained active during both measurements.
Drawing averaged below one millisecond at both rates.
The probe captured 168 desktop frames at 60 Hz and 160 at 120 Hz.
Periodic desktop gaps reached approximately 82 milliseconds and 79 milliseconds.
A separate native GDI control showed similar gaps without tdock's renderer or scheduler.
The exact cause of these shared capture gaps remains unconfirmed.
These results verify submission cadence but cannot establish uninterrupted visual smoothness on this host.
This host rejects combined native vertical-blank waits, so the DWM fallback remains active.
The original 60 Hz mode was restored after the measurements.
Tests now only read display parameters; users select the physical rate manually.
Raw results remain in `tests/.build/animation-present/`.

Run the regression suites:

```powershell
.\tests\run-tests.ps1
```

Build the application inside the workspace:

```powershell
.\tests\build-application.ps1
```

The build script skips the Lazarus deployment command in `copy.bat`.
Test and build outputs stay in `tests\.build`.
The unit suites use hidden native windows and controlled callbacks.
The runner tests startup observation, hover hints, stack animation, and zoom through the real Windows message loop.
It also checks real hotkey registration and synthetic message delivery while the dock is hidden.
These checks use isolated settings and disable process integration.
Visual desktop acceptance still covers themes, task previews, and monitor movement.

Manual desktop checks cover theme changes, settings cancellation, task previews, and monitor movement.
They also cover drag deletion, redocking, undo, and plugin menus.
Physical keyboard delivery and Explorer popup placement also require desktop acceptance.
