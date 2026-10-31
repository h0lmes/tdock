unit framepacingtests;

{$mode delphi}

interface

uses Windows, Messages, SysUtils, fpcunit, testregistry, framepaceru, displayclocku;

type
  TTimerOnlyDisplayClock = class(TDisplayClock)
  protected
    function OpenDisplay(const Device: string; out Adapter, SourceId: Cardinal): Boolean; override;
  end;
  TFramePacingTests = class(TTestCase)
  private
    Window: HWND;
    Pacer: TFramePacer;
    procedure WaitForFrame(out Message: TMsg);
    function RemoveFrames: Integer;
    procedure StartFallbackWithoutOwner;
    procedure StartEventPacer(DisplayHz, RequestedHz: Double);
    procedure PulseBoundary;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ActivePacerPostsFrames;
    procedure SleepingUiReceivesOnlyOnePendingFrame;
    procedure StoppedPacerRejectsQueuedFrame;
    procedure RestartRejectsPreviousGeneration;
    procedure FrameConsumptionAllowsNextFrame;
    procedure InactivePacerDoesNotPost;
    procedure SupportsBothRefreshRates;
    procedure RefreshRateChangeKeepsOneQueuedFrame;
    procedure RepeatedRateChangesKeepOneQueuedFrame;
    procedure RepeatedRestartsKeepOneQueuedFrame;
    procedure RateChangeRejectsHeldGeneration;
    procedure RateChangePreservesOtherMessages;
    procedure FailedPostReleasesFallbackResolution;
    procedure InactiveStopReleasesFallbackResolution;
    procedure DestroyReleasesFailedFallbackResolution;
    procedure NoFrameBeforeDisplayBoundary;
    procedure FrameFollowsDisplayBoundary;
    procedure SixtyOnOneTwentyUsesAlternateBoundaries;
    procedure RequestedRateCannotExceedDisplay;
    procedure FractionalDisplayRateKeepsItsPeriod;
    procedure FallbackPreservesDisplayPhase;
    procedure MonitorChangeRejectsHeldGeneration;
    procedure DisplayWaitStopsPromptly;
    procedure NativeVerticalBlankStatusPostsBoundary;
    procedure NativeUserEventsCancelWaits;
    procedure NativeFailureUsesFallback;
    procedure NativeRebindClosesPreviousAdapter;
    procedure NativeBindingPreservesRationalRefresh;
    procedure DwmFallbackReadsPrimaryDisplayPhase;
    procedure DwmFallbackRejectsOtherDisplayRates;
    procedure DwmFallbackRejectsSecondaryMonitor;
    procedure ActiveMonitorMigrationRejectsPreviousBoundary;
    procedure DisplayBoundariesKeepOnePendingFrame;
    procedure LateUiDoesNotReplayDisplayBoundaries;
    procedure DisplayClockWaitRemainsIdleWhileStopped;
    procedure NativeSourceRetriesAfterDriverRecovery;
    procedure DwmFailureReportsTimerFallback;
    procedure DwmFallbackCannotRepeatAnEarlyBoundary;
    procedure NativeWaitNeverPassesAnInvalidTimerObject;
  end;

implementation

type
  TEventDisplayClock = class(TDisplayClock)
  public
    procedure Bind(Monitor: HMONITOR; const Device: string; Hz: Double); override;
    function WaitBoundary(StopEvent, WakeEvent, TimeoutEvent: THandle): TDisplayClockWait; override;
  end;
  TNativeSeamDisplayClock = class(TDisplayClock)
  protected
    function OpenDisplay(const Device: string; out Adapter, SourceId: Cardinal): Boolean; override;
    function WaitDisplay(Adapter, SourceId: Cardinal; StopEvent, WakeEvent,
      TimeoutEvent: THandle): LongInt; override;
    procedure CloseDisplay(Adapter: Cardinal); override;
    function ClockTicks: QWord; override;
  end;
  TPhaseDisplayClock = class(TNativeSeamDisplayClock)
  protected
    function ReadPhysicalRefreshRate(const Device: string; FallbackHz: Double): Double; override;
    function ReadCompositionTiming(out PhaseMs, PeriodMs, Hz: Double): Boolean; override;
    function IsPrimaryDisplay: Boolean; override;
  end;
  TEventFramePacer = class(TFramePacer)
  protected
    function CreateDisplayClock: TDisplayClock; override;
    function ReadWindowDisplay(Window: HWND): TDisplayBinding; override;
    function ReadWindowMonitor(Window: HWND): HMONITOR; override;
  end;
  TFallbackFramePacer = class(TFramePacer)
  protected
    function CreateDisplayClock: TDisplayClock; override;
    function CreateNativeTimer(out HighResolution: Boolean): THandle; override;
    procedure ReleaseNativeTimerResolution; override;
  public
    function HasResolution: Boolean;
  end;

