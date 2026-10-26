program runthread_tests;

{$mode delphi}

uses heaptrc, simpletestrunner, runthreadtests;

var runner: TTestRunner;
begin
  HaltOnNotReleased := true;
  runner := TTestRunner.Create(nil);
  try
    runner.Initialize;
    runner.Run;
  finally
    runner.Free;
  end;
end.
