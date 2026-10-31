unit animationtimingtests;

{$mode delphi}

interface

uses Windows, Messages, Controls, SysUtils, Classes, MultiMon, fpcunit, testregistry,
  declu, stackitemu, scsubitemu, hintu, aeropeeku, themeu, itemmodelu,
  itemviewu, setsu, gfx;

type
  TStackTimingProbe = class(TStackItem)
  protected
    function AnimationNow: QWord; override;
    function MotionNow: Double; override;
  public
    Now: Double;
    function Progress: Double;
    function AnimationState: TStackState;
    function AnimationDuration: Double;
  end;

  THintTimingProbe = class(THint)
  protected
    procedure Paint; override;
    function AnimationNow: QWord; override;
    function MotionNow: Double; override;
    procedure ApplyWindowPosition; override;
    function PresentNativePixels(const Bitmap: _SimpleBitmap): Boolean; override;
    function PresentNativePosition: Boolean; override;
  public
    Now: Double;
    Paints, Positions: Integer;
    RejectPixels, RejectPosition: Boolean;
    procedure Stable;
    function FrameActive: boolean;
    procedure BeginFade;
    function Alpha: integer;
    function PreciseAlpha: Double;
    procedure BeginResize;
    procedure ForgetPixels;
    procedure ActivateStationary;
  end;

  TPeekTimingProbe = class(TAeroPeekWindow)
  protected
    procedure Paint; override;
    function AnimationNow: QWord; override;
    function MotionNow: Double; override;
    function PointerInside: boolean; override;
    procedure ApplyWindowPosition; override;
    procedure UpdateTitles; override;
    function PresentNativePixels(const Bitmap: _SimpleBitmap): Boolean; override;
    function PresentNativePosition: Boolean; override;
    function CreateSurfaceGraphics(DC: HDC): Pointer; override;
    function CompositionAvailable: Boolean; override;
  public
    Now: Double;
    PointerReads, TitleRefreshes, Paints, Positions: integer;
    RejectPixels, RejectPosition, NativePaint, RejectGraphics: Boolean;
    procedure Stable;
    procedure Tick;
    function FrameActive: boolean;
    procedure Enter;
    function PeekAllowed: boolean;
    function PeekRemaining: QWord;
    procedure BeginMove;
    function LeftPosition: integer;
    procedure ArmTitleRefresh;
    procedure ResizeSettled;
    function PreciseLeft: Double;
    procedure ForgetPixels;
    function PreciseAlpha: Double;
    procedure MoveWithoutPixels;
    procedure PaintOnce;
  end;

  TTimerViewProbe = class(TItemViewAdapter)
  protected
    function TimerNow: QWord; override;
    function SetNativeTimer(Window: HWND; TimerId: UINT_PTR; Interval: UINT): UINT_PTR; override;
  public
    Now: QWord;
    LastInterval: UINT;
  end;

  TAnimationTimingTests = class(TTestCase)
  private
    FixtureTheme: TDTheme;
    Stack: TStackTimingProbe;
    Store: TDSets;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure StackClosePreservesPartialOpening;
    procedure StackReopenPreservesPartialClosing;
    procedure StackProgressUsesElapsedTime;
    procedure StackKeepsLegacyWallTime;
    procedure StackAdvancesAtFractionalTimes;
    procedure StableHintStopsFrameTimer;
    procedure StablePeekStopsFrameTimer;
    procedure RecreatedViewKeepsRemainingDeadline;
    procedure HintFadeOutRestartsFrameTimer;
    procedure PeekCloseRestartsFrameTimer;
    procedure PeekDwellSurvivesPositionChange;
    procedure EarlyPeekDeadlineDoesNotFire;
    procedure CancelledPeekDeadlineDoesNotFire;
    procedure EarlyHintFrameDoesNotAdvance;
    procedure DelayedHintFrameCatchesUp;
    procedure EarlyPeekFrameDoesNotAdvance;
    procedure DelayedPeekFrameCatchesUp;
    procedure NativeMinimumDelayGuardsLogicalTimer;
    procedure EarlyTrackingTimerDoesNotObserveCursor;
    procedure CancelledTrackingTimerDoesNotObserveCursor;
    procedure HiddenStackFinishesClosingImmediately;
    procedure InactivePreviewCloseNeedsNoFrames;
    procedure EarlyTitleTimerDoesNotRefresh;
    procedure InactiveTitleTimerDoesNotRefresh;
    procedure HintFrameAdvancesWithinTenMilliseconds;
    procedure PeekFrameAdvancesWithinTenMilliseconds;
    procedure SettledPeekResizeRestartsFrames;
    procedure HintFadeIgnoresFramePartition;
    procedure PeekMoveIgnoresFramePartition;
    procedure HintReversalPreservesCurrentAlpha;
    procedure HintPositionFramesReusePixels;
    procedure PeekPositionFramesReusePixels;
    procedure HintSizeFramesRepaintPixels;
    procedure ImmediateHintCloseCancelsFrames;
    procedure HintFadeKeepsLegacyDuration;
    procedure PeekMoveKeepsLegacyDuration;
    procedure SettledPeekResizeStopsFramesAgain;
    procedure HintRetriesMissingPixels;
    procedure PeekRetriesMissingPixels;
    procedure CheckedLayeredPixelsReportNativeFailure;
    procedure CheckedLayeredPositionReportsNativeFailure;
    procedure HintRejectedPixelsRemainScheduled;
    procedure PeekRejectedPixelsRemainScheduled;
    procedure HintRejectedPositionResendsPixels;
    procedure PeekRejectedPositionResendsPixels;
    procedure StationaryHintRetriesRejectedPixels;
    procedure PeekRejectedGraphicsReleasesNativeBitmap;
    procedure PeekReopenPreservesClosingAlpha;
    procedure PeekPositionCannotValidateMissingPixels;
    procedure SettledPeekGraphicsFailureStartsRetryFrames;
  end;

