unit animationcurvetests;

{$mode delphi}

interface

uses fpcunit, testregistry, animationcurveu;

type
  TAnimationCurveTests = class(TTestCase)
  published
    procedure RotationUsesFractionalAngles;
    procedure BounceInterpolatesLegacyTable;
    procedure BouncePreservesRepeatCounts;
    procedure QuakeKeepsRepeatedSamplesStable;
    procedure SwingKeepsSlowLegacyOscillator;
    procedure VibrateUsesVisibleFrequency;
    procedure ZoomKeepsSlowLegacyOscillator;
    procedure DisabledChoiceDoesNotMove;
    procedure ClickEndpointsStopWithoutSnapping;
  end;

implementation

procedure TAnimationCurveTests.RotationUsesFractionalAngles;
begin
  AssertEquals(45.0, ClickAnimationValues(1, 7.5, 20, 32).Rotation, 0.000001);
end;
procedure TAnimationCurveTests.BounceInterpolatesLegacyTable;
begin
  AssertEquals((0.8453 + 0.8984) * 10,
    ClickAnimationValues(2, 7.5, 20, 32).Bounce, 0.000001);
end;
procedure TAnimationCurveTests.BouncePreservesRepeatCounts;
begin
  AssertEquals(20.0, ClickAnimationValues(2, 15, 20, 32).Bounce, 0.000001);
  AssertEquals(20.0, ClickAnimationValues(3, 45, 20, 32).Bounce, 0.000001);
  AssertEquals(20.0, ClickAnimationValues(4, 75, 20, 32).Bounce, 0.000001);
end;
procedure TAnimationCurveTests.QuakeKeepsRepeatedSamplesStable;
var A, B, Later: TClickAnimationValues;
begin
  A := ClickAnimationValues(5, 7.5, 20, 32);
  B := ClickAnimationValues(5, 7.5, 20, 32);
  Later := ClickAnimationValues(5, 7.501, 20, 32);
  AssertTrue('Quake must move', Abs(A.OffsetX) + Abs(A.OffsetY) > 0.1);
  AssertEquals(A.OffsetX, B.OffsetX, 0.000001);
  AssertEquals(A.OffsetY, B.OffsetY, 0.000001);
  AssertTrue('Nearby phases must remain continuous', Abs(A.OffsetX - Later.OffsetX) < 0.1);
end;
procedure TAnimationCurveTests.SwingKeepsSlowLegacyOscillator;
begin
  AssertEquals(Sin(8 * 6.0) * 30, ClickAnimationValues(6, 8, 20, 32).Rotation, 0.000001);
  AssertTrue(Abs(ClickAnimationValues(6, 7.5, 20, 32).Rotation) > 10);
end;
procedure TAnimationCurveTests.VibrateUsesVisibleFrequency;
begin
  AssertEquals(6.0, ClickAnimationValues(7, 20 / 3, 20, 32).SizeDelta, 0.000001);
end;
procedure TAnimationCurveTests.ZoomKeepsSlowLegacyOscillator;
begin
  AssertEquals(Sin(8 * 6.0) * 10, ClickAnimationValues(8, 8, 20, 32).SizeDelta, 0.000001);
end;
procedure TAnimationCurveTests.DisabledChoiceDoesNotMove;
var Value: TClickAnimationValues;
begin
  Value := ClickAnimationValues(0, 7.5, 20, 32);
  AssertEquals(0.0, Value.OffsetX + Value.OffsetY + Value.SizeDelta + Value.Rotation + Value.Bounce, 0.000001);
end;

procedure TAnimationCurveTests.ClickEndpointsStopWithoutSnapping;
const LastPhase: array[1..8] of integer = (60, 30, 60, 90, 60, 56, 56, 56);
  Epsilon = 0.0001;
var Kind: integer; Start, Finish, BeforeFinish: TClickAnimationValues;
  function Magnitude(const Value: TClickAnimationValues): Double;
  begin
    Result := Abs(Value.OffsetX) + Abs(Value.OffsetY) + Abs(Value.SizeDelta) +
      Abs(Value.Rotation) + Abs(Value.Bounce);
  end;
begin
  for Kind := 1 to 8 do
  begin
    Start := ClickAnimationValues(Kind, Epsilon, 20, 32);
    Finish := ClickAnimationValues(Kind, LastPhase[Kind], 20, 32);
    BeforeFinish := ClickAnimationValues(Kind, LastPhase[Kind] - Epsilon, 20, 32);
    if Kind = 1 then
    begin
      Finish.Rotation := Finish.Rotation - 360;
      BeforeFinish.Rotation := BeforeFinish.Rotation - 360;
    end;
    AssertEquals('Effects must finish at their resting appearance', 0.0, Magnitude(Finish), 0.000001);
    AssertTrue('Effects must start without a velocity jump', Magnitude(Start) / Epsilon < 0.01);
    AssertTrue('Effects must stop without a velocity jump', Magnitude(BeforeFinish) / Epsilon < 0.01);
  end;
end;

initialization
  RegisterTest(TAnimationCurveTests);
end.