var ReleasedTimerResolutions: LongInt;
  DisplayPulse: THandle;
  DisplayWaiting: THandle;
  FakeDisplayRate: Double;
  FakeMonitor: HMONITOR;
  NativeStatus, ClosedAdapters: LongInt;
  FakeCompositionRate: Double;
  FakePrimary: Boolean;
  FakeNativeTicks: QWord;

function TNativeSeamDisplayClock.ClockTicks: QWord;
begin Result := FakeNativeTicks; end;

procedure TFramePacingTests.NativeSourceRetriesAfterDriverRecovery;
var Clock: TDisplayClock;
begin
  Clock := TNativeSeamDisplayClock.Create;
  try
    FakeNativeTicks := 0;
    Clock.Bind(1, 'recovering display', 60);
    NativeStatus := -1;
    AssertEquals(Ord(dcwUnavailable), Ord(Clock.WaitBoundary(0, 0, 0)));
    FakeNativeTicks := 1001;
    NativeStatus := 0;
    AssertEquals('The display clock must recover after a driver interruption',
      Ord(dcwBoundary), Ord(Clock.WaitBoundary(0, 0, 0)));
  finally Clock.Free; end;
end;

procedure TFramePacingTests.DwmFailureReportsTimerFallback;
var Clock: TDisplayClock; Phase, Period: Double;
begin
  Clock := TPhaseDisplayClock.Create;
  try
    FakePrimary := True;
    FakeCompositionRate := 60000 / 1001;
    Clock.Bind(1, 'primary', 60);
    AssertTrue(Clock.ReadPhase(Phase, Period));
    FakeCompositionRate := 120;
    AssertFalse(Clock.ReadPhase(Phase, Period));
    AssertEquals('An unavailable DWM phase must report timer fallback',
      Ord(dcsTimer), Ord(Clock.Source));
  finally Clock.Free; end;
end;

function TPhaseDisplayClock.ReadPhysicalRefreshRate(const Device: string; FallbackHz: Double): Double;
begin Result := 60000 / 1001; end;

function TPhaseDisplayClock.ReadCompositionTiming(out PhaseMs, PeriodMs, Hz: Double): Boolean;
begin
  PhaseMs := 5;
  PeriodMs := 1000 / FakeCompositionRate;
  Hz := FakeCompositionRate;
  Result := True;
end;

function TPhaseDisplayClock.IsPrimaryDisplay: Boolean;
begin Result := FakePrimary; end;

procedure TFramePacingTests.NativeBindingPreservesRationalRefresh;
var Clock: TDisplayClock;
begin
  Clock := TPhaseDisplayClock.Create;
  try
    Clock.Bind(1, 'rational display', 60);
    AssertEquals('The native clock must use the physical rational rate',
      60000 / 1001, Clock.RefreshRate, 0.000001);
  finally Clock.Free; end;
end;

procedure TFramePacingTests.DwmFallbackReadsPrimaryDisplayPhase;
var Clock: TDisplayClock; Phase, Period: Double;
begin
  Clock := TPhaseDisplayClock.Create;
  try
    FakePrimary := True;
    FakeCompositionRate := 60000 / 1001;
    Clock.Bind(1, 'primary', 60);
    AssertTrue('The primary display must use the DWM phase', Clock.ReadPhase(Phase, Period));
    AssertEquals(5.0, Phase, 0.000001);
    AssertEquals(1001 / 60, Period, 0.000001);
  finally Clock.Free; end;
end;

