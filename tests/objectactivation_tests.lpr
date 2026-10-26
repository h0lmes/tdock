program objectactivation_tests;
{$mode delphi}
uses Interfaces, simpletestrunner, objectactivationtests;
var Runner: TTestRunner;
begin
  Runner := TTestRunner.Create(nil);
  try Runner.Initialize; Runner.Run; finally Runner.Free; end;
end.
