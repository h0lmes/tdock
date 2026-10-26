unit docktimingtests;

{$mode delphi}

interface

uses fpcunit, testregistry, docktimingu, dockpolicyu;

type
  TDockTimingTests = class(TTestCase)
  published
    procedure DeadlineConsumesOnceAtItsBoundary;
    procedure ReplacementRejectsAnOldWakeup;
    procedure CancellationInvalidatesGeneration;
    procedure AnimationReversalKeepsItsCurrentValue;
    procedure IrregularFramesUseElapsedTime;
    procedure ZeroDurationFinishesImmediately;
    procedure ManualHideSurvivesFullscreenExit;
    procedure DisablingFullscreenPolicyRestoresIntent;
    procedure EnablingAutoHideOutsideSchedulesCollapse;
    procedure GeometryRetargetsCollapsedDock;
    procedure BlockedHideResumesAfterDrag;
    procedure ReversalPreservesCurrentOffset;
    procedure HiddenDockRejectsPendingDeadlines;
    procedure ActivationExpandsCollapsedDock;
    procedure ActivationBypassesPendingShow;
  end;

implementation

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
  State := AdvanceReveal(State, 1100);
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
  AssertEquals(20, State.Offset);
  State := AdvanceReveal(State, 60);
  AssertTrue(State.Offset < 20);
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
  State := AdvanceReveal(State, 1500);
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
