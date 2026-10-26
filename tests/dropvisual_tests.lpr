program dropvisual_tests;

{$mode delphi}

uses Interfaces, simpletestrunner, fpcunit, coremigrationtests;

type
  TDropVisualRunner = class(TTestRunner)
  protected
    procedure DoRun; override;
  end;

procedure TDropVisualRunner.DoRun;
var Suite: TTestSuite;
begin
  Suite := TTestSuite.Create('Drop background');
  try
    Suite.AddTest(TCoreMigrationTests.CreateWithName('DropCompletionRepaintsIdenticalGeometry'));
    Suite.AddTest(TCoreMigrationTests.CreateWithName('DragCancellationRepaintsIdenticalGeometry'));
    Suite.AddTest(TCoreMigrationTests.CreateWithName('FailedDragCompletionRetriesIdenticalGeometry'));
    if not DoTestRun(Suite) then ExitCode := 1;
  finally Suite.Free; end;
  Terminate;
end;

var Runner: TDropVisualRunner;
begin
  Runner := TDropVisualRunner.Create(nil);
  try Runner.Initialize; Runner.Run; finally Runner.Free; end;
end.
