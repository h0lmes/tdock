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

Stack properties
------------

Stack properties use General, Items, Appearance, and Animation tabs.
Select **None (custom stack)** under **Stack location** to manage shortcuts manually.
Windows locations include virtual folders such as Control Panel and Recycle Bin.
Windows manages the contents of location-backed stacks.

Item additions, removals, edits, ordering, and settings stay pending until Apply or OK.
Apply keeps the dialog open.
Cancel, Escape, and window close discard changes made since the last Apply.
The fixed preview shows the closed stack icon with zero, four, or nine miniature items.
Use Apply and the actual stack to assess its layout and animation.

Stacks, dock shortcuts, and task items show red badges with their window counts.
A single window shows **1**.
**Show running indicator** controls these badges, including expanded stack shortcuts.
Running programs use no theme indicator or running background.
TDock ignores older themes' `indicator.png`, `button.png`, `attentionbutton.png`, and `button.ini` files.

Applications requesting attention show a separate amber badge at the icon's top left.
The badge contains a bold black exclamation mark.
The dock icon uses the animation selected in settings.
The attention badge stays until its requesting window becomes active or closes.
Activation through Alt+Tab or the Windows taskbar also clears attention.
Grouped icons keep the badge while any requesting window still needs attention.
Stacks collect attention from their child shortcuts.
Attention works when **Show running indicator** is disabled.
Repeated flashes from a pending window do not restart the animation.
Another requesting window can start a new animation, including another item in the same stack.
New attention raises the visible dock without taking keyboard focus.
Attention does not show a dock hidden manually, by auto-hide, or by fullscreen policy.

**Distance from stack** adds zero through two icon sizes of extra distance.
Each slider step adds one quarter of the current configured icon size.
TDock calculates the pixel distance during stack rendering.
Existing pixel offsets convert to the nearest quarter step within the new range.

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
