unit displayclocku;

{$mode delphi}

interface

uses Windows;

type
  TDisplayBinding = record
    Monitor: HMONITOR;
    DeviceName: string;
    RefreshRate: Double;
  end;
  TDisplayClockSource = (dcsTimer, dcsDwmTiming, dcsVerticalBlank);
  TDisplayClockWait = (dcwBoundary, dcwStop, dcwWake, dcwUnavailable);
  TDisplayClock = class
  private
    FAdapter, FSourceId: Cardinal;
    FMonitor: HMONITOR;
    FDwmModule: HMODULE;
    FDevice: string;
    FNextRetry: QWord;
    FLastNativeStatus: LongInt;
    FTimeoutEvent: THandle;
  protected
    FSource: TDisplayClockSource;
    FRefreshRate: Double;
    function OpenDisplay(const Device: string; out Adapter, SourceId: Cardinal): Boolean; virtual;
    function WaitDisplay(Adapter, SourceId: Cardinal; StopEvent, WakeEvent,
      TimeoutEvent: THandle): LongInt; virtual;
    procedure CloseDisplay(Adapter: Cardinal); virtual;
    function ReadPhysicalRefreshRate(const Device: string; FallbackHz: Double): Double; virtual;
    function ReadCompositionTiming(out PhaseMs, PeriodMs, Hz: Double): Boolean; virtual;
    function IsPrimaryDisplay: Boolean; virtual;
    function ClockTicks: QWord; virtual;
  public
    destructor Destroy; override;
    procedure Suspend; virtual;
    procedure Bind(Monitor: HMONITOR; const Device: string; Hz: Double); virtual;
    function WaitBoundary(StopEvent, WakeEvent, TimeoutEvent: THandle): TDisplayClockWait; virtual;
    function ReadPhase(out PhaseMs, PeriodMs: Double): Boolean; virtual;
    property Source: TDisplayClockSource read FSource;
    property RefreshRate: Double read FRefreshRate;
    property LastNativeStatus: LongInt read FLastNativeStatus;
  end;

function WindowDisplayBinding(Window: HWND): TDisplayBinding;
function NextDisplayBoundary(NowMs, PhaseMs, PeriodMs: Double; EarliestMs: Double = 0): Double;

implementation

uses Math, MultiMon, SysUtils;

type
  // Windows uses pointer-sized D3DKMT_PTR_TYPE handles, including WOW64.
  {$push}{$packrecords c}
  TKmtOpenAdapter = record
    Dc: HDC;
    Adapter: Cardinal;
    AdapterLuid: LUID;
    SourceId: Cardinal;
  end;
  TKmtWaitBlank = record
    Adapter, Device, SourceId, ObjectCount: Cardinal;
    Objects: array[0..7] of THandle;
  end;
  TKmtCloseAdapter = record Adapter: Cardinal; end;
  TKmtOpen = function(var Data: TKmtOpenAdapter): LongInt; stdcall;
  TKmtWait = function(Data: Pointer): LongInt; stdcall;
  TKmtClose = function(Data: Pointer): LongInt; stdcall;
  TDisplayRatio = record Numerator, Denominator: Cardinal; end;
  TDisplayPathSource = record
    Adapter: LUID;
    Id, ModeIndex, Flags: Cardinal;
  end;
  TDisplayPathTarget = record
    Adapter: LUID;
    Id, ModeIndex, Technology, Rotation, Scaling: Cardinal;
    Refresh: TDisplayRatio;
    ScanOrder, Available, Flags: Cardinal;
  end;
  TDisplayPath = record
    Source: TDisplayPathSource;
    Target: TDisplayPathTarget;
    Flags: Cardinal;
  end;
  TDisplaySourceName = record
    Kind, Size: Cardinal;
    Adapter: LUID;
    Id: Cardinal;
    Name: array[0..31] of WideChar;
  end;
  TConfigSizes = function(Flags: Cardinal; out Paths, Modes: Cardinal): LongInt; stdcall;
  TQueryConfig = function(Flags: Cardinal; var Paths: Cardinal; PathData: Pointer;
    var Modes: Cardinal; ModeData, Topology: Pointer): LongInt; stdcall;
  TConfigDeviceInfo = function(var Name: TDisplaySourceName): LongInt; stdcall;
  {$pop}
  // dwmapi.h packs DWM_TIMING_INFO to one-byte alignment.
  TDwmClockTiming = packed record
    Size: Cardinal;
    Refresh: TDisplayRatio;
    RefreshPeriod: QWord;
    Compose: TDisplayRatio;
    VBlank, RefreshCount: QWord;
    DxRefresh: Cardinal;
    QpcCompose, Frame: QWord;
    DxPresent: Cardinal;
    RefreshFrame, FrameSubmitted: QWord;
    DxPresentSubmitted: Cardinal;
    FrameConfirmed: QWord;
    DxPresentConfirmed: Cardinal;
    RefreshConfirmed: QWord;
    DxRefreshConfirmed: Cardinal;
    FramesLate: QWord;
    FramesOutstanding: Cardinal;
    FrameDisplayed, QpcFrameDisplayed, RefreshFrameDisplayed: QWord;
    FrameComplete, QpcFrameComplete, FramePending, QpcFramePending: QWord;
    FramesDisplayed, FramesComplete, FramesPending, FramesAvailable: QWord;
    FramesDropped, FramesMissed, RefreshNextDisplayed, RefreshNextPresented: QWord;
    RefreshesDisplayed, RefreshesPresented, RefreshStarted: QWord;
    PixelsReceived, PixelsDrawn, BuffersEmpty: QWord;
  end;
  TDwmGetTiming = function(Window: HWND; var Timing: TDwmClockTiming): HRESULT; stdcall;
  TDwmIsEnabled = function(out Enabled: BOOL): HRESULT; stdcall;
  TClockTimerCallback = procedure(Parameter: Pointer; Fired: Byte); stdcall;
  TCreateClockTimer = function(out Timer: THandle; Queue: THandle;
    Callback: TClockTimerCallback; Parameter: Pointer; DueTime, Period, Flags: DWORD): BOOL; stdcall;
  TDeleteClockTimer = function(Queue, Timer, Completion: THandle): BOOL; stdcall;