implementation

function NativeGetGuiResources(Process: THandle; Flags: DWORD): DWORD; stdcall;
  external 'user32.dll' name 'GetGuiResources';

function TStackTimingProbe.AnimationNow: QWord;
begin Result := Trunc(Now); end;
function TStackTimingProbe.MotionNow: Double;
begin Result := Now; end;
function TStackTimingProbe.Progress: Double;
begin Result := FStateProgress; end;
function TStackTimingProbe.AnimationState: TStackState;
begin Result := FState; end;
function TStackTimingProbe.AnimationDuration: Double;
begin Result := FStackAnimation.DurationMs; end;

procedure THintTimingProbe.Paint;
var Bitmap: _SimpleBitmap;
begin
  Inc(Paints);
  Bitmap := Default(_SimpleBitmap);
  PresentPixels(Bitmap);
end;
function THintTimingProbe.PresentNativePixels(const Bitmap: _SimpleBitmap): Boolean;
begin Result := not RejectPixels; end;
function THintTimingProbe.PresentNativePosition: Boolean;
begin Result := not RejectPosition; end;
function THintTimingProbe.AnimationNow: QWord;
begin Result := Trunc(Now); end;
function THintTimingProbe.MotionNow: Double;
begin Result := Now; end;
procedure THintTimingProbe.ApplyWindowPosition;
begin Inc(Positions); inherited; end;
procedure THintTimingProbe.Stable;
begin
  FVisible := true;
  FAlpha := 255;
  FAlphaTarget := 255;
  FX := 10; FXTarget := FX;
  FY := 20; FYTarget := FY;
  FW := 100; FWTarget := FW;
  FH := 30; FHTarget := FH;
  FSurfaceReady := True;
  StartFrameTimer;
end;
function THintTimingProbe.FrameActive: boolean;
begin Result := FFrameTimerActive; end;
procedure THintTimingProbe.BeginFade;
begin
  Stable;
  StopFrameTimer;
  FAlpha := 0;
  Now := 1000;
  StartFrameTimer;
end;
function THintTimingProbe.Alpha: integer;
begin Result := FAlpha; end;
function THintTimingProbe.PreciseAlpha: Double;
begin Result := FAlphaMotion; end;
procedure THintTimingProbe.BeginResize;
begin
  Stable;
  StopFrameTimer;
  FWTarget := 200;
  Now := 1000;
  StartFrameTimer;
end;
procedure THintTimingProbe.ForgetPixels;
begin FSurfaceReady := False; end;
procedure THintTimingProbe.ActivateStationary;
var Point: Windows.TPoint;
begin
  Point.X := 100; Point.Y := 100;
  ActivateHint(0, 'Native presentation', 100, 100,
    MultiMon.MonitorFromPoint(Point, MONITOR_DEFAULTTONEAREST), bsBottom);
end;

procedure TPeekTimingProbe.Paint;
var Bitmap: _SimpleBitmap;
begin
  Inc(Paints);
  if NativePaint then inherited
  else begin
    Bitmap := Default(_SimpleBitmap);
    PresentPixels(Bitmap);
  end;
end;
function TPeekTimingProbe.PresentNativePixels(const Bitmap: _SimpleBitmap): Boolean;
begin Result := not RejectPixels; end;
function TPeekTimingProbe.PresentNativePosition: Boolean;
begin Result := not RejectPosition; end;
function TPeekTimingProbe.CreateSurfaceGraphics(DC: HDC): Pointer;
begin
  if RejectGraphics then Result := nil else Result := inherited;
