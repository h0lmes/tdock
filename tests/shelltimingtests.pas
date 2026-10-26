unit shelltimingtests;

{$mode delphi}

interface

uses Windows, SysUtils, fpcunit, testregistry, declu, GDIPAPI,
  trayu, shelltraywndu, notifieru;

type
  TShellTimingTests = class(TTestCase)
  published
    procedure MissingPopupExpires;
    procedure LatePopupBecomesVisible;
    procedure DestroyedPopupCanBeReplaced;
    procedure HiddenPopupCompletesRequest;
    procedure LeftReservationUsesMonitorOrigin;
    procedure TopAutoHideUsesMonitorOrigin;
    procedure MissingTaskbarNeverWritesWorkarea;
    procedure FailedReservationDoesNotClaimOwnership;
    procedure FailedRestorationRetainsOwnership;
    procedure AllMonitorSettingUsesDockMonitor;
    procedure StaticAlertNeedsNoTimer;
    procedure StaticMessageUsesExpirationDeadline;
    procedure ExpiredHoveredMessageUsesSlowRecovery;
    procedure AnimationUsesFrameTimer;
    procedure TrayControllerReacquiresLateAndReplacedWindows;
    procedure StartControllerReacquiresLateWindows;
    procedure TrayControllerStopsMissingDiscovery;
    procedure FailedHideWorkareaRetriesAfterVisibilityChanges;
    procedure FailedShowWorkareaRetriesOnWatchdog;
    procedure MissingTaskbarDefersPendingLayout;
    procedure FailedRectangleQueryDefersPendingLayout;
  end;

implementation

function BoundsRect(Left, Top, Right, Bottom: Integer): Windows.TRect;
begin
  Result.Left := Left;
  Result.Top := Top;
  Result.Right := Right;
  Result.Bottom := Bottom;
end;

type
  TTestShell = class(TShellTrayWndController)
  public
    Writes, LastMonitor: Integer;
    AllowWrite: Boolean;
    CurrentWorkarea: Windows.TRect;
    constructor Create;
  protected
    function FindShellWindow: HWND; override;
    function FindStartButton: HWND; override;
    function ReadWindowRect(Window: HWND; out Bounds: Windows.TRect): Boolean; override;
    function GetMonitorWorkareaRect(Monitor: Integer): Windows.TRect; override;
    function GetMonitorBoundsRect(Monitor: Integer): Windows.TRect; override;
    function MonitorForDockRect(const DockRect: GDIPAPI.TRect): Integer; override;
    function SetWorkarea(NewWorkArea: Windows.TRect): Boolean; override;
  end;

  TTestTray = class(TTrayController)
  public
    Now: QWord;
    Found: HWND;
    Shown: Boolean;
    Moves: Integer;
    procedure Request;
  protected
    function ClockNow: QWord; override;
    function LookupPopup(const ClassName, Caption: string): HWND; override;
    function ValidPopup(Window: HWND): Boolean; override;
    function PopupVisible(Window: HWND): Boolean; override;
    function ReadPopupRect(Window: HWND; out Bounds: Windows.TRect): Boolean; override;
    function PlacePopup(Window: HWND; X, Y: Integer): Boolean; override;
  end;

  TTestTaskbar = class(TTestShell)
  public
    TaskbarExists, TaskbarVisible, CanReadRect: Boolean;
    constructor Create;
  protected
    function FindShellWindow: HWND; override;
    function ShellWindowExists(Window: HWND): Boolean; override;
    function ShellWindowVisible(Window: HWND): Boolean; override;
    procedure ShowShellWindow(Window: HWND; Visible: Boolean); override;
    function ReadWindowRect(Window: HWND; out Bounds: Windows.TRect): Boolean; override;
  end;

  TTestStart = class(TTestShell)
  public
    Now: QWord;
    Found: HWND;
    Shown: Boolean;
    Moves: Integer;
  protected
    function ClockNow: QWord; override;
    function FindStartMenu: HWND; override;
    function ValidStartMenu(Window: HWND): Boolean; override;
    function PopupVisible(Window: HWND): Boolean; override;
    function ReadWindowRect(Window: HWND; out Bounds: Windows.TRect): Boolean; override;
    function PlacePopup(Window: HWND; X, Y: Integer): Boolean; override;
  end;

procedure TTestTray.Request;
begin BeginPopup('TestPopup', ''); end;

constructor TTestTaskbar.Create;
begin
  inherited;
  TaskbarExists := True;
  TaskbarVisible := True;
  CanReadRect := True;
  CurrentWorkarea.Bottom := -40;
