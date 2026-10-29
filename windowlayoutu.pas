unit windowlayoutu;

{$mode delphi}

interface

uses Windows, SysUtils, appwindowsu;

type
  TLayoutDisplay = record
    Device: UnicodeString;
    Bounds, WorkArea: TRect;
    Primary: Boolean;
    Orientation, Scale: DWORD;
  end;
  TLayoutDisplays = array of TLayoutDisplay;
  TWindowLayoutEntry = record
    Window: HWND;
    ProcessId, ThreadId: DWORD;
    Description: string;
    Marker: UnicodeString;
    Placement: TWindowPlacement;
  end;
  TWindowLayoutEntries = array of TWindowLayoutEntry;
  TWindowLayoutStatus = (wlsSaved, wlsRestored, wlsNoSnapshot,
    wlsDisplayChanged, wlsUnavailable, wlsSaveFailed, wlsBusy);
  TWindowLayoutFailure = record
    Description, Reason: string;
  end;
  TWindowLayoutFailures = array of TWindowLayoutFailure;
  TWindowLayoutResult = record
    Status: TWindowLayoutStatus;
    Saved, Restored, Skipped, Failed: Integer;
    Failures: TWindowLayoutFailures;
  end;

  TWindowLayoutService = class
  private
    FEntries: TWindowLayoutEntries;
    FDisplays: TLayoutDisplays;
    FHasSnapshot, FBusy: Boolean;
    procedure ReleaseEntries(var Entries: TWindowLayoutEntries);
  protected
    function ReadWindows(out Handles: TApplicationWindows): Boolean; virtual;
    function ReadDisplays(out Displays: TLayoutDisplays): Boolean; virtual;
    function DescribeWindow(Window: HWND): string; virtual;
    function CaptureWindow(Window: HWND; out Entry: TWindowLayoutEntry;
      out Reason: string): Boolean; virtual;
    function MatchesWindow(const Entry: TWindowLayoutEntry): Boolean; virtual;
    function EligibleWindow(Window: HWND): Boolean; virtual;
    function ApplyWindow(const Entry: TWindowLayoutEntry; out Reason: string): Boolean; virtual;
    procedure ReleaseWindow(const Entry: TWindowLayoutEntry); virtual;
  public
    destructor Destroy; override;
    function Save: TWindowLayoutResult;
    function Restore: TWindowLayoutResult;
  end;

function SameLayoutDisplays(const Saved, Current: TLayoutDisplays): Boolean;
function WindowLayoutMessage(const Outcome: TWindowLayoutResult): string;

implementation

uses JwaWinUser;

resourcestring
  XWindowsSaved = 'Window layout saved: %d. Failed: %d.';
  XWindowsRestored = 'Windows restored: %d. Skipped: %d. Failed: %d.';
  XWindowsNoSnapshot = 'No window layout saved. Use /savewindows first.';
  XWindowsDisplayChanged = 'Display setup differs. Restore the saved resolution, monitors, scaling, and work areas first.';
  XWindowsUnavailable = 'Cannot read application windows or display settings. Saved layout unchanged.';
  XWindowsSaveFailed = 'No windows saved. Previous layout unchanged. Failed: %d.';
  XWindowsBusy = 'A window layout command is already running.';
  XWindowWithProcess = '"%s" (PID %d)';
  XWindowWithHandle = '%s (window 0x%s)';
  XWindowUnknown = 'Window 0x%s';
  XWindowUntitled = 'Untitled window [%s]';
  XWindowFailure = '- %s: %s';
  XWindowUnknownFailure = 'The application did not provide an error reason.';
  XWindowAccessDenied = '%s: access denied (Windows error %d). The application may run as administrator.';
  XWindowSystemError = '%s: %s (Windows error %d).';
  XWindowErrorCode = '%s (Windows error %d).';
  XWindowIdentifyFailed = 'Cannot identify the window';
  XWindowMarkerFailed = 'Cannot create a window identity marker (HRESULT 0x%s).';
  XWindowMarkFailed = 'Cannot mark window identity';
  XWindowPlacementFailed = 'Cannot read window placement';
  XWindowBoundsFailed = 'Cannot read window size and position';
  XWindowMonitorFailed = 'Cannot read the window monitor';
  XWindowRestoreFailed = 'Cannot restore window placement';
  XWindowChanged = 'The window closed or changed.';

