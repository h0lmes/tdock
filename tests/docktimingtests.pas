unit docktimingtests;

{$mode delphi}

interface

uses Windows, SysUtils, fpcunit, testregistry, docktimingu, dockpolicyu, animationclocku;

type
  TDockTimingTests = class(TTestCase)
  published
    procedure DeadlineConsumesOnceAtItsBoundary;
    procedure ReplacementRejectsAnOldWakeup;
    procedure CancellationInvalidatesGeneration;
    procedure AnimationReversalKeepsItsCurrentValue;
    procedure IrregularFramesUseElapsedTime;
    procedure ZeroDurationFinishesImmediately;
    procedure NegativeScalarDurationSnapsImmediately;
    procedure CriticalSpringMovesWithoutOvershoot;
    procedure SpringRetargetPreservesPositionAndVelocity;
    procedure UnderdampedSpringHasExpectedOvershoot;
    procedure ZeroSpringResponseSnapsAndStops;
    procedure NestedAnimationFramesShareTheirTimestamp;
    procedure AnimationClockKeepsCounterPrecision;
    procedure IrregularSpringSamplesSettleExactly;
    procedure SpringSamplesBeforeStartKeepTheirInitialState;
    procedure OverdampedSpringUsesTheSlowerResponse;
    procedure ScalarAnimationUsesFractionalTimes;
    procedure SpringStatesMatchAtSixtyAndOneTwentyHertz;
    procedure SpringVelocityUsesUnitsPerSecond;
    procedure DefaultAndResetSpringsRemainStill;
    procedure RetargetAtCurrentPositionKeepsResidualVelocity;
    procedure ManualHideSurvivesFullscreenExit;
    procedure DisablingFullscreenPolicyRestoresIntent;
    procedure EnablingAutoHideOutsideSchedulesCollapse;
    procedure GeometryRetargetsCollapsedDock;
    procedure BlockedHideResumesAfterDrag;
    procedure ReversalPreservesCurrentOffset;
    procedure RevealKeepsLegacyWallTime;
    procedure HiddenDockRejectsPendingDeadlines;
    procedure ActivationExpandsCollapsedDock;
    procedure ActivationBypassesPendingShow;
  end;

implementation

procedure TDockTimingTests.RevealKeepsLegacyWallTime;
var State: TDockRevealState;
begin
  State := CollapseReveal(Default(TDockRevealState), 80, 0);
  State := AdvanceReveal(State, 50);
  AssertEquals('Four pixels per legacy 15.625 ms callback', 13, State.Offset);
end;

procedure TDockTimingTests.DeadlineConsumesOnceAtItsBoundary;
var Deadline: TDeadline;
begin
  Deadline := Default(TDeadline);
  Deadline.Schedule(100, 50);
  AssertEquals(QWord(50), Deadline.Remaining(100));
  AssertFalse(Deadline.Consume(149));
  AssertTrue(Deadline.Consume(150));
  AssertFalse(Deadline.Consume(151));
end;

procedure TDockTimingTests.ReplacementRejectsAnOldWakeup;
var Deadline: TDeadline;
begin
  Deadline := Default(TDeadline);
  Deadline.Schedule(100, 50);
  Deadline.Schedule(120, 100);
  AssertFalse(Deadline.Consume(150));
  AssertTrue(Deadline.Consume(220));
end;

procedure TDockTimingTests.CancellationInvalidatesGeneration;
var Deadline: TDeadline; Generation: QWord;
begin
  Deadline := Default(TDeadline);
  Deadline.Schedule(0, 10);
  Generation := Deadline.Generation;
  Deadline.Cancel;
  AssertTrue(Deadline.Generation <> Generation);
  AssertFalse(Deadline.IsDue(100));
end;

