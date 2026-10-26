program shelltiming_tests;

{$mode delphi}

uses Interfaces, simpletestrunner, shelltimingtests;

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