procedure TFramePacingTests.DwmFallbackRejectsOtherDisplayRates;
var Clock: TDisplayClock; Phase, Period: Double;
begin
  Clock := TPhaseDisplayClock.Create;
  try
    FakePrimary := True;
    FakeCompositionRate := 120;
    Clock.Bind(1, 'primary', 60);
    AssertFalse('A mismatched composition rate cannot supply display phase', Clock.ReadPhase(Phase, Period));
  finally Clock.Free; end;
end;

procedure TFramePacingTests.DwmFallbackRejectsSecondaryMonitor;
var Clock: TDisplayClock; Phase, Period: Double;
begin
  Clock := TPhaseDisplayClock.Create;
  try
    FakePrimary := False;
    FakeCompositionRate := 60000 / 1001;
    Clock.Bind(2, 'secondary', 60);
    AssertFalse('Global DWM timing cannot identify a secondary display phase', Clock.ReadPhase(Phase, Period));
  finally Clock.Free; end;
end;

function TNativeSeamDisplayClock.OpenDisplay(const Device: string;
  out Adapter, SourceId: Cardinal): Boolean;
begin
  Adapter := 44;
  SourceId := 3;
  Result := True;
end;

function TNativeSeamDisplayClock.WaitDisplay(Adapter, SourceId: Cardinal;
  StopEvent, WakeEvent, TimeoutEvent: THandle): LongInt;
begin Result := NativeStatus; end;

procedure TNativeSeamDisplayClock.CloseDisplay(Adapter: Cardinal);
begin Inc(ClosedAdapters); end;

procedure TFramePacingTests.NativeVerticalBlankStatusPostsBoundary;
var Clock: TDisplayClock;
begin
  Clock := TNativeSeamDisplayClock.Create;
  try
    Clock.Bind(1, 'test display', 60);
    NativeStatus := 0;
    AssertEquals('A native vertical blank must produce one boundary',
      Ord(dcwBoundary), Ord(Clock.WaitBoundary(0, 0, 0)));
    AssertEquals(Ord(dcsVerticalBlank), Ord(Clock.Source));
  finally Clock.Free; end;
end;

procedure TFramePacingTests.NativeUserEventsCancelWaits;
var Clock: TDisplayClock;
begin
  Clock := TNativeSeamDisplayClock.Create;
  try
    Clock.Bind(1, 'test display', 60);
    NativeStatus := 1;
    AssertEquals('The stop handle must cancel native waits', Ord(dcwStop),
      Ord(Clock.WaitBoundary(0, 0, 0)));
    NativeStatus := 2;
    AssertEquals('The wake handle must cancel native waits', Ord(dcwWake),
      Ord(Clock.WaitBoundary(0, 0, 0)));
    NativeStatus := 3;
    AssertEquals('The watchdog must cancel display-off waits', Ord(dcwUnavailable),
      Ord(Clock.WaitBoundary(0, 0, 0)));
  finally Clock.Free; end;
end;

procedure TFramePacingTests.NativeFailureUsesFallback;
var Clock: TDisplayClock;
begin
  Clock := TNativeSeamDisplayClock.Create;
  try
    Clock.Bind(1, 'test display', 60);
    NativeStatus := -1;
    AssertEquals(Ord(dcwUnavailable), Ord(Clock.WaitBoundary(0, 0, 0)));
    AssertEquals('A failed native source must report timer fallback',
      Ord(dcsTimer), Ord(Clock.Source));
  finally Clock.Free; end;
end;

procedure TFramePacingTests.NativeRebindClosesPreviousAdapter;
var Clock: TDisplayClock;
begin
  ClosedAdapters := 0;
  Clock := TNativeSeamDisplayClock.Create;
  try
    Clock.Bind(1, 'first', 60);
    Clock.Bind(2, 'second', 120);
    AssertEquals('A monitor change must close the previous adapter', 1, ClosedAdapters);
    Clock.Suspend;
    AssertEquals('Idle must release the current display adapter', 2, ClosedAdapters);
  finally Clock.Free; end;
  AssertEquals('Closed adapters must not close again', 2, ClosedAdapters);
end;

procedure TEventDisplayClock.Bind(Monitor: HMONITOR; const Device: string; Hz: Double);
begin
  inherited;
  FSource := dcsVerticalBlank;
end;

function TEventFramePacer.ReadWindowDisplay(Window: HWND): TDisplayBinding;
begin
  Result.Monitor := FakeMonitor;
  Result.DeviceName := IntToStr(FakeMonitor);
  Result.RefreshRate := FakeDisplayRate;