end;

function TTestTaskbar.FindShellWindow: HWND;
begin
  if TaskbarExists then Result := 42 else Result := 0;
end;

function TTestTaskbar.ShellWindowExists(Window: HWND): Boolean;
begin Result := TaskbarExists and (Window = 42); end;

function TTestTaskbar.ShellWindowVisible(Window: HWND): Boolean;
begin Result := (Window = 42) and TaskbarVisible; end;

procedure TTestTaskbar.ShowShellWindow(Window: HWND; Visible: Boolean);
begin
  if Window = 42 then TaskbarVisible := Visible;
end;

function TTestTaskbar.ReadWindowRect(Window: HWND; out Bounds: Windows.TRect): Boolean;
begin
  Bounds := BoundsRect(-1920, -40, 0, 0);
  Result := (Window = 42) and CanReadRect;
end;

function TTestTray.ClockNow: QWord;
begin Result := Now; end;

function TTestTray.LookupPopup(const ClassName, Caption: string): HWND;
begin Result := Found; end;

function TTestTray.ValidPopup(Window: HWND): Boolean;
begin Result := (Window <> 0) and (Window = Found); end;

function TTestTray.PopupVisible(Window: HWND): Boolean;
begin Result := Shown; end;

function TTestTray.ReadPopupRect(Window: HWND; out Bounds: Windows.TRect): Boolean;
begin Bounds := BoundsRect(100, 100, 160, 140); Result := True; end;

function TTestTray.PlacePopup(Window: HWND; X, Y: Integer): Boolean;
begin Inc(Moves); Result := True; end;

function TTestStart.ClockNow: QWord;
begin Result := Now; end;

function TTestStart.FindStartMenu: HWND;
begin Result := Found; end;

function TTestStart.ValidStartMenu(Window: HWND): Boolean;
begin Result := (Window <> 0) and (Window = Found); end;

function TTestStart.PopupVisible(Window: HWND): Boolean;
begin Result := Shown; end;

function TTestStart.ReadWindowRect(Window: HWND; out Bounds: Windows.TRect): Boolean;
begin Bounds := BoundsRect(100, 100, 160, 140); Result := Window = Found; end;

function TTestStart.PlacePopup(Window: HWND; X, Y: Integer): Boolean;
begin Inc(Moves); Result := True; end;

constructor TTestShell.Create;
begin
  inherited;
  AllowWrite := True;
  LastMonitor := -99;
  CurrentWorkarea := BoundsRect(-1920, -1080, 0, 0);
end;

function TTestShell.FindShellWindow: HWND;
begin Result := 0; end;

function TTestShell.FindStartButton: HWND;
begin Result := 0; end;

function TTestShell.ReadWindowRect(Window: HWND; out Bounds: Windows.TRect): Boolean;
begin Bounds := Default(Windows.TRect); Result := False; end;

function TTestShell.GetMonitorWorkareaRect(Monitor: Integer): Windows.TRect;
begin LastMonitor := Monitor; Result := CurrentWorkarea; end;

function TTestShell.GetMonitorBoundsRect(Monitor: Integer): Windows.TRect;
begin Result := BoundsRect(-1920, -1080, 0, 0); end;

function TTestShell.MonitorForDockRect(const DockRect: GDIPAPI.TRect): Integer;
begin Result := 1; end;

function TTestShell.SetWorkarea(NewWorkArea: Windows.TRect): Boolean;
begin
  Inc(Writes);
  Result := AllowWrite;
  if Result then CurrentWorkarea := NewWorkarea;
end;

function DockRect: GDIPAPI.TRect;
begin
  Result.X := -1920;
  Result.Y := -1080;
  Result.Width := 64;
  Result.Height := 48;
end;

procedure TShellTimingTests.MissingPopupExpires;
var State: TShellPopupState;
begin
  State := Default(TShellPopupState);
  State.Start(100, 3000);
  State.Observe(3099, False, False);
  AssertTrue('Discovery remains active before its deadline', State.NeedsPolling);
  State.Observe(3100, False, False);
  AssertEquals('Missing discovery must terminate at its deadline', Ord(spFailed), Ord(State.Phase));
end;

procedure TShellTimingTests.LatePopupBecomesVisible;
var State: TShellPopupState;
begin
  State := Default(TShellPopupState);
  State.Start(100, 3000);
  State.Observe(150, False, False);
  State.Observe(200, True, True);
  AssertEquals(Ord(spVisible), Ord(State.Phase));
end;