type
  TLayoutMonitorInfo = record
    Size: DWORD;
    Bounds, WorkArea: TRect;
    Flags: DWORD;
    Device: array[0..31] of WideChar;
  end;
  TGetMonitorScale = function(Monitor: HMONITOR; out Scale: Integer): HRESULT; stdcall;
  TDisplayEnumeration = record
    Displays: TLayoutDisplays;
    GetScale: TGetMonitorScale;
    FallbackScale: Integer;
    Failed: Boolean;
  end;
  PDisplayEnumeration = ^TDisplayEnumeration;

function ReadMonitorInfo(Monitor: HMONITOR; Info: Pointer): WINBOOL; stdcall;
  external 'user32.dll' name 'GetMonitorInfoW';

function SingleLine(const Text: string): string;
begin
  Result := StringReplace(Text, #13, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #9, ' ', [rfReplaceAll]);
end;

function WindowSystemError(const Operation: string; ErrorCode: DWORD): string;
var Buffer: array[0..1023] of WideChar; Count: DWORD; ErrorText: string;
begin
  // Use the captured code. Cleanup calls can change the thread's last error.
  if ErrorCode = ERROR_SUCCESS then Exit(Operation);
  if ErrorCode = ERROR_ACCESS_DENIED then
    Exit(Format(XWindowAccessDenied, [Operation, ErrorCode]));
  Count := Windows.FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM or FORMAT_MESSAGE_IGNORE_INSERTS,
    nil, ErrorCode, 0, @Buffer[0], Length(Buffer), nil);
  if Count = 0 then Exit(Format(XWindowErrorCode, [Operation, ErrorCode]));
  ErrorText := SingleLine(UTF8Encode(Trim(UnicodeString(PWideChar(@Buffer[0])))));
  Result := Format(XWindowSystemError, [Operation, ErrorText, ErrorCode]);
end;

procedure AddWindowFailure(var Outcome: TWindowLayoutResult; Window: HWND;
  const Description, Reason: string);
var N: Integer;
begin
  N := Length(Outcome.Failures);
  SetLength(Outcome.Failures, N + 1);
  if Description <> '' then Outcome.Failures[N].Description := SingleLine(Description)
  else Outcome.Failures[N].Description := Format(XWindowUnknown,
    [IntToHex(PtrUInt(Window), SizeOf(HWND) * 2)]);
  if Reason <> '' then Outcome.Failures[N].Reason := SingleLine(Reason)
  else Outcome.Failures[N].Reason := XWindowUnknownFailure;
  Inc(Outcome.Failed);
end;

function SameRect(const A, B: TRect): Boolean;
begin
  Result := (A.Left = B.Left) and (A.Top = B.Top) and
    (A.Right = B.Right) and (A.Bottom = B.Bottom);
end;

function SameLayoutDisplays(const Saved, Current: TLayoutDisplays): Boolean;
var I, J: Integer; Found: Boolean;
begin
  Result := False;
  if (Length(Saved) = 0) or (Length(Saved) <> Length(Current)) then Exit;
  // Monitor enumeration order can change without a layout change.
  for I := 0 to High(Saved) do
  begin
    Found := False;
    for J := 0 to High(Current) do
      if Saved[I].Device = Current[J].Device then
      begin
        Found := SameRect(Saved[I].Bounds, Current[J].Bounds) and
          SameRect(Saved[I].WorkArea, Current[J].WorkArea) and
          (Saved[I].Primary = Current[J].Primary) and
          (Saved[I].Orientation = Current[J].Orientation) and
          (Saved[I].Scale = Current[J].Scale);
        Break;
      end;
    if not Found then Exit;
  end;
  Result := True;
end;

