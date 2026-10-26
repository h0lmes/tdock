unit win32hotkeyu;

{$mode delphi}

interface

uses Windows;

type
  TRegisterDockHotkey = function(Window: HWND; Id: Integer;
    Modifiers, Key: UINT): BOOL; stdcall;
  TUnregisterDockHotkey = function(Window: HWND; Id: Integer): BOOL; stdcall;
  TDockHotkeyBinding = record
    Enabled, Registered: Boolean;
    Shortcut, NativeId: Integer;
  end;
  TDockHotkeys = class
  private
    FWindow: HWND;
    FBindings: array[0..1] of TDockHotkeyBinding;
    FSuspended: Boolean;
    FNextId: Integer;
    FRegister: TRegisterDockHotkey;
    FUnregister: TUnregisterDockHotkey;
    procedure Rebind(Index: Integer);
  public
    constructor Create(Window: HWND; RegisterProc: TRegisterDockHotkey = nil;
      UnregisterProc: TUnregisterDockHotkey = nil);
    destructor Destroy; override;
    procedure Configure(Index: Integer; Enabled: Boolean; Shortcut: Integer);
    procedure Suspend(Value: Boolean);
    function Resolve(NativeId: Integer; KeyData: LPARAM): Integer;
    function Registered(Index: Integer): Boolean;
    function NeedsFallback: Boolean;
    function Binding(Index: Integer): TDockHotkeyBinding;
  end;

function HotkeyModifiers(Shortcut: Integer): UINT;
function HotkeyKey(Shortcut: Integer): UINT;

implementation

constructor TDockHotkeys.Create(Window: HWND; RegisterProc: TRegisterDockHotkey;
  UnregisterProc: TUnregisterDockHotkey);
begin
  inherited Create;
  FWindow := Window;
  FRegister := RegisterProc;
  FUnregister := UnregisterProc;
  if not Assigned(FRegister) then FRegister := Windows.RegisterHotKey;
  if not Assigned(FUnregister) then FUnregister := Windows.UnregisterHotKey;
  FNextId := $6200;
end;
destructor TDockHotkeys.Destroy;
begin
  Suspend(True);
  inherited Destroy;
end;
procedure TDockHotkeys.Rebind(Index: Integer);
begin
  if FBindings[Index].Registered then
    FUnregister(FWindow, FBindings[Index].NativeId);
  FBindings[Index].Registered := False;
  FBindings[Index].NativeId := 0;
  if FSuspended or not FBindings[Index].Enabled or
    (HotkeyKey(FBindings[Index].Shortcut) = 0) then Exit;
  Inc(FNextId);
  if FNextId > $BFFF then FNextId := $6200;
  FBindings[Index].NativeId := FNextId;
  FBindings[Index].Registered := FRegister(FWindow, FNextId,
    HotkeyModifiers(FBindings[Index].Shortcut) or $4000,
    HotkeyKey(FBindings[Index].Shortcut));
end;
procedure TDockHotkeys.Configure(Index: Integer; Enabled: Boolean; Shortcut: Integer);
begin
  if (Index < 0) or (Index > High(FBindings)) then Exit;
  if (FBindings[Index].Enabled = Enabled) and (FBindings[Index].Shortcut = Shortcut) then Exit;
  FBindings[Index].Enabled := Enabled;
  FBindings[Index].Shortcut := Shortcut;
  Rebind(Index);
end;
procedure TDockHotkeys.Suspend(Value: Boolean);
var Index: Integer;
begin
  if FSuspended = Value then Exit;
  FSuspended := Value;
  for Index := 0 to High(FBindings) do Rebind(Index);
end;
function TDockHotkeys.Resolve(NativeId: Integer; KeyData: LPARAM): Integer;
var Index: Integer;
begin
  Result := -1;
  if FSuspended then Exit;
  for Index := 0 to High(FBindings) do
    if FBindings[Index].Registered and (NativeId = FBindings[Index].NativeId) and
      (UINT((KeyData shr 16) and $FFFF) = HotkeyKey(FBindings[Index].Shortcut)) and
      (UINT(KeyData and $FFFF) = HotkeyModifiers(FBindings[Index].Shortcut)) then Exit(Index);
end;
function TDockHotkeys.Registered(Index: Integer): Boolean;
begin Result := (Index >= 0) and (Index <= High(FBindings)) and FBindings[Index].Registered; end;
function TDockHotkeys.NeedsFallback: Boolean;
var Index: Integer;
begin
  Result := False;
  if FSuspended then Exit;
  for Index := 0 to High(FBindings) do
    if FBindings[Index].Enabled and not FBindings[Index].Registered and
      (HotkeyKey(FBindings[Index].Shortcut) <> 0) then Exit(True);
end;
function TDockHotkeys.Binding(Index: Integer): TDockHotkeyBinding;
begin
  Result := Default(TDockHotkeyBinding);
  if (Index >= 0) and (Index <= High(FBindings)) then Result := FBindings[Index];
end;
function HotkeyModifiers(Shortcut: Integer): UINT;
begin
  Result := 0;
  if Shortcut and $2000 <> 0 then Result := Result or MOD_SHIFT;
  if Shortcut and $4000 <> 0 then Result := Result or MOD_CONTROL;
  if Shortcut and $8000 <> 0 then Result := Result or MOD_ALT;
end;
function HotkeyKey(Shortcut: Integer): UINT;
begin
  Result := UINT(Shortcut and not $E000);
  if Result > 255 then Result := 0;
end;
end.
