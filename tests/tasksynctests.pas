unit tasksynctests;

{$mode delphi}

interface

uses Windows, SysUtils, fpcunit, testregistry, tasksyncu;

type
  TTaskSyncTests = class(TTestCase)
  private
    Input: TTaskSyncInput;
    function Window(Id: THandle; const Exe: string; Visible: boolean = true): TTaskWindowSnapshot;
    function Task(Id: THandle; const Exe: string; const Windows: array of TTaskWindowSnapshot;
      Grouping: boolean = true): TTaskDockEntry;
    function CountActions(const Plan: TTaskSyncPlan; Kind: TTaskSyncActionKind): integer;
  protected
    procedure SetUp; override;
  published
    procedure NewWindowCreatesThenUpdatesTask;
    procedure RegisteredProgramsMatchPathOrFilenameWithoutCase;
    procedure GroupedWindowsReuseFirstMatchingTask;
    procedure GroupMatchingKeepsCaseSensitivePaths;
    procedure UngroupedWindowsKeepSeparateTasks;
    procedure RemovesHiddenWindowsButRetainsVisibleOutsideEnumeration;
    procedure NewTasksFollowContiguousTasksAtConfiguredSpot;
    procedure EmptyTasksDeleteInReverseOrder;
    procedure DraggingLeavesOrderAndWindowsUnchanged;
    procedure PlanningDoesNotMutateSnapshot;
    procedure EmptyExistingGroupCanAcceptReplacementWindow;
  end;

implementation

procedure TTaskSyncTests.SetUp;
begin
  Input.Entries := nil;
  Input.AppWindows := nil;
  Input.TaskSpot := -1;
  Input.Grouping := true;
  Input.Dragging := false;
end;

function TTaskSyncTests.Window(Id: THandle; const Exe: string; Visible: boolean): TTaskWindowSnapshot;
begin
  Result.Handle := Id;
  Result.Executable := Exe;
  Result.Visible := Visible;
end;

function TTaskSyncTests.Task(Id: THandle; const Exe: string;
  const Windows: array of TTaskWindowSnapshot; Grouping: boolean): TTaskDockEntry;
var I: integer;
begin
  Result.ItemId := Id;
  Result.IsTask := true;
  Result.Grouping := Grouping;
  Result.IsNew := false;
  Result.RegisteredExecutable := '';
  Result.GroupExecutable := Exe;
  SetLength(Result.Windows, Length(Windows));
  for I := 0 to High(Windows) do Result.Windows[I] := Windows[I];
end;

function TTaskSyncTests.CountActions(const Plan: TTaskSyncPlan; Kind: TTaskSyncActionKind): integer;
var I: integer;
begin
  Result := 0;
  for I := 0 to High(Plan.Actions) do if Plan.Actions[I].Kind = Kind then Inc(Result);
end;

procedure TTaskSyncTests.NewWindowCreatesThenUpdatesTask;
var Plan: TTaskSyncPlan;
begin
  SetLength(Input.AppWindows, 1);
  Input.AppWindows[0] := Window(101, 'c:\apps\one.exe');
  Plan := ReconcileTasks(Input);
  AssertEquals('Create and update', 2, Length(Plan.Actions));
  AssertEquals(Ord(tsaCreateGroup), Ord(Plan.Actions[0].Kind));
  AssertEquals(1, Plan.Actions[0].NewGroupKey);
  AssertEquals(int64(101), int64(Plan.Actions[0].Window));
  AssertEquals(NO_TASK_INSERT, Plan.Actions[0].InsertIndex);
  AssertEquals(Ord(tsaUpdateGroup), Ord(Plan.Actions[1].Kind));
  AssertEquals(1, Plan.FinalOrder[0].NewGroupKey);
end;

procedure TTaskSyncTests.RegisteredProgramsMatchPathOrFilenameWithoutCase;
var Plan: TTaskSyncPlan;
begin
  SetLength(Input.Entries, 1);
  Input.Entries[0].ItemId := 7;
  Input.Entries[0].RegisteredExecutable := 'ONE.EXE';
  SetLength(Input.AppWindows, 1);
  Input.AppWindows[0] := Window(101, 'c:\apps\one.exe');
  Plan := ReconcileTasks(Input);
  AssertEquals(0, CountActions(Plan, tsaCreateGroup));
  AssertEquals(1, Length(Plan.FinalOrder));
  AssertEquals(int64(7), int64(Plan.FinalOrder[0].ItemId));
end;

procedure TTaskSyncTests.GroupedWindowsReuseFirstMatchingTask;
var Plan: TTaskSyncPlan;
begin
  SetLength(Input.Entries, 2);
  Input.Entries[0] := Task(7, 'one.exe', [Window(101, 'one.exe')]);
  Input.Entries[1] := Task(8, 'one.exe', [Window(102, 'one.exe')]);
  SetLength(Input.AppWindows, 1);
  Input.AppWindows[0] := Window(103, 'one.exe');
  Plan := ReconcileTasks(Input);
  AssertEquals(1, CountActions(Plan, tsaAddWindow));
  AssertEquals(int64(7), int64(Plan.Actions[0].ItemId));
  AssertEquals(0, CountActions(Plan, tsaCreateGroup));
end;

procedure TTaskSyncTests.GroupMatchingKeepsCaseSensitivePaths;
var Plan: TTaskSyncPlan;
begin
  SetLength(Input.Entries, 1);
  Input.Entries[0] := Task(7, 'ONE.EXE', [Window(101, 'ONE.EXE')]);
  SetLength(Input.AppWindows, 1);
  Input.AppWindows[0] := Window(103, 'one.exe');
  Plan := ReconcileTasks(Input);
  AssertEquals(1, CountActions(Plan, tsaCreateGroup));