function CollectDisplay(Monitor: HMONITOR; DC: HDC; Bounds: PRect;
  Parameter: LPARAM): WINBOOL; stdcall;
var State: PDisplayEnumeration; Info: TLayoutMonitorInfo;
  Mode: Windows.TDevModeW; Scale, N: Integer;
begin
  State := PDisplayEnumeration(Parameter);
  Result := False;
  try
    Info := Default(TLayoutMonitorInfo);
    Info.Size := SizeOf(Info);
    if not ReadMonitorInfo(Monitor, @Info) then
    begin State^.Failed := True; Exit; end;
    Mode := Default(Windows.TDevModeW);
    Mode.dmSize := SizeOf(Mode);
    if not Windows.EnumDisplaySettingsW(Info.Device, DWORD(-1), @Mode) then
    begin State^.Failed := True; Exit; end;
    Scale := State^.FallbackScale;
    if Assigned(State^.GetScale) then
      if State^.GetScale(Monitor, Scale) <> S_OK then
      begin State^.Failed := True; Exit; end;
    N := Length(State^.Displays);
    SetLength(State^.Displays, N + 1);
    State^.Displays[N].Device := Info.Device;
    State^.Displays[N].Bounds := Info.Bounds;
    State^.Displays[N].WorkArea := Info.WorkArea;
    State^.Displays[N].Primary := Info.Flags and MONITORINFOF_PRIMARY <> 0;
    State^.Displays[N].Orientation := Mode.dmDisplayOrientation;
    State^.Displays[N].Scale := Scale;
    Result := True;
  except
    State^.Failed := True;
  end;
end;

function TWindowLayoutService.ReadDisplays(out Displays: TLayoutDisplays): Boolean;
var State: TDisplayEnumeration; LibraryHandle: HMODULE;
  SystemPath: array[0..MAX_PATH] of WideChar; DirectoryLength: UINT; DC: HDC;
begin
  Displays := nil;
  State := Default(TDisplayEnumeration);
  State.FallbackScale := 100;
  DC := GetDC(0);
  if DC <> 0 then
  try State.FallbackScale := MulDiv(GetDeviceCaps(DC, LOGPIXELSX), 100, 96);
  finally ReleaseDC(0, DC); end;
  LibraryHandle := 0;
  // Load the optional scaling API by its full system path. Vista remains supported.
  DirectoryLength := GetSystemDirectoryW(SystemPath, Length(SystemPath));
  if (DirectoryLength > 0) and (DirectoryLength < UINT(Length(SystemPath))) then
    LibraryHandle := LoadLibraryW(PWideChar(UnicodeString(SystemPath) + '\shcore.dll'));
  try
    if LibraryHandle <> 0 then
      State.GetScale := TGetMonitorScale(GetProcAddress(LibraryHandle, 'GetScaleFactorForMonitor'));
    Result := EnumDisplayMonitors(0, nil, @CollectDisplay, LPARAM(@State));
    Result := Result and not State.Failed and (Length(State.Displays) > 0);
    if Result then Displays := State.Displays;
  finally
    if LibraryHandle <> 0 then FreeLibrary(LibraryHandle);
  end;
end;

function TWindowLayoutService.ReadWindows(out Handles: TApplicationWindows): Boolean;
var TotalCount: Integer;
begin
  Result := CaptureApplicationWindows(Handles, TotalCount);
end;

function TWindowLayoutService.DescribeWindow(Window: HWND): string;
var Buffer: array[0..511] of WideChar; Count: Integer; ProcessId: DWORD;
  Caption: string;
begin
  ProcessId := 0;
  GetWindowThreadProcessId(Window, @ProcessId);
  Count := Windows.GetWindowTextW(Window, @Buffer[0], Length(Buffer));
  if Count > 0 then Caption := UTF8Encode(UnicodeString(PWideChar(@Buffer[0])))
  else
  begin
    Count := Windows.GetClassNameW(Window, @Buffer[0], Length(Buffer));
    if Count > 0 then
      Caption := Format(XWindowUntitled, [UTF8Encode(UnicodeString(PWideChar(@Buffer[0])))])
    else Exit(Format(XWindowUnknown, [IntToHex(PtrUInt(Window), SizeOf(HWND) * 2)]));
  end;
  Caption := SingleLine(Caption);
  if ProcessId <> 0 then Result := Format(XWindowWithProcess, [Caption, ProcessId])
  else Result := Format(XWindowWithHandle,
    [Caption, IntToHex(PtrUInt(Window), SizeOf(HWND) * 2)]);
