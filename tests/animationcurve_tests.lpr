program animationcurve_tests;

{$mode delphi}

uses simpletestrunner, animationcurvetests;

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
