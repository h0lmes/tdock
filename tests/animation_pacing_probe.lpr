program animation_pacing_probe;

{$mode delphi}

uses Windows, Messages, SysUtils, Math, framepaceru, animationclocku;

const Samples = 240;
type TIntervals = array[0..Samples - 1] of Double;

procedure Measure(Hz: Double);
var Window: HWND; Pacer: TFramePacer; Message: TMsg;
  Intervals: TIntervals; Count, I, J: Integer;
  Previous, Now, Started, Total, Value: Double;
begin
  Window := CreateWindowEx(0, 'STATIC', '', WS_POPUP, 0, 0, 1, 1,
    0, 0, HInstance, nil);
  if Window = 0 then RaiseLastOSError;
  Pacer := TFramePacer.Create(Window, DOCK_FRAME_MESSAGE);
  try
    Pacer.SetMonitorForWindow(Window);
    Pacer.SetRefreshRate(Hz);
    Pacer.SetActive(True);
    Count := -1;
    Previous := 0;
    Total := 0;
    Started := AnimationTimeMs;
    while Count < Samples do
    begin
      if AnimationTimeMs - Started > 15000 then
        raise Exception.Create('Frame delivery timed out');
      if PeekMessage(Message, Window, DOCK_FRAME_MESSAGE, DOCK_FRAME_MESSAGE,
        PM_REMOVE) then
      begin
        if not Pacer.ConsumeMessage(Message.wParam) then Continue;
        Now := AnimationTimeMs;
        if Count >= 0 then
        begin
          Intervals[Count] := Now - Previous;
          Total := Total + Intervals[Count];
        end;
        Previous := Now;
        Inc(Count);
      end
      else MsgWaitForMultipleObjects(0, nil, False, 1000, QS_POSTMESSAGE);
    end;
    Pacer.SetActive(False);
    for I := 1 to High(Intervals) do
    begin
      Value := Intervals[I];
      J := I - 1;
      while (J >= 0) and (Intervals[J] > Value) do
      begin
        Intervals[J + 1] := Intervals[J];
        Dec(J);
      end;
      Intervals[J + 1] := Value;
    end;
    Writeln(Hz:0:0, ',', Pacer.DisplayRefreshRate:0:3, ',',
      Pacer.EffectiveRefreshRate:0:3, ',', Ord(Pacer.ClockSource), ',',
      Samples, ',', Ord(Pacer.HighResolution), ',',
      Total / Samples:0:3, ',', Intervals[Samples div 2]:0:3, ',',
      Intervals[Ceil(Samples * 0.95) - 1]:0:3, ',',
      Intervals[Ceil(Samples * 0.99) - 1]:0:3, ',',
      Intervals[High(Intervals)]:0:3);
  finally
    Pacer.Free;
    DestroyWindow(Window);
  end;
end;

begin
  DefaultFormatSettings.DecimalSeparator := '.';
  Writeln('requested_hz,display_hz,effective_hz,clock_source,samples,high_resolution,mean_ms,p50_ms,p95_ms,p99_ms,max_ms');
  Measure(60);
  Measure(120);
end.
