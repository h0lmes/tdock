unit itemtimingtests;

{$mode delphi}

interface

uses Windows, Messages, Classes, SysUtils, Controls, Math, fpcunit, testregistry, declu,
  customitemu, customdrawitemu, customsubitemu, scitemu, scsubitemu, stackitemu, itemmgru,
  itemmodelu, itemsettingsu, itemhostu, itemviewu, docklayoutu, tasksyncu, themeu,
  animationcurveu, gfx, docktimingu;

type
  TTimingManager = class(TItemManager)
  protected
    function ClockNow: QWord; override;
    function MotionNow: Double; override;
    function GetCursorPoint(out pt: Windows.TPoint): boolean; override;
    function FinishPositionBatch(Batch: HDWP): boolean; override;
  public
    Now: Double;
    MouseAvailable: boolean;
    MousePoint: Windows.TPoint;
    BatchFailures: integer;
  end;

  TTimingItem = class(TCustomItem)
  protected
    function ClockNow: QWord; override;
    function MotionNow: Double; override;
  public
    Now: Double;
    TimerCalls, ForegroundCalls, DrawCalls: integer;
    ReenterOnTimer, ReenterOnDraw: TTimingManager;
    RaiseAfterTimer, RaiseAfterDraw: Boolean;
    function AnimationPhase: Double;
    function DockPosition: Double;
    function DockVelocity: Double;
    procedure Draw(Ax, Ay, ASize: integer; AForce: boolean; wpi: HDWP; AShowItem: UINT); override;
    procedure WndMessage(var msg: TMessage); override;
    procedure WMCommand(wParam: WPARAM; lParam: LPARAM; var Result: LRESULT); override;
    function ToString: string; override;
    procedure Save(ini, section: string); override;
    procedure Timer; override;
    procedure MarkHintVisible;
    procedure ForegroundChanged(wnd: HWND); override;
  end;

  TTimingDrawItem = class(TCustomDrawItem)
  protected
    function CreateDrawSurface(var Bitmap: _SimpleBitmap): boolean; override;
    function CreateDrawGraphics(DC: HDC): Pointer; override;
    function PaintDrawImage(Graphics, Attributes: Pointer; X, Y, Size: integer): boolean; override;
    function PresentDrawSurface(const Bitmap: _SimpleBitmap; Alpha: integer): boolean; override;
    function MoveDrawWindow(var Batch: HDWP; X, Y: integer; Flags: UINT): boolean; override;
    function MotionNow: Double; override;
  public
    Now: Double;
    SurfaceCreations: integer;
    SurfaceFailures, GraphicsFailures, ImageFailures, UploadFailures, MoveFailures: integer;
    UploadCalls, MoveCalls: integer;
    procedure DrawPhase(Phase: Double);
    function NativePixelsValid: boolean;
    procedure WndMessage(var msg: TMessage); override;
    procedure WMCommand(wParam: WPARAM; lParam: LPARAM; var Result: LRESULT); override;
    function ToString: string; override;
    procedure Save(ini, section: string); override;
  end;

  TItemTimingTests = class(TTestCase)
  private
    Manager: TTimingManager;
    Item: TTimingItem;
    FixtureTheme: TDTheme;
    procedure DeleteThroughHost(wnd: HWND);
    procedure StartZoom;
    function AddDrawable: TTimingDrawItem;
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
    procedure ClickAnimationKeepsReferenceDuration;
    procedure ClickAnimationHasContinuousPhases;
    procedure HoverCenterChangesRequestOneFrame;
    procedure MotionAndZoomDrawOncePerFrame;
    procedure ClickChoicesRetainContinuousCurves;
    procedure DragReturnPreservesReleaseVelocity;
    procedure DragReturnRetargetKeepsPositionAndVelocity;
    procedure ClickPhasesMatchAt60And120Hz;
    procedure QuakeRedrawKeepsNativeResourcesStable;
    procedure ClickFramesReuseTheirBitmap;
    procedure ExpandedHoverInputCoalescesFrames;
    procedure HoverSpringMatchesAt60And120Hz;
    procedure DragSpringMatchesAt60And120Hz;
    procedure HoverStartsWithSpringAcceleration;
    procedure LateDragFrameReachesDockTarget;
    procedure NestedTimerFrameDoesNotRepeatItemCallbacks;
    procedure NestedDrawFrameDoesNotRepeatItemCallbacks;
    procedure DeletionCancelsPendingMotionBeforeUndo;
    procedure QueuedOffsetAndClickShareOneDrawingPass;
    procedure QueueingCurrentOffsetCancelsObsoleteMotion;
    procedure DirectOffsetWriteDiscardsQueuedMotion;
    procedure CallbackFailureFlushesQueuedGeometryAndRedraws;
    procedure HoverSettlesAtNativePixelPrecision;
    procedure HoverRetargetPreservesContinuousMomentum;
    procedure SurfaceFailureRetriesUntilSuccess;
    procedure GraphicsFailureRetriesUntilSuccess;
    procedure TerminalClickUploadRetriesUntilSuccess;
    procedure TerminalDragUploadRetriesUntilSuccess;
    procedure PositionFailureRetriesUntilSuccess;
    procedure FailedPositionBatchRetriesEveryAffectedItem;
    procedure FailedDeferredPositionRetriesEveryAffectedItem;
    procedure ImageRenderFailureRetriesUntilSuccess;
    procedure RepeatedUploadFailuresReuseResourcesAndReleaseLeases;
    procedure DeletionCancelsFailedNativePresentation;
    procedure HiddenUnpresentedItemMovesInBatch;
    procedure HiddenForcedResizeMovesWithoutUploading;
  end;

