unit tasksyncu;

{$mode delphi}

interface

uses Windows, itemmodelu;

const NO_TASK_INSERT = -MaxInt;

type
  TTaskWindowSnapshot = record
    Handle: THandle;
    Executable: string;
    Visible: boolean;
  end;
  TTaskWindows = array of TTaskWindowSnapshot;

  TTaskDockEntry = record
    ItemId: TItemId;
    IsTask, Grouping, IsNew: boolean;
    RegisteredExecutable, GroupExecutable: string;
    Windows: TTaskWindows;
  end;
  TTaskDockEntries = array of TTaskDockEntry;

  TTaskSyncInput = record
    Entries: TTaskDockEntries;
    AppWindows: TTaskWindows;
    TaskSpot: integer;
    Grouping, Dragging: boolean;
  end;

  TTaskSyncActionKind = (tsaRemoveWindow, tsaRefreshGroup, tsaCreateGroup,
    tsaAddWindow, tsaDeleteGroup, tsaUpdateGroup);

  TTaskSyncAction = record
    Kind: TTaskSyncActionKind;
    ItemId: TItemId;
    Window: THandle;
    NewGroupKey, InsertIndex: integer;
  end;
  TTaskSyncActions = array of TTaskSyncAction;

  TTaskOrderEntry = record
    ItemId: TItemId;
    NewGroupKey: integer;
  end;
  TTaskOrder = array of TTaskOrderEntry;

  TTaskSyncPlan = record
    Actions: TTaskSyncActions;
    FinalOrder: TTaskOrder;
  end;

function ReconcileTasks(const Input: TTaskSyncInput): TTaskSyncPlan;

implementation

uses SysUtils;

type
  TWorkingEntry = record
    Entry: TTaskDockEntry;
    NewGroupKey: integer;
  end;
  TWorkingEntries = array of TWorkingEntry;

function ReconcileTasks(const Input: TTaskSyncInput): TTaskSyncPlan;
var
  Working: TWorkingEntries;
  Plan: TTaskSyncPlan;
  I, J, AppIndex, Found, InsertIndex, Key, CountBefore: integer;
  AppWindow: TTaskWindowSnapshot;
  NewEntry: TWorkingEntry;

  procedure AddAction(Kind: TTaskSyncActionKind; EntryIndex: integer;
    Window: THandle = 0; Position: integer = NO_TASK_INSERT);
  var N: integer;
  begin
    N := Length(Plan.Actions);
    SetLength(Plan.Actions, N + 1);
    Plan.Actions[N].Kind := Kind;
    Plan.Actions[N].ItemId := Working[EntryIndex].Entry.ItemId;
    Plan.Actions[N].NewGroupKey := Working[EntryIndex].NewGroupKey;
    Plan.Actions[N].Window := Window;
    Plan.Actions[N].InsertIndex := Position;
  end;

  function HasWindow(EntryIndex: integer; Window: THandle): boolean;
  var N: integer;
  begin
    Result := false;
    for N := 0 to High(Working[EntryIndex].Entry.Windows) do
      if Working[EntryIndex].Entry.Windows[N].Handle = Window then exit(true);
  end;

  function IsRegistered(const Executable: string): boolean;
  var N: integer; Registered, ProcessName: string;
  begin
    Result := false;
    ProcessName := LowerCase(Executable);
    for N := 0 to High(Working) do
    begin
      Registered := LowerCase(Working[N].Entry.RegisteredExecutable);
      if (Registered <> '') and ((Registered = ProcessName) or
        (Registered = ExtractFileName(ProcessName))) then exit(true);
    end;
  end;

  procedure AppendWindow(EntryIndex: integer; const Window: TTaskWindowSnapshot);
  var N: integer;
  begin
    N := Length(Working[EntryIndex].Entry.Windows);
    SetLength(Working[EntryIndex].Entry.Windows, N + 1);
    Working[EntryIndex].Entry.Windows[N] := Window;
  end;

  procedure CaptureOrder;
  var N, Target: integer;
  begin
    Target := 0;
    for N := 0 to High(Working) do
      if Input.Dragging or not Working[N].Entry.IsTask or
        (Length(Working[N].Entry.Windows) > 0) then
      begin
        SetLength(Plan.FinalOrder, Target + 1);
        Plan.FinalOrder[Target].ItemId := Working[N].Entry.ItemId;
        Plan.FinalOrder[Target].NewGroupKey := Working[N].NewGroupKey;
        Inc(Target);
      end;
  end;

