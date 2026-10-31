unit docktimingu;

{$mode delphi}

interface

type
  TDeadline = record
    Active: Boolean;
    DueAt, Generation: QWord;
    procedure Schedule(Now, Delay: QWord);
    procedure Cancel;
    function IsDue(Now: QWord): Boolean;
    function Consume(Now: QWord): Boolean;
    function Remaining(Now: QWord): QWord;
  end;

  TScalarAnimation = record
    StartValue, TargetValue: Double;
    StartedAt, DurationMs: Double;
    function ValueAt(Now: Double): Double;
    function ActiveAt(Now: Double): Boolean;
    procedure Retarget(Now, Target, Duration: Double);
  end;

  TSpringAnimation = record
    StartValue, StartVelocity, TargetValue: Double;
    StartedAt, ResponseMs, Damping: Double;
    Initialized: Boolean;
    procedure Reset(Now, Value: Double);
    procedure Retarget(Now, Target, Response: Double; DampingRatio: Double = 1);
    function ValueAt(Now: Double): Double;
    function VelocityAt(Now: Double): Double;
    function ActiveAt(Now: Double): Boolean;
  end;

implementation

procedure TDeadline.Schedule(Now, Delay: QWord);
begin
  Cancel;
  Active := True;
  if Delay > High(QWord) - Now then DueAt := High(QWord)
  else DueAt := Now + Delay;
end;
procedure TDeadline.Cancel;
begin
  Active := False;
  DueAt := 0;
  if Generation = High(QWord) then Generation := 1 else Inc(Generation);
end;
function TDeadline.IsDue(Now: QWord): Boolean;
begin Result := Active and (Now >= DueAt); end;
function TDeadline.Consume(Now: QWord): Boolean;
begin
  Result := IsDue(Now);
  if Result then Cancel;
end;
function TDeadline.Remaining(Now: QWord): QWord;
begin
  if Active and (Now < DueAt) then Result := DueAt - Now else Result := 0;
end;
function TScalarAnimation.ValueAt(Now: Double): Double;
begin
  if (DurationMs <= 0) or (StartValue = TargetValue) then Exit(TargetValue);
  if Now <= StartedAt then Exit(StartValue);
  if Now - StartedAt >= DurationMs then Exit(TargetValue);
  Result := StartValue + (TargetValue - StartValue) * ((Now - StartedAt) / DurationMs);
end;
function TScalarAnimation.ActiveAt(Now: Double): Boolean;
begin
  Result := (DurationMs > 0) and (StartValue <> TargetValue) and
    ((Now < StartedAt) or (Now - StartedAt < DurationMs));
end;
procedure TScalarAnimation.Retarget(Now, Target, Duration: Double);
begin
  StartValue := ValueAt(Now);
  TargetValue := Target;
  StartedAt := Now;
  DurationMs := Duration;
end;

procedure TSpringAnimation.Reset(Now, Value: Double);
begin
  StartValue := Value;
  StartVelocity := 0;
  TargetValue := Value;
  StartedAt := Now;
  ResponseMs := 0;
  Damping := 1;
  Initialized := True;
end;

procedure TSpringAnimation.Retarget(Now, Target, Response: Double;
  DampingRatio: Double);
var Current, Velocity: Double;
begin
  Current := StartValue;
  Velocity := 0;
  if Initialized then
  begin
    if ResponseMs > 0 then
    begin
      Current := ValueAt(Now);
      Velocity := VelocityAt(Now);
    end
    else Current := TargetValue;
  end;
  StartValue := Current;
  StartVelocity := Velocity;
  TargetValue := Target;
  StartedAt := Now;
  ResponseMs := Response;
  Damping := DampingRatio;
  Initialized := True;
  if Response <= 0 then
  begin
    StartValue := Target;
    StartVelocity := 0;
    ResponseMs := 0;
  end;
end;

procedure EvaluateSpring(const Spring: TSpringAnimation; Now: Double;
  out Value, Velocity: Double);
const ResponseFactor = 4.743864518390578;
  PositionTolerance = 0.001;
  VelocityTolerance = 0.01;
var Time, Omega, Displacement, Coefficient, Decay: Double;
  Alpha, Frequency, Sine, Cosine, Position: Double;
  Root, Rate1, Rate2, Contribution1, Contribution2: Double;
begin
  if not Spring.Initialized or (Spring.ResponseMs <= 0) then
  begin
    Value := Spring.TargetValue;
    Velocity := 0;
    Exit;
  end;
  if Now <= Spring.StartedAt then
  begin
    Value := Spring.StartValue;
    Velocity := Spring.StartVelocity;
    Exit;
  end;
  Time := (Now - Spring.StartedAt) / 1000;
  Omega := ResponseFactor * 1000 / Spring.ResponseMs;
  Displacement := Spring.StartValue - Spring.TargetValue;
  if Spring.Damping < 1 then
  begin
    Alpha := Spring.Damping * Omega;
    Frequency := Omega * Sqrt(1 - Sqr(Spring.Damping));
    Coefficient := (Spring.StartVelocity + Alpha * Displacement) / Frequency;
    Decay := Exp(-Alpha * Time);
    Sine := Sin(Frequency * Time);
    Cosine := Cos(Frequency * Time);
    Position := Displacement * Cosine + Coefficient * Sine;
    Value := Spring.TargetValue + Position * Decay;
    Velocity := (Frequency * (Coefficient * Cosine - Displacement * Sine) -
      Alpha * Position) * Decay;
  end
  else if Spring.Damping > 1 then
  begin
    Root := Sqrt(Sqr(Spring.Damping) - 1);
    Rate1 := -Omega / (Spring.Damping + Root);
    Rate2 := -Omega * (Spring.Damping + Root);
    Coefficient := (Spring.StartVelocity - Rate2 * Displacement) / (Rate1 - Rate2);
    Contribution1 := Coefficient * Exp(Rate1 * Time);
    Contribution2 := (Displacement - Coefficient) * Exp(Rate2 * Time);
    Value := Spring.TargetValue + Contribution1 + Contribution2;
    Velocity := Rate1 * Contribution1 + Rate2 * Contribution2;
  end
  else
  begin
    Coefficient := Spring.StartVelocity + Omega * Displacement;
    Decay := Exp(-Omega * Time);
    Value := Spring.TargetValue + (Displacement + Coefficient * Time) * Decay;
    Velocity := (Spring.StartVelocity - Omega * Coefficient * Time) * Decay;
  end;
  if (Abs(Value - Spring.TargetValue) <= PositionTolerance) and
    (Abs(Velocity) <= VelocityTolerance) then
  begin
    Value := Spring.TargetValue;
    Velocity := 0;
  end;
end;

function TSpringAnimation.ValueAt(Now: Double): Double;
var Velocity: Double;
begin
  EvaluateSpring(Self, Now, Result, Velocity);
end;

function TSpringAnimation.VelocityAt(Now: Double): Double;
var Value: Double;
begin
  EvaluateSpring(Self, Now, Value, Result);
end;

function TSpringAnimation.ActiveAt(Now: Double): Boolean;
var Value, Velocity: Double;
begin
  EvaluateSpring(Self, Now, Value, Velocity);
  Result := Initialized and ((Value <> TargetValue) or (Velocity <> 0));
end;

end.