end;

function TWindowLayoutService.CaptureWindow(Window: HWND;
  out Entry: TWindowLayoutEntry; out Reason: string): Boolean;
var Id: TGUID; Bounds: TRect; Info: TLayoutMonitorInfo; Status: HRESULT;
  ErrorCode: DWORD;
begin
  Result := False;
  Reason := '';
  Entry := Default(TWindowLayoutEntry);
  Entry.Window := Window;
  Windows.SetLastError(ERROR_SUCCESS);
  Entry.ThreadId := GetWindowThreadProcessId(Window, @Entry.ProcessId);
  if Entry.ThreadId = 0 then
  begin
    ErrorCode := Windows.GetLastError;
    Reason := WindowSystemError(XWindowIdentifyFailed, ErrorCode);
    Exit;
  end;
  Status := CreateGUID(Id);
  if Status <> S_OK then
  begin Reason := Format(XWindowMarkerFailed, [IntToHex(DWORD(Status), 8)]); Exit; end;
  // Mark the lifetime before reading geometry. A replacement cannot retain it.
  Entry.Marker := 'TDock.WindowLayout.' + UnicodeString(GUIDToString(Id));
  Windows.SetLastError(ERROR_SUCCESS);
  if not SetPropW(Window, PWideChar(Entry.Marker), THandle(1)) then
  begin
    ErrorCode := Windows.GetLastError;
    Reason := WindowSystemError(XWindowMarkFailed, ErrorCode);
    Exit;
  end;
  try
    Entry.Placement.length := SizeOf(Entry.Placement);
    Windows.SetLastError(ERROR_SUCCESS);
    if not Windows.GetWindowPlacement(Window, @Entry.Placement) then
    begin
      ErrorCode := Windows.GetLastError;
      Reason := WindowSystemError(XWindowPlacementFailed, ErrorCode);
      Exit;
    end;
    if Entry.Placement.showCmd = SW_SHOWNORMAL then
    begin
      // Snapped windows can have different visible and normal rectangles.
      Windows.SetLastError(ERROR_SUCCESS);
      if not GetWindowRect(Window, Bounds) then
      begin
        ErrorCode := Windows.GetLastError;
        Reason := WindowSystemError(XWindowBoundsFailed, ErrorCode);
        Exit;
      end;
      if Windows.GetWindowLongPtr(Window, GWL_EXSTYLE) and WS_EX_TOOLWINDOW = 0 then
      begin
        Info := Default(TLayoutMonitorInfo);
        Info.Size := SizeOf(Info);
        Windows.SetLastError(ERROR_SUCCESS);
        if not ReadMonitorInfo(MonitorFromWindow(Window, MONITOR_DEFAULTTONEAREST), @Info) then
        begin
          ErrorCode := Windows.GetLastError;
          Reason := WindowSystemError(XWindowMonitorFailed, ErrorCode);
          Exit;
        end;
        OffsetRect(Bounds, Info.Bounds.Left - Info.WorkArea.Left,
          Info.Bounds.Top - Info.WorkArea.Top);
      end;
      Entry.Placement.rcNormalPosition := Bounds;
    end;
    Result := MatchesWindow(Entry);
    if not Result then Reason := XWindowChanged;
  finally
    if not Result then ReleaseWindow(Entry);
  end;
end;

