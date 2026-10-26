unit itemtimingtests;

{$mode delphi}

interface

uses Windows, Messages, Classes, SysUtils, Controls, fpcunit, testregistry, declu,
  customitemu, customsubitemu, scitemu, scsubitemu, stackitemu, itemmgru,
  itemmodelu, itemsettingsu, itemhostu, itemviewu, docklayoutu, tasksyncu, themeu;

type
  TTimingManager = class(TItemManager)
  protected
    function ClockNow: QWord; override;
    function GetCursorPoint(out pt: Windows.TPoint): boolean; override;
  public
    Now: QWord;
    MouseAvailable: boolean;
    MousePoint: Windows.TPoint;
  end;

  TTimingItem = class(TCustomItem)
  protected
    function ClockNow: QWord; override;
  public
    Now: QWord;
    TimerCalls, ForegroundCalls: integer;
    procedure Draw(Ax, Ay, ASize: integer; AForce: boolean; wpi: HDWP; AShowItem: UINT); override;
    procedure WndMessage(var msg: TMessage); override;
    procedure WMCommand(wParam: WPARAM; lParam: LPARAM; var Result: LRESULT); override;
    function ToString: string; override;
    procedure Save(ini, section: string); override;
    procedure Timer; override;
    procedure MarkHintVisible;
    procedure ForegroundChanged(wnd: HWND); override;
  end;

  TItemTimingTests = class(TTestCase)
  private
    Manager: TTimingManager;
    Item: TTimingItem;
    FixtureTheme: TDTheme;
    procedure DeleteThroughHost(wnd: HWND);
    procedure StartZoom;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure StableItemDoesNotReceiveFrames;
    procedure ZoomReversalPreservesCurrentSize;
    procedure DragCompletionReplaysPendingTaskSnapshot;
    procedure IconAnimationUsesElapsedTime;
    procedure DeletionReleasesOwnedHintAndDeadlines;
    procedure TaskHasNoUnusedMaintenanceTimer;
    procedure ForegroundEventReachesActiveItems;
    procedure EarlyHoldMessagePreservesDeadline;
    procedure NativeDragLossReplaysPendingTasks;
    procedure UndoRestoresDynamicIconDeadline;
    procedure ClosingZoomKeepsLegacyRounding;
    procedure DockingUsesElapsedTime;
    procedure ChildDeletionCancelsOwnedDeadline;
    procedure DisablingZoomCollapsesImmediately;
    procedure ChangingZoomSizeRetargetsAnimation;
    procedure ChangingZoomDurationRetargetsAnimation;
  end;

procedure DeactivateHint(wnd: HWND); stdcall;

implementation

var HintDeactivations: integer;

procedure DeactivateHint(wnd: HWND); stdcall;
begin Inc(HintDeactivations); end;

function TTimingManager.ClockNow: QWord;
begin Result := Now; end;
function TTimingManager.GetCursorPoint(out pt: Windows.TPoint): boolean;
begin pt := MousePoint; Result := MouseAvailable; end;

procedure TTimingItem.Draw(Ax, Ay, ASize: integer; AForce: boolean; wpi: HDWP; AShowItem: UINT);
begin FX := Ax; FY := Ay; FSize := ASize; FShowItem := AShowItem; end;
function TTimingItem.ClockNow: QWord;
begin Result := Now; end;
procedure TTimingItem.WndMessage(var msg: TMessage);
begin msg.Result := 0; end;
procedure TTimingItem.WMCommand(wParam: WPARAM; lParam: LPARAM; var Result: LRESULT);
begin Result := 0; end;
function TTimingItem.ToString: string;
begin Result := 'class="separator";'; end;
procedure TTimingItem.Save(ini, section: string);
begin end;
procedure TTimingItem.Timer;
begin Inc(TimerCalls); inherited; end;
procedure TTimingItem.MarkHintVisible;
begin FHintVisible := true; end;
procedure TTimingItem.ForegroundChanged(wnd: HWND);
begin Inc(ForegroundCalls); end;

procedure TItemTimingTests.DeleteThroughHost(wnd: HWND);
begin Manager.DeleteItem(wnd); end;

procedure TItemTimingTests.SetUp;
var Settings: TItemManagerSettings; Params: TDItemCreateParams; Services: TItemHostServices;
begin
  Settings := Default(TItemManagerSettings);
  FixtureTheme := TDTheme(TDTheme.NewInstance);
  theme := FixtureTheme;
  Settings.ItemSize := 32;
  Settings.BigItemSize := 64;
  Settings.ZoomWidth := 4;
  Settings.ZoomTime := 1000;
  Manager := TTimingManager.Create(0, Settings, nil);
  HintDeactivations := 0;
  Manager.Enable(true);
  Params := Default(TDItemCreateParams);
  Params.ItemSize := 32;
  Params.BigItemSize := 64;
  Params.AnimationType := 1;
  Item := TTimingItem.Create(0, Params);
  Manager.AdoptItem(Item);
  Services := Default(TItemHostServices);
  Services.OnDelete := DeleteThroughHost;
  BindItemHost(0, Services);