end;
function TPeekTimingProbe.CompositionAvailable: Boolean;
begin Result := True; end;
function TPeekTimingProbe.AnimationNow: QWord;
begin Result := Trunc(Now); end;
function TPeekTimingProbe.MotionNow: Double;
begin Result := Now; end;
function TPeekTimingProbe.PointerInside: boolean;
begin Inc(PointerReads); Result := true; end;
procedure TPeekTimingProbe.ApplyWindowPosition;
begin Inc(Positions); inherited; end;
procedure TPeekTimingProbe.UpdateTitles;
begin Inc(TitleRefreshes); end;
procedure TPeekTimingProbe.Stable;
begin
  FActive := true;
  FAnimate := true;
  FState := apwsOpen;
  FAlpha := 255; FAlphaTarget := 255;
  Fx := 10; FXTarget := Fx;
  Fy := 20; FYTarget := Fy;
  FWidth := 100; FWTarget := FWidth;
  FHeight := 30; FHTarget := FHeight;
  FSurfaceReady := True;
  FWorkArea.Left := 0; FWorkArea.Top := 0;
  FWorkArea.Right := 1920; FWorkArea.Bottom := 1080;
  StartFrameTimer;
end;
procedure TPeekTimingProbe.Tick;
begin Timer; end;
function TPeekTimingProbe.FrameActive: boolean;
begin Result := FFrameTimerActive; end;
procedure TPeekTimingProbe.Enter;
begin MouseEnter; end;
function TPeekTimingProbe.PeekAllowed: boolean;
begin Result := FAeroPeekAllowedInt; end;
function TPeekTimingProbe.PeekRemaining: QWord;
begin Result := FPeekDeadline.Remaining(Trunc(Now)); end;
procedure TPeekTimingProbe.BeginMove;
begin
  Stable;
  StopFrameTimer;
  Fx := 0;
  FXTarget := 100;
  Now := 1000;
  StartFrameTimer;
end;
function TPeekTimingProbe.LeftPosition: integer;
begin Result := Fx; end;
procedure TPeekTimingProbe.ArmTitleRefresh;
begin FTitleDeadline.Schedule(Trunc(Now), 1000); end;
procedure TPeekTimingProbe.ResizeSettled;
begin
  FWTarget := 200;
  SetItems;
end;
function TPeekTimingProbe.PreciseLeft: Double;
begin Result := FXMotion; end;
procedure TPeekTimingProbe.ForgetPixels;
begin FSurfaceReady := False; end;
function TPeekTimingProbe.PreciseAlpha: Double;
begin Result := FAlphaMotion; end;
procedure TPeekTimingProbe.MoveWithoutPixels;
begin
  FAnimate := False;
  FSurfaceReady := False;
  SetAPWindowPosition(100, 100);
end;
procedure TPeekTimingProbe.PaintOnce;
begin Paint; end;

function TTimerViewProbe.TimerNow: QWord;
begin Result := Now; end;
function TTimerViewProbe.SetNativeTimer(Window: HWND; TimerId: UINT_PTR; Interval: UINT): UINT_PTR;
begin
  LastInterval := Interval;
  Result := TimerId;
end;

procedure TAnimationTimingTests.SetUp;
var Params: TDItemCreateParams;
begin
  Store := TDSets.Create('', '', 0);
  sets := Store;
  Store.container.HintEffects := true;
  FixtureTheme := TDTheme(TDTheme.NewInstance);
  theme := FixtureTheme;
  Params := Default(TDItemCreateParams);
  Params.ItemSize := 32;
  Params.BigItemSize := 32;
  Params.StackAnimationEnabled := true;
  Params.Parameter := TStackItem.Make;
  Stack := TStackTimingProbe.Create(0, Params);
  Stack.Now := 1000;
  Stack.AddSubitem(TShortcutSubitem.Make('Timing probe', '/probe'));
end;

procedure TAnimationTimingTests.TearDown;
begin
  Stack.Free;
  theme := nil;
  FixtureTheme.Free;
  sets := nil;
  Store.Free;
end;

procedure TAnimationTimingTests.StackClosePreservesPartialOpening;
var Before: Double;
begin
  Stack.MouseClick(mbLeft, [], 0, 0);
  Stack.Now := 1030;
  Stack.Timer;
  Before := Stack.Progress;
  AssertTrue('The stack must be partially open', (Before > 0) and (Before < 1));
  Stack.MouseClick(mbLeft, [], 0, 0);
  AssertEquals('Closing must start at the current position', Before, Stack.Progress, 0.00001);
end;

procedure TAnimationTimingTests.StackReopenPreservesPartialClosing;
var Before: Double;
begin
  Stack.MouseClick(mbLeft, [], 0, 0);
  Stack.Now := 1030;
  Stack.Timer;
  Stack.MouseClick(mbLeft, [], 0, 0);
  Stack.Now := 1040;
  Stack.Timer;
  Before := Stack.Progress;
  Stack.MouseClick(mbLeft, [], 0, 0);
  AssertEquals('Reopening must preserve closing progress', Before, Stack.Progress, 0.00001);
end;

procedure TAnimationTimingTests.StackProgressUsesElapsedTime;
begin
  Stack.MouseClick(mbLeft, [], 0, 0);
  Stack.Now := 3000;
  Stack.Timer;
  AssertEquals('A delayed frame must finish elapsed movement', Ord(stsOpen), Ord(Stack.AnimationState));
end;