procedure TShellTimingTests.DestroyedPopupCanBeReplaced;
var State: TShellPopupState;
begin
  State := Default(TShellPopupState);
  State.Start(100, 3000);
  State.Observe(200, True, True);
  State.Observe(300, False, False);
  AssertEquals('Destroyed windows require bounded rediscovery', Ord(spWaiting), Ord(State.Phase));
  State.Observe(400, True, True);
  AssertEquals(Ord(spVisible), Ord(State.Phase));
end;

procedure TShellTimingTests.HiddenPopupCompletesRequest;
var State: TShellPopupState;
begin
  State := Default(TShellPopupState);
  State.Start(100, 3000);
  State.Observe(200, True, True);
  State.Observe(300, True, False);
  AssertFalse(State.NeedsPolling);
end;

procedure TShellTimingTests.LeftReservationUsesMonitorOrigin;
var Bounds, Planned: Windows.TRect;
begin
  Bounds := BoundsRect(-1920, -1080, 0, 0);
  Planned := ReservedWorkarea(Bounds, Bounds, bsLeft, 100, DockRect, False);
  AssertEquals('The reservation starts at the monitor origin', -1856, Planned.Left);
end;

procedure TShellTimingTests.TopAutoHideUsesMonitorOrigin;
var Bounds, Planned: Windows.TRect;
begin
  Bounds := BoundsRect(-1920, -1080, 0, 0);
  Planned := ReservedWorkarea(Bounds, Bounds, bsTop, 100, DockRect, True);
  AssertEquals(-1080, Planned.Top);
end;

procedure TShellTimingTests.MissingTaskbarNeverWritesWorkarea;
var Shell: TTestShell;
begin
  Shell := TTestShell.Create;
  try
    Shell.HideTaskbar(False);
    AssertEquals('Missing taskbar geometry must never reach Windows', 0, Shell.Writes);
  finally Shell.Free; end;
end;

procedure TShellTimingTests.FailedReservationDoesNotClaimOwnership;
var Shell: TTestShell;
begin
  Shell := TTestShell.Create;
  try
    Shell.AllowWrite := False;
    Shell.ReserveScreenEdge(0, bsLeft, 100, DockRect, False);
    AssertFalse('Failed effects cannot create reservation ownership', Shell.EdgeReserved);
  finally Shell.Free; end;
end;

procedure TShellTimingTests.FailedRestorationRetainsOwnership;
var Shell: TTestShell;
begin
  Shell := TTestShell.Create;
  try
    Shell.ReserveScreenEdge(0, bsLeft, 100, DockRect, False);
    Shell.AllowWrite := False;
    Shell.UnreserveScreenEdge;
    AssertTrue('Failed restoration remains available for retry', Shell.EdgeReserved);
  finally Shell.Free; end;
end;

procedure TShellTimingTests.AllMonitorSettingUsesDockMonitor;
var Shell: TTestShell;
begin
  Shell := TTestShell.Create;
  try
    Shell.ReserveScreenEdge(-1, bsBottom, 100, DockRect, False);
    AssertEquals('All-monitor selection resolves the dock rectangle center', 1, Shell.LastMonitor);
  finally Shell.Free; end;
end;

procedure TShellTimingTests.StaticAlertNeedsNoTimer;
begin AssertEquals(0, Integer(NotificationTimerInterval(True, True, False, 100, 8100))); end;

procedure TShellTimingTests.StaticMessageUsesExpirationDeadline;
begin AssertEquals(8000, Integer(NotificationTimerInterval(True, False, False, 100, 8100))); end;

procedure TShellTimingTests.ExpiredHoveredMessageUsesSlowRecovery;
begin AssertEquals(250, Integer(NotificationTimerInterval(True, False, False, 8200, 8100))); end;

procedure TShellTimingTests.AnimationUsesFrameTimer;
begin AssertEquals(10, Integer(NotificationTimerInterval(True, False, True, 100, 8100))); end;

procedure TShellTimingTests.TrayControllerReacquiresLateAndReplacedWindows;
var Tray: TTestTray;
begin
  Tray := TTestTray.Create;
  try
    Tray.Now := 100;
    Tray.Request;
    Tray.Timer;
    AssertTrue(Tray.NeedsPolling);
    Tray.Now := 200;
    Tray.Found := 42;
    Tray.Shown := True;
    Tray.ObserveWindowChange(42);
    AssertEquals(Ord(spVisible), Ord(Tray.PlacementPhase));
    AssertFalse('Visible windows use observation events and the slow watchdog', Tray.NeedsPolling);
    AssertEquals(1, Tray.Moves);
    Tray.Now := 300;
    Tray.Found := 0;
    Tray.ObserveWindowChange(42);
    AssertTrue(Tray.NeedsPolling);
    Tray.Now := 400;
    Tray.Found := 43;
    Tray.ObserveWindowChange(43);
    AssertEquals(Ord(spVisible), Ord(Tray.PlacementPhase));
    Tray.Shown := False;
    Tray.ObserveWindowChange(43);
    AssertEquals(Ord(spIdle), Ord(Tray.PlacementPhase));
  finally Tray.Free; end;
