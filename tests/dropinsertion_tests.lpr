program dropinsertion_tests;
{$mode delphi}
uses Interfaces, fpcunit, plaintestreport, itemmanagertests;
exports DockDeleteItem;
const Names: array[0..7] of string = (
  'MultiFileDropCallsEveryFile', 'ManagerDropRetainsExecutingItem',
  'FullStackRejectsFileDrop', 'FullStackDropPreservesSource',
  'ImportedTargetsReportInsertionAndReload', 'ImportedTargetsReportDisabledRejection',
  'ImportedTargetsStopAtStackCapacity', 'UnlaunchableImportedTargetsSurviveReload');
var Suite: TTestSuite; Results: TTestResult; Writer: TPlainResultsWriter; Name: string;
begin
  Suite := TTestSuite.Create('Drop insertion');
  Results := TTestResult.Create;
  Writer := TPlainResultsWriter.Create(nil);
  try
    for Name in Names do Suite.AddTest(TItemManagerTests.CreateWith(Name, 'TItemManagerTests'));
    Results.AddListener(Writer);
    Suite.Run(Results);
    Writer.WriteResult(Results);
    if (Results.NumberOfErrors + Results.NumberOfFailures) <> 0 then ExitCode := 1;
  finally Results.Free; Writer.Free; Suite.Free; end;
end.
