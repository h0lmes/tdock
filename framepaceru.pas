unit framepaceru;

{$mode delphi}

interface

uses Windows, Classes, SyncObjs, displayclocku;

const DOCK_FRAME_MESSAGE = WM_APP + $318;

type
  TFramePacer = class
  private
    FWindow: HWND;
    FMonitorWindow: HWND;
    FMessageId: UINT;
    FThread: TThread;
    FLock: TCriticalSection;
    FWakeEvent, FStopEvent, FTimer: THandle;
    FActive: Boolean;
    FPending: Boolean;
    FGeneration: WPARAM;
    FRefreshRate: Double;
    FHighResolution, FTimerResolution: Boolean;
    FDisplayClock: TDisplayClock;
    FDisplay: TDisplayBinding;
    FClockSource: TDisplayClockSource;
    function GetActive: Boolean;
    function GetRefreshRate: Double;
    function GetEffectiveRefreshRate: Double;
    function GetDisplayRefreshRate: Double;
    function GetClockSource: TDisplayClockSource;
    function GetMonitorDevice: string;
    procedure DrainFrames;
    procedure ReleaseTimerResolution;
    procedure Run;
  protected
    function CreateDisplayClock: TDisplayClock; virtual;
    function ReadWindowDisplay(Window: HWND): TDisplayBinding; virtual;
    function ReadWindowMonitor(Window: HWND): HMONITOR; virtual;
    function CreateNativeTimer(out HighResolution: Boolean): THandle; virtual;
    procedure ReleaseNativeTimerResolution; virtual;
    function TimerResolutionActive: Boolean;
  public
    // Reserve MessageId for this pacer on Window.
    // Window's UI thread owns construction, state changes, message consumption, and destruction.
    constructor Create(Window: HWND; MessageId: UINT);
    destructor Destroy; override;
    procedure SetActive(Value: Boolean);
    procedure SetRefreshRate(Hz: Double);
    procedure SetMonitorForWindow(Window: HWND);
    function ConsumeMessage(Generation: WPARAM): Boolean;
    property Active: Boolean read GetActive;
    property RefreshRate: Double read GetRefreshRate;
    property DisplayRefreshRate: Double read GetDisplayRefreshRate;
    property EffectiveRefreshRate: Double read GetEffectiveRefreshRate;
    property ClockSource: TDisplayClockSource read GetClockSource;
    property MonitorDevice: string read GetMonitorDevice;
    property HighResolution: Boolean read FHighResolution;
  end;

function RefreshRateForWindow(Window: HWND): Double;

implementation

uses SysUtils, Math, MultiMon, MMSystem, animationclocku;

type
  TCreateWaitableTimerEx = function(Security: Pointer; Name: PWideChar;
    Flags, Access: DWORD): THandle; stdcall;
  TFramePacerThread = class(TThread)
  private
    FOwner: TFramePacer;
  protected
    procedure Execute; override;
  public
    constructor Create(Owner: TFramePacer);
  end;

var FrameGeneration: LongInt;

function EffectiveRate(RequestedHz, DisplayHz: Double): Double;
var Divider: Integer;
begin
  Result := Min(RequestedHz, DisplayHz);
  Divider := Max(1, Round(DisplayHz / RequestedHz));
  if Abs(DisplayHz / Divider - RequestedHz) <= RequestedHz * 0.01 then
    Result := DisplayHz / Divider;
end;

function NextGeneration: WPARAM; forward;

function TFramePacer.CreateDisplayClock: TDisplayClock;
begin Result := TDisplayClock.Create; end;

function TFramePacer.ReadWindowDisplay(Window: HWND): TDisplayBinding;
begin Result := WindowDisplayBinding(Window); end;

function TFramePacer.ReadWindowMonitor(Window: HWND): HMONITOR;
begin Result := MultiMon.MonitorFromWindow(Window, MONITOR_DEFAULTTONEAREST); end;