begin
  Plan.Actions := nil;
  Plan.FinalOrder := nil;
  SetLength(Working, Length(Input.Entries));
  for I := 0 to High(Working) do
  begin
    Working[I].Entry := Input.Entries[I];
    Working[I].Entry.Windows := Copy(Input.Entries[I].Windows);
    Working[I].NewGroupKey := 0;
  end;
  if Input.Dragging then
  begin
    CaptureOrder;
    exit(Plan);
  end;

  for I := 0 to High(Working) do
    if Working[I].Entry.IsTask then
    begin
      CountBefore := Length(Working[I].Entry.Windows);
      for J := CountBefore - 1 downto 0 do
        if not Working[I].Entry.Windows[J].Visible then
        begin
          AddAction(tsaRemoveWindow, I, Working[I].Entry.Windows[J].Handle);
          Delete(Working[I].Entry.Windows, J, 1);
        end;
      if (Length(Working[I].Entry.Windows) <> CountBefore) and
        (Length(Working[I].Entry.Windows) > 0) then AddAction(tsaRefreshGroup, I);
    end;

  Key := 0;
  for AppIndex := 0 to High(Input.AppWindows) do
  begin
    AppWindow := Input.AppWindows[AppIndex];
    if IsRegistered(AppWindow.Executable) then continue;
    Found := -1;
    for I := 0 to High(Working) do
      if Working[I].Entry.IsTask then
      begin
        if HasWindow(I, AppWindow.Handle) then
        begin
          Found := I;
          break;
        end;
        if not Working[I].Entry.Grouping and (Length(Working[I].Entry.Windows) > 0) then continue;
        if (Working[I].Entry.GroupExecutable = '') and
          (Length(Working[I].Entry.Windows) > 0) then
          Working[I].Entry.GroupExecutable := Working[I].Entry.Windows[0].Executable;
        if Working[I].Entry.IsNew or ((AppWindow.Executable <> '') and
          (AppWindow.Executable = Working[I].Entry.GroupExecutable)) then
        begin
          if Working[I].Entry.IsNew then
          begin
            Working[I].Entry.GroupExecutable := AppWindow.Executable;
            Working[I].Entry.IsNew := false;
          end;
          AppendWindow(I, AppWindow);
          AddAction(tsaAddWindow, I, AppWindow.Handle);
          Found := I;
          break;
        end;
      end;
    if Found >= 0 then continue;

    InsertIndex := Input.TaskSpot;
    if (InsertIndex < 0) or (InsertIndex >= Length(Working)) then InsertIndex := NO_TASK_INSERT
    else
    begin
      while (InsertIndex < Length(Working)) and Working[InsertIndex].Entry.IsTask do Inc(InsertIndex);
      if InsertIndex >= Length(Working) then InsertIndex := NO_TASK_INSERT;
    end;
    Inc(Key);
    NewEntry.Entry.ItemId := 0;
    NewEntry.Entry.IsTask := true;
    NewEntry.Entry.Grouping := Input.Grouping;
    NewEntry.Entry.IsNew := false;
    NewEntry.Entry.RegisteredExecutable := '';
    NewEntry.Entry.GroupExecutable := AppWindow.Executable;
    NewEntry.Entry.Windows := nil;
    SetLength(NewEntry.Entry.Windows, 1);
    NewEntry.Entry.Windows[0] := AppWindow;
    NewEntry.NewGroupKey := Key;
    I := InsertIndex;
    if I = NO_TASK_INSERT then I := Length(Working);
    SetLength(Working, Length(Working) + 1);
    for J := High(Working) downto I + 1 do Working[J] := Working[J - 1];
    Working[I] := NewEntry;
    AddAction(tsaCreateGroup, I, AppWindow.Handle, InsertIndex);
  end;
  for I := High(Working) downto 0 do
    if Working[I].Entry.IsTask then
      if Length(Working[I].Entry.Windows) = 0 then AddAction(tsaDeleteGroup, I)
      else AddAction(tsaUpdateGroup, I);
  CaptureOrder;
  Result := Plan;
end;

end.
