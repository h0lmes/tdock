program itemtiming_tests;

{$mode delphi}

uses Interfaces, simpletestrunner, itemtimingtests;

exports DeactivateHint;

var Runner: TTestRunner;
begin
  Runner := TTestRunner.Create(nil);
  try
    Runner.Initialize;
    Runner.Run;
  finally
    Runner.Free;
  end;
end.
