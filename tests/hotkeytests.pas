unit hotkeytests;
{$mode delphi}
interface
uses Windows, fpcunit, testregistry, win32hotkeyu;
type
  THotkeyTests = class(TTestCase)
  protected
    procedure SetUp; override;
  published
    procedure RegistersGlobalWindowBinding;
    procedure SettingsSuspendRejectsQueuedPresses;
    procedure ReplacementRejectsOldIdentity;
    procedure ConflictUsesFallback;
  end;
implementation
var LastWindow: HWND; LastModifiers, LastKey: UINT; CanRegister: Boolean;
function RegisterTestHotkey(Window: HWND; Id: Integer; Modifiers, Key: UINT): BOOL; stdcall;
begin LastWindow := Window; LastModifiers := Modifiers; LastKey := Key; Result := CanRegister; end;
function UnregisterTestHotkey(Window: HWND; Id: Integer): BOOL; stdcall;
begin Result := True; end;
procedure THotkeyTests.SetUp;
begin CanRegister := True; LastWindow := 0; LastModifiers := 0; LastKey := 0; end;
procedure THotkeyTests.RegistersGlobalWindowBinding;
var Keys: TDockHotkeys; Data: LPARAM;
begin
  Keys := TDockHotkeys.Create(12345, RegisterTestHotkey, UnregisterTestHotkey);
  try
    Keys.Configure(0, True, $4000 or VK_F24);
    AssertEquals(QWord(12345), QWord(LastWindow));
    AssertEquals(UINT(MOD_CONTROL or $4000), LastModifiers);
    AssertEquals(UINT(VK_F24), LastKey);
    Data := (LPARAM(VK_F24) shl 16) or MOD_CONTROL;
    AssertEquals(0, Keys.Resolve(Keys.Binding(0).NativeId, Data));
    AssertFalse(Keys.NeedsFallback);
  finally Keys.Free; end;
end;
procedure THotkeyTests.SettingsSuspendRejectsQueuedPresses;
var Keys: TDockHotkeys; OldId: Integer; Data: LPARAM;
begin
  Keys := TDockHotkeys.Create(1, RegisterTestHotkey, UnregisterTestHotkey);
  try
    Keys.Configure(0, True, VK_F24);
    OldId := Keys.Binding(0).NativeId;
    Data := LPARAM(VK_F24) shl 16;
    Keys.Suspend(True);
    AssertEquals(-1, Keys.Resolve(OldId, Data));
    Keys.Suspend(False);
    AssertEquals(-1, Keys.Resolve(OldId, Data));
    AssertEquals(0, Keys.Resolve(Keys.Binding(0).NativeId, Data));
  finally Keys.Free; end;
end;
procedure THotkeyTests.ReplacementRejectsOldIdentity;
var Keys: TDockHotkeys; OldId: Integer;
begin
  Keys := TDockHotkeys.Create(1, RegisterTestHotkey, UnregisterTestHotkey);
  try
    Keys.Configure(0, True, VK_F23);
    OldId := Keys.Binding(0).NativeId;
    Keys.Configure(0, True, VK_F24);
    AssertEquals(-1, Keys.Resolve(OldId, LPARAM(VK_F23) shl 16));
    AssertEquals(0, Keys.Resolve(Keys.Binding(0).NativeId, LPARAM(VK_F24) shl 16));
  finally Keys.Free; end;
end;
procedure THotkeyTests.ConflictUsesFallback;
var Keys: TDockHotkeys;
begin
  CanRegister := False;
  Keys := TDockHotkeys.Create(1, RegisterTestHotkey, UnregisterTestHotkey);
  try
    Keys.Configure(0, True, VK_F24);
    AssertTrue(Keys.NeedsFallback);
    Keys.Suspend(True);
    AssertFalse(Keys.NeedsFallback);
  finally Keys.Free; end;
end;
initialization RegisterTest(THotkeyTests);
end.