procedure TAnimationTimingTests.StackKeepsLegacyWallTime;
begin
  Stack.MouseClick(mbLeft, [], 0, 0);
  AssertEquals('Default stack motion retains its legacy timing',
    15.625 / 0.15, Stack.AnimationDuration, 0.0001);
end;

procedure TAnimationTimingTests.StackAdvancesAtFractionalTimes;
begin
  Stack.Now := 1000.25;
  Stack.MouseClick(mbLeft, [], 0, 0);
  Stack.Now := 1000.5;
  Stack.Timer;
  AssertTrue('Precise stack frames retain submillisecond motion', Stack.Progress > 0);
end;

procedure TAnimationTimingTests.StableHintStopsFrameTimer;
var Hint: THintTimingProbe;
begin
  Hint := THintTimingProbe.Create;
  try
    Hint.Stable;
    Hint.Timer;
    AssertFalse('A stable hint needs no frame callbacks', Hint.FrameActive);
  finally Hint.Free; end;
end;

procedure TAnimationTimingTests.StablePeekStopsFrameTimer;
var Peek: TPeekTimingProbe;
begin
  Peek := TPeekTimingProbe.Create;
  try
    Peek.Stable;
    Peek.Tick;
    AssertFalse('A stable preview needs no frame callbacks', Peek.FrameActive);
  finally Peek.Free; end;
end;

procedure TAnimationTimingTests.RecreatedViewKeepsRemainingDeadline;
var Views: TTimerViewProbe; Model: TItemModel; First, Replacement: HWND;
begin
  Views := TTimerViewProbe.Create;
  Model := TItemModel.Create;
  First := Windows.CreateWindowEx(0, 'STATIC', '', WS_POPUP, 0, 0, 1, 1, 0, 0, HInstance, nil);
  Replacement := Windows.CreateWindowEx(0, 'STATIC', '', WS_POPUP, 0, 0, 1, 1, 0, 0, HInstance, nil);
  try
    AssertTrue(Views.RegisterItem(First, 0, Model));
    Views.Now := 1000;
    Views.SetItemTimer(Model.ItemId, ID_TIMER_OPEN, 1000);
    AssertTrue(Views.RegisterItem(Replacement, 0, Model));
    Views.Now := 1600;
    Views.RestoreItemTimers(Model.ItemId);
    AssertEquals('Recreation must retain the original deadline', 400, Integer(Views.LastInterval));
  finally
    Views.UnregisterItem(First, Model);
    Views.UnregisterItem(Replacement, Model);
    Windows.DestroyWindow(First);
    Windows.DestroyWindow(Replacement);
    Model.Free;
    Views.Free;
  end;
end;

procedure TAnimationTimingTests.HintFadeOutRestartsFrameTimer;
var Hint: THintTimingProbe;
begin
  Hint := THintTimingProbe.Create;
  try
    Hint.Stable;
    Hint.Timer;
    Hint.DeactivateHint(0);
    AssertTrue('Fading a settled hint must restart frames', Hint.FrameActive);
  finally Hint.Free; end;
end;

procedure TAnimationTimingTests.PeekCloseRestartsFrameTimer;
var Peek: TPeekTimingProbe;
begin
  Peek := TPeekTimingProbe.Create;
  try
    Peek.Stable;
    Peek.Tick;
    Peek.CloseAPWindow;
    AssertTrue('Closing a settled preview must restart frames', Peek.FrameActive);
  finally Peek.Free; end;
end;

procedure TAnimationTimingTests.PeekDwellSurvivesPositionChange;
var Peek: TPeekTimingProbe;
begin
  Peek := TPeekTimingProbe.Create;
  try
    Peek.Stable;
    Peek.Now := 1000;
    Peek.Enter;
    Peek.Now := 1400;
    Peek.SetAPWindowPosition(100, 100);
    AssertEquals('Movement must preserve the remaining preview dwell', 600, Integer(Peek.PeekRemaining));
  finally Peek.Free; end;
end;

procedure TAnimationTimingTests.EarlyPeekDeadlineDoesNotFire;
var Peek: TPeekTimingProbe;
begin
  Peek := TPeekTimingProbe.Create;
  try
    Peek.Stable;
    Peek.Now := 1000;
    Peek.Enter;
    Peek.Now := 1400;
    Peek.WMTimer(ID_TIMER_AEROPEEK);
    AssertFalse('An early timer must not finish preview dwell', Peek.PeekAllowed);
  finally Peek.Free; end;
end;

procedure TAnimationTimingTests.CancelledPeekDeadlineDoesNotFire;
var Peek: TPeekTimingProbe;
begin
  Peek := TPeekTimingProbe.Create;
  try
    Peek.Stable;
    Peek.Now := 1000;
    Peek.Enter;
    Peek.MouseLeave;
    Peek.Now := 3000;
    Peek.WMTimer(ID_TIMER_AEROPEEK);
    AssertFalse('A cancelled timer must not restore preview eligibility', Peek.PeekAllowed);
  finally Peek.Free; end;
end;

