program settingssave_tests;

{$mode delphi}

uses simpletestrunner, settingssavetests;

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