procedure TFramePacer.SetMonitorForWindow(Window: HWND);
var Display: TDisplayBinding;
begin
  Display := ReadWindowDisplay(Window);
  FLock.Acquire;
  try
    FMonitorWindow := Window;
    if (FDisplay.Monitor = Display.Monitor) and
      (FDisplay.DeviceName = Display.DeviceName) and
      (Abs(FDisplay.RefreshRate - Display.RefreshRate) < 0.001) then Exit;
    FDisplay := Display;
    FGeneration := NextGeneration;
    DrainFrames;
    FPending := False;
    SetEvent(FWakeEvent);
  finally FLock.Release; end;
end;

function TFramePacer.GetEffectiveRefreshRate: Double;
begin
  FLock.Acquire;
  try Result := EffectiveRate(FRefreshRate, FDisplay.RefreshRate);
  finally FLock.Release; end;
end;

function TFramePacer.GetDisplayRefreshRate: Double;
begin
  FLock.Acquire;
  try Result := FDisplay.RefreshRate; finally FLock.Release; end;
end;

function TFramePacer.GetClockSource: TDisplayClockSource;
begin
  FLock.Acquire;
  try Result := FClockSource; finally FLock.Release; end;
end;

function TFramePacer.GetMonitorDevice: string;
begin
  FLock.Acquire;
  try Result := FDisplay.DeviceName; finally FLock.Release; end;
end;

function NextGeneration: WPARAM;
var Value: LongInt;
begin
  repeat Value := InterlockedIncrement(FrameGeneration); until Value <> 0;
  Result := WPARAM(LongWord(Value));
end;

constructor TFramePacerThread.Create(Owner: TFramePacer);
begin
  inherited Create(True);
  FOwner := Owner;
  FreeOnTerminate := False;
  Start;
end;

procedure TFramePacerThread.Execute;
begin FOwner.Run; end;

function TFramePacer.CreateNativeTimer(out HighResolution: Boolean): THandle;
var CreateTimer: TCreateWaitableTimerEx;
begin
  Result := 0;
  CreateTimer := TCreateWaitableTimerEx(GetProcAddress(GetModuleHandle('kernel32.dll'),
    'CreateWaitableTimerExW'));
  if Assigned(CreateTimer) then
    Result := CreateTimer(nil, nil, $00000002, $00100002);
  HighResolution := Result <> 0;
  if Result = 0 then Result := CreateWaitableTimer(nil, False, nil);
end;

procedure TFramePacer.ReleaseNativeTimerResolution;
begin timeEndPeriod(1); end;

function TFramePacer.TimerResolutionActive: Boolean;
begin
  FLock.Acquire;
  try Result := FTimerResolution; finally FLock.Release; end;
end;

constructor TFramePacer.Create(Window: HWND; MessageId: UINT);
begin
  inherited Create;
  FWindow := Window;
  FMessageId := MessageId;
  FRefreshRate := 60;
  FGeneration := NextGeneration;
  FLock := TCriticalSection.Create;
  FWakeEvent := CreateEvent(nil, False, False, nil);
  FStopEvent := CreateEvent(nil, True, False, nil);
  if (FWakeEvent = 0) or (FStopEvent = 0) then RaiseLastOSError;
  FTimer := CreateNativeTimer(FHighResolution);
  if FTimer = 0 then RaiseLastOSError;
  FDisplayClock := CreateDisplayClock;
  SetMonitorForWindow(Window);
  FThread := TFramePacerThread.Create(Self);
end;

destructor TFramePacer.Destroy;
begin
  if FLock <> nil then SetActive(False);
  if FStopEvent <> 0 then SetEvent(FStopEvent);
  if FWakeEvent <> 0 then SetEvent(FWakeEvent);
  if FThread <> nil then
  begin
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
  if FTimer <> 0 then CloseHandle(FTimer);
  FreeAndNil(FDisplayClock);
  if FStopEvent <> 0 then CloseHandle(FStopEvent);
  if FWakeEvent <> 0 then CloseHandle(FWakeEvent);
  FreeAndNil(FLock);
  inherited Destroy;
