program subitemlifetime_tests;

{$mode delphi}

uses Interfaces, simpletestrunner, subitemlifetimetests;

exports DockExecute, DockCreateItem, Undock;

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