procedure SignalClockTimeout(Parameter: Pointer; Fired: Byte); stdcall;
begin SetEvent(THandle(Parameter)); end;

function QueryDisplayRate(const Device: string; FallbackHz: Double): Double;
var Sizes: TConfigSizes; Query: TQueryConfig; DeviceInfo: TConfigDeviceInfo;
  Paths: array of TDisplayPath; Modes: array of Byte;
  PathCount, ModeCount, Index: Cardinal; Attempt, Status: Integer;
  Name: TDisplaySourceName; UserModule: HMODULE; Rate: Double; Found: Boolean;
begin
  Result := FallbackHz;
  UserModule := GetModuleHandle('user32.dll');
  Sizes := TConfigSizes(GetProcAddress(UserModule, 'GetDisplayConfigBufferSizes'));
  Query := TQueryConfig(GetProcAddress(UserModule, 'QueryDisplayConfig'));
  DeviceInfo := TConfigDeviceInfo(GetProcAddress(UserModule, 'DisplayConfigGetDeviceInfo'));
  if not Assigned(Sizes) or not Assigned(Query) or not Assigned(DeviceInfo) then Exit;
  for Attempt := 1 to 3 do
  begin
    if Sizes(2, PathCount, ModeCount) <> 0 then Exit;
    if (PathCount = 0) or (PathCount > 1024) or (ModeCount = 0) or (ModeCount > 4096) then Exit;
    SetLength(Paths, PathCount);
    SetLength(Modes, ModeCount * 64);
    Status := Query(2, PathCount, @Paths[0], ModeCount, @Modes[0], nil);
    if Status = ERROR_INSUFFICIENT_BUFFER then Continue;
    if Status <> 0 then Exit;
    Found := False;
    for Index := 0 to PathCount - 1 do
    begin
      FillChar(Name, SizeOf(Name), 0);
      Name.Kind := 1;
      Name.Size := SizeOf(Name);
      Name.Adapter := Paths[Index].Source.Adapter;
      Name.Id := Paths[Index].Source.Id;
      if (DeviceInfo(Name) <> 0) or
        not SameText(string(PWideChar(@Name.Name[0])), Device) then Continue;
      if Paths[Index].Target.Refresh.Denominator = 0 then Continue;
      Rate := Paths[Index].Target.Refresh.Numerator / Paths[Index].Target.Refresh.Denominator;
      if (Rate < 10) or (Rate > 1000) then Continue;
      if Found then Result := Min(Result, Rate) else Result := Rate;
      Found := True;
    end;
    Exit;
  end;
end;

destructor TDisplayClock.Destroy;
begin
  Suspend;
  if FTimeoutEvent <> 0 then CloseHandle(FTimeoutEvent);
  if FDwmModule <> 0 then FreeLibrary(FDwmModule);
  inherited;
end;

procedure TDisplayClock.Suspend;
begin
  if FAdapter <> 0 then CloseDisplay(FAdapter);
  FAdapter := 0;
  FSource := dcsTimer;
end;