procedure TAnimationTimingTests.EarlyHintFrameDoesNotAdvance;
var Hint: THintTimingProbe;
begin
  Hint := THintTimingProbe.Create;
  try
    Hint.BeginFade;
    Hint.Timer;
    AssertEquals('A frame needs elapsed animation time', 0, Hint.Alpha);
  finally Hint.Free; end;
end;

procedure TAnimationTimingTests.DelayedHintFrameCatchesUp;
var Hint: THintTimingProbe;
begin
  Hint := THintTimingProbe.Create;
  try
    Hint.BeginFade;
    Hint.Now := 2000;
    Hint.Timer;
    AssertEquals('Delayed hint frames must catch up', 255, Hint.Alpha);
    AssertFalse(Hint.FrameActive);
  finally Hint.Free; end;
end;

procedure TAnimationTimingTests.EarlyPeekFrameDoesNotAdvance;
var Peek: TPeekTimingProbe;
begin
  Peek := TPeekTimingProbe.Create;
  try
    Peek.BeginMove;
    Peek.Tick;
    AssertEquals('An early preview frame must preserve position', 0, Peek.LeftPosition);
  finally Peek.Free; end;
end;

procedure TAnimationTimingTests.DelayedPeekFrameCatchesUp;
var Peek: TPeekTimingProbe;
begin
  Peek := TPeekTimingProbe.Create;
  try
    Peek.BeginMove;
    Peek.Now := 2000;
    Peek.Tick;
    AssertEquals('Delayed preview frames must catch up', 100, Peek.LeftPosition);
    AssertFalse(Peek.FrameActive);
  finally Peek.Free; end;
end;

procedure TAnimationTimingTests.NativeMinimumDelayGuardsLogicalTimer;
var Views: TTimerViewProbe; Model: TItemModel; Window: HWND;
begin
  Views := TTimerViewProbe.Create;
  Model := TItemModel.Create;
  Window := Windows.CreateWindowEx(0, 'STATIC', '', WS_POPUP, 0, 0, 1, 1, 0, 0, HInstance, nil);
  try
    AssertTrue(Views.RegisterItem(Window, 0, Model));
    Views.Now := 1000;
    Views.SetItemTimer(Model.ItemId, ID_TIMER_OPEN, 0);
    AssertFalse('Logical deadlines must honor the native minimum',
      Views.ConsumeItemTimer(Model.ItemId, ID_TIMER_OPEN, 1000));
  finally
    Views.UnregisterItem(Window, Model);
    Windows.DestroyWindow(Window);
    Model.Free;
    Views.Free;
  end;
end;

procedure TAnimationTimingTests.EarlyTrackingTimerDoesNotObserveCursor;
var Peek: TPeekTimingProbe;
begin
  Peek := TPeekTimingProbe.Create;
  try
    Peek.Stable;
    Peek.Now := 1000;
    Peek.Enter;
    Peek.WMTimer(ID_TIMER_TRACKMOUSE);
    AssertEquals('Tracking must wait for its logical deadline', 0, Peek.PointerReads);
  finally Peek.Free; end;
end;

procedure TAnimationTimingTests.CancelledTrackingTimerDoesNotObserveCursor;
var Peek: TPeekTimingProbe;
begin
  Peek := TPeekTimingProbe.Create;
  try
    Peek.Stable;
    Peek.Now := 1000;
    Peek.Enter;
    Peek.MouseLeave;
    Peek.Now := 3000;
    Peek.WMTimer(ID_TIMER_TRACKMOUSE);
    AssertEquals('Cancelled tracking must perform no cursor work', 0, Peek.PointerReads);
  finally Peek.Free; end;
end;

procedure TAnimationTimingTests.HiddenStackFinishesClosingImmediately;
begin
  Stack.MouseClick(mbLeft, [], 0, 0);
  Stack.Now := 1030;
  Stack.Timer;
  Stack.MouseClick(mbLeft, [], 0, 0);
  Stack.cmd(icVisible, 0);
  AssertEquals('Hidden stacks must finish an active close', Ord(stsClosed), Ord(Stack.AnimationState));
end;

procedure TAnimationTimingTests.InactivePreviewCloseNeedsNoFrames;
var Peek: TPeekTimingProbe;
begin
  Peek := TPeekTimingProbe.Create;
  try
    Peek.CloseAPWindow;
    AssertFalse('Inactive previews must not start closing frames', Peek.FrameActive);
  finally Peek.Free; end;
end;

procedure TAnimationTimingTests.EarlyTitleTimerDoesNotRefresh;
var Peek: TPeekTimingProbe;
begin
  Peek := TPeekTimingProbe.Create;
  try
    Peek.Stable;
    Peek.Now := 1000;
    Peek.ArmTitleRefresh;
    Peek.WMTimer(ID_TIMER_SLOW);
    AssertEquals('Title refresh must wait for its logical deadline', 0, Peek.TitleRefreshes);
  finally Peek.Free; end;
end;

