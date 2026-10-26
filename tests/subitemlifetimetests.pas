unit subitemlifetimetests;

{$mode delphi}

interface

uses Windows, Messages, Classes, Controls, SysUtils, fpcunit, testregistry,
  declu, itemmgru, itemsettingsu, customitemu, customsubitemu, scsubitemu,
  stackitemu, itemhostu, applifecycleu, themeu, itemmodelu, itemviewu;

type
  TSubitemFailure = (sfNone, sfAllocation, sfNative, sfParse, sfFreed,
    sfNativeLossWhileParsing, sfParentDeletionWhileParsing,
    sfParentRetirementWhileParsing, sfFillWhileParsing, sfSecondParse);

  TFailingShortcut = class(TShortcutSubitem)
  protected
    function CreateViewWindow: HWND; override;
  public
    destructor Destroy; override;
    procedure FromString(Data: string); override;
  end;

  TFailingStack = class(TStackItem)
  protected
    function CreateSubitem: TCustomSubitem; override;
  end;

  TCleanupShortcut = class(TShortcutSubitem)
  protected
    procedure DisposeShortcutImage; override;
    procedure DisposeShortcutPIDL; override;
  end;

  TSubitemLifetimeTests = class(TTestCase)
  private
    Manager: TItemManager;
    Stack: TStackItem;
    Life: TApplicationLifecycle;
    FixtureTheme: TDTheme;
    StackWindow, SubitemWindow: HWND;
    Entered, Left: Integer;
    SurvivedCallback, StackSurvivedCallback, ClosePostedInside: Boolean;
    ClosePostedDuringCallback: Boolean;
    CallbackDepth: Integer;
    CreatedCopies: integer;
    CreatedCopyId: TItemId;
    RejectDrag, CopyCreationFails, CopyLookupFails: boolean;
    ActiveMouseLocks: integer;
    procedure EnterHost;
    procedure LeaveHost;
    procedure CreateShortcut(const Command: string);
    procedure ClickShortcut;
    procedure ExecuteShortcut(id: HWND; const Command: string);
    procedure CreateFailingStack;
    procedure CheckFailedAddition(Failure: TSubitemFailure);
    procedure DeleteThroughHost(wnd: HWND);
    function CreateCopy(Data: PChar): HWND;
    procedure AdoptDrag(wnd: HWND);
    procedure LockMouseEffect(wnd: HWND; Lock: boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ClearRetainsStackAndSubitemUntilCallbackReturns;
    procedure NestedStackDeletionRetainsSubitemUntilCallbackReturns;
    procedure QuitRemainsPendingUntilSubitemCallbackReturns;
    procedure CallbackFailureReleasesBothPinsAndHostScope;
    procedure NativeChildDestructionRemovesOnlyItsBucket;
    procedure AllocationFailurePreservesExistingSubitems;
    procedure NativeCreationFailurePreservesExistingSubitems;
    procedure ParseFailurePreservesExistingSubitems;
    procedure FreedCreationDoesNotDoubleDecrement;
    procedure RepeatedDeleteKeepsExactlyOneUndoCopy;
    procedure FailedDragAdoptionKeepsSourceAndReleasesCopy;
    procedure SuccessfulDragAdoptionMarksSourceForDeletion;
    procedure ImageCleanupFailureStillDestroysNativeChild;
    procedure PIDLCleanupFailureStillDestroysNativeChild;
    procedure StackViewReplacementPreservesChildrenAndCallbackRouting;
    procedure DeletingOpenStackHidesChildrenAndUndoReopens;
    procedure LastNativeChildLossReleasesOpenStackLock;
    procedure AnimatedReopenReleasesExactlyOneStackLock;
    procedure FailedUndoCopyKeepsSourceAndAllowsRetry;
    procedure RejectedUndoDeletionKeepsSourceAndReleasesPendingCopy;
    procedure NativeLossDuringParsingRetainsChildUntilAdditionReturns;
    procedure ParentDeletionDuringParsingRejectsPendingChild;
    procedure ParentRetirementDuringParsingRetainsAdditionFrame;
    procedure ReentrantAdditionRechecksCapacityBeforePublication;
    procedure BatchFailureRollsBackPublishedChildren;
    procedure FullStackReportsRejectedAddition;
  end;

procedure DockExecute(id: HWND; exename, params, dir: PChar; showcmd: Integer); stdcall;
function DockCreateItem(Data: PChar): HWND; stdcall;
procedure Undock(wnd: HWND); stdcall;

implementation

var CurrentTest: TSubitemLifetimeTests;
  SubitemFailure: TSubitemFailure;
  FailedChildId: TItemId;
  FailedChildrenDestroyed: integer;
  RaiseImageCleanup, RaisePIDLCleanup: boolean;
  PIDLCleanupCalls: integer;
  ParsingChildId, ParsingParentId, ParsingChildLease: TItemId;
  ParsingChildSurvived, ParsingParentSurvived: boolean;
  HiddenCopies: array of record
    Window: HWND;
    Previous: WNDPROC;
    RequestedVisible: boolean;
  end;

function HiddenCopyWindowProc(wnd: HWND; Msg: UINT; wParam: WPARAM;
  lParam: LPARAM): LRESULT; stdcall;
var index: integer;
begin
  for index := 0 to High(HiddenCopies) do
    if HiddenCopies[index].Window = wnd then
    begin
      if Msg = WM_WINDOWPOSCHANGING then
      begin
        if PWindowPos(lParam)^.flags and SWP_SHOWWINDOW <> 0 then
          HiddenCopies[index].RequestedVisible := true;
        if PWindowPos(lParam)^.flags and SWP_HIDEWINDOW <> 0 then
          HiddenCopies[index].RequestedVisible := false;
        PWindowPos(lParam)^.flags :=
          (PWindowPos(lParam)^.flags and not SWP_SHOWWINDOW) or SWP_HIDEWINDOW;
      end;
      exit(Windows.CallWindowProc(HiddenCopies[index].Previous, wnd, Msg, wParam, lParam));
    end;
  Result := Windows.DefWindowProc(wnd, Msg, wParam, lParam);
end;

function KeepWindowHidden(wnd: HWND): integer;
begin
  Result := Length(HiddenCopies);
  SetLength(HiddenCopies, Result + 1);
  HiddenCopies[Result].Window := wnd;
  HiddenCopies[Result].Previous := WNDPROC(Windows.SetWindowLongPtr(wnd,
    GWL_WNDPROC, PtrInt(@HiddenCopyWindowProc)));
end;

function DockCreateItem(Data: PChar): HWND; stdcall;
begin
  Result := 0;
  if CurrentTest <> nil then Result := CurrentTest.CreateCopy(Data);
end;

procedure Undock(wnd: HWND); stdcall;
begin
  if CurrentTest <> nil then CurrentTest.AdoptDrag(wnd);
end;

function TFailingShortcut.CreateViewWindow: HWND;
begin
  FailedChildId := ItemId;
  if SubitemFailure = sfNative then exit(0);
  Result := inherited;
end;

destructor TFailingShortcut.Destroy;
begin
  inc(FailedChildrenDestroyed);
  inherited;
end;

procedure TFailingShortcut.FromString(Data: string);
var failure: TSubitemFailure;
begin
  if (SubitemFailure = sfSecondParse) and (Pos('Second', Data) > 0) then
    raise Exception.Create('Injected second parse failure');
  if SubitemFailure = sfParse then raise Exception.Create('Injected parse failure');
  if SubitemFailure in [sfNativeLossWhileParsing, sfParentDeletionWhileParsing,
    sfParentRetirementWhileParsing, sfFillWhileParsing] then
  begin
    ParsingChildId := ItemId;
    ParsingParentId := ParentItemId;
    case SubitemFailure of
      sfNativeLossWhileParsing:
        begin
          Windows.DestroyWindow(Handle);
          ParsingChildSurvived := FindItemModel(ParsingChildId) = Self;
        end;
      sfParentDeletionWhileParsing:
        CurrentTest.Manager.DeleteItemById(ParsingParentId);
      sfParentRetirementWhileParsing:
        begin
          if Pin then ParsingChildLease := ItemId;
          CurrentTest.Manager.command('clear', '');
          ParsingParentSurvived := FindItemModel(ParsingParentId) <> nil;
          raise Exception.Create('Stop retired-parent parsing');
        end;
      sfFillWhileParsing:
        begin
          failure := SubitemFailure;
          SubitemFailure := sfNone;
          try
            while CurrentTest.Stack.ItemCount < MAX_SUBITEMS do
              CurrentTest.Stack.AddSubitem(TShortcutSubitem.Make('Added child', '/added'));
          finally SubitemFailure := failure; end;
        end;
    end;
    exit;
  end;
  inherited;
end;

function TFailingStack.CreateSubitem: TCustomSubitem;
var Params: TDItemCreateParams;
begin
  if SubitemFailure = sfAllocation then raise EOutOfMemory.Create('Injected allocation failure');
  Params := Default(TDItemCreateParams);
  Params.ItemSize := 32;
  Result := TFailingShortcut.Create(Handle, Params);
  if SubitemFailure = sfFreed then Result.Freed := true;
end;

procedure TCleanupShortcut.DisposeShortcutImage;
begin
  if RaiseImageCleanup then raise Exception.Create('Injected image cleanup failure');
  inherited;
end;

procedure TCleanupShortcut.DisposeShortcutPIDL;
begin
  inc(PIDLCleanupCalls);
  if RaisePIDLCleanup then raise Exception.Create('Injected PIDL cleanup failure');
  inherited;
end;

procedure DockExecute(id: HWND; exename, params, dir: PChar; showcmd: Integer); stdcall;
begin
  if CurrentTest <> nil then CurrentTest.ExecuteShortcut(id, string(exename));
end;

function FindSubitem(wnd: HWND; data: LPARAM): BOOL; stdcall;
var Name: array[0..127] of Char; Fixture: TSubitemLifetimeTests;
begin
  Fixture := TSubitemLifetimeTests(Pointer(data));
  GetClassName(wnd, Name, Length(Name));
  Result := True;
  if (GetWindow(wnd, GW_OWNER) = Fixture.StackWindow) and
    (string(Name) = TDSUBITEM_WCLASS) then
  begin
    Fixture.SubitemWindow := wnd;
    Result := False;
  end;
end;

procedure TSubitemLifetimeTests.EnterHost;
begin
  Inc(Entered);
  Life.EnterOperation;
end;

procedure TSubitemLifetimeTests.LeaveHost;
begin
  Inc(Left);
  Life.LeaveOperation;
  if Life.TakeCloseRequest then ClosePostedInside := True;
end;

procedure TSubitemLifetimeTests.DeleteThroughHost(wnd: HWND);
begin
  Manager.DeleteItem(wnd);
end;

function TSubitemLifetimeTests.CreateCopy(Data: PChar): HWND;
begin
  Result := 0;
  if CopyCreationFails then exit;
  if CopyLookupFails then exit(HWND(High(PtrUInt)));
  Result := Manager.CreateItemFromString(string(Data));
  if Result = 0 then exit;
  inc(CreatedCopies);
  CreatedCopyId := ItemViews.ItemIdOf(Result);
  KeepWindowHidden(Result);
end;

procedure TSubitemLifetimeTests.AdoptDrag(wnd: HWND);
begin
  if not RejectDrag then Manager.Undock(wnd);
end;

procedure TSubitemLifetimeTests.LockMouseEffect(wnd: HWND; Lock: boolean);
begin
  if Lock then inc(ActiveMouseLocks) else dec(ActiveMouseLocks);
end;

procedure TSubitemLifetimeTests.SetUp;
var Settings: TItemManagerSettings; Services: TItemHostServices;
begin
  SubitemFailure := sfNone;
  FailedChildId := NO_ITEM_ID;
  FailedChildrenDestroyed := 0;
  HiddenCopies := nil;
  RaiseImageCleanup := false;
  RaisePIDLCleanup := false;
  PIDLCleanupCalls := 0;
  ParsingChildId := NO_ITEM_ID;
  ParsingParentId := NO_ITEM_ID;
  ParsingChildLease := NO_ITEM_ID;
  ParsingChildSurvived := false;
  ParsingParentSurvived := false;
  Life := TApplicationLifecycle.Create;
  Life.Started;
  FixtureTheme := TDTheme(TDTheme.NewInstance);
  theme := FixtureTheme;
  Settings := Default(TItemManagerSettings);
  Settings.ItemSize := 32;
  Settings.BigItemSize := 32;
  Settings.ItemSpacing := 4;
  Settings.ZoomTime := 100;
  Settings.SeparatorAlpha := 255;
  Settings.Site := bsBottom;
  Settings.TaskSpot := -1;
  Manager := TItemManager.Create(0, Settings, nil);
  Manager.Enable(True);
  Services := Default(TItemHostServices);
  Services.OnEnter := EnterHost;
  Services.OnLeave := LeaveHost;
  Services.OnDelete := DeleteThroughHost;
  Services.OnLockMouseEffect := LockMouseEffect;
  BindItemHost(0, Services);
  CurrentTest := Self;
end;

procedure TSubitemLifetimeTests.TearDown;
begin
  CurrentTest := nil;
  Manager.Free;
  theme := nil;
  FixtureTheme.Free;
  UnbindItemHost(0);
  Life.Free;
end;

procedure TSubitemLifetimeTests.CreateShortcut(const Command: string);
var Item: TCustomItem;
begin
  StackWindow := Manager.InsertItem(TStackItem.Make);
  AssertTrue(Manager.TryGetManagedItem(StackWindow, Item));
  AssertTrue(Item is TStackItem);
  Stack := TStackItem(Item);
  Stack.AddSubitem(TShortcutSubitem.Make('Lifetime probe', Command));
  EnumWindows(@FindSubitem, LPARAM(Self));
  AssertTrue('The real stack must own a shortcut window', IsWindow(SubitemWindow));
  Entered := 0;
  Left := 0;
  ClosePostedInside := False;
end;

procedure TSubitemLifetimeTests.ClickShortcut;
var Item: TCustomSubitem; Rect: Windows.TRect; Position: LPARAM;
begin
  Item := TCustomSubitem(FindItemModel(ItemViews.ItemIdOf(SubitemWindow)));
  Rect := Item.Rect;
  Position := LPARAM(((Rect.Top + 1) shl 16) or (Rect.Left + 1));
  SendMessage(SubitemWindow, WM_LBUTTONDOWN, MK_LBUTTON, Position);
  SendMessage(SubitemWindow, WM_LBUTTONUP, 0, Position);
end;

procedure TSubitemLifetimeTests.ExecuteShortcut(id: HWND; const Command: string);
var Scope: TItemHostScope;
begin
  if Command = '/itemmgr.clear' then Manager.command('clear', '')
  else if Command = '/subitem.delete' then Stack.DeleteSubitem(0)
  else if Command = '/quit' then
  begin
    // Match the command operation, then test its caller's retained scope.
    Scope := BeginItemHostOperation(0);
    try Life.RequestClose;
    finally EndItemHostOperation(Scope); end;
  end
  else if Command = '/raise' then raise Exception.Create('Shortcut callback failed');
  SurvivedCallback := IsWindow(id);
  StackSurvivedCallback := IsWindow(StackWindow);
  CallbackDepth := Life.OperationDepth;
  ClosePostedDuringCallback := ClosePostedInside;
end;

procedure TSubitemLifetimeTests.ClearRetainsStackAndSubitemUntilCallbackReturns;
begin
  CreateShortcut('/itemmgr.clear');
  ClickShortcut;
  AssertTrue('Clear must retain the active shortcut', SurvivedCallback);
  AssertTrue('Clear must retain its owning stack', StackSurvivedCallback);
  AssertTrue('The callback must retain the dock operation', CallbackDepth > 0);
  AssertFalse('The pending stack must be released after dispatch', IsWindow(StackWindow));
  AssertFalse(IsWindow(SubitemWindow));
  AssertEquals(0, Manager.ItemCount);
  AssertEquals(Entered, Left);
  AssertEquals(0, Life.OperationDepth);
end;

procedure TSubitemLifetimeTests.NestedStackDeletionRetainsSubitemUntilCallbackReturns;
begin
  CreateShortcut('/subitem.delete');
  ClickShortcut;
  AssertTrue('Nested deletion must retain the executing subitem', SurvivedCallback);
  AssertTrue(StackSurvivedCallback);
  AssertFalse('The removed subitem must be released after dispatch', IsWindow(SubitemWindow));
  AssertTrue(IsWindow(StackWindow));
  AssertEquals(0, Stack.ItemCount);
  AssertEquals(Entered, Left);
  AssertEquals(0, Life.OperationDepth);
end;

procedure TSubitemLifetimeTests.QuitRemainsPendingUntilSubitemCallbackReturns;
begin
  CreateShortcut('/quit');
  ClickShortcut;
  AssertTrue('Quit must not escape the active subitem operation', CallbackDepth > 0);
  AssertFalse('Quit must stay unposted inside the callback', ClosePostedDuringCallback);
  AssertTrue('The outer return must post deferred close', ClosePostedInside);
  AssertTrue(SurvivedCallback);
  AssertTrue(Life.ClosePending);
  AssertEquals(Entered, Left);
  AssertEquals(0, Life.OperationDepth);
end;

procedure TSubitemLifetimeTests.CallbackFailureReleasesBothPinsAndHostScope;
begin
  CreateShortcut('/raise');
  ClickShortcut;
  AssertEquals(Entered, Left);
  AssertEquals(0, Life.OperationDepth);
  Manager.command('clear', '');
  AssertFalse('The failed callback must release its stack pin', IsWindow(StackWindow));
  AssertFalse('The failed callback must release its subitem pin', IsWindow(SubitemWindow));
end;

procedure TSubitemLifetimeTests.NativeChildDestructionRemovesOnlyItsBucket;
var Id: TItemId;
begin
  CreateShortcut('/probe');
  Id := ItemViews.ItemIdOf(SubitemWindow);
  Stack.AddSubitem(TShortcutSubitem.Make('Surviving child', '/survivor'));
  Windows.DestroyWindow(SubitemWindow);
  AssertEquals('Native destruction must remove its stack bucket', 1, Stack.ItemCount);
  AssertEquals('Surviving child', string(Stack.GetSubitemCaption(0)));
  AssertTrue('Native destruction must release the child model', FindItemModel(Id) = nil);
  Manager.Timer;
  AssertTrue('The surviving child must keep its owner', IsWindow(StackWindow));
end;

procedure TSubitemLifetimeTests.CreateFailingStack;
var Params: TDItemCreateParams;
begin
  Params := Default(TDItemCreateParams);
  Params.ItemSize := 32;
  Params.BigItemSize := 32;
  Params.Parameter := TStackItem.Make;
  Stack := TFailingStack.Create(0, Params);
  StackWindow := Manager.AdoptItem(Stack, false);
  AssertTrue(StackWindow <> 0);
  Stack.AddSubitem(TShortcutSubitem.Make('Existing child', '/existing'));
  FailedChildrenDestroyed := 0;
end;

procedure TSubitemLifetimeTests.CheckFailedAddition(Failure: TSubitemFailure);
begin
  CreateFailingStack;
  SubitemFailure := Failure;
  try
    try Stack.AddSubitem(TShortcutSubitem.Make('Failed child', '/failure'));
    except on Exception do ; end;
  finally
    SubitemFailure := sfNone;
  end;
  AssertEquals('Failed creation must preserve the bucket count', 1, Stack.ItemCount);
  AssertEquals('Existing child', string(Stack.GetSubitemCaption(0)));
  AssertEquals('Failed creation must preserve store ownership', 1, Stack.ChildStore.Count);
  if Failure <> sfAllocation then
  begin
    AssertTrue('Failed creation must release its pending model', FindItemModel(FailedChildId) = nil);
    AssertEquals('Failed creation must destroy its model once', 1, FailedChildrenDestroyed);
  end;
  Stack.AddSubitem(TShortcutSubitem.Make('Next child', '/next'));
  AssertEquals('The stack must accept the next valid child', 2, Stack.ItemCount);
end;

procedure TSubitemLifetimeTests.AllocationFailurePreservesExistingSubitems;
begin
  CheckFailedAddition(sfAllocation);
end;

procedure TSubitemLifetimeTests.NativeCreationFailurePreservesExistingSubitems;
begin
  CheckFailedAddition(sfNative);
end;

procedure TSubitemLifetimeTests.ParseFailurePreservesExistingSubitems;
begin
  CheckFailedAddition(sfParse);
end;

procedure TSubitemLifetimeTests.FreedCreationDoesNotDoubleDecrement;
begin
  CheckFailedAddition(sfFreed);
end;

procedure TSubitemLifetimeTests.RepeatedDeleteKeepsExactlyOneUndoCopy;
var Item: TCustomSubitem; CopyItem: TCustomItem;
begin
  CreateShortcut('/probe');
  Item := TCustomSubitem(FindItemModel(ItemViews.ItemIdOf(SubitemWindow)));
  Item.Delete(true);
  Item.Delete(true);
  AssertEquals('Repeated delete must create one undo copy', 1, CreatedCopies);
  AssertEquals('The manager must own one undo copy', 1, Manager.DeletedCount);
  AssertTrue(Manager.TryGetItemById(CreatedCopyId, CopyItem));
  AssertFalse('Undo copies must stay hidden', IsWindowVisible(CopyItem.Handle));
  Stack.DeleteSubitem(0);
  Manager.UnDelete;
  AssertEquals('Undo must restore the copied shortcut once', 2, Manager.ItemCount);
  AssertEquals(0, Manager.DeletedCount);
end;

procedure TSubitemLifetimeTests.FailedDragAdoptionKeepsSourceAndReleasesCopy;
var Item: TCustomSubitem;
begin
  CreateShortcut('/probe');
  Item := TCustomSubitem(FindItemModel(ItemViews.ItemIdOf(SubitemWindow)));
  RejectDrag := true;
  Item.BeginDrag;
  AssertFalse('Failed drag adoption must retain the source', Item.QueryDelete);
  AssertTrue('Failed drag adoption must keep the source window', IsWindow(SubitemWindow));
  AssertEquals(1, Stack.ItemCount);
  AssertTrue('Failed drag adoption must release its pending copy',
    FindItemModel(CreatedCopyId) = nil);
  AssertFalse(Manager.InteractionSnapshot.DraggingItem);
end;

procedure TSubitemLifetimeTests.SuccessfulDragAdoptionMarksSourceForDeletion;
var Item: TCustomSubitem; CopyItem: TCustomItem;
begin
  CreateShortcut('/probe');
  Item := TCustomSubitem(FindItemModel(ItemViews.ItemIdOf(SubitemWindow)));
  Item.BeginDrag;
  AssertTrue('Successful drag adoption must mark the source', Item.QueryDelete);
  AssertTrue(Manager.TryGetItemById(CreatedCopyId, CopyItem));
  AssertTrue('The manager must own the dragging copy', CopyItem.State = imsDragging);
  AssertFalse('The native test copy must stay hidden', IsWindowVisible(CopyItem.Handle));
  AssertTrue(Manager.InteractionSnapshot.DraggingItem);
end;

procedure TSubitemLifetimeTests.ImageCleanupFailureStillDestroysNativeChild;
var Item: TCleanupShortcut; Params: TDItemCreateParams; wnd: HWND;
begin
  CreateShortcut('/probe');
  Params := Default(TDItemCreateParams);
  Params.ItemSize := 32;
  Item := TCleanupShortcut.Create(StackWindow, Params);
  wnd := Item.Handle;
  RaiseImageCleanup := true;
  try Item.Free;
  except on Exception do ; end;
  AssertFalse('Image cleanup failure must destroy the native view', IsWindow(wnd));
  AssertEquals('Image cleanup failure must still release PIDL resources', 1, PIDLCleanupCalls);
  AssertEquals(1, Stack.ChildStore.Count);
end;

procedure TSubitemLifetimeTests.PIDLCleanupFailureStillDestroysNativeChild;
var Item: TCleanupShortcut; Params: TDItemCreateParams; wnd: HWND;
begin
  CreateShortcut('/probe');
  Params := Default(TDItemCreateParams);
  Params.ItemSize := 32;
  Item := TCleanupShortcut.Create(StackWindow, Params);
  wnd := Item.Handle;
  RaisePIDLCleanup := true;
  try Item.Free;
  except on Exception do ; end;
  AssertFalse('PIDL cleanup failure must destroy the native view', IsWindow(wnd));
  AssertEquals(1, Stack.ChildStore.Count);
end;

procedure TSubitemLifetimeTests.StackViewReplacementPreservesChildrenAndCallbackRouting;
var StackId, ChildId: TItemId; PreviousStack: HWND;
begin
  CreateShortcut('/quit');
  StackId := Stack.ItemId;
  ChildId := ItemViews.ItemIdOf(SubitemWindow);
  PreviousStack := StackWindow;
  Stack.RecreateWindow;
  StackWindow := Stack.Handle;
  AssertTrue('Stack replacement must create a new native window', StackWindow <> PreviousStack);
  AssertFalse(IsWindow(PreviousStack));
  AssertEquals('The stack model identity must remain stable', QWord(StackId), QWord(Stack.ItemId));
  AssertEquals('Stack replacement must preserve child membership', 1, Stack.ItemCount);
  AssertTrue('Stack replacement must retain the child model', Stack.ChildStore.Contains(ChildId));
  AssertEquals('The child must keep its native window', QWord(SubitemWindow),
    QWord(ItemViews.HandleOf(ChildId)));
  AssertEquals('The child window must use the new owner', QWord(StackWindow),
    QWord(GetWindow(SubitemWindow, GW_OWNER)));
  ClickShortcut;
  AssertTrue('Child callbacks must route through the replacement owner', SurvivedCallback);
  AssertTrue(StackSurvivedCallback);
  AssertTrue(CallbackDepth > 0);
  AssertEquals(Entered, Left);
  AssertEquals(0, Life.OperationDepth);
end;

procedure TSubitemLifetimeTests.DeletingOpenStackHidesChildrenAndUndoReopens;
var StackId, ChildId: TItemId; index: integer;
begin
  CreateShortcut('/probe');
  StackId := Stack.ItemId;
  ChildId := ItemViews.ItemIdOf(SubitemWindow);
  index := KeepWindowHidden(SubitemWindow);
  Stack.cmd(gpStackAnimationEnabled, 0);
  Stack.MouseClick(mbLeft, [], 0, 0);
  AssertTrue('Opening a stack must request visible children', HiddenCopies[index].RequestedVisible);
  AssertEquals('Opening a stack must acquire one mouse lock', 1, ActiveMouseLocks);
  Stack.Delete;
  AssertFalse('Deleting an open stack must hide its children', HiddenCopies[index].RequestedVisible);
  AssertFalse('Native fixture windows must stay hidden', IsWindowVisible(SubitemWindow));
  AssertEquals('Stack deletion must release its mouse lock', 0, ActiveMouseLocks);
  AssertEquals(1, Stack.ItemCount);
  AssertTrue(Stack.ChildStore.Contains(ChildId));
  Manager.UnDelete;
  AssertEquals(QWord(StackId), QWord(Stack.ItemId));
  Stack.MouseClick(mbLeft, [], 0, 0);
  AssertTrue('Undo must allow the same stack to reopen', HiddenCopies[index].RequestedVisible);
  AssertEquals(1, ActiveMouseLocks);
  Stack.Delete;
  AssertEquals(0, ActiveMouseLocks);
end;

procedure TSubitemLifetimeTests.LastNativeChildLossReleasesOpenStackLock;
var Item: TCustomItem;
begin
  CreateShortcut('/probe');
  KeepWindowHidden(SubitemWindow);
  Stack.cmd(gpStackAnimationEnabled, 0);
  Stack.MouseClick(mbLeft, [], 0, 0);
  AssertEquals(1, ActiveMouseLocks);
  Windows.DestroyWindow(SubitemWindow);
  AssertEquals(0, Stack.ItemCount);
  AssertEquals('Losing the last child must release the stack lock', 0, ActiveMouseLocks);
  AssertTrue('Native child loss must keep the active stack',
    Manager.TryGetManagedItem(StackWindow, Item));
  AssertEquals(0, Stack.ChildStore.Count);
end;

procedure TSubitemLifetimeTests.AnimatedReopenReleasesExactlyOneStackLock;
var deadline: QWord;
begin
  CreateShortcut('/probe');
  KeepWindowHidden(SubitemWindow);
  Stack.cmd(gpStackAnimationEnabled, 1);
  Stack.MouseClick(mbLeft, [], 0, 0);
  Stack.Timer;
  Stack.MouseClick(mbLeft, [], 0, 0);
  Stack.MouseClick(mbLeft, [], 0, 0);
  Stack.MouseClick(mbLeft, [], 0, 0);
  deadline := GetTickCount64 + 2000;
  while (ActiveMouseLocks <> 0) and (GetTickCount64 < deadline) do
  begin
    Sleep(10);
    Stack.Timer;
  end;
  AssertEquals('A rapid animated reopen must balance its stack lock', 0, ActiveMouseLocks);
  AssertFalse('Native fixture windows must stay hidden', IsWindowVisible(SubitemWindow));
end;

procedure TSubitemLifetimeTests.FailedUndoCopyKeepsSourceAndAllowsRetry;
var Item: TCustomSubitem;
begin
  CreateShortcut('/probe');
  Item := TCustomSubitem(FindItemModel(ItemViews.ItemIdOf(SubitemWindow)));
  CopyCreationFails := true;
  Item.Delete(true);
  AssertFalse('Failed undo-copy creation must keep the source', Item.QueryDelete);
  AssertTrue(IsWindow(SubitemWindow));
  AssertEquals(1, Stack.ItemCount);
  AssertEquals(0, Manager.DeletedCount);
  CopyCreationFails := false;
  CopyLookupFails := true;
  Item.Delete(true);
  AssertFalse('Failed undo-copy lookup must keep the source', Item.QueryDelete);
  AssertEquals(0, Manager.DeletedCount);
  CopyLookupFails := false;
  Item.Delete(true);
  AssertTrue('A failed deletion must allow a later retry', Item.QueryDelete);
  AssertEquals(1, Manager.DeletedCount);
  AssertEquals(1, CreatedCopies);
end;

procedure TSubitemLifetimeTests.RejectedUndoDeletionKeepsSourceAndReleasesPendingCopy;
var Item: TCustomSubitem;
begin
  CreateShortcut('/probe');
  Item := TCustomSubitem(FindItemModel(ItemViews.ItemIdOf(SubitemWindow)));
  Manager.Enable(false);
  Item.Delete(true);
  AssertFalse('Rejected undo deletion must preserve the source', Item.QueryDelete);
  AssertTrue('Rejected undo deletion must release its pending copy',
    FindItemModel(CreatedCopyId) = nil);
  AssertTrue(IsWindow(SubitemWindow));
  AssertEquals(1, Stack.ItemCount);
  AssertEquals(0, Manager.DeletedCount);
  Manager.Enable(true);
  Item.Delete(true);
  AssertTrue('Rejected undo deletion must allow a later retry', Item.QueryDelete);
  AssertEquals(1, Manager.DeletedCount);
  AssertEquals(2, CreatedCopies);
end;

procedure TSubitemLifetimeTests.NativeLossDuringParsingRetainsChildUntilAdditionReturns;
begin
  CreateFailingStack;
  SubitemFailure := sfNativeLossWhileParsing;
  try
    try Stack.AddSubitem(TShortcutSubitem.Make('Retired child', '/retired'));
    except on Exception do ; end;
  finally SubitemFailure := sfNone; end;
  AssertTrue('Native loss must retain the parsing child frame', ParsingChildSurvived);
  AssertEquals('Native loss must not publish the retired child', 1, Stack.ItemCount);
  AssertEquals(1, Stack.ChildStore.Count);
  AssertTrue(FindItemModel(ParsingChildId) = nil);
  AssertEquals(1, FailedChildrenDestroyed);
end;

procedure TSubitemLifetimeTests.ParentDeletionDuringParsingRejectsPendingChild;
begin
  CreateFailingStack;
  SubitemFailure := sfParentDeletionWhileParsing;
  try
    try Stack.AddSubitem(TShortcutSubitem.Make('Rejected child', '/rejected'));
    except on Exception do ; end;
  finally SubitemFailure := sfNone; end;
  AssertEquals('Parent deletion must reject the pending child', 1, Stack.ItemCount);
  AssertEquals(1, Stack.ChildStore.Count);
  AssertTrue(FindItemModel(ParsingChildId) = nil);
  AssertEquals(1, Manager.DeletedCount);
  Manager.UnDelete;
  Stack.AddSubitem(TShortcutSubitem.Make('Next child', '/next'));
  AssertEquals('Undo must leave the stack usable', 2, Stack.ItemCount);
end;

procedure TSubitemLifetimeTests.ParentRetirementDuringParsingRetainsAdditionFrame;
begin
  CreateFailingStack;
  SubitemFailure := sfParentRetirementWhileParsing;
  try
    try Stack.AddSubitem(TShortcutSubitem.Make('Retired child', '/retired'));
    except on Exception do ; end;
  finally
    SubitemFailure := sfNone;
    ReleaseItemModel(ParsingChildLease);
    ParsingChildLease := NO_ITEM_ID;
  end;
  AssertTrue('Parent retirement must retain the addition frame', ParsingParentSurvived);
  AssertTrue('The final parent lease must complete retirement', FindItemModel(ParsingParentId) = nil);
  AssertTrue(FindItemModel(ParsingChildId) = nil);
  AssertEquals(2, FailedChildrenDestroyed);
  AssertEquals(0, Manager.ItemCount);
end;

procedure TSubitemLifetimeTests.ReentrantAdditionRechecksCapacityBeforePublication;
var returned: boolean;
begin
  CreateFailingStack;
  SubitemFailure := sfFillWhileParsing;
  returned := false;
  try
    try
      Stack.AddSubitem(TShortcutSubitem.Make('Outer child', '/outer'));
      returned := true;
    except on Exception do ; end;
  finally SubitemFailure := sfNone; end;
  AssertTrue('Capacity changes must reject the outer addition safely', returned);
  AssertEquals(MAX_SUBITEMS, Stack.ItemCount);
  AssertEquals(MAX_SUBITEMS, Stack.ChildStore.Count);
  AssertTrue('Capacity rejection must release the pending child', FindItemModel(ParsingChildId) = nil);
  AssertEquals(1, FailedChildrenDestroyed);
end;

procedure TSubitemLifetimeTests.BatchFailureRollsBackPublishedChildren;
var Data: TStringList; Rejected: boolean;
begin
  CreateFailingStack;
  Data := TStringList.Create;
  try
    Data.Add(TShortcutSubitem.Make('First child'));
    Data.Add(TShortcutSubitem.Make('Second child'));
    SubitemFailure := sfSecondParse;
    Rejected := False;
    try Stack.AddSubitems(Data); except on Exception do Rejected := True; end;
    SubitemFailure := sfNone;
    AssertTrue(Rejected);
    AssertEquals(1, Stack.ItemCount);
    AssertEquals(1, Stack.ChildStore.Count);
    AssertEquals('Existing child', UTF8Encode(Stack.GetSubitemCaption(0)));
  finally SubitemFailure := sfNone; Data.Free; end;
end;

procedure TSubitemLifetimeTests.FullStackReportsRejectedAddition;
var Index: integer;
begin
  CreateFailingStack;
  for Index := 2 to MAX_SUBITEMS do AssertTrue(Stack.AddSubitem(TShortcutSubitem.Make('Child')));
  AssertFalse(Stack.AddSubitem(TShortcutSubitem.Make('Rejected child')));
  AssertEquals(MAX_SUBITEMS, Stack.ItemCount);
  AssertEquals(MAX_SUBITEMS, Stack.ChildStore.Count);
end;

initialization
  RegisterTest(TSubitemLifetimeTests);
end.