function TDisplayClock.OpenDisplay(const Device: string; out Adapter, SourceId: Cardinal): Boolean;
var OpenAdapter: TKmtOpen; Data: TKmtOpenAdapter; Gdi: HMODULE;
begin
  Result := False;
  Adapter := 0;
  SourceId := 0;
  Gdi := GetModuleHandle('gdi32.dll');
  OpenAdapter := TKmtOpen(GetProcAddress(Gdi, 'D3DKMTOpenAdapterFromHdc'));
  if not Assigned(OpenAdapter) or
    (GetProcAddress(Gdi, 'D3DKMTWaitForVerticalBlankEvent2') = nil) or
    (GetProcAddress(Gdi, 'D3DKMTCloseAdapter') = nil) or (Device = '') then Exit;
  FillChar(Data, SizeOf(Data), 0);
  Data.Dc := CreateDCA('DISPLAY', PAnsiChar(Device), nil, nil);
  if Data.Dc = 0 then Exit;
  try
    if OpenAdapter(Data) <> 0 then Exit;
    Adapter := Data.Adapter;
    SourceId := Data.SourceId;
    Result := Adapter <> 0;
  finally DeleteDC(Data.Dc); end;
end;

function TDisplayClock.WaitDisplay(Adapter, SourceId: Cardinal; StopEvent, WakeEvent,
  TimeoutEvent: THandle): LongInt;
var WaitBlank: TKmtWait; Data: TKmtWaitBlank;
  CreateClockTimer: TCreateClockTimer; DeleteClockTimer: TDeleteClockTimer;
  Timer: THandle; Kernel: HMODULE;
begin
  Result := -1;
  WaitBlank := TKmtWait(GetProcAddress(GetModuleHandle('gdi32.dll'),
    'D3DKMTWaitForVerticalBlankEvent2'));
  if not Assigned(WaitBlank) then Exit;
  Kernel := GetModuleHandle('kernel32.dll');
  CreateClockTimer := TCreateClockTimer(GetProcAddress(Kernel, 'CreateTimerQueueTimer'));
  DeleteClockTimer := TDeleteClockTimer(GetProcAddress(Kernel, 'DeleteTimerQueueTimer'));
  if not Assigned(CreateClockTimer) or not Assigned(DeleteClockTimer) then Exit;
  if FTimeoutEvent = 0 then FTimeoutEvent := CreateEvent(nil, False, False, nil);
  if FTimeoutEvent = 0 then Exit;
  ResetEvent(FTimeoutEvent);
  Timer := 0;
  if not CreateClockTimer(Timer, 0, @SignalClockTimeout, Pointer(FTimeoutEvent),
    250, 0, 8) then Exit;
  FillChar(Data, SizeOf(Data), 0);
  Data.Adapter := Adapter;
  Data.SourceId := SourceId;
  Data.ObjectCount := 3;
  Data.Objects[0] := StopEvent;
  Data.Objects[1] := WakeEvent;
  // KMT accepts events here. A waitable timer returns STATUS_INVALID_PARAMETER.
  Data.Objects[2] := FTimeoutEvent;
  try Result := WaitBlank(@Data);
  finally DeleteClockTimer(0, Timer, INVALID_HANDLE_VALUE); end;
end;

procedure TDisplayClock.CloseDisplay(Adapter: Cardinal);
var CloseAdapter: TKmtClose; Data: TKmtCloseAdapter;
begin
  CloseAdapter := TKmtClose(GetProcAddress(GetModuleHandle('gdi32.dll'), 'D3DKMTCloseAdapter'));
  Data.Adapter := Adapter;
  if Assigned(CloseAdapter) then CloseAdapter(@Data);
end;

function TDisplayClock.ReadPhysicalRefreshRate(const Device: string; FallbackHz: Double): Double;
begin Result := QueryDisplayRate(Device, FallbackHz); end;

function TDisplayClock.ReadCompositionTiming(out PhaseMs, PeriodMs, Hz: Double): Boolean;
var GetTiming: TDwmGetTiming; IsEnabled: TDwmIsEnabled; Timing: TDwmClockTiming;
  Enabled: BOOL; Frequency: Int64; Scale: Double; SystemDirectory: array[0..MAX_PATH] of WideChar;
  Counter: Double;