end;

function TEventFramePacer.ReadWindowMonitor(Window: HWND): HMONITOR;
begin Result := FakeMonitor; end;

procedure TFramePacingTests.ActiveMonitorMigrationRejectsPreviousBoundary;
var Message: TMsg;
begin
  StartEventPacer(60, 60);
  PulseBoundary;
  WaitForFrame(Message);
  FakeMonitor := 2;
  AssertFalse('A moving window must reject its previous monitor boundary',
    Pacer.ConsumeMessage(Message.wParam));
  PulseBoundary;
  WaitForFrame(Message);
  AssertTrue(Pacer.ConsumeMessage(Message.wParam));
  AssertEquals('The clock must bind to the new monitor', '2', Pacer.MonitorDevice);
end;

procedure TFramePacingTests.DisplayBoundariesKeepOnePendingFrame;
var Index: Integer;
begin
  StartEventPacer(120, 120);
  for Index := 1 to 8 do PulseBoundary;
  AssertEquals('Display events must retain one pending UI frame', 1, RemoveFrames);
end;

procedure TFramePacingTests.LateUiDoesNotReplayDisplayBoundaries;
var Index: Integer; Message: TMsg;
begin
  StartEventPacer(120, 120);
  for Index := 1 to 8 do PulseBoundary;
  WaitForFrame(Message);
  AssertTrue(Pacer.ConsumeMessage(Message.wParam));
  Sleep(40);
  AssertEquals('The worker must wait for a new display event after a UI stall', 0, RemoveFrames);
  PulseBoundary;
  WaitForFrame(Message);
  AssertTrue(Pacer.ConsumeMessage(Message.wParam));
end;

procedure TFramePacingTests.DisplayClockWaitRemainsIdleWhileStopped;
begin
  StartEventPacer(60, 60);
  Pacer.SetActive(False);
  Sleep(20);
  ResetEvent(DisplayWaiting);
  SetEvent(DisplayPulse);
  Sleep(30);
  AssertEquals('An inactive worker must not wait on the display clock', DWORD(WAIT_TIMEOUT),
    WaitForSingleObject(DisplayWaiting, 0));
  AssertEquals(0, RemoveFrames);
end;

procedure TFramePacingTests.StartEventPacer(DisplayHz, RequestedHz: Double);
begin
  FreeAndNil(Pacer);
  FakeMonitor := 1;
  FakeDisplayRate := DisplayHz;
  Pacer := TEventFramePacer.Create(Window, DOCK_FRAME_MESSAGE);
  Pacer.SetRefreshRate(RequestedHz);
  Pacer.SetActive(True);
end;

procedure TFramePacingTests.PulseBoundary;
begin
  AssertEquals('The worker must wait for the display', DWORD(WAIT_OBJECT_0),
    WaitForSingleObject(DisplayWaiting, 1000));
  ResetEvent(DisplayWaiting);
  SetEvent(DisplayPulse);
  AssertEquals('The worker must finish the display boundary', DWORD(WAIT_OBJECT_0),
    WaitForSingleObject(DisplayWaiting, 1000));
end;

function TEventFramePacer.CreateDisplayClock: TDisplayClock;
begin Result := TEventDisplayClock.Create; end;

function TEventDisplayClock.WaitBoundary(StopEvent, WakeEvent, TimeoutEvent: THandle): TDisplayClockWait;
var Handles: array[0..2] of THandle; Value: DWORD;
begin
  SetEvent(DisplayWaiting);
  Handles[0] := StopEvent;
  Handles[1] := WakeEvent;
  Handles[2] := DisplayPulse;
  Value := WaitForMultipleObjects(3, @Handles[0], False, INFINITE);
  case Value of
    WAIT_OBJECT_0: Result := dcwStop;
    WAIT_OBJECT_0 + 1: Result := dcwWake;
    WAIT_OBJECT_0 + 2: Result := dcwBoundary;
  else Result := dcwUnavailable;
  end;
end;

procedure TFramePacingTests.NoFrameBeforeDisplayBoundary;
begin
  StartEventPacer(60, 60);
  Sleep(70);
  AssertEquals('The display clock must gate frames', 0, RemoveFrames);