end;

function TFramePacer.GetActive: Boolean;
begin
  FLock.Acquire;
  try Result := FActive; finally FLock.Release; end;
end;

function TFramePacer.GetRefreshRate: Double;
begin
  FLock.Acquire;
  try Result := FRefreshRate; finally FLock.Release; end;
end;

procedure TFramePacer.DrainFrames;
var Message: TMsg;
begin
  // The caller holds FLock, so the worker cannot post during removal.
  if FWindow = 0 then Exit;
  while PeekMessage(Message, FWindow, FMessageId, FMessageId, PM_REMOVE) do;
end;

procedure TFramePacer.ReleaseTimerResolution;
begin
  if not FTimerResolution then Exit;
  ReleaseNativeTimerResolution;
  FTimerResolution := False;
end;

procedure TFramePacer.SetActive(Value: Boolean);
begin
  FLock.Acquire;
  try
    if FActive = Value then
    begin
      if not Value then ReleaseTimerResolution;
      Exit;
    end;
    FActive := Value;
    FGeneration := NextGeneration;
    DrainFrames;
    FPending := False;
    // Older Windows needs a scoped resolution request for its fallback timer.
    if Value and not FHighResolution and not FTimerResolution then
      FTimerResolution := timeBeginPeriod(1) = TIMERR_NOERROR;
    if not Value then ReleaseTimerResolution;
    SetEvent(FWakeEvent);
  finally FLock.Release; end;
end;

procedure TFramePacer.SetRefreshRate(Hz: Double);
begin
  if IsNan(Hz) or IsInfinite(Hz) or (Hz < 30) or (Hz > 360) then Hz := 60;
  FLock.Acquire;
  try
    if Abs(FRefreshRate - Hz) < 0.001 then Exit;
    FRefreshRate := Hz;
    FGeneration := NextGeneration;
    DrainFrames;
    FPending := False;
    SetEvent(FWakeEvent);
  finally FLock.Release; end;
end;

function TFramePacer.ConsumeMessage(Generation: WPARAM): Boolean;
var MonitorWindow: HWND; Monitor: HMONITOR;
begin
  FLock.Acquire;
  try
    MonitorWindow := FMonitorWindow;
    Monitor := FDisplay.Monitor;
  finally FLock.Release; end;
  // This inexpensive UI-thread check also covers moving hints and previews.
  if ReadWindowMonitor(MonitorWindow) <> Monitor then SetMonitorForWindow(MonitorWindow);
  FLock.Acquire;
  try
    Result := FActive and FPending and (Generation = FGeneration);
    if Result then FPending := False;
  finally FLock.Release; end;
end;

procedure TFramePacer.Run;
var Handles: array[0..2] of THandle; WaitResult: DWORD;
  Generation, PreviousGeneration: WPARAM; Enabled: Boolean;
  Interval, NextFrame, Earliest, Now, Delay, Step, Credit, Phase, Period, Requested: Double;
  Due: Int64; Display: TDisplayBinding;
  Boundary: TDisplayClockWait;
