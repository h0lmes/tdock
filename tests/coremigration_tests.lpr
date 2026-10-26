program coremigration_tests;
{$mode delphi}
uses Interfaces, simpletestrunner, coremigrationtests;
var Runner: TTestRunner;
begin
  Runner := TTestRunner.Create(nil);
  try Runner.Initialize; Runner.Run; finally Runner.Free; end;
end.