procedure DeactivateHint(wnd: HWND); stdcall;

implementation

var HintDeactivations: integer;

procedure DeactivateHint(wnd: HWND); stdcall;
begin Inc(HintDeactivations); end;

function TTimingManager.ClockNow: QWord;
begin Result := Trunc(Now); end;
function TTimingManager.MotionNow: Double;
begin Result := Now; end;
function TTimingManager.GetCursorPoint(out pt: Windows.TPoint): boolean;
begin pt := MousePoint; Result := MouseAvailable; end;
function TTimingManager.FinishPositionBatch(Batch: HDWP): boolean;
begin
  Result := inherited;
  if BatchFailures > 0 then
  begin Dec(BatchFailures); Result := false; end;
end;

procedure TTimingItem.Draw(Ax, Ay, ASize: integer; AForce: boolean; wpi: HDWP; AShowItem: UINT);
var Reentry: TTimingManager;
begin
  Inc(DrawCalls);
  FX := Ax; FY := Ay; FSize := ASize; FShowItem := AShowItem;
  Reentry := ReenterOnDraw;
  ReenterOnDraw := nil;
  if Assigned(Reentry) then Reentry.Timer;
  if RaiseAfterDraw then
  begin
    RaiseAfterDraw := false;
    raise Exception.Create('Injected item draw failure');
  end;
end;
function TTimingItem.AnimationPhase: Double;
begin Result := FAnimationProgress; end;
function TTimingItem.DockPosition: Double;
begin Result := FDockingXAnimation.ValueAt(Now); end;
function TTimingItem.DockVelocity: Double;
begin Result := FDockingXAnimation.VelocityAt(Now); end;
function TTimingItem.ClockNow: QWord;
begin Result := Trunc(Now); end;
function TTimingItem.MotionNow: Double;
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
var Reentry: TTimingManager;
begin
  Inc(TimerCalls);
  Reentry := ReenterOnTimer;
  ReenterOnTimer := nil;
  if Assigned(Reentry) then Reentry.Timer;
  inherited;
  if RaiseAfterTimer then
  begin
    RaiseAfterTimer := false;
    raise Exception.Create('Injected item timer failure');
  end;
end;
procedure TTimingItem.MarkHintVisible;
begin FHintVisible := true; end;
procedure TTimingItem.ForegroundChanged(wnd: HWND);
begin Inc(ForegroundCalls); end;

procedure TTimingDrawItem.DrawPhase(Phase: Double);
begin
  FItemAnimationType := 5;
  FAnimationProgress := Phase;
  Draw(-20000, -20000, 32, true, 0, 0);
end;
function TTimingDrawItem.NativePixelsValid: boolean;
begin Result := FNativePresentationValid; end;
function TTimingDrawItem.CreateDrawSurface(var Bitmap: _SimpleBitmap): boolean;
begin
  Inc(SurfaceCreations);
  if SurfaceFailures > 0 then
  begin Dec(SurfaceFailures); exit(false); end;
  Result := inherited;
end;
function TTimingDrawItem.CreateDrawGraphics(DC: HDC): Pointer;
begin
  if GraphicsFailures > 0 then
  begin Dec(GraphicsFailures); exit(nil); end;
  Result := inherited;
end;
function TTimingDrawItem.PaintDrawImage(Graphics, Attributes: Pointer; X, Y, Size: integer): boolean;
begin
  if ImageFailures > 0 then
  begin Dec(ImageFailures); exit(false); end;
  Result := inherited;
end;
function TTimingDrawItem.PresentDrawSurface(const Bitmap: _SimpleBitmap; Alpha: integer): boolean;
begin
  Inc(UploadCalls);
  if UploadFailures > 0 then
  begin Dec(UploadFailures); exit(false); end;
  Result := inherited;
end;
function TTimingDrawItem.MoveDrawWindow(var Batch: HDWP; X, Y: integer; Flags: UINT): boolean;
begin
  Inc(MoveCalls);
  if MoveFailures > 0 then
  begin
    Dec(MoveFailures);
    if Batch <> 0 then
    begin EndDeferWindowPos(Batch); Batch := 0; end;
    exit(false);
  end;
  Result := inherited;
end;
function TTimingDrawItem.MotionNow: Double;
begin Result := Now; end;
procedure TTimingDrawItem.WndMessage(var msg: TMessage);
begin msg.Result := 0; end;
procedure TTimingDrawItem.WMCommand(wParam: WPARAM; lParam: LPARAM; var Result: LRESULT);
begin Result := 0; end;
function TTimingDrawItem.ToString: string;
begin Result := ''; end;
procedure TTimingDrawItem.Save(ini, section: string);
begin end;

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