end;

procedure TTaskSyncTests.UngroupedWindowsKeepSeparateTasks;
var Plan: TTaskSyncPlan;
begin
  Input.Grouping := false;
  SetLength(Input.AppWindows, 2);
  Input.AppWindows[0] := Window(101, 'one.exe');
  Input.AppWindows[1] := Window(102, 'one.exe');
  Plan := ReconcileTasks(Input);
  AssertEquals(2, CountActions(Plan, tsaCreateGroup));
  AssertEquals(0, CountActions(Plan, tsaAddWindow));
end;

procedure TTaskSyncTests.RemovesHiddenWindowsButRetainsVisibleOutsideEnumeration;
var Plan: TTaskSyncPlan;
begin
  SetLength(Input.Entries, 1);
  Input.Entries[0] := Task(7, 'one.exe', [Window(101, 'one.exe', false), Window(102, 'one.exe')]);
  Plan := ReconcileTasks(Input);
  AssertEquals(1, CountActions(Plan, tsaRemoveWindow));
  AssertEquals(int64(101), int64(Plan.Actions[0].Window));
  AssertEquals(1, CountActions(Plan, tsaRefreshGroup));
  AssertEquals(0, CountActions(Plan, tsaDeleteGroup));
  AssertEquals(1, Length(Plan.FinalOrder));
end;

procedure TTaskSyncTests.NewTasksFollowContiguousTasksAtConfiguredSpot;
var Plan: TTaskSyncPlan;
begin
  SetLength(Input.Entries, 3);
  Input.Entries[0].ItemId := 11;
  Input.Entries[1] := Task(12, 'old.exe', [Window(100, 'old.exe')]);
  Input.Entries[2].ItemId := 13;
  Input.TaskSpot := 1;
  SetLength(Input.AppWindows, 2);
  Input.AppWindows[0] := Window(101, 'one.exe');
  Input.AppWindows[1] := Window(102, 'two.exe');
  Plan := ReconcileTasks(Input);
  AssertEquals(5, Length(Plan.Actions));
  AssertEquals(2, Plan.Actions[0].InsertIndex);
  AssertEquals(3, Plan.Actions[1].InsertIndex);
  AssertEquals(5, Length(Plan.FinalOrder));
  AssertEquals(int64(11), int64(Plan.FinalOrder[0].ItemId));
  AssertEquals(int64(12), int64(Plan.FinalOrder[1].ItemId));
  AssertEquals(1, Plan.FinalOrder[2].NewGroupKey);
  AssertEquals(2, Plan.FinalOrder[3].NewGroupKey);
  AssertEquals(int64(13), int64(Plan.FinalOrder[4].ItemId));
end;

procedure TTaskSyncTests.EmptyTasksDeleteInReverseOrder;
var Plan: TTaskSyncPlan;
begin
  SetLength(Input.Entries, 2);
  Input.Entries[0] := Task(7, 'one.exe', [Window(101, 'one.exe', false)]);
  Input.Entries[1] := Task(8, 'two.exe', [Window(102, 'two.exe', false)]);
  Plan := ReconcileTasks(Input);
  AssertEquals(4, Length(Plan.Actions));
  AssertEquals(Ord(tsaDeleteGroup), Ord(Plan.Actions[2].Kind));
  AssertEquals(int64(8), int64(Plan.Actions[2].ItemId));
  AssertEquals(int64(7), int64(Plan.Actions[3].ItemId));
  AssertEquals(0, Length(Plan.FinalOrder));
end;

procedure TTaskSyncTests.DraggingLeavesOrderAndWindowsUnchanged;
var Plan: TTaskSyncPlan;
begin
  Input.Dragging := true;
  SetLength(Input.Entries, 1);
  Input.Entries[0] := Task(7, 'one.exe', [Window(101, 'one.exe', false)]);
  Plan := ReconcileTasks(Input);
  AssertEquals(0, Length(Plan.Actions));
  AssertEquals(1, Length(Plan.FinalOrder));
  AssertEquals(int64(7), int64(Plan.FinalOrder[0].ItemId));
end;

procedure TTaskSyncTests.PlanningDoesNotMutateSnapshot;
var Plan: TTaskSyncPlan;
begin
  SetLength(Input.Entries, 1);
  Input.Entries[0] := Task(7, 'one.exe', [Window(101, 'one.exe', false)]);
  Plan := ReconcileTasks(Input);
  AssertEquals(1, Length(Input.Entries[0].Windows));
  AssertEquals(int64(101), int64(Input.Entries[0].Windows[0].Handle));
  AssertEquals(1, CountActions(Plan, tsaRemoveWindow));
end;

procedure TTaskSyncTests.EmptyExistingGroupCanAcceptReplacementWindow;
var Plan: TTaskSyncPlan;
begin
  SetLength(Input.Entries, 1);
  Input.Entries[0] := Task(7, 'one.exe', [Window(101, 'one.exe', false)]);
  SetLength(Input.AppWindows, 1);
  Input.AppWindows[0] := Window(102, 'one.exe');
  Plan := ReconcileTasks(Input);
  AssertEquals(1, CountActions(Plan, tsaAddWindow));
  AssertEquals(0, CountActions(Plan, tsaCreateGroup));
  AssertEquals(0, CountActions(Plan, tsaDeleteGroup));
end;

initialization
  RegisterTest(TTaskSyncTests);
end.
