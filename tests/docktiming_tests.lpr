program docktiming_tests;
{$mode delphi}
uses simpletestrunner, docktimingtests;
var Runner: TTestRunner;
begin
  Runner := TTestRunner.Create(nil);
  try Runner.Initialize; Runner.Run; finally Runner.Free; end;
end.