function TItemTimingTests.AddDrawable: TTimingDrawItem;
var Params: TDItemCreateParams; Layout: TDockLayoutConfiguration;
begin
  Layout := Default(TDockLayoutConfiguration);
  Layout.MonitorRect := Rect(-20000, -21000, -10000, -20000);
  Manager.ConfigureLayout(Layout);
  Manager.Visible := true;
  Params := Default(TDItemCreateParams);
  Params.ItemSize := 32;
  Params.BigItemSize := 64;
  Params.AnimationType := 1;
  Result := TTimingDrawItem.Create(0, Params);
  Manager.AdoptItem(Result);
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
  AssertTrue('Reversing zoom must preserve nearby spring position', Abs(Item.Size - 32 - Before) <= 2);
  Manager.Now := 6000;
  Manager.Timer;
  AssertEquals('Reversing zoom must eventually collapse', 32, Item.Size);
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
  Item.Now := 2000;
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
  Manager.Now := 6000;
  Manager.Timer;
  Manager.MousePoint := Point(-30000, -30000);
  Manager.WHMouseMove(Manager.MousePoint);
  Manager.Now := 6001;
  Manager.Timer;
  AssertEquals('Closing zoom must retain the previous integer rounding', 64, Item.Size);
end;

procedure TItemTimingTests.DockingUsesElapsedTime;
begin
  Item.Now := 1000;
  Item.Undock;
  Item.Dock;
  AssertTrue('Docking must request frames', Item.NeedsFrame);
  Item.Now := 2000;
  Manager.Timer;
  AssertFalse('Docking must complete after its spring settles', Item.NeedsFrame);
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
  Manager.Now := 6000;
  Manager.Timer;
  Manager.SetParam(gpBigItemSize, 96);
  Manager.Now := 11000;
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
  Manager.Now := 1750;
  Manager.Timer;
  AssertEquals('A changed zoom duration must apply to the remaining movement', 64, Item.Size);
end;

procedure TItemTimingTests.ClickAnimationKeepsReferenceDuration;
begin
  Item.cmd(gpItemAnimationType, 1);
  Item.Now := 1000;
  Item.Animate;
  Item.Now := 1600;
  Manager.Timer;
  AssertTrue('Rotation must retain its 937.5 ms reference duration', Item.NeedsFrame);
end;

procedure TItemTimingTests.ClickAnimationHasContinuousPhases;
begin
  Item.cmd(gpItemAnimationType, 1);
  Item.Now := 1000;
  Item.Animate;
  Item.Now := 1008;
  Manager.Timer;
  AssertEquals('Click phases must keep fractional frame progress', 0.512,
    Item.AnimationPhase, 0.00001);
end;

procedure TItemTimingTests.HoverCenterChangesRequestOneFrame;
var Before: integer;
begin
  StartZoom;
  Manager.Now := 1100;
  Manager.Timer;
  Before := Item.DrawCalls;
  Manager.MousePoint := Point(Item.X + Item.Size div 2 + 3, Item.Y + 16);
  Manager.WHMouseMove(Manager.MousePoint);
  AssertEquals('Mouse input must defer its drawing until the next frame', Before, Item.DrawCalls);
  Manager.Timer;
  AssertEquals('A changed center must draw despite unchanged rounded extent', Before + 1, Item.DrawCalls);
end;

procedure TItemTimingTests.MotionAndZoomDrawOncePerFrame;
var Before: integer;
begin
  StartZoom;
  Item.cmd(gpItemAnimationType, 1);
  Item.Now := 1000;
  Item.Animate;
  Before := Item.DrawCalls;
  Manager.Now := 1250;
  Item.Now := 1250;
  Manager.Timer;
  AssertEquals('Layout and click motion must share one drawing pass', Before + 1, Item.DrawCalls);
end;

procedure TItemTimingTests.ClickChoicesRetainContinuousCurves;
var Value: TClickAnimationValues;
begin
  Value := ClickAnimationValues(1, 7.5, 20, 32);
  AssertEquals('Rotation must preserve a fractional angle', 45.0, Value.Rotation, 0.00001);
  Value := ClickAnimationValues(2, 7.5, 20, 32);
  AssertEquals('Bounce must interpolate the existing table', (0.8453 + 0.8984) * 10,
    Value.Bounce, 0.00001);
  Value := ClickAnimationValues(5, 7.5, 20, 32);
  AssertTrue('Quake must move at fractional phases', Abs(Value.OffsetX) + Abs(Value.OffsetY) > 0.1);
  Value := ClickAnimationValues(6, 7.5, 20, 32);
  AssertTrue('Swing must retain the visible slow oscillation', Abs(Value.Rotation) > 10);
  Value := ClickAnimationValues(7, 20 / 3, 20, 32);
  AssertEquals('Vibrate must use a visible 12 Hz oscillator', 6.0, Value.SizeDelta, 0.00001);
  Value := ClickAnimationValues(8, 7.5, 20, 32);
  AssertTrue('Zoom must retain its slow oscillator', Abs(Value.SizeDelta) > 3);
end;

procedure TItemTimingTests.DragReturnPreservesReleaseVelocity;
begin
  Item.Draw(500, 600, 32, false, 0, 0);
  SetWindowPos(Item.Handle, 0, 480, 580, 0, 0, SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE);
  Item.Now := 1000;
  Item.Undock;
  Item.Now := 1016;
  SetWindowPos(Item.Handle, 0, 520, 580, 0, 0, SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE);
  Item.Dock;
  AssertEquals('Drag return must retain measured release velocity', 2500.0, Item.DockVelocity, 0.0001);
