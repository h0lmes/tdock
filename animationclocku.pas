unit animationclocku;

{$mode delphi}

interface

function AnimationTimeMs: Double;
procedure BeginAnimationFrame;
procedure EndAnimationFrame;

implementation

uses Windows, SysUtils;

var
  PerformanceFrequency: Int64;
  MillisecondsPerCount: Double;

threadvar
  FrameDepth: Cardinal;
  FrameTimestamp: Double;

function ReadAnimationTimeMs: Double;
var Counter: Int64; CounterValue: Double;
begin
  if (PerformanceFrequency > 0) and Windows.QueryPerformanceCounter(Counter) then
  begin
    CounterValue := Counter;
    Result := CounterValue * MillisecondsPerCount;
  end
  else Result := GetTickCount64;
end;

function AnimationTimeMs: Double;
begin
  if FrameDepth > 0 then Result := FrameTimestamp
  else Result := ReadAnimationTimeMs;
end;

procedure BeginAnimationFrame;
begin
  if FrameDepth = 0 then FrameTimestamp := ReadAnimationTimeMs;
  Inc(FrameDepth);
end;

procedure EndAnimationFrame;
begin
  if FrameDepth > 0 then Dec(FrameDepth);
end;

initialization
  if not Windows.QueryPerformanceFrequency(PerformanceFrequency) then
    PerformanceFrequency := 0;
  if PerformanceFrequency > 0 then
  begin
    MillisecondsPerCount := PerformanceFrequency;
    MillisecondsPerCount := 1000 / MillisecondsPerCount;
  end;
end.