end;

procedure TItemTimingTests.TearDown;
begin
  UnbindItemHost(0);
  Manager.Free;
  theme := nil;
  FixtureTheme.Free;
end;

procedure TItemTimingTests.StableItemDoesNotReceiveFrames;
begin
  Manager.Timer;
  AssertEquals('A stable item must not receive a frame callback', 0, Item.TimerCalls);
end;

procedure TItemTimingTests.StartZoom;
var Layout: TDockLayoutConfiguration;
begin
  Layout := Default(TDockLayoutConfiguration);
  Layout.MonitorRect := Rect(-20000, -21000, -10000, -20000);
  Manager.ConfigureLayout(Layout);
  Manager.SetParam(gpSite, Ord(bsBottom));
  Manager.SetParam(gpCenterOffsetPercent, 0);
  Manager.SetParam(gpZoomEnabled, 1);
  Manager.Visible := true;
  Manager.MouseAvailable := true;
  Manager.MousePoint := Point(Item.X + 16, Item.Y + 16);
  Manager.Now := 1000;
  Manager.WHMouseMove(Manager.MousePoint);
end;

procedure TItemTimingTests.ZoomReversalPreservesCurrentSize;
var Before: integer;
begin
  StartZoom;
  Manager.Now := 1250;
  Manager.Timer;
  Before := Item.Size - 32;
  AssertTrue('Opening must reach an intermediate size', (Before > 0) and (Before < 32));
  Manager.MousePoint := Point(-30000, -30000);
  Manager.WHMouseMove(Manager.MousePoint);
  Manager.Now := 1260;
  Manager.Timer;
  AssertTrue('Reversing zoom must not increase icon size', Item.Size - 32 <= Before);
end;

procedure TItemTimingTests.DragCompletionReplaysPendingTaskSnapshot;
var Task: TCustomItem; Windows: TTaskWindows;
begin
  AssertTrue(Manager.TryGetManagedItem(Manager.CreateTaskItem, Task));
  Manager.AdoptItem(Task);
  Manager.Undock(Item.Handle);
  Windows := nil;
  Manager.SynchronizeTasks(Windows);
  AssertTrue('The item drag must remain active', Manager.InteractionSnapshot.DraggingItem);
  AssertEquals('Task removal waits during dragging', 1, Manager.ItemCount);
  Manager.Dock(Item.Handle);
  AssertEquals('Drag completion must replay the pending task removal', 1, Manager.ItemCount);
end;

procedure TItemTimingTests.IconAnimationUsesElapsedTime;
begin
  Item.cmd(gpItemAnimationType, 1);
  Item.Now := 1000;
  Item.Animate;
  AssertTrue('Animation must request frames', Manager.NeedsFrames);
  Item.Now := 1600;
  Manager.Timer;
  AssertFalse('A delayed frame must complete the animation', Item.NeedsFrame);
end;

procedure TItemTimingTests.DeletionReleasesOwnedHintAndDeadlines;
begin
  Item.MarkHintVisible;
  ItemViews.SetItemTimer(Item.ItemId, ID_TIMER_MOUSEHELD, 1000);
  Manager.DeleteItem(Item.Handle);
  AssertEquals('Deletion must close the owned hint', 1, HintDeactivations);
  AssertFalse('Deletion must cancel internal deadlines',
    ItemViews.ConsumeItemTimer(Item.ItemId, ID_TIMER_MOUSEHELD, GetTickCount64 + 2000));
end;

procedure TItemTimingTests.TaskHasNoUnusedMaintenanceTimer;
var Task: TCustomItem;
begin
  AssertTrue(Manager.TryGetManagedItem(Manager.CreateTaskItem, Task));
  Manager.AdoptItem(Task);
  AssertFalse('A task must not schedule an unused maintenance timer',
    ItemViews.ConsumeItemTimer(Task.ItemId, ID_TIMER, GetTickCount64 + 2000));
end;

procedure TItemTimingTests.ForegroundEventReachesActiveItems;
begin
  Manager.ForegroundChanged(77);
  AssertEquals('Foreground events must reach active items', 1, Item.ForegroundCalls);
  Manager.DeleteItem(Item.Handle);
  Manager.ForegroundChanged(88);
  AssertEquals('Deleted items must not receive foreground events', 1, Item.ForegroundCalls);
end;