end;

procedure TItemTimingTests.DragReturnRetargetKeepsPositionAndVelocity;
var Position, Velocity: Double;
begin
  Item.Draw(500, 600, 32, false, 0, 0);
  SetWindowPos(Item.Handle, 0, 680, 580, 0, 0, SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE);
  Item.Now := 1000;
  Item.Undock;
  Item.Dock;
  Item.Now := 1050;
  Item.Timer;
  Position := Item.DockPosition;
  Velocity := Item.DockVelocity;
  Item.SetDockTarget(800, 600);
  AssertEquals('Live targets must preserve spring position', Position, Item.DockPosition, 0.00001);
  AssertEquals('Live targets must preserve spring velocity', Velocity, Item.DockVelocity, 0.00001);
end;

procedure TItemTimingTests.ClickPhasesMatchAt60And120Hz;
var Step: integer; At60: Double;
begin
  Item.cmd(gpItemAnimationType, 1);
  Item.Now := 1000;
  Item.Animate;
  for Step := 1 to 30 do
  begin
    Item.Now := 1000 + Step * 1000 / 60;
    Manager.Timer;
  end;
  At60 := Item.AnimationPhase;
  Item.Now := 1000;
  Item.Animate;
  for Step := 1 to 60 do
  begin
    Item.Now := 1000 + Step * 1000 / 120;
    Manager.Timer;
  end;
  AssertEquals('Equal elapsed time must produce equal phases', At60, Item.AnimationPhase, 0.000001);
end;

function GetGuiResources(Process: THandle; Flags: DWORD): DWORD; stdcall;
  external 'user32.dll' name 'GetGuiResources';

procedure TItemTimingTests.QuakeRedrawKeepsNativeResourcesStable;
var Drawable: TTimingDrawItem; Params: TDItemCreateParams; Before: DWORD; Index: integer;
begin
  Params := Default(TDItemCreateParams);
  Params.ItemSize := 32;
  Params.BigItemSize := 64;
  Drawable := TTimingDrawItem.Create(0, Params);
  try
    Drawable.DrawPhase(1);
    Before := GetGuiResources(GetCurrentProcess, 0);
    for Index := 1 to 200 do Drawable.DrawPhase(1 + Index / 8);
    AssertEquals('Quake redraws must release native drawing resources', Before,
      GetGuiResources(GetCurrentProcess, 0));
  finally
    Drawable.Free;
  end;
end;

procedure TItemTimingTests.ClickFramesReuseTheirBitmap;
var Drawable: TTimingDrawItem; Params: TDItemCreateParams; Before: DWORD;
begin
  Params := Default(TDItemCreateParams);
  Params.ItemSize := 32;
  Params.BigItemSize := 64;
  Before := GetGuiResources(GetCurrentProcess, 0);
  Drawable := TTimingDrawItem.Create(0, Params);
  try
    Drawable.DrawPhase(1);
    Drawable.DrawPhase(1.5);
    AssertEquals('Equal-sized animation frames must reuse their bitmap', 1, Drawable.SurfaceCreations);
  finally
    Drawable.Free;
  end;
  AssertEquals('Item destruction must release its cached bitmap', Before,
    GetGuiResources(GetCurrentProcess, 0));
end;

procedure TItemTimingTests.ExpandedHoverInputCoalescesFrames;
var Before, Index: integer;
begin
  StartZoom;
  Manager.Now := 6000;
  Manager.Timer;
  AssertFalse('Settled hover must stop frame callbacks', Manager.NeedsFrames);
  Before := Item.DrawCalls;
  for Index := 1 to 3 do
  begin
    Manager.MousePoint := Point(Item.X + Item.Size div 2 + Index, Item.Y + 16);
    Manager.WHMouseMove(Manager.MousePoint);
  end;
  AssertEquals('Mouse input must wait for the frame', Before, Item.DrawCalls);
  AssertTrue('Changed hover position must request a frame', Manager.NeedsFrames);
  Manager.Timer;
  AssertEquals('Several mouse movements must share one drawing pass', Before + 1, Item.DrawCalls);
  AssertFalse('The completed input frame must stop callbacks', Manager.NeedsFrames);
end;

procedure TItemTimingTests.HoverSpringMatchesAt60And120Hz;
var Step, At60: integer;
begin
  StartZoom;
  for Step := 1 to 30 do
  begin
    Manager.Now := 1000 + Step * 1000 / 60;
    Manager.Timer;
  end;
  At60 := Item.Size;
  Manager.SetParam(gpZoomEnabled, 0);
  Manager.Now := 1000;
  StartZoom;
  for Step := 1 to 60 do
  begin
    Manager.Now := 1000 + Step * 1000 / 120;
    Manager.Timer;
  end;
  AssertEquals('Hover size must depend on elapsed time', At60, Item.Size);
end;

procedure TItemTimingTests.DragSpringMatchesAt60And120Hz;
var Step: integer; At60: Double;
  procedure StartReturn;
  begin
    Item.Draw(500, 600, 32, false, 0, 0);
    SetWindowPos(Item.Handle, 0, 680, 580, 0, 0, SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE);
    Item.Now := 1000;
    Item.Undock;
    Item.Dock;
  end;
