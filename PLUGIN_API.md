# TDock plugin API

Legacy exports keep their names and `stdcall` signatures.
Legacy item arguments remain native `HWND` values.
Existing callbacks run synchronously on the dock UI thread.

`DockH.pas` provides optional wrappers for the versioned API.
Each wrapper resolves its export from the host executable.
A missing export returns zero or `FALSE`.

## Version and identity

All signatures below use `stdcall`.
`BOOL` has the Windows 32-bit representation.
`Cardinal` is an unsigned 32-bit integer.
`TDockItemId` is an unsigned 64-bit integer.
`HWND` keeps the native pointer width.

```pascal
type TDockItemId = type QWord;

function TDockApiVersion: Cardinal; stdcall;
function TDockItemCreateV1(Data: PAnsiChar): TDockItemId; stdcall;
function TDockItemInsertV1(Id: TDockItemId): TDockItemId; stdcall;
function TDockItemDeleteV1(Id: TDockItemId): BOOL; stdcall;
function TDockItemGetWindowV1(Id: TDockItemId): HWND; stdcall;
function TDockItemFromWindowV1(Window: HWND): TDockItemId; stdcall;
function TDockItemGetCaptionV1(Id: TDockItemId; Buffer: PWideChar;
  Capacity: Cardinal): Cardinal; stdcall;
function TDockItemSetCaptionV1(Id: TDockItemId; Caption: PWideChar): BOOL; stdcall;
function TDockItemSetImageV1(Id: TDockItemId; Image: Pointer;
  AutoDelete: BOOL): BOOL; stdcall;
function TDockItemSetOverlayV1(Id: TDockItemId; Image: Pointer;
  AutoDelete: BOOL): BOOL; stdcall;
function TDockItemDockV1(Id: TDockItemId): BOOL; stdcall;
function TDockItemUndockV1(Id: TDockItemId): BOOL; stdcall;
function TDockItemAnimateV1(Id: TDockItemId): BOOL; stdcall;
```

`TDockApiVersion` returns `1` for this API.
Zero identifies hosts without this API.
An item ID identifies one model during its complete lifetime.
IDs do not identify windows or memory addresses.
Zero never identifies an item.
The host does not reuse retired IDs.

Use the conversion functions to obtain native windows or item IDs.
Never cast an item ID to `HWND`.
Never truncate an item ID to 32 bits.

## Creation and ownership

`TDockItemCreateV1` accepts the existing serialized item syntax and byte encoding.
The input string ends with a zero byte.
The host copies the input before returning.
A nil input returns zero.

Creation returns an owned pending item.
Pending items support caption, image, and window queries during `OnCreate`.
The host owns pending items until insertion, deletion, or manager disposal.
Plugins must not free item models or native item windows.

`TDockItemInsertV1` inserts a pending item at the current drop position.
It returns the same ID on success.
It returns zero when insertion fails.

`TDockItemDeleteV1` performs the host deletion operation.
Deleted active items remain available for undo.
Deletion hides and disables their native windows.
Undo keeps the item ID and the plugin native window.
The versioned API rejects deleted items until undo restores them.

All item operations validate the bound manager's ownership.
Foreign, deleted, retiring, and stale IDs return zero or `FALSE`.
Worker threads cannot access the bound manager through this API.

## Captions and images

Caption strings use UTF-16.
`TDockItemGetCaptionV1` returns the required UTF-16 capacity, including the final zero.
A valid empty caption requires one UTF-16 code unit.
An invalid item returns zero.

A nil buffer requests the required capacity.
A zero capacity leaves the buffer unchanged.
A nonzero capacity reserves one code unit for the final zero.
Short buffers receive a truncated caption and a final zero.
The function always returns the full required capacity.

`TDockItemSetCaptionV1` copies the caption before returning.
A nil caption returns `FALSE`.

Image arguments use the existing GDI+ image representation.
Image and overlay operations apply to plugin items.
The host keeps its own image copy.
`AutoDelete=TRUE` transfers the accepted source image to the host.
Ownership validation failures leave the source image with the caller.
The host can fail after it accepts source ownership.
`AutoDelete=FALSE` leaves the source image with the caller.

Dock, undock, and animation functions return `TRUE` for accepted owned items.
The animation setting can suppress the visible animation.

## Legacy compatibility

Legacy item operations first convert `HWND` to a checked stable item ID.
They then validate ownership and retain the model during the operation.
Plugin callback frames retain their models until the callbacks return.
Exceptions release these model leases through `finally` blocks.

Plugins retain real native item windows during their instance lifetime.
Native timers and window messages continue to use those windows.
Plugin window recreation raises an exception before changing the instance.
The exception preserves the item ID, native window, and plugin data.
Auxiliary drawing windows belong to the native view adapter.

`DockExecute`, hints, mouse-effect locks, and `ExcludeFromPeek` keep their existing native arguments.
These arguments can identify native windows that are not dock items.
The stable identity migration does not reinterpret those values.
Mouse-effect locking rejects zero, destroyed, and detaching native windows.
Deleted or retiring items cannot acquire new mouse-effect locks.
The adapter validates its native context before resolving an item window.
Lost or replaced contexts retire the old model without destroying a foreign window.

Legacy image and color dialogs require the bound UI thread.
The host retains an application operation until each dialog closes.
Nil image and color buffers return `FALSE`.
