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
    StartedAt, DurationMs: QWord;
    function ValueAt(Now: QWord): Double;
    function ActiveAt(Now: QWord): Boolean;
    procedure Retarget(Now: QWord; Target: Double; Duration: QWord);
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
function TScalarAnimation.ValueAt(Now: QWord): Double;
begin
  if (DurationMs = 0) or (StartValue = TargetValue) then Exit(TargetValue);
  if Now <= StartedAt then Exit(StartValue);
  if Now - StartedAt >= DurationMs then Exit(TargetValue);
  Result := StartValue + (TargetValue - StartValue) * ((Now - StartedAt) / DurationMs);
end;
function TScalarAnimation.ActiveAt(Now: QWord): Boolean;
begin
  Result := (DurationMs > 0) and (StartValue <> TargetValue) and
    ((Now < StartedAt) or (Now - StartedAt < DurationMs));
end;
procedure TScalarAnimation.Retarget(Now: QWord; Target: Double; Duration: QWord);
begin
  StartValue := ValueAt(Now);
  TargetValue := Target;
  StartedAt := Now;
  DurationMs := Duration;
end;

end.
