program launchservice_tests;
{$mode delphi}
uses Interfaces, simpletestrunner, launchservicetests;
var Runner: TTestRunner;
begin
  Runner := TTestRunner.Create(nil);
  try Runner.Initialize; Runner.Run; finally Runner.Free; end;
end.