end;

procedure TFramePacingTests.FrameFollowsDisplayBoundary;
var Message: TMsg;
begin
  StartEventPacer(60, 60);
  PulseBoundary;
  WaitForFrame(Message);
  AssertTrue(Pacer.ConsumeMessage(Message.wParam));
end;

procedure TFramePacingTests.SixtyOnOneTwentyUsesAlternateBoundaries;
var Message: TMsg;
begin
  StartEventPacer(120, 60);
  PulseBoundary;
  AssertEquals('The first half-rate boundary must not post', 0, RemoveFrames);
  PulseBoundary;
  WaitForFrame(Message);
  AssertTrue(Pacer.ConsumeMessage(Message.wParam));
  PulseBoundary;
  AssertEquals('The divider must retain display phase', 0, RemoveFrames);
end;

procedure TFramePacingTests.RequestedRateCannotExceedDisplay;
begin
  StartEventPacer(60, 120);
  AssertEquals('The effective rate must report physical capability',
    60.0, Pacer.EffectiveRefreshRate, 0.0001);
end;

procedure TFramePacingTests.FractionalDisplayRateKeepsItsPeriod;
begin
  StartEventPacer(120000 / 1001, 60);
  AssertEquals('The physical rational rate must remain precise',
    60000 / 1001, Pacer.EffectiveRefreshRate, 0.000001);
end;

procedure TFramePacingTests.FallbackPreservesDisplayPhase;
begin
  AssertEquals('A fallback deadline must use display phase',
    105.0, NextDisplayBoundary(102, 5, 10), 0.000001);
  AssertEquals('A late frame must skip expired display boundaries',
    145.0, NextDisplayBoundary(136, 5, 10), 0.000001);
end;

procedure TFramePacingTests.DwmFallbackCannotRepeatAnEarlyBoundary;
begin
  AssertEquals('An early timer return must not select the same display boundary again',
    115.0, NextDisplayBoundary(104.98, 5, 10, 115), 0.000001);
end;

procedure TFramePacingTests.NativeWaitNeverPassesAnInvalidTimerObject;
var Clock: TDisplayClock; Display: TDisplayBinding;
  StopEvent, WakeEvent, Timer: THandle;
begin
  Clock := TDisplayClock.Create;
  StopEvent := CreateEvent(nil, True, True, nil);
  WakeEvent := CreateEvent(nil, False, False, nil);
  Timer := CreateWaitableTimer(nil, False, nil);
  try
    Display := WindowDisplayBinding(Window);
    Clock.Bind(Display.Monitor, Display.DeviceName, Display.RefreshRate);
    if Clock.Source <> dcsVerticalBlank then Exit;
    Clock.WaitBoundary(StopEvent, WakeEvent, Timer);
    AssertTrue('Native wait parameters must contain supported event objects',
      LongWord(Clock.LastNativeStatus) <> $C000000D);
  finally
    Clock.Free;
    CloseHandle(Timer);
    CloseHandle(WakeEvent);
    CloseHandle(StopEvent);
  end;
end;

procedure TFramePacingTests.MonitorChangeRejectsHeldGeneration;
var OldMessage, NewMessage: TMsg;
begin
  StartEventPacer(60, 60);
  PulseBoundary;
  WaitForFrame(OldMessage);
  FakeMonitor := 2;
  Pacer.SetMonitorForWindow(Window);
  PulseBoundary;
  WaitForFrame(NewMessage);
  AssertFalse('A different monitor must invalidate the held frame',
    Pacer.ConsumeMessage(OldMessage.wParam));
  AssertTrue(Pacer.ConsumeMessage(NewMessage.wParam));
end;

procedure TFramePacingTests.DisplayWaitStopsPromptly;
var Started: QWord;
begin
  StartEventPacer(60, 60);
  AssertEquals(DWORD(WAIT_OBJECT_0), WaitForSingleObject(DisplayWaiting, 1000));
  Started := GetTickCount64;
  FreeAndNil(Pacer);
  AssertTrue('Display-off waits must not block shutdown', GetTickCount64 - Started < 200);
end;

function TFallbackFramePacer.CreateNativeTimer(out HighResolution: Boolean): THandle;
begin
  HighResolution := False;
  Result := CreateWaitableTimer(nil, False, nil);