procedure TDockTimingTests.AnimationReversalKeepsItsCurrentValue;
var Animation: TScalarAnimation;
begin
  Animation := Default(TScalarAnimation);
  Animation.Retarget(0, 32, 200);
  AssertEquals(8.0, Animation.ValueAt(50), 0.001);
  Animation.Retarget(50, 0, 50);
  AssertEquals(8.0, Animation.ValueAt(50), 0.001);
  AssertEquals(4.0, Animation.ValueAt(75), 0.001);
  AssertEquals(0.0, Animation.ValueAt(100), 0.001);
end;

procedure TDockTimingTests.IrregularFramesUseElapsedTime;
var Animation: TScalarAnimation;
begin
  Animation := Default(TScalarAnimation);
  Animation.Retarget(100, 100, 200);
  AssertEquals(5.0, Animation.ValueAt(110), 0.001);
  AssertEquals(75.0, Animation.ValueAt(250), 0.001);
  AssertTrue(Animation.ActiveAt(299));
  AssertFalse(Animation.ActiveAt(300));
  AssertEquals(100.0, Animation.ValueAt(1000), 0.001);
end;

procedure TDockTimingTests.ZeroDurationFinishesImmediately;
var Animation: TScalarAnimation;
begin
  Animation := Default(TScalarAnimation);
  Animation.Retarget(100, 12, 0);
  AssertEquals(12.0, Animation.ValueAt(100), 0.001);
  AssertFalse(Animation.ActiveAt(100));
end;

procedure TDockTimingTests.NegativeScalarDurationSnapsImmediately;
var Animation: TScalarAnimation; Duration: Int64;
begin
  Animation := Default(TScalarAnimation);
  Duration := -20;
  try
    Animation.Retarget(100, 12, Duration);
  except
    on E: Exception do Fail('Negative duration must not raise ' + E.ClassName);
  end;
  AssertEquals('Negative duration snaps immediately', 12.0, Animation.ValueAt(100), 0.0);
  AssertFalse(Animation.ActiveAt(100));
end;

procedure TDockTimingTests.CriticalSpringMovesWithoutOvershoot;
var Spring: TSpringAnimation; I: Integer; Previous, Current: Double;
begin
  Spring := Default(TSpringAnimation);
  Spring.Reset(0, 0);
  Spring.Retarget(0, 100, 250);
  AssertEquals('Response reaches approximately 95 percent',
    95.0, Spring.ValueAt(250), 0.001);
  Previous := 0;
  for I := 0 to 100 do
  begin
    Current := Spring.ValueAt(I * 10);
    AssertTrue('Critical motion does not reverse', Current >= Previous);
    AssertTrue('Critical motion does not overshoot', Current <= 100);
    Previous := Current;
  end;
end;

procedure TDockTimingTests.SpringRetargetPreservesPositionAndVelocity;
var Spring: TSpringAnimation; Position, Velocity: Double;
begin
  Spring := Default(TSpringAnimation);
  Spring.Reset(10, 0);
  Spring.Retarget(10, 100, 250);
  Position := Spring.ValueAt(93.25);
  Velocity := Spring.VelocityAt(93.25);
  AssertTrue('Spring has nonzero velocity before reversal', Velocity > 0);
  Spring.Retarget(93.25, -20, 200);
  AssertEquals('Retarget preserves position', Position, Spring.ValueAt(93.25), 1E-10);
  AssertEquals('Retarget preserves velocity', Velocity, Spring.VelocityAt(93.25), 1E-10);
end;

procedure TDockTimingTests.UnderdampedSpringHasExpectedOvershoot;
var Spring: TSpringAnimation; HalfCycle: Double;
begin
  Spring := Default(TSpringAnimation);
  Spring.Reset(0, 0);
  Spring.Retarget(0, 1, 250, 0.5);
  HalfCycle := Pi * 250 / (4.743864518390578 * Sqrt(0.75));
  AssertEquals('Half cycle reaches the analytical overshoot',
    1 + Exp(-Pi / Sqrt(3)), Spring.ValueAt(HalfCycle), 1E-10);
  AssertEquals('Velocity reaches zero at the turning point',
    0.0, Spring.VelocityAt(HalfCycle), 1E-10);
end;