function TWindowLayoutService.MatchesWindow(const Entry: TWindowLayoutEntry): Boolean;
var ProcessId, ThreadId: DWORD;
begin
  Result := False;
  if (Entry.Window = 0) or (Entry.Marker = '') then Exit;
  ProcessId := 0;
  ThreadId := GetWindowThreadProcessId(Entry.Window, @ProcessId);
  Result := (ThreadId <> 0) and (ThreadId = Entry.ThreadId) and
    (ProcessId = Entry.ProcessId) and
    (GetPropW(Entry.Window, PWideChar(Entry.Marker)) = THandle(1));
end;

function TWindowLayoutService.EligibleWindow(Window: HWND): Boolean;
begin
  Result := IsApplicationWindow(Window);
end;

function TWindowLayoutService.ApplyWindow(const Entry: TWindowLayoutEntry;
  out Reason: string): Boolean;
var Placement: Windows.TWindowPlacement; Foreground, Previous: HWND; Flags: UINT;
  Topmost: Boolean; ErrorCode: DWORD;
begin
  Result := False;
  Reason := '';
  if not MatchesWindow(Entry) or not EligibleWindow(Entry.Window) then
  begin Reason := XWindowChanged; Exit; end;
  Foreground := GetForegroundWindow;
  Previous := GetWindow(Entry.Window, GW_HWNDPREV);
  Topmost := Windows.GetWindowLongPtr(Entry.Window, GWL_EXSTYLE) and WS_EX_TOPMOST <> 0;
  // Keep restoration within the window's current topmost band.
  while Previous <> 0 do
  begin
    if (Windows.GetWindowLongPtr(Previous, GWL_EXSTYLE) and WS_EX_TOPMOST <> 0) = Topmost then Break;
    Previous := GetWindow(Previous, GW_HWNDPREV);
  end;
  if Previous = 0 then
    if Topmost then Previous := HWND_TOPMOST else Previous := HWND_TOP;
  Placement := Entry.Placement;
  Placement.length := SizeOf(Placement);
  Placement.flags := Placement.flags or WPF_ASYNCWINDOWPLACEMENT;
  if Placement.showCmd = SW_SHOWNORMAL then Placement.showCmd := SW_SHOWNOACTIVATE;
  Windows.SetLastError(ERROR_SUCCESS);
  Result := Windows.SetWindowPlacement(Entry.Window, @Placement);
  if not Result then
  begin
    ErrorCode := Windows.GetLastError;
    Reason := WindowSystemError(XWindowRestoreFailed, ErrorCode);
  end;
  if Result and MatchesWindow(Entry) then
  begin
    Flags := SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE or SWP_NOOWNERZORDER or SWP_ASYNCWINDOWPOS;
    SetWindowPos(Entry.Window, Previous, 0, 0, 0, 0, Flags);
  end;
  if (Foreground <> 0) and (GetForegroundWindow <> Foreground) and IsWindow(Foreground) then
    Windows.SetForegroundWindow(Foreground);
end;

procedure TWindowLayoutService.ReleaseWindow(const Entry: TWindowLayoutEntry);
begin
  if MatchesWindow(Entry) then RemovePropW(Entry.Window, PWideChar(Entry.Marker));
end;

procedure TWindowLayoutService.ReleaseEntries(var Entries: TWindowLayoutEntries);
var I: Integer;
begin
  for I := 0 to High(Entries) do
    try ReleaseWindow(Entries[I]); except end;
  Entries := nil;
end;

destructor TWindowLayoutService.Destroy;
begin
  ReleaseEntries(FEntries);
  inherited Destroy;
end;

function TWindowLayoutService.Save: TWindowLayoutResult;
var Handles: TApplicationWindows; Displays, Confirmed: TLayoutDisplays;
  Candidate: TWindowLayoutEntries; Entry: TWindowLayoutEntry; I, Count: Integer;
  Description, Reason: string; Captured: Boolean;
