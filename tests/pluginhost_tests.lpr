program pluginhost_tests;

{$mode delphi}

uses Interfaces, simpletestrunner, pluginhosttests;

exports OnCreate, ActivateHint,
  ProbeItemInsertV1 name 'TDockItemInsertV1',
  ProbeItemFromWindowV1 name 'TDockItemFromWindowV1';

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