procedure TDockTimingTests.ZeroSpringResponseSnapsAndStops;
var Spring: TSpringAnimation;
begin
  Spring := Default(TSpringAnimation);
  Spring.Reset(0, 0);
  Spring.Retarget(0, 100, 250);
  Spring.Retarget(75.5, 12, 0);
  AssertFalse('Zero response finishes immediately', Spring.ActiveAt(75.5));
  AssertEquals('Zero response snaps position', 12.0, Spring.ValueAt(75.5), 0.0);
  AssertEquals('Zero response removes velocity', 0.0, Spring.VelocityAt(75.5), 0.0);
  Spring.Retarget(100, -5, -20);
  AssertEquals('Negative response also snaps', -5.0, Spring.ValueAt(100), 0.0);
  AssertFalse(Spring.ActiveAt(100));
end;

procedure TDockTimingTests.NestedAnimationFramesShareTheirTimestamp;
var Timestamp: Double;
begin
  BeginAnimationFrame;
  try
    Timestamp := AnimationTimeMs;
    AssertTrue('Clock returns positive milliseconds: ' + FloatToStr(Timestamp), Timestamp > 0);
    Sleep(2);
    AssertEquals('One frame shares one timestamp', Timestamp, AnimationTimeMs, 0.0);
    BeginAnimationFrame;
    try
      Sleep(2);
      AssertEquals('Nested frame retains the outer timestamp',
        Timestamp, AnimationTimeMs, 0.0);
    finally
      EndAnimationFrame;
    end;
    AssertEquals('Ending the nested frame preserves the outer timestamp',
      Timestamp, AnimationTimeMs, 0.0);
  finally
    EndAnimationFrame;
  end;
  AssertTrue('Ending the outer frame restores live time: ' + FloatToStr(Timestamp) +
    ' -> ' + FloatToStr(AnimationTimeMs), AnimationTimeMs > Timestamp);
end;

procedure TDockTimingTests.AnimationClockKeepsCounterPrecision;
var Frequency, BeforeCounter, AfterCounter: Int64;
  Timestamp, Earliest, Latest, FrequencyValue: Double;
begin
  AssertTrue(Windows.QueryPerformanceFrequency(Frequency));
  AssertTrue(Windows.QueryPerformanceCounter(BeforeCounter));
  Timestamp := AnimationTimeMs;
  AssertTrue(Windows.QueryPerformanceCounter(AfterCounter));
  FrequencyValue := Frequency;
  Earliest := BeforeCounter;
  Earliest := Earliest * 1000 / FrequencyValue;
  Latest := AfterCounter;
  Latest := Latest * 1000 / FrequencyValue;
  AssertTrue('Clock does not lose precision through Single intermediates',
    (Timestamp >= Earliest - 0.00001) and (Timestamp <= Latest + 0.00001));
end;

procedure TDockTimingTests.IrregularSpringSamplesSettleExactly;
var Spring: TSpringAnimation;
begin
  Spring := Default(TSpringAnimation);
  Spring.Reset(1000, 0);
  Spring.Retarget(1000, 64, 240, 0.7);
  AssertTrue(Spring.ValueAt(1010) > 0);
  AssertTrue(Spring.ValueAt(1077) > Spring.ValueAt(1010));
  AssertTrue(Spring.ActiveAt(1111));
  AssertFalse('An irregular time jump finishes the spring', Spring.ActiveAt(5000));
  AssertEquals('Settled position equals the exact target', 64.0, Spring.ValueAt(5000), 0.0);
  AssertEquals('Settled velocity equals zero', 0.0, Spring.VelocityAt(5000), 0.0);
  AssertEquals('Large forward jumps remain settled', 64.0, Spring.ValueAt(1E12), 0.0);
end;

