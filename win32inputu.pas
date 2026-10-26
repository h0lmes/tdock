unit win32inputu;

{$mode delphi}

interface

uses Windows;

type
  TRawMouseData = record
    Flags, ButtonFlags, ButtonData: WORD;
    RawButtons, ExtraInformation: DWORD;
    LastX, LastY: LONG;
  end;
  TRawInputReader = function(InputHandle: THandle; Command: UINT; Buffer: Pointer;
    var BufferSize: UINT; HeaderSize: UINT): UINT; stdcall;

function DecodeRawMouse(Buffer: Pointer; BufferSize: UINT;
  out Mouse: TRawMouseData): boolean;
function ReadRawMouse(InputHandle: THandle; out Mouse: TRawMouseData;
  Reader: TRawInputReader = nil): boolean;

implementation

uses JwaWinUser;

function DecodeRawMouse(Buffer: Pointer; BufferSize: UINT;
  out Mouse: TRawMouseData): boolean;
var header: JwaWinUser.RAWINPUTHEADER; rawMouse: JwaWinUser.RAWMOUSE;
  required: UINT;
begin
  Mouse := Default(TRawMouseData);
  result := false;
  if (Buffer = nil) or (BufferSize < SizeOf(header)) then exit;
  Move(Buffer^, header, SizeOf(header));
  required := SizeOf(header) + SizeOf(rawMouse);
  if (header.dwType <> RIM_TYPEMOUSE) or (header.dwSize < required) or
     (header.dwSize > BufferSize) then exit;
  Move((PByte(Buffer) + SizeOf(header))^, rawMouse, SizeOf(rawMouse));
  with rawMouse do
  begin
    Mouse.Flags := usFlags;
    Mouse.ButtonFlags := union.usButtonFlags;
    Mouse.ButtonData := union.usButtonData;
    Mouse.RawButtons := ulRawButtons;
    Mouse.ExtraInformation := ulExtraInformation;
    Mouse.LastX := lLastX;
    Mouse.LastY := lLastY;
  end;
  result := true;
end;

function ReadRawMouse(InputHandle: THandle; out Mouse: TRawMouseData;
  Reader: TRawInputReader): boolean;
var size, capacity, received: UINT; data: array of byte;
begin
  Mouse := Default(TRawMouseData);
  result := false;
  if not assigned(Reader) then Reader := JwaWinUser.GetRawInputData;
  size := 0;
  if Reader(InputHandle, RID_INPUT, nil, size, SizeOf(JwaWinUser.RAWINPUTHEADER)) <> 0 then exit;
  if size < SizeOf(JwaWinUser.RAWINPUTHEADER) then exit;
  capacity := size;
  SetLength(data, size);
  received := Reader(InputHandle, RID_INPUT, @data[0], size, SizeOf(JwaWinUser.RAWINPUTHEADER));
  if (received = UINT(-1)) or (received > capacity) or (size > capacity) then exit;
  result := DecodeRawMouse(@data[0], received, Mouse);
end;

end.
