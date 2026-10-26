program animationtiming_tests;

{$mode delphi}

uses Interfaces, simpletestrunner, animationtimingtests;

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
