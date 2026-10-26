program itemcollection_tests;

{$mode delphi}

uses simpletestrunner, itemcollectiontests;

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
