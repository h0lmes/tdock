program docklayout_tests;

{$mode delphi}

uses simpletestrunner, docklayouttests;

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