procedure TDockTimingTests.SpringSamplesBeforeStartKeepTheirInitialState;
var Spring: TSpringAnimation; Position, Velocity: Double;
begin
  Spring := Default(TSpringAnimation);
  Spring.Reset(100.5, 7);
  Spring.Retarget(100.5, 100, 250);
  AssertEquals('Backward samples retain the starting position',
    7.0, Spring.ValueAt(-100), 0.0);
  AssertEquals('Backward samples retain the starting velocity',
    0.0, Spring.VelocityAt(-100), 0.0);
  Spring.Retarget(150, 25, 200);
  Position := Spring.StartValue;
  Velocity := Spring.StartVelocity;
  AssertTrue(Velocity > 0);
  AssertEquals(Position, Spring.ValueAt(120), 0.0);
  AssertEquals(Velocity, Spring.VelocityAt(120), 0.0);
  Spring.Retarget(120, -5, 200);
  AssertEquals(Position, Spring.ValueAt(120), 0.0);
  AssertEquals(Velocity, Spring.VelocityAt(120), 0.0);
end;

procedure TDockTimingTests.OverdampedSpringUsesTheSlowerResponse;
var Spring: TSpringAnimation;
begin
  Spring := Default(TSpringAnimation);
  Spring.Reset(0, 0);
  Spring.Retarget(0, 1, 4743.864518390578, 2);
  AssertEquals('Overdamping follows the slower analytical response',
    0.177736576098190, Spring.ValueAt(1000), 1E-12);
end;

procedure TDockTimingTests.ScalarAnimationUsesFractionalTimes;
var Animation: TScalarAnimation;
begin
  Animation := Default(TScalarAnimation);
  Animation.Retarget(100.25, 100, 16.5);
  AssertEquals('Backward time preserves the initial position',
    0.0, Animation.ValueAt(-10), 0.0);
  AssertEquals('Fractional samples preserve subframe progress',
    50.0, Animation.ValueAt(108.5), 1E-10);
  Animation.Retarget(108.5, 0, 8.25);
  AssertEquals(50.0, Animation.ValueAt(108.5), 1E-10);
  AssertEquals(25.0, Animation.ValueAt(112.625), 1E-10);
  AssertFalse(Animation.ActiveAt(116.75));
  AssertEquals(0.0, Animation.ValueAt(116.75), 0.0);
end;

procedure TDockTimingTests.SpringStatesMatchAtSixtyAndOneTwentyHertz;
var Sixty, OneTwenty: TSpringAnimation; Frame: Integer;
  Time, HalfTime, ExtraSample: Double;
begin
  Sixty := Default(TSpringAnimation);
  Sixty.Reset(0, 0);
  Sixty.Retarget(0, 64, 240, 0.7);
  OneTwenty := Sixty;
  for Frame := 1 to 60 do
  begin
    HalfTime := Frame * 2 - 1;
    HalfTime := HalfTime * 1000 / 120;
    ExtraSample := OneTwenty.ValueAt(HalfTime);
    AssertTrue('Intermediate samples remain bounded', Abs(ExtraSample) < 200);
    Time := Frame;
    Time := Time * 1000 / 60;
    AssertEquals('Matched times have equal positions',
      Sixty.ValueAt(Time), OneTwenty.ValueAt(Time), 1E-10);
    AssertEquals('Matched times have equal velocities',
      Sixty.VelocityAt(Time), OneTwenty.VelocityAt(Time), 1E-10);
    if Frame = 6 then
    begin
      Sixty.Retarget(Time, 0, 180);
      OneTwenty.Retarget(Time, 0, 180);
    end;
    if Frame = 12 then
    begin
      Sixty.Retarget(Time, 80, 240, 0.7);
      OneTwenty.Retarget(Time, 80, 240, 0.7);
    end;
  end;
end;

procedure TDockTimingTests.SpringVelocityUsesUnitsPerSecond;
var Spring: TSpringAnimation; Index: Integer;
  Damping, Time, NumericalVelocity: Double;
