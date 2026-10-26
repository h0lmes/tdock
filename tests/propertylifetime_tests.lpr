program propertylifetime_tests;

{$mode delphi}

uses Interfaces, Forms, simpletestrunner, propertylifetimetests;

var Runner: TTestRunner;
begin
  Application.Initialize;
  Application.ShowMainForm := False;
  Runner := TTestRunner.Create(nil);
  try
    Runner.Initialize;
    Runner.Run;
  finally
    Runner.Free;
  end;
end.
