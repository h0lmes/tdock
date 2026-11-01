program taskbarimport_tests;
{$mode delphi}
uses Interfaces, Forms, SysUtils, simpletestrunner, taskbarimporttests, taskbarimportu;
var Runner: TTestRunner; Source: TTaskbarSource; Snapshot: TTaskbarSnapshot;
begin
  Application.Initialize;
  Application.ShowMainForm := False;
  if ParamStr(1) = '--probe' then
  begin
    Source := TTaskbarSource.Create;
    try
      Snapshot := Source.ReadPins;
      WriteLn('Pins: ', Length(Snapshot.Pins), '; failed: ', Snapshot.Failed);
      WriteLn(Snapshot.Warning);
      WriteLn(Snapshot.Details);
    finally Source.Free; end;
    Halt(0);
  end;
  Runner := TTestRunner.Create(nil);
  try Runner.Initialize; Runner.Run; finally Runner.Free; end;
end.