begin
  for Index := 0 to 2 do
  begin
    case Index of
      0: Damping := 0.5;
      1: Damping := 1;
      else Damping := 2;
    end;
    Spring := Default(TSpringAnimation);
    Spring.Reset(10, 5);
    Spring.Retarget(10, 50, 250, Damping);
    Time := 123.75;
    NumericalVelocity := (Spring.ValueAt(Time + 0.001) -
      Spring.ValueAt(Time - 0.001)) / 0.000002;
    AssertEquals('Velocity equals position change per second',
      NumericalVelocity, Spring.VelocityAt(Time), 0.00001);
  end;
end;

procedure TDockTimingTests.DefaultAndResetSpringsRemainStill;
var Spring: TSpringAnimation;
begin
  Spring := Default(TSpringAnimation);
  AssertEquals(0.0, Spring.ValueAt(-100), 0.0);
  AssertEquals(0.0, Spring.VelocityAt(100), 0.0);
  AssertFalse(Spring.ActiveAt(100));
  Spring.Retarget(100, 40, 250);
  AssertTrue(Spring.ActiveAt(150));
  Spring.Reset(150, 8);
  AssertEquals(8.0, Spring.ValueAt(-100), 0.0);
  AssertEquals(8.0, Spring.ValueAt(1000), 0.0);
  AssertEquals(0.0, Spring.VelocityAt(150), 0.0);
  AssertFalse(Spring.ActiveAt(150));
end;

procedure TDockTimingTests.RetargetAtCurrentPositionKeepsResidualVelocity;
var Spring: TSpringAnimation; Position, Velocity: Double;
begin
  Spring := Default(TSpringAnimation);
  Spring.Reset(0, 0);
  Spring.Retarget(0, 100, 250);
  Position := Spring.ValueAt(75);
  Velocity := Spring.VelocityAt(75);
  Spring.Retarget(75, Position, 200);
  AssertEquals(Velocity, Spring.VelocityAt(75), 0.0);
  AssertTrue('Residual velocity requires more frames', Spring.ActiveAt(75));
  AssertTrue('Residual velocity carries motion through the new target',
    Spring.ValueAt(80) > Position);
end;

procedure TDockTimingTests.ManualHideSurvivesFullscreenExit;
var State: TDockVisibilityState;
begin
  State := ReduceVisibility(Default(TDockVisibilityState), veShow);
  State := ReduceVisibility(State, vePolicyEnabled);
  AssertTrue(EffectiveVisibility(State));
  State := ReduceVisibility(State, veFullscreenEntered);
  AssertFalse(EffectiveVisibility(State));
  State := ReduceVisibility(State, veHide);
  State := ReduceVisibility(State, veFullscreenLeft);
  AssertFalse(EffectiveVisibility(State));
end;

procedure TDockTimingTests.DisablingFullscreenPolicyRestoresIntent;
var State: TDockVisibilityState;
begin
  State := ReduceVisibility(Default(TDockVisibilityState), veShow);
  State := ReduceVisibility(State, vePolicyEnabled);
  State := ReduceVisibility(State, veFullscreenEntered);
  AssertFalse(EffectiveVisibility(State));
  State := ReduceVisibility(State, vePolicyDisabled);
  AssertTrue(EffectiveVisibility(State));
end;

function OutsideInput: TDockRevealInput;
begin
  Result := Default(TDockRevealInput);
  Result.Shown := True;
  Result.AutoHide := True;
  Result.Thickness := 100;
  Result.VisiblePixels := 15;
  Result.HideDelay := 800;
  Result.ShowDelay := 400;
end;

procedure TDockTimingTests.EnablingAutoHideOutsideSchedulesCollapse;
var State: TDockRevealState; Input: TDockRevealInput;
begin
  State := Default(TDockRevealState);
  Input := OutsideInput;
  State := ReconcileReveal(State, Input, 0);
  AssertEquals(Ord(rpWaitingToHide), Ord(State.Phase));
  AssertEquals(QWord(800), State.Deadline.DueAt);
  State := ReconcileReveal(State, Input, 500);
  AssertEquals(QWord(800), State.Deadline.DueAt);
  State := AdvanceReveal(State, 799);
  AssertEquals(0, State.Offset);
  State := AdvanceReveal(State, 1200);
  AssertEquals(85, State.Offset);
