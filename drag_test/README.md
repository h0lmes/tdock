# Windows drag-source test app

Run `DragTest.exe` from this folder.
The app uses Windows OLE drag-and-drop.
It creates its sample files inside `samples`.
Existing sample files remain unchanged.

## Use

1. Select a sample in the left tree.
2. Check its expected result.
3. Select the required format.
4. Edit the target when needed.
5. Hold the blue area with the left mouse button.
6. Drag onto tdock.
7. Check the created item and its opening behavior.

Use empty dock space first.
Repeat accepted drops inside a normal stack.
Use normal elevation for both applications.
Existing dock icons keep their own document and image handling.

The lower-left inspector accepts a local test drop.
It reads and releases each offered format.
It does not create dock items or report tdock acceptance.

## Isolated formats

The format selector contains 24 profiles.

| Profile | Offered data |
| --- | --- |
| Native Shell | The object's actual Shell data object and its offered formats |
| Shell IDList only | `Shell IDList Array` through HGLOBAL |
| Shell IDList stream | CIDA bytes through IStream, limited to 4096 bytes |
| Unicode or ANSI HDROP | `CF_HDROP` through HGLOBAL |
| Unicode URL only | `UniformResourceLocatorW` through HGLOBAL |
| ANSI URL only | `UniformResourceLocator` through HGLOBAL |
| Unicode text only | `CF_UNICODETEXT` through HGLOBAL |
| ANSI text only | `CF_TEXT` using the Windows ANSI code page |
| CP1252 text | `CF_TEXT` plus English `CF_LOCALE` |
| Unicode or ANSI filename | `FileNameW` or `FileName` through HGLOBAL, IStream, or TYMED_FILE |
| Unicode or ANSI virtual files | Matching file-group descriptors with indexed IStream, HGLOBAL, or IStorage contents |
| Mixed formats | Unicode text, Unicode URL, and HDROP, in that enumeration order |
| Unsupported only | A registered private format without a supported alternative |

Isolated profiles omit competing representations.
Native Shell mode preserves the provider's formats.
The mixed sample checks whether tdock selects HDROP despite its enumeration position.

ANSI formats use the Windows ANSI code page unless the profile explicitly selects CP1252.
Unrepresentable ANSI text produces an error instead of replacement characters.
The CP1252 mode tests source-locale decoding without changing Windows settings.

## Object samples

The tree includes executable, script, document, folder, drive, shortcut, URI, image, and virtual-file samples.
It includes real COM executables, MSC consoles, CPL files, DLLs, and an RDP configuration.
Shell samples include This PC, Recycle Bin, Control Panel, Network, AppsFolder, Desktop, Downloads, printers, and devices.

Use **Load installed applications** to enumerate this account's AppsFolder entries.
Some accounts expose no application catalog.
Use **Browse Shell objects** to select available namespace objects and provider children.
That picker retains the selected object's native data object.
Editing the target clears that retained selection.

Use **Browse files** for real installers, application references, browser shortcuts, and other files.
No fake installers or application references are generated.
The custom target field also accepts paths and Shell parsing names.
Native Shell profiles require targets that Windows can parse.
Raw text profiles can offer other identifiers for rejection checks.

DLLs, arbitrary GUIDs, service identifiers, and scheduled-task identifiers have no universal opening operation.
Sample notes describe relevant activation boundaries.
Script opening follows the registered handler.
The RDP sample specifies localhost.
Dragging does not run these targets.
Opening a resulting dock item invokes its normal handler.

## WO-04 through WO-07 checks

| Entry | Start with | Check |
| --- | --- | --- |
| WO-04 | URL only: Unicode, URL only: ANSI, Custom URI only | One launcher, correct target, opening, and restart persistence |
| WO-05 | Text paths, multiple targets, command rejection, CP1252 text | Correct target count, Unicode preservation, and explicit rejection |
| WO-06 | Virtual IStream, duplicate names, compound storage | Saved contents, unique paths, and persistence after closing this source |
| WO-07 | FileNameW only, FileName only, temporary file medium | Filename import without HDROP or Shell-ID fallback |

For filename checks, repeat HGLOBAL, IStream, and TYMED_FILE modes.
For virtual checks, repeat both descriptor encodings and all three content media.
Virtual names occupy the target box.
The contents box supplies UTF-8 file bytes.
Each file includes its item number, so duplicate-name outputs have distinguishable contents.
The compound-storage sample uses `.stg` and a `Contents` stream.
Windows may have no default viewer for `.stg` files.

After a virtual drop, close this source.
Exit tdock normally.
Restart tdock.
Verify that its launcher still points to the saved file.
Open the saved text file to compare its contents.

## Ownership and failure checks

**Provider-owned synthetic HGLOBAL** installs a cleanup owner on synthetic global-memory transfers.
Native Shell objects retain their original ownership rules.
The log records the provider's cleanup callback.

**Force GetData failure** advertises formats while refusing their retrieval.
The target should create no launcher after a complete transfer failure.

TYMED_FILE transfers expose disposable copies under `transfers`.
The medium owns those copies.
Windows medium cleanup can delete them after retrieval.
Original sample files remain intact.
Empty transfer directories may remain as test evidence.

## Logs

`source.log` records offered formats, GetData requests, media, content indices, HRESULTs, and final effects.
`result=0x00000000` identifies successful retrieval.
Effect `0` means no accepted effect.
Effect `1` means copy.
Effect `4` means link.
The final effect describes target feedback, not verified content or launch behavior.
Record your desktop result separately.

## Build and checks

Build with `./build.ps1`.
Close the app before replacing its executable.
Run `./check.ps1` for checked and release verification.
The scripts use the existing Lazarus and Free Pascal installation.
They install no dependencies.

Checks cover format isolation, native Shell objects, ownership, injected failures, and production-importer compatibility.
The latest run passed 182 assertions in each build mode.
Installed-application enumeration was unavailable in the sandbox account.
Actual desktop drags require manual acceptance.

All helper sources and outputs stay inside `drag_test`.
This helper does not change tdock code, settings, or remediation status.

API references:

- [Windows Shell clipboard formats](https://learn.microsoft.com/en-us/windows/win32/shell/clipboard).
- [OLE DoDragDrop](https://learn.microsoft.com/en-us/windows/win32/api/ole2/nf-ole2-dodragdrop).
- [IDataObject GetData](https://learn.microsoft.com/en-us/windows/win32/api/objidl/nf-objidl-idataobject-getdata).