begin
  StartReturn;
  for Step := 1 to 6 do
  begin
    Item.Now := 1000 + Step * 1000 / 60;
    Item.Timer;
  end;
  At60 := Item.DockPosition;
  StartReturn;
  for Step := 1 to 12 do
  begin
    Item.Now := 1000 + Step * 1000 / 120;
    Item.Timer;
  end;
  AssertEquals('Drag return must depend on elapsed time', At60, Item.DockPosition, 0.000001);
end;

procedure TItemTimingTests.HoverStartsWithSpringAcceleration;
begin
  StartZoom;
  Manager.Now := 1100;
  Manager.Timer;
  AssertEquals('Hover must accelerate from rest', 35, Item.Size);
end;

procedure TItemTimingTests.SurfaceFailureRetriesUntilSuccess;
var Drawable: TTimingDrawItem; Uploads: integer;
begin
  Drawable := AddDrawable;
  Uploads := Drawable.UploadCalls;
  Drawable.SurfaceFailures := 1;
  Drawable.Draw(Drawable.X, Drawable.Y, 33, true, 0, 0);
  AssertTrue('A failed surface must retain a frame request', Drawable.NeedsFrame);
  Manager.Timer;
  AssertEquals('The next frame must upload the recovered surface', Uploads + 1, Drawable.UploadCalls);
  AssertFalse('Recovery must stop frame requests', Drawable.NeedsFrame);
end;

procedure TItemTimingTests.GraphicsFailureRetriesUntilSuccess;
var Drawable: TTimingDrawItem; Uploads: integer;
begin
  Drawable := AddDrawable;
  Drawable.Draw(Drawable.X, Drawable.Y, 32, true, 0, 0);
  Uploads := Drawable.UploadCalls;
  Drawable.GraphicsFailures := 1;
  Drawable.Draw(Drawable.X, Drawable.Y, 32, true, 0, 0);
  AssertTrue('A failed graphics context must retain a frame request', Drawable.NeedsFrame);
  Manager.Timer;
  AssertEquals('The next frame must upload after graphics recovery', Uploads + 1, Drawable.UploadCalls);
  AssertFalse('Recovery must stop frame requests', Drawable.NeedsFrame);
end;

procedure TItemTimingTests.TerminalClickUploadRetriesUntilSuccess;
var Drawable: TTimingDrawItem; Uploads: integer;
begin
  Drawable := AddDrawable;
  Drawable.cmd(gpItemAnimationType, 1);
  Drawable.Now := 1000;
  Drawable.Animate;
  Drawable.Now := 1100;
  Manager.Timer;
  Uploads := Drawable.UploadCalls;
  Drawable.UploadFailures := 1;
  Drawable.Now := 3000;
  Manager.Timer;
  AssertTrue('A failed terminal click frame must remain pending', Drawable.NeedsFrame);
  Manager.Timer;
  AssertEquals('The terminal click frame must retry its upload', Uploads + 2, Drawable.UploadCalls);
  AssertFalse('Successful upload must stop frame requests', Drawable.NeedsFrame);
end;

procedure TItemTimingTests.TerminalDragUploadRetriesUntilSuccess;
var Drawable: TTimingDrawItem; Uploads: integer;
begin
  Drawable := AddDrawable;
  Drawable.Draw(Drawable.X, Drawable.Y, 32, true, 0, 0);
  Drawable.Now := 1000;
  Drawable.Undock;
  SetWindowPos(Drawable.Handle, 0, -19000, -19000, 0, 0,
    SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE);
  Drawable.Dock;
  Uploads := Drawable.UploadCalls;
  Drawable.UploadFailures := 1;
  Drawable.Now := 3000;
  Manager.Timer;
  AssertTrue('A failed terminal drag frame must remain pending', Drawable.NeedsFrame);
  Manager.Timer;
  AssertEquals('The terminal drag frame must retry its upload', Uploads + 2, Drawable.UploadCalls);
  AssertFalse('Successful upload must stop frame requests', Drawable.NeedsFrame);
end;

procedure TItemTimingTests.PositionFailureRetriesUntilSuccess;
var Drawable: TTimingDrawItem; Moves: integer;
begin
  Drawable := AddDrawable;
  Drawable.Draw(-20000, -20000, 32, true, 0, 0);
  Moves := Drawable.MoveCalls;
  Drawable.MoveFailures := 1;
  Drawable.Draw(-19990, -20000, 32, false, 0, 0);
  AssertTrue('A failed position update must retain a frame request', Drawable.NeedsFrame);
  Manager.Timer;
  AssertFalse('The recovered position must stop frame requests', Drawable.NeedsFrame);
  AssertTrue('Recovery must issue another native update',
    (Drawable.MoveCalls > Moves + 1) or (Drawable.UploadCalls > 1));
end;