end;

procedure TDockTimingTests.GeometryRetargetsCollapsedDock;
var State: TDockRevealState; Input: TDockRevealInput;
begin
  Input := OutsideInput;
  State := ReconcileReveal(Default(TDockRevealState), Input, 0);
  State := AdvanceReveal(State, 1200);
  Input.Thickness := 40;
  State := ReconcileReveal(State, Input, 1200);
  AssertEquals(25, State.Target);
  State := AdvanceReveal(State, 1500);
  AssertEquals(25, State.Offset);
end;

procedure TDockTimingTests.BlockedHideResumesAfterDrag;
var State: TDockRevealState; Input: TDockRevealInput;
begin
  Input := OutsideInput;
  Input.Dragging := True;
  State := ReconcileReveal(Default(TDockRevealState), Input, 0);
  AssertEquals(Ord(rpBlocked), Ord(State.Phase));
  Input.Dragging := False;
  State := ReconcileReveal(State, Input, 1000);
  AssertEquals(Ord(rpWaitingToHide), Ord(State.Phase));
  State := AdvanceReveal(State, 2200);
  AssertEquals(85, State.Offset);
end;

procedure TDockTimingTests.ReversalPreservesCurrentOffset;
var State: TDockRevealState; Input: TDockRevealInput;
begin
  Input := OutsideInput;
  Input.HideDelay := 0;
  Input.ShowDelay := 0;
  State := ReconcileReveal(Default(TDockRevealState), Input, 0);
  State := AdvanceReveal(State, 50);
  AssertTrue(State.Offset > 0);
  Input.PointerOver := True;
  State := ReconcileReveal(State, Input, 50);
  AssertEquals(13, State.Offset);
  State := AdvanceReveal(State, 60);
  AssertTrue(State.Offset < 13);
  State := AdvanceReveal(State, 500);
  AssertEquals(0, State.Offset);
end;

procedure TDockTimingTests.HiddenDockRejectsPendingDeadlines;
var State: TDockRevealState; Input: TDockRevealInput;
begin
  Input := OutsideInput;
  State := ReconcileReveal(Default(TDockRevealState), Input, 0);
  Input.Shown := False;
  State := ReconcileReveal(State, Input, 10);
  AssertFalse(State.Deadline.Active);
  State := AdvanceReveal(State, 5000);
  AssertEquals(0, State.Offset);
end;

procedure TDockTimingTests.ActivationExpandsCollapsedDock;
var State: TDockRevealState; Input: TDockRevealInput;
begin
  Input := OutsideInput;
  State := ReconcileReveal(Default(TDockRevealState), Input, 0);
  State := AdvanceReveal(State, 1200);
  AssertEquals(85, State.Offset);
  State.ManualReveal := True;
  State := ReconcileReveal(State, Input, 1200);
  State := AdvanceReveal(State, 1550);
  AssertEquals(0, State.Offset);
  Input.PointerOver := True;
  State := ReconcileReveal(State, Input, 1600);
  AssertFalse(State.ManualReveal);
  Input.PointerOver := False;
  State := ReconcileReveal(State, Input, 1700);
  AssertEquals(Ord(rpWaitingToHide), Ord(State.Phase));
end;

procedure TDockTimingTests.ActivationBypassesPendingShow;
var State: TDockRevealState; Input: TDockRevealInput;
begin
  Input := OutsideInput;
  State := ReconcileReveal(Default(TDockRevealState), Input, 0);
  State := AdvanceReveal(State, 1200);
  Input.PointerOver := True;
  State := ReconcileReveal(State, Input, 1300);
  AssertEquals(Ord(rpWaitingToShow), Ord(State.Phase));
  State.ManualReveal := True;
  State := ReconcileReveal(State, Input, 1400);
  State := AdvanceReveal(State, 1500);
  AssertTrue(State.Offset < 85);
end;

initialization
  RegisterTest(TDockTimingTests);
end.
