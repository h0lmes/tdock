terry
=====

This project is a desktop dock panel written in Lazarus (Free Pascal).

Operating systems: Win Vista and later.
Can be compiled for x86/x64.

Window layout commands
------------

Add these commands through the dock's "Add command" dialog:

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