end;

function TTimerOnlyDisplayClock.OpenDisplay(const Device: string;
  out Adapter, SourceId: Cardinal): Boolean;
begin Result := False; end;

function TFallbackFramePacer.CreateDisplayClock: TDisplayClock;
begin Result := TTimerOnlyDisplayClock.Create; end;

procedure TFallbackFramePacer.ReleaseNativeTimerResolution;
begin
  InterlockedIncrement(ReleasedTimerResolutions);
  inherited;
end;

function TFallbackFramePacer.HasResolution: Boolean;
begin Result := TimerResolutionActive; end;

procedure TFramePacingTests.SetUp;
begin
  ReleasedTimerResolutions := 0;
  DisplayPulse := CreateEvent(nil, False, False, nil);
  DisplayWaiting := CreateEvent(nil, True, False, nil);
  Window := CreateWindowEx(0, 'STATIC', '', WS_POPUP, 0, 0, 10, 10,
    0, 0, HInstance, nil);
  AssertTrue('A hidden owner window must exist', Window <> 0);
  Pacer := TFramePacer.Create(Window, DOCK_FRAME_MESSAGE);
end;

procedure TFramePacingTests.TearDown;
begin
  Pacer.Free;
  CloseHandle(DisplayPulse);
  CloseHandle(DisplayWaiting);
  RemoveFrames;
  DestroyWindow(Window);
end;

procedure TFramePacingTests.WaitForFrame(out Message: TMsg);
var Deadline: QWord;
begin
  Deadline := GetTickCount64 + 1000;
  repeat
    if PeekMessage(Message, Window, DOCK_FRAME_MESSAGE, DOCK_FRAME_MESSAGE,
      PM_REMOVE) then Exit;
    Sleep(1);
  until GetTickCount64 >= Deadline;
  Fail('An active frame pacer must deliver a frame');
end;

function TFramePacingTests.RemoveFrames: Integer;
var Message: TMsg;
begin
  Result := 0;
  while PeekMessage(Message, Window, DOCK_FRAME_MESSAGE, DOCK_FRAME_MESSAGE,
    PM_REMOVE) do Inc(Result);
end;

procedure TFramePacingTests.ActivePacerPostsFrames;
var Message: TMsg;
begin
  Pacer.SetActive(True);
  WaitForFrame(Message);
  AssertTrue('The current generation must be accepted',
    Pacer.ConsumeMessage(Message.wParam));
end;

procedure TFramePacingTests.SleepingUiReceivesOnlyOnePendingFrame;
begin
  Pacer.SetRefreshRate(120);
  Pacer.SetActive(True);
  Sleep(150);
  AssertEquals('A stalled UI must not accumulate frame messages', 1, RemoveFrames);
end;

procedure TFramePacingTests.StoppedPacerRejectsQueuedFrame;
var Message: TMsg;
begin
  Pacer.SetActive(True);
  WaitForFrame(Message);
  Pacer.SetActive(False);
  AssertFalse('A stopped animation rejects its old wakeup',
    Pacer.ConsumeMessage(Message.wParam));
  Sleep(30);
  AssertEquals(0, RemoveFrames);
end;

procedure TFramePacingTests.RestartRejectsPreviousGeneration;
var OldMessage, NewMessage: TMsg;
begin
  Pacer.SetActive(True);
  WaitForFrame(OldMessage);
  Pacer.SetActive(False);
  Pacer.SetActive(True);
  WaitForFrame(NewMessage);
  AssertFalse(Pacer.ConsumeMessage(OldMessage.wParam));
  AssertTrue(Pacer.ConsumeMessage(NewMessage.wParam));
end;

procedure TFramePacingTests.FrameConsumptionAllowsNextFrame;
var FirstMessage, NextMessage: TMsg;
begin
  Pacer.SetActive(True);
  WaitForFrame(FirstMessage);
  AssertTrue(Pacer.ConsumeMessage(FirstMessage.wParam));
  WaitForFrame(NextMessage);
  AssertTrue(Pacer.ConsumeMessage(NextMessage.wParam));
end;

procedure TFramePacingTests.InactivePacerDoesNotPost;
begin
  Sleep(30);
  AssertEquals(0, RemoveFrames);
end;