procedure TAnimationTimingTests.InactiveTitleTimerDoesNotRefresh;
var Peek: TPeekTimingProbe;
begin
  Peek := TPeekTimingProbe.Create;
  try
    Peek.WMTimer(ID_TIMER_SLOW);
    AssertEquals('Inactive previews need no title work', 0, Peek.TitleRefreshes);
  finally Peek.Free; end;
end;

procedure TAnimationTimingTests.HintFrameAdvancesWithinTenMilliseconds;
var Hint: THintTimingProbe;
begin
  Hint := THintTimingProbe.Create;
  try
    Hint.BeginFade;
    Hint.Now := 1008;
    Hint.Timer;
    AssertTrue('A 120 Hz frame must advance the fade', Hint.Alpha > 0);
  finally Hint.Free; end;
end;

procedure TAnimationTimingTests.PeekFrameAdvancesWithinTenMilliseconds;
var Peek: TPeekTimingProbe;
begin
  Peek := TPeekTimingProbe.Create;
  try
    Peek.BeginMove;
    Peek.Now := 1008;
    Peek.Tick;
    AssertTrue('A 120 Hz frame must advance the preview', Peek.LeftPosition > 0);
  finally Peek.Free; end;
end;

procedure TAnimationTimingTests.SettledPeekResizeRestartsFrames;
var Peek: TPeekTimingProbe;
begin
  Peek := TPeekTimingProbe.Create;
  try
    Peek.Stable;
    Peek.Tick;
    Peek.ResizeSettled;
    AssertTrue('A settled preview must schedule its new layout', Peek.FrameActive);
  finally Peek.Free; end;
end;

procedure TAnimationTimingTests.HintFadeIgnoresFramePartition;
var Sparse, Dense: THintTimingProbe;
begin
  Sparse := THintTimingProbe.Create;
  Dense := THintTimingProbe.Create;
  try
    Sparse.BeginFade;
    Dense.BeginFade;
    Dense.Now := 1008.25; Dense.Timer;
    Dense.Now := 1016.75; Dense.Timer;
    Dense.Now := 1025.5; Dense.Timer;
    Dense.Now := 1037.5; Dense.Timer;
    Sparse.Now := 1037.5; Sparse.Timer;
    AssertEquals('Precise fade sampling must ignore frame count',
      Sparse.PreciseAlpha, Dense.PreciseAlpha, 0.000001);
  finally Dense.Free; Sparse.Free; end;
end;

procedure TAnimationTimingTests.PeekMoveIgnoresFramePartition;
var Sparse, Dense: TPeekTimingProbe;
begin
  Sparse := TPeekTimingProbe.Create;
  Dense := TPeekTimingProbe.Create;
  try
    Sparse.BeginMove;
    Dense.BeginMove;
    Dense.Now := 1008.25; Dense.Tick;
    Dense.Now := 1016.75; Dense.Tick;
    Dense.Now := 1025.5; Dense.Tick;
    Dense.Now := 1037.5; Dense.Tick;
    Sparse.Now := 1037.5; Sparse.Tick;
    AssertEquals('Precise movement must ignore frame count',
      Sparse.PreciseLeft, Dense.PreciseLeft, 0.000001);
  finally Dense.Free; Sparse.Free; end;
end;

procedure TAnimationTimingTests.HintReversalPreservesCurrentAlpha;
var Hint: THintTimingProbe; Before: Double;
begin
  Hint := THintTimingProbe.Create;
  try
    Hint.BeginFade;
    Hint.Now := 1037.5;
    Hint.Timer;
    Before := Hint.PreciseAlpha;
    Hint.DeactivateHint(0);
    AssertEquals('Reversal must preserve alpha at its timestamp', Before, Hint.PreciseAlpha, 0.000001);
    Hint.Now := 1045.75;
    Hint.Timer;
    AssertTrue('The next frame must follow the new fade target', Hint.PreciseAlpha < Before);
  finally Hint.Free; end;
end;

procedure TAnimationTimingTests.HintPositionFramesReusePixels;
var Hint: THintTimingProbe;
begin
  Hint := THintTimingProbe.Create;
  try
    Hint.BeginFade;
    Hint.Now := 1016.75;
    Hint.Timer;
    AssertEquals('An alpha frame needs no new pixels', 0, Hint.Paints);
    AssertEquals('An alpha frame updates the native surface', 1, Hint.Positions);
  finally Hint.Free; end;
end;

procedure TAnimationTimingTests.PeekPositionFramesReusePixels;
var Peek: TPeekTimingProbe;
begin
  Peek := TPeekTimingProbe.Create;
  try
    Peek.BeginMove;
    Peek.Now := 1016.75;
    Peek.Tick;
    AssertEquals('A position frame needs no new pixels', 0, Peek.Paints);
    AssertEquals('A position frame updates the native surface', 1, Peek.Positions);
  finally Peek.Free; end;
end;

procedure TAnimationTimingTests.HintSizeFramesRepaintPixels;
var Hint: THintTimingProbe;
begin
  Hint := THintTimingProbe.Create;
  try
    Hint.BeginResize;
    Hint.Now := 1016.75;
    Hint.Timer;
    AssertEquals('A changed surface size requires new pixels', 1, Hint.Paints);
  finally Hint.Free; end;
