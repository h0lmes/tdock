unit appwindowsu;

{$mode delphi}

interface

uses Windows;

type
  TApplicationWindows = array of HWND;

function IsApplicationWindow(Window: HWND): Boolean;
function CaptureApplicationWindows(out Handles: TApplicationWindows;
  out TotalWindowCount: Integer): Boolean;

implementation

uses dwm_unit;

type
  TWindowEnumeration = record
    Handles: TApplicationWindows;
    TotalCount: Integer;
    Failed: Boolean;
  end;
  PWindowEnumeration = ^TWindowEnumeration;

function IsApplicationWindow(Window: HWND): Boolean;
var ExStyle: PtrUInt; Caption: array[0..10] of Char;
begin
  Result := False;
  if not IsWindowVisible(Window) then Exit;
  ExStyle := Windows.GetWindowLongPtr(Window, GWL_EXSTYLE);
  // Preserve the task list's explicit APPWINDOW override.
  if ExStyle and WS_EX_APPWINDOW = 0 then
  begin
    if GetWindow(Window, GW_OWNER) <> 0 then Exit;
    if ExStyle and WS_EX_TOOLWINDOW <> 0 then Exit;
    if Windows.GetWindowText(Window, @Caption[0], 10) < 1 then Exit;
    if GetProp(Window, 'ITaskList_Deleted') <> 0 then Exit;
    if Assigned(DWM) and DWM.IsWindowCloaked(Window) then Exit;
  end;
  Result := True;
end;

function CollectApplicationWindow(Window: HWND; Parameter: LPARAM): WINBOOL; stdcall;
var State: PWindowEnumeration; N: Integer;
begin
  State := PWindowEnumeration(Parameter);
  Result := False;
  // Exceptions must not cross a native callback boundary.
  try
    Inc(State^.TotalCount);
    if IsApplicationWindow(Window) then
    begin
      N := Length(State^.Handles);
      SetLength(State^.Handles, N + 1);
      State^.Handles[N] := Window;
    end;
    Result := True;
  except
    State^.Failed := True;
  end;
end;

function CaptureApplicationWindows(out Handles: TApplicationWindows;
  out TotalWindowCount: Integer): Boolean;
var State: TWindowEnumeration;
begin
  State := Default(TWindowEnumeration);
  Handles := nil;
  TotalWindowCount := 0;
  Result := EnumWindows(@CollectApplicationWindow, LPARAM(@State));
  Result := Result and not State.Failed;
  if not Result then Exit;
  Handles := State.Handles;
  TotalWindowCount := State.TotalCount;
end;

end.