begin
  Handles[0] := FStopEvent;
  Handles[1] := FWakeEvent;
  Handles[2] := FTimer;
  PreviousGeneration := 0;
  NextFrame := 0;
  try
  repeat
    FLock.Acquire;
    try
      Enabled := FActive;
      Generation := FGeneration;
      Display := FDisplay;
      Requested := FRefreshRate;
    finally FLock.Release; end;
    if not Enabled then
    begin
      CancelWaitableTimer(FTimer);
      FDisplayClock.Suspend;
      if WaitForMultipleObjects(2, @Handles[0], False, INFINITE) = WAIT_OBJECT_0 then Exit;
      PreviousGeneration := 0;
      Continue;
    end;
    Now := AnimationTimeMs;
    if Generation <> PreviousGeneration then
    begin
      FDisplayClock.Bind(Display.Monitor, Display.DeviceName, Display.RefreshRate);
      Display.RefreshRate := FDisplayClock.RefreshRate;
      FLock.Acquire;
      try
        if Generation = FGeneration then
        begin
          FDisplay.RefreshRate := Display.RefreshRate;
          FClockSource := FDisplayClock.Source;
          if FClockSource = dcsVerticalBlank then ReleaseTimerResolution;
        end;
      finally FLock.Release; end;
      Interval := 1000 / Display.RefreshRate;
      Credit := 0;
      Earliest := 0;
      NextFrame := Now + Interval;
      PreviousGeneration := Generation;
    end;
    Interval := 1000 / Display.RefreshRate;
    Step := EffectiveRate(Requested, Display.RefreshRate) / Display.RefreshRate;
    Boundary := FDisplayClock.WaitBoundary(FStopEvent, FWakeEvent, FTimer);
    case Boundary of
      dcwStop: Exit;
      dcwWake: Continue;
    end;
    if Boundary = dcwBoundary then
    begin
      FLock.Acquire;
      try
        if Generation = FGeneration then
        begin
          FClockSource := FDisplayClock.Source;
          ReleaseTimerResolution;
        end;
      finally FLock.Release; end;
    end;
    if Boundary = dcwUnavailable then
    begin
      FLock.Acquire;
      try
        if FActive and (Generation = FGeneration) and not FHighResolution and
          not FTimerResolution then FTimerResolution := timeBeginPeriod(1) = TIMERR_NOERROR;
      finally FLock.Release; end;
      Now := AnimationTimeMs;
      Period := Interval;
      if FDisplayClock.ReadPhase(Phase, Period) then
        NextFrame := NextDisplayBoundary(Now, Phase, Period, Earliest)
      else if NextFrame <= Now then
        NextFrame := NextDisplayBoundary(Now, NextFrame, Interval);
      FLock.Acquire;
      try
        if Generation = FGeneration then FClockSource := FDisplayClock.Source;
      finally FLock.Release; end;
      Delay := Max(0.1, NextFrame - Now);
      Due := -Round(Delay * 10000);
      if SetWaitableTimer(FTimer, Due, 0, nil, nil, False) then
        WaitResult := WaitForMultipleObjects(3, @Handles[0], False, INFINITE)
      else
        WaitResult := WaitForMultipleObjects(2, @Handles[0], False, Max(1, Ceil(Delay)));
      if WaitResult = WAIT_OBJECT_0 then Exit;
      if WaitResult = WAIT_FAILED then Exit;
      if WaitResult = WAIT_OBJECT_0 + 1 then Continue;
      Now := AnimationTimeMs;
      if Now + 0.05 < NextFrame then Continue;
      // Advance every physical slot, including slots skipped by the rate divider.
      NextFrame := NextDisplayBoundary(Now + 0.05, NextFrame, Period);
      Earliest := NextFrame;
    end;
    Now := AnimationTimeMs;
    Credit := Credit + Step;
    if Credit < 1 - 0.000001 then Continue;
    Credit := Max(0, Credit - 1);
    FLock.Acquire;
    try
      if FActive and (Generation = FGeneration) and not FPending then
      begin
        FPending := PostMessage(FWindow, FMessageId, FGeneration, 0);
        if not FPending then
        begin
          FActive := False;
          ReleaseTimerResolution;
        end;
      end;
    finally FLock.Release; end;
  until False;
  finally
    FDisplayClock.Suspend;
    FLock.Acquire;
    try
      FActive := False;
      ReleaseTimerResolution;
    finally FLock.Release; end;
  end;
end;

function RefreshRateForWindow(Window: HWND): Double;
var Display: TDisplayBinding;
begin
  Display := WindowDisplayBinding(Window);
  Result := Display.RefreshRate;
end;

end.