end;

procedure TAnimationTimingTests.ImmediateHintCloseCancelsFrames;
var Hint: THintTimingProbe;
begin
  Hint := THintTimingProbe.Create;
  try
    Hint.BeginFade;
    Hint.DeactivateImmediate;
    Hint.Now := 2000;
    Hint.Timer;
    AssertFalse('Immediate closure cancels pending frame work', Hint.FrameActive);
    AssertEquals('Cancelled frames cannot present pixels', 0, Hint.Positions);
  finally Hint.Free; end;
end;

procedure TAnimationTimingTests.HintFadeKeepsLegacyDuration;
var Hint: THintTimingProbe;
begin
  Hint := THintTimingProbe.Create;
  try
    Hint.BeginFade;
    Hint.Now := 1250;
    Hint.Timer;
    AssertFalse('The fade must finish within its familiar duration', Hint.FrameActive);
  finally Hint.Free; end;
end;

procedure TAnimationTimingTests.PeekMoveKeepsLegacyDuration;
var Peek: TPeekTimingProbe;
begin
  Peek := TPeekTimingProbe.Create;
  try
    Peek.BeginMove;
    Peek.Now := 1250;
    Peek.Tick;
    AssertFalse('The preview must finish within its familiar duration', Peek.FrameActive);
  finally Peek.Free; end;
end;

procedure TAnimationTimingTests.SettledPeekResizeStopsFramesAgain;
var Peek: TPeekTimingProbe;
begin
  Peek := TPeekTimingProbe.Create;
  try
    Peek.Stable;
    Peek.Tick;
    Peek.ResizeSettled;
    Peek.Now := 1000;
    Peek.Tick;
    AssertFalse('A completed layout change must stop frame work', Peek.FrameActive);
  finally Peek.Free; end;
end;

procedure TAnimationTimingTests.HintRetriesMissingPixels;
var Hint: THintTimingProbe;
begin
  Hint := THintTimingProbe.Create;
  try
    Hint.BeginFade;
    Hint.ForgetPixels;
    Hint.Now := 1016.75;
    Hint.Timer;
    AssertEquals('A missing native surface needs a full paint', 1, Hint.Paints);
  finally Hint.Free; end;
end;

procedure TAnimationTimingTests.PeekRetriesMissingPixels;
var Peek: TPeekTimingProbe;
begin
  Peek := TPeekTimingProbe.Create;
  try
    Peek.BeginMove;
    Peek.ForgetPixels;
    Peek.Now := 1016.75;
    Peek.Tick;
    AssertEquals('A missing preview surface needs a full paint', 1, Peek.Paints);
  finally Peek.Free; end;
end;

procedure TAnimationTimingTests.CheckedLayeredPixelsReportNativeFailure;
var Bitmap: _SimpleBitmap;
begin
  Bitmap := Default(_SimpleBitmap);
  AssertFalse('An invalid native owner must reject full pixels', TryUpdateLWindow(0, Bitmap));
end;

procedure TAnimationTimingTests.CheckedLayeredPositionReportsNativeFailure;
begin
  AssertFalse('An invalid native owner must reject geometry', TryUpdateLWindowPosAlpha(0, 10, 20));
end;

procedure TAnimationTimingTests.HintRejectedPixelsRemainScheduled;
var Hint: THintTimingProbe;
begin
  Hint := THintTimingProbe.Create;
  try
    Hint.Stable;
    Hint.ForgetPixels;
    Hint.RejectPixels := True;
    Hint.Timer;
    AssertTrue('Rejected pixels must retain frame work', Hint.FrameActive);
    Hint.RejectPixels := False;
    Hint.Now := 10;
    Hint.Timer;
    AssertEquals('The next frame must resend full pixels', 2, Hint.Paints);
    AssertFalse('Successful stationary presentation stops frames', Hint.FrameActive);
  finally Hint.Free; end;
end;

procedure TAnimationTimingTests.PeekRejectedPixelsRemainScheduled;
var Peek: TPeekTimingProbe;
begin
  Peek := TPeekTimingProbe.Create;
  try
    Peek.Stable;
    Peek.ForgetPixels;
    Peek.RejectPixels := True;
    Peek.Tick;
    AssertTrue('Rejected preview pixels must retain frame work', Peek.FrameActive);
    Peek.RejectPixels := False;
    Peek.Now := 10;
    Peek.Tick;
    AssertEquals('The next preview frame must resend full pixels', 2, Peek.Paints);
    AssertFalse('Successful stationary preview presentation stops frames', Peek.FrameActive);
  finally Peek.Free; end;
end;

procedure TAnimationTimingTests.HintRejectedPositionResendsPixels;
var Hint: THintTimingProbe;
begin
  Hint := THintTimingProbe.Create;
  try
    Hint.BeginFade;
    Hint.RejectPosition := True;
    Hint.Now := 1250;
    Hint.Timer;
    AssertTrue('Rejected alpha must retain frame work', Hint.FrameActive);
    Hint.RejectPosition := False;
    Hint.Now := 1260;
    Hint.Timer;
    AssertEquals('Rejected alpha requires a full pixel retry', 1, Hint.Paints);
    AssertFalse(Hint.FrameActive);
  finally Hint.Free; end;
