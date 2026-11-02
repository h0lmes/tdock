program stackrunning_tests;

{$mode delphi}

uses Interfaces, simpletestrunner, stackrunningtests;

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