procedure TItemTimingTests.FailedPositionBatchRetriesEveryAffectedItem;
var First, Second: TTimingDrawItem; FirstUploads, SecondUploads: integer;
begin
  First := AddDrawable;
  Second := AddDrawable;
  FirstUploads := First.UploadCalls;
  SecondUploads := Second.UploadCalls;
  Manager.BatchFailures := 1;
  Manager.QueueWndOffset(20);
  Manager.Timer;
  AssertTrue('A failed batch must retain the first item', First.NeedsFrame);
  AssertTrue('A failed batch must retain the second item', Second.NeedsFrame);
  AssertEquals('The first model lease must end after batch failure', 0, First.PinCount);
  AssertEquals('The second model lease must end after batch failure', 0, Second.PinCount);
  Manager.Timer;
  AssertEquals('The first item must upload on retry', FirstUploads + 1, First.UploadCalls);
  AssertEquals('The second item must upload on retry', SecondUploads + 1, Second.UploadCalls);
  AssertFalse('A recovered batch must stop frames', Manager.NeedsFrames);
end;

procedure TItemTimingTests.FailedDeferredPositionRetriesEveryAffectedItem;
var First, Second: TTimingDrawItem;
begin
  First := AddDrawable;
  Second := AddDrawable;
  Second.MoveFailures := 1;
  Manager.QueueWndOffset(20);
  Manager.Timer;
  AssertTrue('A failed defer must retain earlier batch items', First.NeedsFrame);
  AssertTrue('A failed defer must retain its own item', Second.NeedsFrame);
  Manager.Timer;
  AssertFalse('A recovered defer must stop frames', Manager.NeedsFrames);
end;

procedure TItemTimingTests.ImageRenderFailureRetriesUntilSuccess;
var Drawable: TTimingDrawItem; Uploads: integer;
begin
  Drawable := AddDrawable;
  Uploads := Drawable.UploadCalls;
  Drawable.ImageFailures := 1;
  Drawable.Draw(Drawable.X, Drawable.Y, 32, true, 0, 0);
  AssertTrue('A failed image render must retain a frame request', Drawable.NeedsFrame);
  AssertEquals('A failed image render must not upload incomplete pixels', Uploads, Drawable.UploadCalls);
  Manager.Timer;
  AssertEquals('The next frame must upload the complete image', Uploads + 1, Drawable.UploadCalls);
  AssertFalse('Render recovery must stop frame requests', Drawable.NeedsFrame);
end;

procedure TItemTimingTests.RepeatedUploadFailuresReuseResourcesAndReleaseLeases;
var Drawable: TTimingDrawItem; Step, Surfaces: integer; Resources: DWORD;
begin
  Drawable := AddDrawable;
  Surfaces := Drawable.SurfaceCreations;
  Resources := GetGuiResources(GetCurrentProcess, 0);
  Drawable.UploadFailures := 100;
  Drawable.Draw(Drawable.X, Drawable.Y, 32, true, 0, 0);
  for Step := 1 to 99 do
  begin
    Manager.Timer;
    AssertTrue('Every failed upload must retain the frame request', Drawable.NeedsFrame);
    AssertEquals('A failed upload must release the model lease', 0, Drawable.PinCount);
  end;
  AssertEquals('Upload failure must preserve the valid surface', Surfaces, Drawable.SurfaceCreations);
  AssertEquals('Repeated upload failures must not leak GDI objects', Resources,
    GetGuiResources(GetCurrentProcess, 0));
  Manager.Timer;
  AssertFalse('Recovery must end the frame subscription', Manager.NeedsFrames);
end;

procedure TItemTimingTests.DeletionCancelsFailedNativePresentation;
var Drawable: TTimingDrawItem; Uploads: integer;
begin
  Drawable := AddDrawable;
  Drawable.UploadFailures := 10;
  Drawable.Draw(Drawable.X, Drawable.Y, 32, true, 0, 0);
  AssertTrue(Drawable.NeedsFrame);
  Manager.DeleteItem(Drawable.Handle);
  Uploads := Drawable.UploadCalls;
  Manager.Timer;
  AssertEquals('Deletion must cancel failed native uploads', Uploads, Drawable.UploadCalls);
  AssertFalse('Deletion must cancel the pending frame', Drawable.NeedsFrame);
  AssertFalse('Deletion must clear the redraw request', Drawable.FrameRedrawPending);
  AssertEquals('Deletion must release the model lease', 0, Drawable.PinCount);
end;

procedure TItemTimingTests.HiddenUnpresentedItemMovesInBatch;
var Drawable: TTimingDrawItem; Params: TDItemCreateParams; Batch: HDWP;
begin
  Params := Default(TDItemCreateParams);
  Params.ItemSize := 32;
  Params.BigItemSize := 64;
  Drawable := TTimingDrawItem.Create(0, Params);
  try
    Batch := BeginDeferWindowPos(1);
    AssertTrue('The native position batch must start', Batch <> 0);
    Drawable.DrawInPositionBatch(-20000, -20100, 32, false, Batch, SWP_HIDEWINDOW);
    AssertTrue('The native position batch must complete', EndDeferWindowPos(Batch));
    AssertEquals('Hidden native geometry must match the model position',
      -20000, Drawable.ScreenRect.Left);
    AssertEquals('Hidden native geometry must match the model height',
      -20100, Drawable.ScreenRect.Top);
    AssertEquals('Hidden placement must not upload pixels', 0, Drawable.UploadCalls);
    AssertFalse('Hidden placement cannot validate absent pixels', Drawable.NativePixelsValid);
    AssertFalse('Hidden placement must not request idle frames', Drawable.NeedsFrame);
    Drawable.Draw(-20000, -20100, 32, false, 0, SWP_SHOWWINDOW);
    AssertEquals('Showing the item must upload its missing pixels', 1, Drawable.UploadCalls);
    AssertTrue('Successful visible upload must validate the pixels', Drawable.NativePixelsValid);
  finally Drawable.Free; end;
