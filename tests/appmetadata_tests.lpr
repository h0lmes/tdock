program appmetadata_tests;
{$mode delphi}
uses Interfaces, simpletestrunner, appmetadatatests;
var Runner: TTestRunner;
begin
  Runner := TTestRunner.Create(nil);
  try Runner.Initialize; Runner.Run; finally Runner.Free; end;
end.
