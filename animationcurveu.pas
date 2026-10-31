unit animationcurveu;

{$mode delphi}

interface

type
  TClickAnimationValues = record
    OffsetX, OffsetY, SizeDelta, Rotation, Bounce: Double;
  end;

function ClickAnimationValues(Kind: integer; Phase, Border, ItemSize: Double): TClickAnimationValues;

implementation

uses Math;

const
  BounceTable: array[0..15] of Double = (0, 0.1670, 0.3290, 0.4680,
    0.5956, 0.6937, 0.7790, 0.8453, 0.8984, 0.9360, 0.9630,
    0.9810, 0.9920, 0.9976, 0.9997, 1);
  LegacyPhaseSeconds = 0.015625;

function SmoothEndpoint(Value: Double): Double;
begin
  Value := EnsureRange(Value, 0.0, 1.0);
  Result := Value * Value * (3 - 2 * Value);
end;

function RotationPhase(Phase: Double): Double;
const Edge = 3.0;
var Fraction: Double;
begin
  Phase := EnsureRange(Phase, 0.0, 60.0);
  if Phase < Edge then
  begin
    Fraction := Phase / Edge;
    Exit(Edge * Fraction * Fraction * (2 - Fraction));
  end;
  if Phase > 60 - Edge then
  begin
    Fraction := (60 - Phase) / Edge;
    Exit(60 - Edge * Fraction * Fraction * (2 - Fraction));
  end;
  Result := Phase;
end;

function ClickAnimationValues(Kind: integer; Phase, Border, ItemSize: Double): TClickAnimationValues;
const LastPhase: array[0..8] of integer = (0, 60, 30, 60, 90, 60, 56, 56, 56);
var Step, Seconds, SlowOscillator, Envelope: Double; Index: integer;
begin
  Result := Default(TClickAnimationValues);
  if (Kind < 1) or (Kind > 8) then exit;
  if Phase < 0 then Phase := 0;
  Seconds := Phase * LegacyPhaseSeconds;
  // Integer legacy samples alias six radians into this slow oscillator.
  SlowOscillator := Sin(Phase * (6 - 2 * Pi));
  Envelope := SmoothEndpoint(Phase / 4) * SmoothEndpoint((LastPhase[Kind] - Phase) / 4);
  case Kind of
    1: Result.Rotation := RotationPhase(Phase) * 6;
    2..4:
      begin
        Step := Phase - Floor(Phase / 30) * 30;
        if Step > 15 then Step := 30 - Step;
        Index := Floor(Step);
        if Index >= 15 then Result.Bounce := Min(Border, 40)
        else Result.Bounce := (BounceTable[Index] +
          (BounceTable[Index + 1] - BounceTable[Index]) * (Step - Index)) * Min(Border, 40);
      end;
    5:
      begin
        Result.OffsetX := ItemSize / 6 * (0.65 * Sin(2 * Pi * 11 * Seconds) +
          0.35 * Sin(2 * Pi * 17 * Seconds));
        Result.OffsetY := ItemSize / 6 * (0.65 * Sin(2 * Pi * 13 * Seconds) +
          0.35 * Sin(2 * Pi * 19 * Seconds));
      end;
    6: Result.Rotation := SlowOscillator * 30;
    7: Result.SizeDelta := Sin(2 * Pi * 12 * Seconds) * 6;
    8: Result.SizeDelta := SlowOscillator * 10;
  end;
  if Kind <> 1 then
  begin
    Result.OffsetX := Result.OffsetX * Envelope;
    Result.OffsetY := Result.OffsetY * Envelope;
    Result.SizeDelta := Result.SizeDelta * Envelope;
    Result.Rotation := Result.Rotation * Envelope;
    Result.Bounce := Result.Bounce * Envelope;
  end;
end;

end.
