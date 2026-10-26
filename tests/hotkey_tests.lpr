program hotkey_tests;
{$mode delphi}
uses simpletestrunner, hotkeytests;
var Runner: TTestRunner;
begin
  Runner := TTestRunner.Create(nil);
  try Runner.Initialize; Runner.Run; finally Runner.Free; end;
end.