procedure TItemTimingTests.EarlyHoldMessagePreservesDeadline;
begin
  Item.MouseDown(mbLeft, [], 0, 0);
  SendMessage(Item.Handle, WM_TIMER, ID_TIMER_MOUSEHELD, 0);
  AssertTrue('An early native message must preserve the current hold deadline',
    ItemViews.ConsumeItemTimer(Item.ItemId, ID_TIMER_MOUSEHELD, GetTickCount64 + 2000));
end;

procedure TItemTimingTests.NativeDragLossReplaysPendingTasks;
var Task: TCustomItem; Snapshot: TTaskWindows;
begin
  AssertTrue(Manager.TryGetManagedItem(Manager.CreateTaskItem, Task));
  Manager.AdoptItem(Task);
  Manager.Undock(Item.Handle);
  Snapshot := nil;
  Manager.SynchronizeTasks(Snapshot);
  AssertTrue(Windows.DestroyWindow(Item.Handle));
  AssertEquals('Native drag loss must replay pending tasks', 0, Manager.ItemCount);
  Item := nil;
end;

procedure TItemTimingTests.UndoRestoresDynamicIconDeadline;
var Dynamic: TCustomItem; wnd: HWND;
begin
  wnd := Manager.InsertItem(TShortcutItem.Make('Dynamic', '', '', '', '{LANGID}.png'));
  AssertTrue(Manager.TryGetManagedItem(wnd, Dynamic));
  Manager.DeleteItem(wnd);
  Manager.UnDelete;
  AssertTrue('Undo must restore the dynamic icon deadline',
    ItemViews.ConsumeItemTimer(Dynamic.ItemId, ID_TIMER_UPDATE_SHORTCUT, GetTickCount64 + 2000));
end;

procedure TItemTimingTests.ClosingZoomKeepsLegacyRounding;
begin
  StartZoom;
  Manager.Now := 2000;
  Manager.Timer;
  Manager.MousePoint := Point(-30000, -30000);
  Manager.WHMouseMove(Manager.MousePoint);
  Manager.Now := 2001;
  Manager.Timer;
  AssertEquals('Closing zoom must retain the previous integer rounding', 64, Item.Size);
end;

procedure TItemTimingTests.DockingUsesElapsedTime;
begin
  Item.Now := 1000;
  Item.Undock;
  Item.Dock;
  AssertTrue('Docking must request frames', Item.NeedsFrame);
  Item.Now := 1100;
  Manager.Timer;
  AssertFalse('Docking must complete after its elapsed duration', Item.NeedsFrame);
end;

procedure TItemTimingTests.ChildDeletionCancelsOwnedDeadline;
var Parent: TCustomItem; Stack: TStackItem; Child: TCustomSubitem; Ids: TItemIds;
begin
  AssertTrue(Manager.TryGetManagedItem(Manager.InsertItem(TStackItem.Make('Parent')), Parent));
  Stack := TStackItem(Parent);
  AssertTrue(Stack.AddSubitem(TShortcutSubitem.Make('Child')));
  Ids := Stack.ChildStore.Snapshot;
  Child := TCustomSubitem(Stack.ChildStore.Find(Ids[0]));
  ItemViews.SetItemTimer(Child.ItemId, ID_TIMER_MOUSEHELD, 1000);
  Child.Delete(false);
  AssertFalse('Child deletion must cancel its hold deadline',
    ItemViews.ConsumeItemTimer(Child.ItemId, ID_TIMER_MOUSEHELD, GetTickCount64 + 2000));
end;

procedure TItemTimingTests.DisablingZoomCollapsesImmediately;
begin
  StartZoom;
  Manager.Now := 1500;
  Manager.Timer;
  Manager.SetParam(gpZoomEnabled, 0);
  AssertEquals('Disabling zoom must collapse expanded items', 32, Item.Size);
  AssertFalse('Disabling zoom must clear its interaction state', Manager.InteractionSnapshot.Zooming);
  AssertFalse('Disabled zoom must not retain a frame subscription', Manager.NeedsFrames);
end;

procedure TItemTimingTests.ChangingZoomSizeRetargetsAnimation;
begin
  StartZoom;
  Manager.Now := 2000;
  Manager.Timer;
  Manager.SetParam(gpBigItemSize, 96);
  Manager.Now := 3000;
  Manager.Timer;
  AssertEquals('A changed zoom size must become the new endpoint', 96, Item.Size);
  AssertFalse('The changed endpoint must finish its frame subscription', Manager.NeedsFrames);
end;

procedure TItemTimingTests.ChangingZoomDurationRetargetsAnimation;
begin
  StartZoom;
  Manager.Now := 1250;
  Manager.Timer;
  Manager.SetParam(gpZoomTime, 100);
  Manager.Now := 1350;
  Manager.Timer;
  AssertEquals('A changed zoom duration must apply to the remaining movement', 64, Item.Size);
end;

initialization
  RegisterTest(TItemTimingTests);
end.