begin
  Result := False;
  if FDwmModule = 0 then
  begin
    if GetSystemDirectoryW(@SystemDirectory[0], Length(SystemDirectory)) = 0 then Exit;
    FDwmModule := LoadLibraryW(PWideChar(WideString(SystemDirectory) + '\dwmapi.dll'));
  end;
  if FDwmModule = 0 then Exit;
  GetTiming := TDwmGetTiming(GetProcAddress(FDwmModule, 'DwmGetCompositionTimingInfo'));
  IsEnabled := TDwmIsEnabled(GetProcAddress(FDwmModule, 'DwmIsCompositionEnabled'));
  if not Assigned(GetTiming) or not Assigned(IsEnabled) then Exit;
  if (IsEnabled(Enabled) <> 0) or not Enabled then Exit;
  FillChar(Timing, SizeOf(Timing), 0);
  Timing.Size := SizeOf(Timing);
  if (GetTiming(0, Timing) <> 0) or (Timing.Refresh.Denominator = 0) or
    (Timing.RefreshPeriod = 0) or not QueryPerformanceFrequency(Frequency) or (Frequency <= 0) then Exit;
  Hz := Timing.Refresh.Numerator / Timing.Refresh.Denominator;
  Scale := Frequency;
  Scale := 1000 / Scale;
  Counter := Timing.VBlank;
  PhaseMs := Counter * Scale;
  Counter := Timing.RefreshPeriod;
  PeriodMs := Counter * Scale;
  Result := (Hz >= 10) and (Hz <= 1000) and (PeriodMs > 0);
end;

function TDisplayClock.IsPrimaryDisplay: Boolean;
var Info: TMonitorInfo;
begin
  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  Result := MultiMon.GetMonitorInfo(FMonitor, @Info) and
    ((Info.dwFlags and MONITORINFOF_PRIMARY) <> 0);
end;

function TDisplayClock.ClockTicks: QWord;
begin Result := GetTickCount64; end;

function WindowDisplayBinding(Window: HWND): TDisplayBinding;
var Info: TMonitorInfoExA; Mode: TDeviceModeA;
begin
  Result.Monitor := MultiMon.MonitorFromWindow(Window, MONITOR_DEFAULTTONEAREST);
  Result.DeviceName := '';
  Result.RefreshRate := 60;
  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  if not MultiMon.GetMonitorInfo(Result.Monitor, PMonitorInfo(@Info)) then Exit;
  Result.DeviceName := PAnsiChar(@Info.szDevice[0]);
  FillChar(Mode, SizeOf(Mode), 0);
  Mode.dmSize := SizeOf(Mode);
  if Windows.EnumDisplaySettingsA(@Info.szDevice[0], ENUM_CURRENT_SETTINGS, Mode) and
    (Mode.dmDisplayFrequency >= 30) and (Mode.dmDisplayFrequency <= 360) then
    Result.RefreshRate := Mode.dmDisplayFrequency;
  Result.RefreshRate := QueryDisplayRate(Result.DeviceName, Result.RefreshRate);
end;

function NextDisplayBoundary(NowMs, PhaseMs, PeriodMs: Double; EarliestMs: Double): Double;
begin
  Result := PhaseMs + (Floor((NowMs - PhaseMs) / PeriodMs) + 1) * PeriodMs;
  Result := Max(Result, EarliestMs);
end;

procedure TDisplayClock.Bind(Monitor: HMONITOR; const Device: string; Hz: Double);
begin
  Suspend;
  FMonitor := Monitor;
  FDevice := Device;
  FNextRetry := ClockTicks + 1000;
  FRefreshRate := ReadPhysicalRefreshRate(Device, Hz);
  if OpenDisplay(Device, FAdapter, FSourceId) then FSource := dcsVerticalBlank;
end;

function TDisplayClock.WaitBoundary(StopEvent, WakeEvent, TimeoutEvent: THandle): TDisplayClockWait;
var Status: LongInt;
begin
  Result := dcwUnavailable;
  if (FAdapter = 0) and (FDevice <> '') and (ClockTicks >= FNextRetry) then
  begin
    FNextRetry := ClockTicks + 1000;
    OpenDisplay(FDevice, FAdapter, FSourceId);
  end;
  if FAdapter = 0 then Exit;
  Status := WaitDisplay(FAdapter, FSourceId, StopEvent, WakeEvent, TimeoutEvent);
  FLastNativeStatus := Status;
  case Status of
    0: begin FSource := dcsVerticalBlank; Result := dcwBoundary; end;
    1: Result := dcwStop;
    2: Result := dcwWake;
    3: FSource := dcsTimer;
  else
    Suspend;
    FNextRetry := ClockTicks + 1000;
  end;
end;

function TDisplayClock.ReadPhase(out PhaseMs, PeriodMs: Double): Boolean;
var Hz: Double;
begin
  Result := IsPrimaryDisplay and ReadCompositionTiming(PhaseMs, PeriodMs, Hz);
  if Result then Result := Abs(Hz - FRefreshRate) <= 1.1;
  if Result then FSource := dcsDwmTiming else FSource := dcsTimer;
end;

end.
