program framepacing_tests;
{$mode delphi}
uses simpletestrunner, framepacingtests;
var Runner: TTestRunner;
begin
  Runner := TTestRunner.Create(nil);
  try Runner.Initialize; Runner.Run; finally Runner.Free; end;
end.
