unit dockstateu;

{$mode delphi}

interface

uses itemmodelu, docksettingsu, dockpolicyu;

type
  TDockState = class
  private
    FReveal: TDockRevealState;
    FVisibility: TDockVisibilityState;
    FAutoHide: Boolean;
    FSettings: PDockSettings;
    FMouseLocks: array of TItemId;
    function GetMouseEffectLocked: Boolean;
    function GetAutoHide: Boolean;
    function GetSettings: TDockSettings;
    procedure SetAutoHide(Value: Boolean);
    function GetOffset: Integer;
    function GetTarget: Integer;
    function GetVisible: Boolean;
    function GetUserShown: Boolean;
    function GetHiddenByFullScreen: Boolean;
    procedure SetVisible(Value: Boolean);
    procedure SetHiddenByFullScreen(Value: Boolean);
  public
    procedure SetMouseEffectLock(Id: TItemId; Locked: Boolean);
    procedure ReleaseItemLocks(Id: TItemId);
    procedure BindSettings(Settings: PDockSettings);
    procedure RequestHide(Thickness, VisiblePixels: Integer; Dragging: Boolean; Now: QWord = 0);
    procedure RequestShow;
    function Step(StepSize: Integer): Boolean;
    procedure ObserveFullscreen(Active, Enabled: Boolean);
    procedure Reconcile(const Input: TDockRevealInput; Now: QWord);
    function Advance(Now: QWord): Boolean;
    function RevealSnapshot: TDockRevealState;
    function NeedsFrames: Boolean;
    property MouseEffectLocked: Boolean read GetMouseEffectLocked;
    property Settings: TDockSettings read GetSettings;
    property Offset: Integer read GetOffset;
    property Target: Integer read GetTarget;
    property AutoHide: Boolean read GetAutoHide write SetAutoHide;
    property Visible: Boolean read GetVisible write SetVisible;
    property UserShown: Boolean read GetUserShown;
    property HiddenByFullScreen: Boolean read GetHiddenByFullScreen write SetHiddenByFullScreen;
  end;

implementation

function TDockState.GetMouseEffectLocked: Boolean;
begin Result := Length(FMouseLocks) > 0; end;

procedure TDockState.SetMouseEffectLock(Id: TItemId; Locked: Boolean);
var I, J: Integer;
begin
  if Locked then
  begin
    SetLength(FMouseLocks, Length(FMouseLocks) + 1);
    FMouseLocks[High(FMouseLocks)] := Id;
  end
  else
    for I := 0 to High(FMouseLocks) do
      if FMouseLocks[I] = Id then
      begin
        for J := I to High(FMouseLocks) - 1 do FMouseLocks[J] := FMouseLocks[J + 1];
        SetLength(FMouseLocks, Length(FMouseLocks) - 1);
        Exit;
      end;
end;

procedure TDockState.ReleaseItemLocks(Id: TItemId);
var index: integer;
begin
  for index := High(FMouseLocks) downto 0 do
    if FMouseLocks[index] = Id then SetMouseEffectLock(Id, false);
end;

procedure TDockState.BindSettings(Settings: PDockSettings);
begin
  FSettings := Settings;
end;

function TDockState.GetAutoHide: Boolean;
begin
  if FSettings <> nil then Result := FSettings^.AutoHide else Result := FAutoHide;
end;

function TDockState.GetSettings: TDockSettings;
begin
  if FSettings <> nil then Result := FSettings^ else Result := Default(TDockSettings);
end;

procedure TDockState.SetAutoHide(Value: Boolean);
begin
  FAutoHide := Value;
  FReveal.ManualReveal := False;
  if FSettings <> nil then FSettings^.AutoHide := Value;
  if not Value then FReveal.Target := 0;
end;

procedure TDockState.RequestHide(Thickness, VisiblePixels: Integer; Dragging: Boolean; Now: QWord);
var Target: Integer;
begin
  if Dragging or not GetAutoHide then Exit;
  Target := Thickness - VisiblePixels;
  if Target < 0 then Target := 0;
  FReveal := CollapseReveal(FReveal, Target, Now);
end;

procedure TDockState.RequestShow;
begin
  FReveal.ManualReveal := True;
  FReveal.Target := 0;
end;

function TDockState.Step(StepSize: Integer): Boolean;
begin
  Result := False;
  if (StepSize <= 0) or (FReveal.Offset = FReveal.Target) then Exit;
  if Abs(FReveal.Target - FReveal.Offset) <= StepSize then FReveal.Offset := FReveal.Target
  else if FReveal.Target > FReveal.Offset then Inc(FReveal.Offset, StepSize)
  else Dec(FReveal.Offset, StepSize);
  Result := True;
end;

function TDockState.GetOffset: Integer;
begin Result := FReveal.Offset; end;
function TDockState.GetTarget: Integer;
begin Result := FReveal.Target; end;
function TDockState.GetVisible: Boolean;
begin Result := EffectiveVisibility(FVisibility); end;
function TDockState.GetUserShown: Boolean;
begin Result := FVisibility.UserShown; end;
function TDockState.GetHiddenByFullScreen: Boolean;
begin Result := FVisibility.FullscreenEnabled and FVisibility.FullscreenActive; end;
procedure TDockState.SetVisible(Value: Boolean);
begin
  if Value then FVisibility := ReduceVisibility(FVisibility, veShow)
  else FVisibility := ReduceVisibility(FVisibility, veHide);
end;
procedure TDockState.SetHiddenByFullScreen(Value: Boolean);
begin ObserveFullscreen(Value, True); end;
procedure TDockState.ObserveFullscreen(Active, Enabled: Boolean);
begin
  if Active then FVisibility := ReduceVisibility(FVisibility, veFullscreenEntered)
  else FVisibility := ReduceVisibility(FVisibility, veFullscreenLeft);
  if Enabled then FVisibility := ReduceVisibility(FVisibility, vePolicyEnabled)
  else FVisibility := ReduceVisibility(FVisibility, vePolicyDisabled);
end;
procedure TDockState.Reconcile(const Input: TDockRevealInput; Now: QWord);
begin FReveal := ReconcileReveal(FReveal, Input, Now); end;
function TDockState.Advance(Now: QWord): Boolean;
var Previous: Integer;
begin
  Previous := FReveal.Offset;
  FReveal := AdvanceReveal(FReveal, Now);
  Result := Previous <> FReveal.Offset;
end;
function TDockState.RevealSnapshot: TDockRevealState;
begin Result := FReveal; end;
function TDockState.NeedsFrames: Boolean;
begin Result := RevealNeedsFrames(FReveal); end;

end.