end;

procedure TShellTimingTests.StartControllerReacquiresLateWindows;
var Shell: TTestStart; Bounds: Windows.TRect;
begin
  Shell := TTestStart.Create;
  try
    Bounds := BoundsRect(0, 0, 1920, 1080);
    Shell.Now := 100;
    Shell.ShowStartMenu(bsBottom, 0, Bounds, Bounds);
    Shell.Timer;
    AssertTrue(Shell.NeedsPolling);
    Shell.Now := 200;
    Shell.Found := 42;
    Shell.Shown := True;
    Shell.ObserveWindowChange(42);
    AssertEquals(Ord(spVisible), Ord(Shell.PlacementPhase));
    AssertEquals(1, Shell.Moves);
  finally Shell.Free; end;
end;

procedure TShellTimingTests.TrayControllerStopsMissingDiscovery;
var Tray: TTestTray;
begin
  Tray := TTestTray.Create;
  try
    Tray.Now := 100;
    Tray.Request;
    Tray.Now := 100 + SHELL_POPUP_TIMEOUT;
    Tray.Timer;
    AssertEquals(Ord(spFailed), Ord(Tray.PlacementPhase));
    AssertFalse(Tray.NeedsPolling);
  finally Tray.Free; end;
end;

procedure TShellTimingTests.FailedHideWorkareaRetriesAfterVisibilityChanges;
var Shell: TTestTaskbar;
begin
  Shell := TTestTaskbar.Create;
  try
    Shell.AllowWrite := False;
    Shell.HideTaskbar(True);
    AssertFalse('The first visibility effect succeeds', Shell.TaskbarVisible);
    AssertEquals(1, Shell.Writes);
    Shell.AllowWrite := True;
    Shell.HideTaskbar(True);
    AssertEquals('Matching visibility must not discard failed layout work', 2, Shell.Writes);
    AssertEquals(0, Shell.CurrentWorkarea.Bottom);
  finally Shell.Free; end;
end;

procedure TShellTimingTests.FailedShowWorkareaRetriesOnWatchdog;
var Shell: TTestTaskbar;
begin
  Shell := TTestTaskbar.Create;
  try
    Shell.TaskbarVisible := False;
    Shell.CurrentWorkarea.Bottom := 0;
    Shell.AllowWrite := False;
    Shell.HideTaskbar(False);
    AssertTrue(Shell.TaskbarVisible);
    Shell.AllowWrite := True;
    Shell.Timer;
    AssertEquals('The watchdog retries restoration after hiding is disabled', 2, Shell.Writes);
    AssertEquals(-40, Shell.CurrentWorkarea.Bottom);
    Shell.Timer;
    AssertEquals('Successful restoration releases pending work', 2, Shell.Writes);
  finally Shell.Free; end;
end;

procedure TShellTimingTests.MissingTaskbarDefersPendingLayout;
var Shell: TTestTaskbar;
begin
  Shell := TTestTaskbar.Create;
  try
    Shell.AllowWrite := False;
    Shell.HideTaskbar(True);
    Shell.AllowWrite := True;
    Shell.TaskbarExists := False;
    Shell.Timer;
    AssertEquals('Missing handles cannot authorize geometry writes', 1, Shell.Writes);
    Shell.TaskbarExists := True;
    Shell.Timer;
    AssertEquals('Valid rediscovery resumes pending layout', 2, Shell.Writes);
  finally Shell.Free; end;
end;

procedure TShellTimingTests.FailedRectangleQueryDefersPendingLayout;
var Shell: TTestTaskbar;
begin
  Shell := TTestTaskbar.Create;
  try
    Shell.AllowWrite := False;
    Shell.HideTaskbar(True);
    Shell.AllowWrite := True;
    Shell.CanReadRect := False;
    Shell.Timer;
    AssertEquals(1, Shell.Writes);
    Shell.CanReadRect := True;
    Shell.Timer;
    AssertEquals('A valid observation resumes the retained layout request', 2, Shell.Writes);
  finally Shell.Free; end;
end;

initialization
  RegisterTest(TShellTimingTests);
end.