end;

procedure TAnimationTimingTests.PeekRejectedPositionResendsPixels;
var Peek: TPeekTimingProbe;
begin
  Peek := TPeekTimingProbe.Create;
  try
    Peek.BeginMove;
    Peek.RejectPosition := True;
    Peek.Now := 1250;
    Peek.Tick;
    AssertTrue('Rejected preview geometry must retain frame work', Peek.FrameActive);
    Peek.RejectPosition := False;
    Peek.Now := 1260;
    Peek.Tick;
    AssertEquals('Rejected geometry requires a full preview retry', 1, Peek.Paints);
    AssertFalse(Peek.FrameActive);
  finally Peek.Free; end;
end;

procedure TAnimationTimingTests.StationaryHintRetriesRejectedPixels;
var Hint: THintTimingProbe;
begin
  Store.container.HintEffects := False;
  Hint := THintTimingProbe.Create;
  try
    Hint.RejectPixels := True;
    Hint.ActivateStationary;
    AssertTrue('Stationary activation must retry rejected pixels', Hint.FrameActive);
    Hint.RejectPixels := False;
    Hint.Timer;
    AssertEquals('Stationary activation must resend its full pixels', 2, Hint.Paints);
    AssertFalse(Hint.FrameActive);
  finally Hint.Free; end;
end;

procedure TAnimationTimingTests.PeekRejectedGraphicsReleasesNativeBitmap;
var Peek: TPeekTimingProbe; Before: DWORD; Index: Integer;
begin
  Peek := TPeekTimingProbe.Create;
  try
    Peek.Stable;
    Peek.ForgetPixels;
    Peek.NativePaint := True;
    Peek.RejectGraphics := True;
    Before := NativeGetGuiResources(GetCurrentProcess, 0);
    for Index := 1 to 8 do
    begin
      Peek.Now := Index;
      Peek.Tick;
    end;
    AssertEquals('Failed graphics creation must release bitmap and DC handles',
      Int64(Before), Int64(NativeGetGuiResources(GetCurrentProcess, 0)));
    AssertTrue('Failed graphics creation must retain frame work', Peek.FrameActive);
  finally Peek.Free; end;
end;

procedure TAnimationTimingTests.PeekReopenPreservesClosingAlpha;
var Peek, Reference: TPeekTimingProbe; AppList: TFPList; Owner: HWND;
begin
  Peek := TPeekTimingProbe.Create;
  Reference := TPeekTimingProbe.Create;
  AppList := TFPList.Create;
  Owner := CreateWindowEx(0, 'STATIC', 'Preview', WS_POPUP, 0, 0, 10, 10,
    0, 0, HInstance, nil);
  try
    AppList.Add(Pointer(PtrUInt(Owner)));
    Peek.Now := 1000; Peek.Stable; Peek.Tick; Peek.CloseAPWindow;
    Reference.Now := 1000; Reference.Stable; Reference.Tick; Reference.CloseAPWindow;
    Peek.Now := 1037.5; Peek.Tick;
    Reference.Now := 1075; Reference.Tick;
    Peek.Now := 1075;
    Peek.OpenAPWindow(0, AppList, 0, 100, 100, 0, 100, True, True);
    AssertEquals('Reopening must sample closing alpha before retargeting',
      Reference.PreciseAlpha, Peek.PreciseAlpha, 0.000001);
    AssertEquals('Reopening must preserve closing position',
      Reference.PreciseLeft, Peek.PreciseLeft, 0.000001);
  finally
    DestroyWindow(Owner);
    AppList.Free;
    Reference.Free;
    Peek.Free;
  end;
end;

procedure TAnimationTimingTests.PeekPositionCannotValidateMissingPixels;
var Peek: TPeekTimingProbe;
begin
  Peek := TPeekTimingProbe.Create;
  try
    Peek.Stable;
    Peek.Tick;
    Peek.MoveWithoutPixels;
    AssertTrue('Successful movement cannot validate missing pixels', Peek.FrameActive);
    Peek.Tick;
    AssertEquals('The retry must send full preview pixels', 1, Peek.Paints);
    AssertFalse(Peek.FrameActive);
  finally Peek.Free; end;
end;

procedure TAnimationTimingTests.SettledPeekGraphicsFailureStartsRetryFrames;
var Peek: TPeekTimingProbe;
begin
  Peek := TPeekTimingProbe.Create;
  try
    Peek.Stable;
    Peek.Tick;
    Peek.NativePaint := True;
    Peek.RejectGraphics := True;
    Peek.PaintOnce;
    AssertTrue('A settled preview must retry failed graphics creation', Peek.FrameActive);
  finally Peek.Free; end;
end;

initialization
  RegisterTest(TAnimationTimingTests);
end.
