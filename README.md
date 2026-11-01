terry
=====

This project is a desktop dock panel written in Lazarus (Free Pascal).

Operating systems: Win Vista and later.
Can be compiled for x86/x64.

Import taskbar shortcuts
------------

Right-click the dock.
Select **Add ... > Import taskbar shortcuts**.
TDock copies pinned Windows taskbar launchers into the current dock.
Existing launchers stay in place.
New launchers follow taskbar order.
Repeated imports skip launchers already in this dock.
TDock reports added, updated, skipped, and failed counts.
Both commands run in `tdock.exe`.
The command window and **Standard items** dialog provide these commands:

| Command | Behavior |
| --- | --- |
| `/importtaskbar` | Copy shortcuts into `ImportedFiles` |
| `/importtaskbarlinks` | Use original Windows shortcuts without copying them |

TDock keeps copied shortcuts beside its settings under `ImportedFiles`.
Copies retain shortcut arguments, working directories, icons, and launch settings.
Unpinning the source shortcut does not remove the dock copy.
Store apps use their Shell application targets.
The import leaves Windows taskbar pins unchanged.

`/importtaskbarlinks` creates no shortcut copies.
Unpinning or deleting a source shortcut can break its dock launcher.
Running `/importtaskbarlinks` updates matching launchers that use generated `ImportedFiles` copies.
TDock keeps their positions, labels, icons, and launch settings.
TDock reports these changes as updated launchers.
Existing copied files remain available.

Build TDock with `tests\build-application.ps1`.

Windows uses an undocumented interface to list pinned apps.
If that interface fails, TDock reads the taskbar shortcut folder.
TDock warns that this fallback can miss Store apps and taskbar order.
The import excludes unpinned running apps and taskbar controls.

Window layout commands
------------

Add these commands through the dock's **Standard items** dialog:

| Command | Icon label |
| --- | --- |
| `/savewindows` | Save window layout |
| `/restorewindows` | Restore window layout |

Run `/savewindows` before starting a game.
Return to the original display setup after playing.
Run `/restorewindows` to recover saved window positions, sizes, and minimized or maximized states.

Both commands use the existing application window filter across all monitors.
They work when dock task icons are disabled.
Restore skips closed windows and windows that no longer pass the application filter.
New and reopened windows stay unchanged.
The display check includes resolution, monitor arrangement, primary monitor, orientation, scaling, and work areas.
Restore refuses to move windows when those settings differ.

TDock keeps one layout in memory per dock process.
Each successful Save replaces it.
Restore keeps it available for repeated use.
Closing TDock clears it.
Results show saved or restored counts and failures.
Restore also reports skipped windows.
Failure details list window titles, process IDs, and the operation that failed.
Native failures include the Windows error code and available error text.
Untitled windows use their class name or window handle.
Windows can block access to elevated applications.
Those windows count as failures during Save.
Access-denied messages mention possible administrator privileges.
Restoration does not recreate Windows Snap groups.

=====

Distribution package
------------

Folders
```
Docklets
Images
Locale
Themes
```

Files
```
tdock.exe
tips.txt
```