begin
  Result := Default(TWindowLayoutResult);
  Result.Status := wlsBusy;
  if FBusy then Exit;
  FBusy := True;
  Candidate := nil;
  try
    Result.Status := wlsUnavailable;
    if not ReadDisplays(Displays) or not ReadWindows(Handles) then Exit;
    SetLength(Candidate, Length(Handles));
    Count := 0;
    for I := 0 to High(Handles) do
    begin
      Entry := Default(TWindowLayoutEntry);
      Description := '';
      Reason := '';
      Captured := False;
      try
        Description := DescribeWindow(Handles[I]);
        Captured := CaptureWindow(Handles[I], Entry, Reason);
      except
        on E: Exception do Reason := E.Message;
      end;
      if Captured then
      begin
        Entry.Description := Description;
        Candidate[Count] := Entry;
        Inc(Count);
      end
      else
      begin
        try ReleaseWindow(Entry); except end;
        AddWindowFailure(Result, Handles[I], Description, Reason);
      end;
    end;
    if not ReadDisplays(Confirmed) then Exit;
    Result.Status := wlsDisplayChanged;
    if not SameLayoutDisplays(Displays, Confirmed) then Exit;
    Result.Status := wlsSaveFailed;
    if (Length(Handles) > 0) and (Count = 0) then Exit;
    SetLength(Candidate, Count);
    ReleaseEntries(FEntries);
    FEntries := Candidate;
    Candidate := nil;
    FDisplays := Displays;
    FHasSnapshot := True;
    Result.Status := wlsSaved;
    Result.Saved := Count;
  finally
    ReleaseEntries(Candidate);
    FBusy := False;
  end;
end;

function TWindowLayoutService.Restore: TWindowLayoutResult;
var Handles: TApplicationWindows; Displays: TLayoutDisplays;
  I, J: Integer; Found: Boolean;
  Description, Reason: string;
begin
  Result := Default(TWindowLayoutResult);
  Result.Status := wlsBusy;
  if FBusy then Exit;
  Result.Status := wlsNoSnapshot;
  if not FHasSnapshot then Exit;
  FBusy := True;
  try
    Result.Status := wlsUnavailable;
    if not ReadWindows(Handles) or not ReadDisplays(Displays) then Exit;
    Result.Status := wlsDisplayChanged;
    if not SameLayoutDisplays(FDisplays, Displays) then Exit;
    Result.Status := wlsRestored;
    for I := 0 to High(FEntries) do
    begin
      Found := False;
      for J := 0 to High(Handles) do
        if Handles[J] = FEntries[I].Window then
        begin Found := True; Break; end;
      Description := FEntries[I].Description;
      Reason := '';
      try
        if not Found or not MatchesWindow(FEntries[I]) or
          not EligibleWindow(FEntries[I].Window) then Inc(Result.Skipped)
        else
        begin
          Description := DescribeWindow(FEntries[I].Window);
          if ApplyWindow(FEntries[I], Reason) then Inc(Result.Restored)
          else if not MatchesWindow(FEntries[I]) or not EligibleWindow(FEntries[I].Window) then
            Inc(Result.Skipped)
          else AddWindowFailure(Result, FEntries[I].Window, Description, Reason);
        end;
      except
        on E: Exception do AddWindowFailure(Result, FEntries[I].Window, Description, E.Message);
      end;
    end;
  finally
    FBusy := False;
  end;
end;

function WindowLayoutMessage(const Outcome: TWindowLayoutResult): string;
var I: Integer;
begin
  case Outcome.Status of
    wlsSaved: Result := Format(XWindowsSaved, [Outcome.Saved, Outcome.Failed]);
    wlsRestored: Result := Format(XWindowsRestored,
      [Outcome.Restored, Outcome.Skipped, Outcome.Failed]);
    wlsNoSnapshot: Result := XWindowsNoSnapshot;
    wlsDisplayChanged: Result := XWindowsDisplayChanged;
    wlsUnavailable: Result := XWindowsUnavailable;
    wlsSaveFailed: Result := Format(XWindowsSaveFailed, [Outcome.Failed]);
    wlsBusy: Result := XWindowsBusy;
  end;
  for I := 0 to High(Outcome.Failures) do
    Result := Result + LineEnding + Format(XWindowFailure,
      [Outcome.Failures[I].Description, Outcome.Failures[I].Reason]);
end;

end.
