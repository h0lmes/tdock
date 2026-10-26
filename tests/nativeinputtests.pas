unit nativeinputtests;

{$mode delphi}

interface

uses Windows, SysUtils, fpcunit, testregistry, win32inputu;

type
  TNativeInputTests = class(TTestCase)
  published
    procedure DecodesNativeMouseButtonUnion;
    procedure RejectsTruncatedMousePacket;
    procedure RejectsDeclaredSizeOutsideBuffer;
    procedure RejectsNonMouseInput;
    procedure ReadsQueriedPacketWithoutFixedBuffer;
  end;

implementation

uses JwaWinUser;

var fixture: array[0..55] of byte;

procedure WriteWord(offset: integer; value: WORD);
begin
  Move(value, fixture[offset], SizeOf(value));
end;

procedure WriteDWord(offset: integer; value: DWORD);
begin
  Move(value, fixture[offset], SizeOf(value));
end;

procedure PrepareMouse;
begin
  FillChar(fixture, SizeOf(fixture), 0);
  WriteDWord(0, RIM_TYPEMOUSE);
  WriteDWord(4, SizeOf(fixture));
  WriteWord(24, $1234);
  WriteWord(28, RI_MOUSE_LEFT_BUTTON_DOWN or RI_MOUSE_RIGHT_BUTTON_DOWN);
  WriteWord(30, $ff88);
  WriteDWord(32, $abcdef01);
  WriteDWord(36, DWORD(-123));
  WriteDWord(40, 456);
  WriteDWord(44, $12345678);
end;

function ReadFixture(InputHandle: THandle; Command: UINT; Buffer: Pointer;
  var BufferSize: UINT; HeaderSize: UINT): UINT; stdcall;
begin
  if Buffer = nil then
  begin
    BufferSize := SizeOf(fixture);
    exit(0);
  end;
  if (BufferSize < SizeOf(fixture)) or (HeaderSize <> 24) then exit(UINT(-1));
  Move(fixture, Buffer^, SizeOf(fixture));
  result := SizeOf(fixture);
end;

procedure TNativeInputTests.DecodesNativeMouseButtonUnion;
var mouse: TRawMouseData;
begin
  PrepareMouse;
  AssertTrue(DecodeRawMouse(@fixture, SizeOf(fixture), mouse));
  AssertEquals('Native button flags start at byte 28', 5, integer(mouse.ButtonFlags));
  AssertEquals($ff88, integer(mouse.ButtonData));
  AssertEquals(-123, mouse.LastX);
  AssertEquals(456, mouse.LastY);
  AssertEquals(int64($abcdef01), int64(mouse.RawButtons));
end;

procedure TNativeInputTests.RejectsTruncatedMousePacket;
var mouse: TRawMouseData;
begin
  PrepareMouse;
  AssertFalse('A mouse payload requires 24 bytes after its 24-byte header',
    DecodeRawMouse(@fixture, 46, mouse));
end;

procedure TNativeInputTests.RejectsDeclaredSizeOutsideBuffer;
var mouse: TRawMouseData;
begin
  PrepareMouse;
  WriteDWord(4, 100);
  AssertFalse('Declared packet size cannot exceed the received bytes',
    DecodeRawMouse(@fixture, SizeOf(fixture), mouse));
end;

procedure TNativeInputTests.RejectsNonMouseInput;
var mouse: TRawMouseData;
begin
  PrepareMouse;
  WriteDWord(0, RIM_TYPEKEYBOARD);
  AssertFalse(DecodeRawMouse(@fixture, SizeOf(fixture), mouse));
end;

procedure TNativeInputTests.ReadsQueriedPacketWithoutFixedBuffer;
var mouse: TRawMouseData;
begin
  PrepareMouse;
  AssertTrue(ReadRawMouse(0, mouse, ReadFixture));
  AssertEquals(5, integer(mouse.ButtonFlags));
end;

initialization
  RegisterTest(TNativeInputTests);
end.
