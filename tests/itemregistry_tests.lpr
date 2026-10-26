program itemregistry_tests;

{$mode delphi}

uses simpletestrunner, itemregistrytests;

var runner: TTestRunner;
begin
  runner := TTestRunner.Create(nil);
  try
    runner.Initialize;
    runner.Run;
  finally
    runner.Free;
  end;
end.