end;

procedure TItemTimingTests.HiddenForcedResizeMovesWithoutUploading;
var Drawable: TTimingDrawItem; Params: TDItemCreateParams; Batch: HDWP;
begin
  Params := Default(TDItemCreateParams);
  Params.ItemSize := 32;
  Params.BigItemSize := 64;
  Drawable := TTimingDrawItem.Create(0, Params);
  try
    Drawable.Draw(-20000, -20100, 32, true, 0, SWP_SHOWWINDOW);
    Batch := BeginDeferWindowPos(1);
    AssertTrue('The native position batch must start', Batch <> 0);
    Drawable.DrawInPositionBatch(-19000, -19100, 64, true, Batch, SWP_HIDEWINDOW);
    AssertTrue('The native position batch must complete', EndDeferWindowPos(Batch));
    AssertEquals('A forced hidden resize must move the native window',
      -19000, Drawable.ScreenRect.Left);
    AssertEquals('A hidden resize must retain the new logical size', 64, Drawable.Size);
    AssertEquals('A hidden resize must defer its pixel upload', 1, Drawable.UploadCalls);
    AssertFalse('A hidden resize must invalidate the old pixel size', Drawable.NativePixelsValid);
    AssertFalse('A hidden resize must not request idle frames', Drawable.NeedsFrame);
    Drawable.Draw(-19000, -19100, 64, false, 0, SWP_SHOWWINDOW);
    AssertEquals('Showing the resized item must upload the new pixels', 2, Drawable.UploadCalls);
    AssertTrue('The resized visible upload must validate the pixels', Drawable.NativePixelsValid);
  finally Drawable.Free; end;
end;

procedure TItemTimingTests.HoverSettlesAtNativePixelPrecision;
var Rate, Step: integer;
begin
  Manager.SetParam(gpBigItemSize, 80);
  Manager.SetParam(gpZoomTime, 120);
  for Rate in [60, 120] do
  begin
    Manager.SetParam(gpZoomEnabled, 0);
    StartZoom;
    for Step := 1 to Rate * 3 div 10 do
    begin
      Manager.Now := 1000 + Step * 1000 / Rate;
      Manager.Timer;
    end;
    AssertEquals('Opening must display its target within half a pixel', 80, Item.Size);
    Manager.MousePoint := Point(-30000, -30000);
    Manager.WHMouseMove(Manager.MousePoint);
    for Step := 1 to Rate * 3 div 10 do
    begin
      Manager.Now := 1300 + Step * 1000 / Rate;
      Manager.Timer;
    end;
    AssertEquals('Closing must display its target within half a pixel', 32, Item.Size);
  end;
end;

procedure TItemTimingTests.HoverRetargetPreservesContinuousMomentum;
var Spring: TSpringAnimation; Step: integer;
begin
  Manager.SetParam(gpBigItemSize, 80);
  Manager.SetParam(gpZoomTime, 120);
  Spring.Reset(1000, 0);
  Spring.Retarget(1000, 48, 120);
  StartZoom;
  Manager.Now := 1033.333333;
  Manager.Timer;
  Manager.MousePoint := Point(-30000, -30000);
  Manager.WHMouseMove(Manager.MousePoint);
  Spring.Retarget(Manager.Now, 0, 120);
  for Step := 1 to 12 do
  begin
    Manager.Now := 1033.333333 + Step * 1000 / 120;
    Manager.Timer;
    AssertEquals('Reversal must preserve the continuous spring and its velocity',
      32 + EnsureRange(Round(Spring.ValueAt(Manager.Now)), 0, 48), Item.Size);
  end;
end;

procedure TItemTimingTests.LateDragFrameReachesDockTarget;
var Drawable: TTimingDrawItem; Params: TDItemCreateParams;
begin
  Params := Default(TDItemCreateParams);
  Params.ItemSize := 32;
  Params.BigItemSize := 64;
  Drawable := TTimingDrawItem.Create(0, Params);
  try
    Drawable.Draw(500, 600, 32, true, 0, 0);
    Drawable.Now := 1000;
    Drawable.Undock;
    SetWindowPos(Drawable.Handle, 0, 680, 580, 0, 0, SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE);
    Drawable.Dock;
    Drawable.Now := 3000;
    Drawable.Timer;
    AssertFalse('A delayed drag return must settle', Drawable.NeedsFrame);
    AssertEquals('The terminal frame must move the native window', 500, Drawable.ScreenRect.Left);
  finally
    Drawable.Free;
  end;
end;

procedure TItemTimingTests.NestedTimerFrameDoesNotRepeatItemCallbacks;
var Before: Integer;
begin
  Item.cmd(gpItemAnimationType, 1);
  Item.Now := 1000;
  Item.Animate;
  Before := Item.DrawCalls;
  Item.ReenterOnTimer := Manager;
  Item.Now := 1100;
  Manager.Timer;
  AssertEquals('One frame must call each active item once', 1, Item.TimerCalls);
  AssertEquals('The outer frame must flush its redraw once', Before + 1, Item.DrawCalls);