procedure TFramePacingTests.SupportsBothRefreshRates;
begin
  Pacer.SetRefreshRate(60);
  AssertEquals(60.0, Pacer.RefreshRate, 0.0001);
  Pacer.SetRefreshRate(120);
  AssertEquals(120.0, Pacer.RefreshRate, 0.0001);
end;

procedure TFramePacingTests.RefreshRateChangeKeepsOneQueuedFrame;
begin
  Pacer.SetActive(True);
  Sleep(30);
  Pacer.SetRefreshRate(120);
  Sleep(30);
  AssertEquals('A rate change must retain one queued frame', 1, RemoveFrames);
end;

procedure TFramePacingTests.RepeatedRateChangesKeepOneQueuedFrame;
var Index: Integer;
begin
  Pacer.SetActive(True);
  for Index := 1 to 6 do
  begin
    Sleep(30);
    if Odd(Index) then Pacer.SetRefreshRate(120) else Pacer.SetRefreshRate(60);
  end;
  Sleep(30);
  AssertEquals('Repeated rate changes must retain one queued frame', 1, RemoveFrames);
end;

procedure TFramePacingTests.RepeatedRestartsKeepOneQueuedFrame;
var Index: Integer;
begin
  Pacer.SetActive(True);
  for Index := 1 to 6 do
  begin
    Sleep(30);
    Pacer.SetActive(False);
    Pacer.SetActive(True);
  end;
  Sleep(30);
  AssertEquals('Repeated restarts must retain one queued frame', 1, RemoveFrames);
end;

procedure TFramePacingTests.RateChangeRejectsHeldGeneration;
var OldMessage, NewMessage: TMsg;
begin
  Pacer.SetActive(True);
  WaitForFrame(OldMessage);
  Pacer.SetRefreshRate(120);
  WaitForFrame(NewMessage);
  AssertFalse('The old rate generation must be rejected', Pacer.ConsumeMessage(OldMessage.wParam));
  AssertTrue('The new rate generation must remain usable', Pacer.ConsumeMessage(NewMessage.wParam));
end;

procedure TFramePacingTests.RateChangePreservesOtherMessages;
var Message: TMsg;
begin
  Pacer.SetActive(True);
  PostMessage(Window, DOCK_FRAME_MESSAGE + 1, 11, 22);
  Pacer.SetRefreshRate(120);
  AssertTrue('State changes must preserve unrelated window messages',
    PeekMessage(Message, Window, DOCK_FRAME_MESSAGE + 1, DOCK_FRAME_MESSAGE + 1, PM_REMOVE));
  AssertEquals(11, Int64(Message.wParam));
end;

procedure TFramePacingTests.StartFallbackWithoutOwner;
var Deadline: QWord;
begin
  FreeAndNil(Pacer);
  Pacer := TFallbackFramePacer.Create(Window, DOCK_FRAME_MESSAGE);
  Pacer.SetActive(True);
  AssertTrue('Fallback pacing must acquire its timer resolution',
    TFallbackFramePacer(Pacer).HasResolution);
  DestroyWindow(Window);
  Window := 0;
  Deadline := GetTickCount64 + 1000;
  while Pacer.Active and (GetTickCount64 < Deadline) do Sleep(1);
  AssertFalse('Posting to a destroyed owner must deactivate pacing', Pacer.Active);
end;

procedure TFramePacingTests.FailedPostReleasesFallbackResolution;
begin
  StartFallbackWithoutOwner;
  AssertFalse('A failed post must release timer resolution immediately',
    TFallbackFramePacer(Pacer).HasResolution);
end;

procedure TFramePacingTests.InactiveStopReleasesFallbackResolution;
begin
  StartFallbackWithoutOwner;
  Pacer.SetActive(False);
  AssertFalse('Stopping an inactive pacer must release timer resolution',
    TFallbackFramePacer(Pacer).HasResolution);
  AssertEquals('Timer resolution must be released once', 1, ReleasedTimerResolutions);
end;

procedure TFramePacingTests.DestroyReleasesFailedFallbackResolution;
begin
  StartFallbackWithoutOwner;
  FreeAndNil(Pacer);
  AssertEquals('Destruction must release timer resolution once', 1, ReleasedTimerResolutions);
end;

initialization
  RegisterTest(TFramePacingTests);
end.
