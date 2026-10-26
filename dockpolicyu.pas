unit dockpolicyu;

{$mode delphi}

interface

uses docktimingu;

type
  TVisibilityEvent = (veShow, veHide, veToggle, veFullscreenEntered,
    veFullscreenLeft, vePolicyEnabled, vePolicyDisabled, veClosing);
  TDockVisibilityState = record
    UserShown, FullscreenActive, FullscreenEnabled, Closing: Boolean;
  end;
  TRevealPhase = (rpExpanded, rpWaitingToHide, rpHiding, rpCollapsed,
    rpWaitingToShow, rpShowing, rpSuspended, rpBlocked);
  TDockRevealInput = record
    Shown, AutoHide, PointerOver, Dragging, Locked, SettingsOpen: Boolean;
    Thickness, VisiblePixels: Integer;
    ShowDelay, HideDelay: QWord;
  end;
  TDockRevealState = record
    Phase: TRevealPhase;
    ManualReveal: Boolean;
    Offset, Target, WantedTarget: Integer;
    Input: TDockRevealInput;
    Deadline: TDeadline;
    Motion: TScalarAnimation;
  end;

function ReduceVisibility(const State: TDockVisibilityState;
  Event: TVisibilityEvent): TDockVisibilityState;
function EffectiveVisibility(const State: TDockVisibilityState): Boolean;
function ReconcileReveal(const State: TDockRevealState;
  const Input: TDockRevealInput; Now: QWord): TDockRevealState;
function AdvanceReveal(const State: TDockRevealState; Now: QWord): TDockRevealState;
function RevealNeedsFrames(const State: TDockRevealState): Boolean;
function CollapseReveal(const State: TDockRevealState; Target: Integer;
  Now: QWord): TDockRevealState;

implementation

function ReduceVisibility(const State: TDockVisibilityState;
  Event: TVisibilityEvent): TDockVisibilityState;
begin
  Result := State;
  case Event of
    veShow: if not State.Closing then Result.UserShown := True;
    veHide: Result.UserShown := False;
    veToggle: if not State.Closing then Result.UserShown := not State.UserShown;
    veFullscreenEntered: Result.FullscreenActive := True;
    veFullscreenLeft: Result.FullscreenActive := False;
    vePolicyEnabled: Result.FullscreenEnabled := True;
    vePolicyDisabled: Result.FullscreenEnabled := False;
    veClosing: Result.Closing := True;
  end;
end;
function EffectiveVisibility(const State: TDockVisibilityState): Boolean;
begin
  Result := State.UserShown and not State.Closing and
    not (State.FullscreenEnabled and State.FullscreenActive);
end;

procedure StartMotion(var State: TDockRevealState; Target: Integer; Now: QWord);
var Duration: QWord;
begin
  State.Target := Target;
  State.Motion.StartValue := State.Offset;
  State.Motion.TargetValue := Target;
  State.Motion.StartedAt := Now;
  Duration := (QWord(Abs(Target - State.Offset)) * 10 + 3) div 4;
  State.Motion.DurationMs := Duration;
  if Target = State.Offset then
  begin
    if Target = 0 then State.Phase := rpExpanded else State.Phase := rpCollapsed;
  end
  else if Target = 0 then State.Phase := rpShowing else State.Phase := rpHiding;
end;

function CollapseReveal(const State: TDockRevealState; Target: Integer;
  Now: QWord): TDockRevealState;
begin
  Result := State;
  Result.ManualReveal := False;
  Result.Deadline.Cancel;
  Result.WantedTarget := Target;
  StartMotion(Result, Target, Now);
end;

function ReconcileReveal(const State: TDockRevealState;
  const Input: TDockRevealInput; Now: QWord): TDockRevealState;
var Wanted: Integer; Delay: QWord;
begin
  Result := AdvanceReveal(State, Now);
  Result.Input := Input;
  if Input.PointerOver <> State.Input.PointerOver then Result.ManualReveal := False;
  if not Input.Shown then
  begin
    Result.Deadline.Cancel;
    Result.Phase := rpSuspended;
    Exit;
  end;
  if not Input.AutoHide then
  begin
    Result.Deadline.Cancel;
    Result.WantedTarget := 0;
    if (Result.Target <> 0) or not (Result.Phase in [rpShowing, rpExpanded]) then
      StartMotion(Result, 0, Now);
    Exit;
  end;
  if not Input.PointerOver and not Result.ManualReveal and
    (Input.Dragging or Input.Locked or Input.SettingsOpen) then
  begin
    Result.Deadline.Cancel;
    Result.Target := Result.Offset;
    Result.Phase := rpBlocked;
    Exit;
  end;
  Wanted := Input.Thickness - Input.VisiblePixels;
  if (Wanted < 0) or Input.PointerOver or Result.ManualReveal then Wanted := 0;
  Result.WantedTarget := Wanted;
  if Wanted = 0 then
  begin
    if Result.ManualReveal then
    begin
      Result.Deadline.Cancel;
      if (Result.Target <> 0) or not (Result.Phase in [rpShowing, rpExpanded]) then
        StartMotion(Result, 0, Now);
      Exit;
    end;
    if Result.Phase in [rpWaitingToShow, rpShowing, rpExpanded] then Exit;
    if Result.Offset = 0 then
    begin
      Result.Deadline.Cancel;
      StartMotion(Result, 0, Now);
      Exit;
    end;
    Delay := Input.ShowDelay;
    Result.Phase := rpWaitingToShow;
  end
  else
  begin
    if Result.Phase = rpWaitingToHide then Exit;
    if Result.Phase in [rpHiding, rpCollapsed] then
    begin
      if Result.Target <> Wanted then StartMotion(Result, Wanted, Now);
      Exit;
    end;
    Delay := Input.HideDelay;
    Result.Phase := rpWaitingToHide;
  end;
  Result.Deadline.Schedule(Now, Delay);
end;
function AdvanceReveal(const State: TDockRevealState; Now: QWord): TDockRevealState;
var StartAt: QWord;
begin
  Result := State;
  if Result.Phase in [rpSuspended, rpBlocked] then Exit;
  if Result.Deadline.IsDue(Now) then
  begin
    StartAt := Result.Deadline.DueAt;
    Result.Deadline.Cancel;
    StartMotion(Result, Result.WantedTarget, StartAt);
  end;
  if Result.Phase in [rpShowing, rpHiding] then
  begin
    Result.Offset := Round(Result.Motion.ValueAt(Now));
    if not Result.Motion.ActiveAt(Now) then
    begin
      Result.Offset := Result.Target;
      if Result.Target = 0 then Result.Phase := rpExpanded else Result.Phase := rpCollapsed;
    end;
  end;
end;
function RevealNeedsFrames(const State: TDockRevealState): Boolean;
begin Result := State.Phase in [rpShowing, rpHiding]; end;

end.
