unit animationtimingtests;

{$mode delphi}

interface

uses Windows, Messages, Controls, SysUtils, fpcunit, testregistry,
  declu, stackitemu, scsubitemu, hintu, aeropeeku, themeu, itemmodelu,
  itemviewu, setsu;

type
  TStackTimingProbe = class(TStackItem)
  protected
    function AnimationNow: QWord; override;
  public
    Now: QWord;
    function Progress: Double;
    function AnimationState: TStackState;
  end;

  THintTimingProbe = class(THint)
  protected
    procedure Paint; override;
    function AnimationNow: QWord; override;
  public
    Now: QWord;
    procedure Stable;
    function FrameActive: boolean;
    procedure BeginFade;
    function Alpha: integer;
  end;

  TPeekTimingProbe = class(TAeroPeekWindow)
  protected
    procedure Paint; override;
    function AnimationNow: QWord; override;
    function PointerInside: boolean; override;
    procedure ApplyWindowPosition; override;
    procedure UpdateTitles; override;
  public
    Now: QWord;
    PointerReads, TitleRefreshes: integer;
    procedure Stable;
    procedure Tick;
    function FrameActive: boolean;
    procedure Enter;
    function PeekAllowed: boolean;
    function PeekRemaining: QWord;
    procedure BeginMove;
    function LeftPosition: integer;
    procedure ArmTitleRefresh;
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
  end;

implementation

function TStackTimingProbe.AnimationNow: QWord;
begin Result := Now; end;
function TStackTimingProbe.Progress: Double;
begin Result := FStateProgress; end;
function TStackTimingProbe.AnimationState: TStackState;
begin Result := FState; end;

procedure THintTimingProbe.Paint;
begin end;
function THintTimingProbe.AnimationNow: QWord;
begin Result := Now; end;
procedure THintTimingProbe.Stable;
begin
  FVisible := true;
  FAlpha := 255;
  FAlphaTarget := 255;
  FX := 10; FXTarget := FX;
  FY := 20; FYTarget := FY;
  FW := 100; FWTarget := FW;
  FH := 30; FHTarget := FH;
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

procedure TPeekTimingProbe.Paint;
begin end;
function TPeekTimingProbe.AnimationNow: QWord;
begin Result := Now; end;
function TPeekTimingProbe.PointerInside: boolean;
begin Inc(PointerReads); Result := true; end;
procedure TPeekTimingProbe.ApplyWindowPosition;
begin end;
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
begin Result := FPeekDeadline.Remaining(Now); end;
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
begin FTitleDeadline.Schedule(Now, 1000); end;

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

initialization
  RegisterTest(TAnimationTimingTests);
end.