end;

procedure TItemTimingTests.NestedDrawFrameDoesNotRepeatItemCallbacks;
var Before: Integer;
begin
  Item.cmd(gpItemAnimationType, 1);
  Item.Now := 1000;
  Item.Animate;
  Before := Item.DrawCalls;
  Item.ReenterOnDraw := Manager;
  Item.Now := 1100;
  Manager.Timer;
  AssertEquals('Drawing hooks must not start another item frame', 1, Item.TimerCalls);
  AssertEquals('The outer frame must retain one drawing pass', Before + 1, Item.DrawCalls);
end;

procedure TItemTimingTests.DeletionCancelsPendingMotionBeforeUndo;
begin
  Item.cmd(gpItemAnimationType, 1);
  Item.Now := 1000;
  Item.Animate;
  Item.Now := 1100;
  Item.BeginMotionFrame;
  try Item.Timer;
  finally Item.EndMotionFrame; end;
  AssertTrue('The active frame must contain a pending redraw', Item.FrameRedrawPending);
  Manager.DeleteItem(Item.Handle);
  AssertFalse('Deletion must discard its deferred redraw', Item.FrameRedrawPending);
  Manager.UnDelete;
  AssertEquals('Undo must restore the resting phase', 0.0, Item.AnimationPhase, 0.0);
  AssertFalse('Undo must not resume the deleted animation', Item.NeedsFrame);
end;

procedure TItemTimingTests.QueuedOffsetAndClickShareOneDrawingPass;
var Before: Integer;
begin
  Item.cmd(gpItemAnimationType, 1);
  Item.Now := 1000;
  Item.Animate;
  Before := Item.DrawCalls;
  Manager.QueueWndOffset(10);
  Manager.QueueWndOffset(20);
  AssertEquals('Queued movement must wait for the frame', Before, Item.DrawCalls);
  AssertEquals('Queued movement must preserve the current offset', 0, Manager.WndOffset);
  Item.Now := 1100;
  Manager.Timer;
  AssertEquals('The newest queued offset must win', 20, Manager.WndOffset);
  AssertEquals('Click and dock movement must share one draw', Before + 1, Item.DrawCalls);
end;

procedure TItemTimingTests.QueueingCurrentOffsetCancelsObsoleteMotion;
var Before: Integer;
begin
  Before := Item.DrawCalls;
  AssertFalse(Manager.NeedsFrames);
  Manager.QueueWndOffset(10);
  AssertTrue('Queued movement must request a frame', Manager.NeedsFrames);
  Manager.QueueWndOffset(0);
  AssertFalse('The current offset cancels obsolete movement', Manager.NeedsFrames);
  Manager.Timer;
  AssertEquals(0, Manager.WndOffset);
  AssertEquals('Cancelled movement must not draw', Before, Item.DrawCalls);
end;

procedure TItemTimingTests.DirectOffsetWriteDiscardsQueuedMotion;
begin
  Manager.QueueWndOffset(10);
  Manager.WndOffset := 30;
  Manager.Timer;
  AssertEquals('A direct write supersedes the queued offset', 30, Manager.WndOffset);
  AssertFalse(Manager.NeedsFrames);
end;

procedure TItemTimingTests.CallbackFailureFlushesQueuedGeometryAndRedraws;
var BeforeDraw, BeforeY: Integer;
  procedure FailFrame(AtTime: Double);
  var Raised: Boolean;
  begin
    Item.Now := AtTime;
    Item.RaiseAfterTimer := true;
    Raised := false;
    try
      Manager.Timer;
    except
      on E: Exception do
      begin
        AssertEquals('The original callback exception must propagate',
          'Injected item timer failure', E.Message);
        Raised := true;
      end;
    end;
    AssertTrue('The item callback must fail', Raised);
  end;
begin
  StartZoom;
  Item.cmd(gpItemAnimationType, 1);
  Item.Now := 1000;
  Item.Animate;
  BeforeDraw := Item.DrawCalls;
  BeforeY := Item.Y;
  Manager.QueueWndOffset(20);
  Manager.Now := 1100;
  FailFrame(1100);
  AssertEquals('Hover sampling must precede the failing callback', 35, Item.Size);
  AssertEquals('Queued geometry must reach the drawing callback after failure',
    BeforeY + 17, Item.Y);
  AssertEquals('Failed sampling must flush one combined draw', BeforeDraw + 1, Item.DrawCalls);
  AssertFalse('The failed frame must consume its pending redraw', Item.FrameRedrawPending);
  BeforeDraw := Item.DrawCalls;
  FailFrame(1200);
  AssertEquals('A failed callback without layout changes must still flush its redraw',
    BeforeDraw + 1, Item.DrawCalls);
  AssertFalse(Item.FrameRedrawPending);
  BeforeDraw := Item.DrawCalls;
  Item.RaiseAfterDraw := true;
  FailFrame(1300);
  Item.Now := 1400;
  Manager.Timer;
  AssertEquals('A failed cleanup draw must preserve the callback exception and release the frame',
    BeforeDraw + 2, Item.DrawCalls);
end;

initialization
  RegisterTest(TItemTimingTests);
end.
