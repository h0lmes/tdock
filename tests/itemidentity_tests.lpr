program itemidentity_tests;

{$mode delphi}

uses Interfaces, simpletestrunner, itemidentitytests;

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
