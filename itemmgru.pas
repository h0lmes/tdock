unit itemmgru;

{$undef EXT_DEBUG}

interface
uses
  Windows, Messages, Classes, SysUtils, Forms, IniFiles, Math,
  declu, DockH, toolu, gfx, GDIPAPI, processhlp, iniproc,
  customitemu, scitemu, sepitemu, plgitemu, stackitemu, taskitemu, loggeru, itemcollectionu,
  itemsettingsu, itemregistryu, docklayoutu, tasksyncu, itemhostu, itemmodelu, itemviewu, itemfactoryu,
  docktimingu, dropimportu, taskbarimportu, itemserializationu;

type
  PItem = itemcollectionu.PItem;
  TItem = itemcollectionu.TItem;

  { TItemManager }

  TItemManager = class
  private
    FItems: TItemCollection;
    FModels: TItemStore;
    FTaskbarImporting: Boolean;
    FTaskbarImportStorage: UnicodeString;
    FOnItemRemoved: TItemRemovedEvent;
    FItemSize: integer;
    FBigItemSize: integer;
    FZoomWidth: integer;
    FItemSpacing: integer;
    FZoomItems: boolean; // enables zoom //
    FZoomTime: integer;
    FZoomAnimation: TSpringAnimation;
    FZoomLayoutDirty, FSamplingFrames, FFrameItemsDirty, FFrameLayoutDirty,
      FFrameFullUpdate, FFrameRunning: boolean;
    FReflection: boolean;
    FReflectionSize: integer;
    FItemAnimation: integer;
    FLaunchInterval: integer;
    FActivateRunning: boolean;
    FUseShellContextMenus: boolean;
    FShowHint: boolean;
    FStackAnimationEnabled: boolean;
    FSeparatorAlpha: integer;
    FOccupyFullMonitor: boolean;
    FFont: TDFontData;
    FLockMouseEffect: boolean;
    FSetsFilename: string;
    FUnknownItems: TLegacyItemSections;
    FVisible: boolean;
    FEnabled: boolean;
    FAeroPeekEnabled: boolean;
    FTaskLivePreviews: boolean;
    FTaskThumbSize: integer;
    FTaskGrouping: boolean;
    FTaskSystemMenus: boolean;
    FTaskSpot: integer;
    FShowRunningIndicator: boolean;
    FTaskSameMonitor: boolean;
    FOnRepaint: TItemRepaintEvent;
    FLayoutRevision: QWord;
    FLoadDepth, FRebuildDepth: integer;
    FTaskRefreshPending, FTaskSnapshotPending: boolean;
    FPendingTaskWindows: TTaskWindows;
    // for smooth zooming in and out //
    // 0 <= ZoomItemSizeDiff <= (BigItemSize - ItemSize) //
    ZoomItemSizeDiff: integer;
    // monitor index //
    FMonitor: integer;
    FSite: TBaseSite;
    FSiteVertical: boolean;
    FCenterOffsetPercent: integer;
    FEdgeOffset: integer;
    FWndOffset: integer;
    FQueuedWndOffset: Integer;
    FWndOffsetQueued: Boolean;
    // Wnd Item Vars //
    FItemsArea: windows.TRect;
    FItemsArea2: windows.TRect;
    FMargin: integer; // dock icons offset from a monitor edge
    FMargin2: integer; // dock icons additional offset from a monitor edge
    FHoverItemId: TItemId; // handle of the item over which the mouse is //
    FSelectedItemId: TItemId;
    // pos/size of ItemManager //
    x: integer;
    y: integer;
    width: integer;
    height: integer;
    widthZoomed: integer;
    heightZoomed: integer;
    FMonitorRect: Windows.TRect;
    FBaseWindowRect: GDIPAPI.TRect; // rect of the dock main window. updated on every RecalcDock //
    FBaseImageRect: GDIPAPI.TRect; // rect of the dock image. updated on every RecalcDock //
    FZoomInOutItem: extended; // relative mouse position on last WHMouseMove //
    FZooming: boolean; // true if mouse is over the panel and any items are zoomed //
    FDropDistance: integer;
    FLockDragging: boolean;
    FDraggingItem: boolean; // indicates that item is being dragged //
    FDragItemId: TItemId; // handle of the item that is being dragged //
    FDraggingFile: boolean; // indicates that file is being dragged //
    FDropPlace: integer; // index of free space //
    FDropPlaceEx: integer; // index of a place to drop to //
    FParentHWnd: THandle;
    FBaseCmd: TDBaseCmd;

    function GetManagedItem(wnd: HWND): TCustomItem;
    function GetModel(Id: TItemId): TCustomItem;
    procedure DisposeOwnedItem(Item: TObject; const Context: string);
    procedure ForgetOwnedItem(Id: TItemId);
    function PinManagedItem(const Identity: TItemIdentity; out Item: TCustomItem): boolean;
    function InsertTaskbarLauncher(const Data: TShortcutDtoV1): Boolean;
    function RepointTaskbarLauncher(const Data: TShortcutDtoV1): Boolean;
    function PinActiveItem(const Identity: TItemIdentity; out Item: TCustomItem): boolean;
    procedure ApplyCurrentSettings(wnd: HWND);
    function CaptureItems(ForSaving: boolean): TItemIdentities;
    function ResolveActiveItem(const Identity: TItemIdentity; out Item: TCustomItem): boolean;
    function GetLayoutInput: TDockLayoutInput;
    function GetLayoutItems: TDockLayoutItems;
    function GetDockGeometry: TDockGeometry;
    function GetLayoutCount: integer;
    function GetItemCount: integer;
    function GetDeletedCount: integer;
    procedure SyncDropPlace;
    procedure ActivateItem(wnd: HWND; Update: boolean);
    procedure Clear;
    procedure ClearDeleted;
    procedure err(where: string; e: Exception; Critical: boolean = false);
    procedure notify(message: string);
    procedure UpdateDock(forceDraw: boolean);
    procedure SetVisible(value: boolean);
    procedure ItemsChanged(FullUpdate: boolean = false);
    function  GetRect: windows.TRect;
    procedure SetWndOffset(value: integer);

    // load/save //
    procedure LoadDefault;
    procedure SaveItems;
    procedure SaveItemsTo(const Filename: string);
    procedure SaveItem(wnd: HWND);

    procedure RecalcItems;
    procedure RecalcDock;
    procedure UpdateItems(forceDraw: boolean);
    function  IASize: integer;
    function  ItemFromPoint(Ax, Ay, distance: integer): extended;
    function  ItemRectFromPoint(Ax, Ay: integer): integer;

    // items //
    function  ItemHWnd(index: integer): THandle;
    function  AddItem(wnd: HWND; Update: boolean = false): THandle;
    function  CreateItem(IniFile, IniSection, Parameter: string): THandle;

    procedure Zoom(x, y: integer);
    procedure UnZoom(do_now: boolean = false);
    procedure ZoomInOut;
    procedure RetargetZoom;
    procedure SetDropPlaceFromPoint(pt: windows.TPoint);
    procedure SetDropPlace(index: integer);
    procedure SetDropPlaceEx(index: integer);

    property LayoutCount: integer read GetLayoutCount;
    procedure AllItemTimer;
    procedure FlushPendingTasks;
    function  IsSeparator(wnd: HWND): boolean;
  protected
    function ClockNow: QWord; virtual;
    function MotionNow: Double; virtual;
    function FinishPositionBatch(Batch: HDWP): boolean; virtual;
    function GetCursorPoint(out pt: Windows.TPoint): boolean; virtual;
    function CreatePluginItem(var Params: TDItemCreateParams): TCustomItem; virtual;
  public

    property Visible: boolean read FVisible write SetVisible;
    property Rect: windows.TRect read GetRect;
    property ItemsArea: windows.TRect read FItemsArea;
    property ItemsArea2: windows.TRect read FItemsArea2;
    property Margin: integer read FMargin;
    property Margin2: integer read FMargin2;
    property WndOffset: integer read FWndOffset write SetWndOffset;
    property ItemCount: integer read GetItemCount;
    property DeletedCount: integer read GetDeletedCount;
    property OnRepaint: TItemRepaintEvent read FOnRepaint write FOnRepaint;
    property ParentWindow: HWND read FParentHWnd;

    constructor Create(Handle: THandle; ABaseCmd: TDBaseCmd;
      ItemSize, BigItemSize, ZoomWidth, ZoomTime, ItemSpacing: integer;
      ZoomItems, Reflection: boolean;
      ReflectionSize, LaunchInterval, ItemAnimation, SeparatorAlpha: integer;
      ActivateRunning, UseShellContextMenus, LockDragging, StackAnimationEnabled: boolean;
      AeroPeekEnabled, TaskLivePreviews, TaskGrouping, TaskSystemMenus: boolean;
      TaskThumbSize, TaskSpot: integer;
      ShowHint: boolean; Font: TDFontData); overload;
    constructor Create(Handle: THandle; const Settings: TItemManagerSettings;
      Repaint: TItemRepaintEvent); overload;
    destructor Destroy; override;
    procedure Enable(value: boolean);
    procedure SetParam(id: TDParam; value: PtrInt);
    procedure ApplySetting(Key: TDParam; Value: integer);
    procedure ApplySettings(const Settings: TItemManagerSettings);
    procedure ConfigureLayout(const Configuration: TDockLayoutConfiguration);
    function LayoutSnapshot: TDockLayoutSnapshot;
    function InteractionSnapshot: TDockInteractionSnapshot;
    procedure command(cmd, params: string);
    function  GetZoomEdge: integer;

    procedure Timer;
    procedure QueueWndOffset(Value: Integer);
    function NeedsFrames: boolean;
    procedure ForegroundChanged(wnd: HWND);
    procedure SetTheme;

    // load & save //
    procedure Load(fsets: string);
    procedure Save(fsets: string);
    procedure SaveTo(const Filename: string);

    // task item procs //
    procedure Taskbar;
    procedure SynchronizeTasks(const AppWindows: TTaskWindows);
    procedure ClearTaskbar;

    // items //
    procedure UnDelete;
    procedure CheckDeleted;
    function  ZOrder(InsertAfter: THandle): THandle;
    function  ItemIndex(HWnd: THandle): integer;
    procedure InsertFiles(list: TStrings);
    procedure ImportDropFiles(Batch: TDropImportBatch; wndItem: HWND; pt: windows.TPoint);
    function ImportTaskbar(const StorageRoot: UnicodeString;
      Source: TTaskbarSource = nil;
      Mode: TTaskbarImportMode = DEFAULT_TASKBAR_IMPORT_MODE): TTaskbarImportResult;
    function InsertFile(Filename: string): THandle;
    function InsertItem(AData: string): THandle;
    function  CreateItemFromIni(IniFile, IniSection: string): THandle;
    function  CreateItemFromString(value: string): THandle;
    function  CreateTaskItem: THandle;
    procedure DeleteItem(HWnd: THandle);

    // mouse effects //
    function  CheckMouseOn: boolean;
    procedure WHMouseMove(pt: windows.TPoint; allow_zoom: boolean = true);
    procedure DragEnter;
    procedure DragOver;
    procedure DragLeave;
    procedure WMDeactivateApp;

    // Win Item Procs //
    procedure Undock(wnd: HWND);
    procedure Dock(wnd: HWND);
    function  IsItem(wnd: HWND): HWND;
    function  ItemDropFile(wndItem: HWND; pt: windows.TPoint; filename: string): boolean;
    function  ItemDropFiles(wndItem: HWND; pt: windows.TPoint; files: TStrings): boolean;
    function  ItemCmd(wnd: HWND; id: TDParam; param: PtrInt): PtrInt;
    procedure ItemDock(wnd: HWND);
    function  AllItemCmd(id: TDParam; param: PtrInt): PtrInt;
    procedure SetFont(var Value: TDFontData);
    function TryGetManagedItem(wnd: HWND; out Item: TCustomItem): boolean;
    function TryGetItemById(Id: TItemId; out Item: TCustomItem): boolean;
    function CreateItemId(const Data: string): TItemId;
    function InsertItemById(Id: TItemId; Update: boolean = true): TItemId;
    procedure DeleteItemById(Id: TItemId);
    procedure UndockItemById(Id: TItemId);
    procedure DockItemById(Id: TItemId);
    procedure PluginAnimateById(Id: TItemId);
    property OnItemRemoved: TItemRemovedEvent read FOnItemRemoved write FOnItemRemoved;
    function AdoptItem(Item: TCustomItem; Update: boolean = true): THandle;
    function  GetPluginFile(wnd: HWND): string;
    procedure SetPluginImage(wnd: HWND; lpImageNew: Pointer; AutoDelete: boolean);
    procedure SetPluginOverlay(wnd: HWND; lpOverlayNew: Pointer; AutoDelete: boolean);
    procedure PluginAnimate(wnd: HWND);
    function  SetPluginCaption(wnd: HWND; NewCaption: string): integer;
    function  GetPluginCaption(wnd: HWND): string;
    function  GetPluginRect(wnd: HWND; var r: windows.TRect): boolean;
    function  IsPluginUndocked(wnd: HWND): boolean;
end;

implementation

uses animationclocku, customdrawitemu, shelltextu;

function TItemManager.TryGetManagedItem(wnd: HWND; out Item: TCustomItem): boolean;
begin
  result := TryGetItemById(ItemViews.ItemIdOf(wnd), Item);
end;

function TItemManager.TryGetItemById(Id: TItemId; out Item: TCustomItem): boolean;
var model: TItemModel;
begin
  Item := nil;
  model := nil;
  if assigned(FModels) then model := FModels.Find(Id);
  result := assigned(model) and (model is TCustomItem) and (model.State <> imsRetiring);
  if result then Item := TCustomItem(model);
end;

function TItemManager.GetModel(Id: TItemId): TCustomItem;
begin TryGetItemById(Id, result); end;

function TItemManager.CreateItemId(const Data: string): TItemId;
begin result := ItemViews.ItemIdOf(CreateItemFromString(Data)); end;

function TItemManager.InsertItemById(Id: TItemId; Update: boolean): TItemId;
var item: TCustomItem;
begin
  result := NO_ITEM_ID;
  if TryGetItemById(Id, item) and (AddItem(item.Handle, Update) <> 0) then result := Id;
end;

procedure TItemManager.UndockItemById(Id: TItemId);
var item: TCustomItem;
begin if TryGetItemById(Id, item) then Undock(item.Handle); end;

procedure TItemManager.DockItemById(Id: TItemId);
var item: TCustomItem;
begin if TryGetItemById(Id, item) then Dock(item.Handle); end;

procedure TItemManager.PluginAnimateById(Id: TItemId);
var item: TCustomItem;
begin
  if not TryGetItemById(Id, item) or not item.Pin then exit;
  try
    if FItemAnimation > 0 then item.Animate;
  finally ReleaseItemModel(Id); end;
end;

function TItemManager.GetManagedItem(wnd: HWND): TCustomItem;
begin
  TryGetManagedItem(wnd, result);
end;

procedure TItemManager.DisposeOwnedItem(Item: TObject; const Context: string);
var id: TItemId;
begin
  try
    id := TCustomItem(Item).ItemId;
    TCustomItem(Item).Freed := true;
    if assigned(FItems) then
    begin
      FItems.Forget(id);
      SyncDropPlace;
      FDraggingItem := FItems.DraggedId <> 0;
      FDragItemId := FItems.DraggedId;
      if not FDraggingItem then FDropPlaceEx := NOT_AN_ITEM;
      if FHoverItemId = id then FHoverItemId := 0;
      if FSelectedItemId = id then FSelectedItemId := 0;
    end;
    TCustomItem(Item).Free;
  except
    on e: Exception do
      try AddLog(Context + LineEnding + e.Message); except end;
  end;
end;

function TItemManager.PinManagedItem(const Identity: TItemIdentity; out Item: TCustomItem): boolean;
var registered: TObject;
begin
  Item := nil;
  result := ItemRegistry.TryResolve(Identity, FParentHWnd, registered);
  if result then result := (registered is TCustomItem) and ItemRegistry.Pin(Identity);
  if result then Item := TCustomItem(registered);
end;

procedure TItemManager.ForgetOwnedItem(Id: TItemId);
var scope: TItemHostScope; changed: boolean;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    ItemViews.ForgetMouseLocks(Id);
    changed := assigned(FItems) and FItems.Forget(Id);
    if assigned(FItems) then
    begin
      SyncDropPlace;
      FDraggingItem := FItems.DraggedId <> 0;
      FDragItemId := FItems.DraggedId;
      FDropPlaceEx := NOT_AN_ITEM;
    end;
    if FHoverItemId = Id then FHoverItemId := 0;
    if FSelectedItemId = Id then FSelectedItemId := 0;
    if changed then ItemsChanged(true);
    if assigned(FOnItemRemoved) then FOnItemRemoved(Id);
    FlushPendingTasks;
  finally
    EndItemHostOperation(scope);
  end;
end;

procedure TItemManager.ApplyCurrentSettings(wnd: HWND);
var scope: TItemHostScope; identity: TItemIdentity; item: TCustomItem;
  procedure Apply(id: TDParam; value: PtrInt);
  begin
    if not item.Freed then item.cmd(id, value);
  end;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    identity := ItemRegistry.IdentityOf(wnd);
    if not PinManagedItem(identity, item) then exit;
    try
      Apply(gpItemSize, FItemSize);
      Apply(gpBigItemSize, FBigItemSize);
      Apply(gpItemSpacing, FItemSpacing);
      Apply(gpMonitor, FMonitor);
      Apply(gpSite, Ord(FSite));
      Apply(gpReflectionEnabled, Ord(FReflection));
      Apply(gpReflectionSize, FReflectionSize);
      Apply(gpLaunchInterval, FLaunchInterval);
      Apply(gpActivateRunning, Ord(FActivateRunning));
      Apply(gpUseShellContextMenus, Ord(FUseShellContextMenus));
      Apply(gpItemAnimationType, FItemAnimation);
      Apply(gpLockDragging, Ord(FLockDragging));
      Apply(gpShowHint, Ord(FShowHint));
      Apply(gpShowRunningIndicator, Ord(FShowRunningIndicator));
      Apply(gpStackAnimationEnabled, Ord(FStackAnimationEnabled));
      Apply(gpAeroPeekEnabled, Ord(FAeroPeekEnabled));
      Apply(gpTaskSameMonitor, Ord(FTaskSameMonitor));
      Apply(gpTaskLivePreviews, Ord(FTaskLivePreviews));
      Apply(gpTaskThumbSize, FTaskThumbSize);
      Apply(gpTaskGrouping, Ord(FTaskGrouping));
      Apply(gpTaskSystemMenus, Ord(FTaskSystemMenus));
      Apply(gpSeparatorAlpha, FSeparatorAlpha);
      Apply(gpLockMouseEffect, Ord(FLockMouseEffect));
      if not item.Freed then item.SetFont(FFont);
    finally
      ItemRegistry.Unpin(identity);
    end;
  finally
    EndItemHostOperation(scope);
  end;
end;

function TItemManager.CaptureItems(ForSaving: boolean): TItemIdentities;
var i, count: integer; ids: TItemIds;
begin
  if ForSaving then count := FItems.SaveCount else count := LayoutCount;
    SetLength(ids, count);
    for i := 0 to count - 1 do
      if ForSaving then ids[i] := FItems.SavedItems[i].Id else ids[i] := FItems[i]^.Id;
  SetLength(result, count);
  for i := 0 to count - 1 do
      result[i] := ItemViews.IdentityForId(ids[i]);
end;

function TItemManager.ResolveActiveItem(const Identity: TItemIdentity; out Item: TCustomItem): boolean;
var registered: TObject;
begin
  Item := nil;
  result := (FItems.IndexOf(Identity.ItemId) <> NO_ITEM_INDEX) and
    ItemRegistry.TryResolve(Identity, FParentHWnd, registered);
  if result then result := registered is TCustomItem;
  if result then Item := TCustomItem(registered);
end;

function TItemManager.PinActiveItem(const Identity: TItemIdentity; out Item: TCustomItem): boolean;
begin
  result := ResolveActiveItem(Identity, Item);
  if result then result := PinManagedItem(Identity, Item);
end;

function TItemManager.GetLayoutInput: TDockLayoutInput;
begin
  result.Site := Ord(FSite);
  result.MonitorRect := FMonitorRect;
  result.ItemsArea := FItemsArea;
  result.ItemsArea2 := FItemsArea2;
  result.ItemSize := FItemSize;
  result.BigItemSize := FBigItemSize;
  result.ItemSpacing := FItemSpacing;
  result.ZoomWidth := FZoomWidth;
  result.CenterOffsetPercent := FCenterOffsetPercent;
  result.Margin := FMargin;
  result.Margin2 := FMargin2;
  result.WndOffset := FWndOffset;
  result.EdgeOffset := FEdgeOffset;
  result.ZoomSizeDiff := ZoomItemSizeDiff;
  result.ZoomPosition := FZoomInOutItem;
  result.OccupyFullMonitor := FOccupyFullMonitor;
end;

function TItemManager.GetLayoutItems: TDockLayoutItems;
var i: integer; item: TItem;
begin
  SetLength(result, LayoutCount);
  for i := 0 to High(result) do
  begin
    item := FItems[i]^;
    result[i].X := item.x;
    result[i].Y := item.y;
    result[i].Size := item.s;
    result[i].ExactX := item.xe;
    result[i].ExactY := item.ye;
    result[i].ExactSize := item.se;
    result[i].IsSeparator := GetModel(item.Id) is TSeparatorItem;
  end;
end;

function TItemManager.GetDockGeometry: TDockGeometry;
begin
  result.X := x;
  result.Y := y;
  result.Width := width;
  result.Height := height;
  result.WidthZoomed := widthZoomed;
  result.HeightZoomed := heightZoomed;
  result.BaseWindowRect := FBaseWindowRect;
  result.BaseImageRect := FBaseImageRect;
end;

procedure TItemManager.ConfigureLayout(const Configuration: TDockLayoutConfiguration);
begin
  FMonitorRect := Configuration.MonitorRect;
  FItemsArea := Configuration.ItemsArea;
  FItemsArea2 := Configuration.ItemsArea2;
  FMargin := Configuration.Margin;
  FMargin2 := Configuration.Margin2;
end;

function TItemManager.LayoutSnapshot: TDockLayoutSnapshot;
begin
  result.MonitorRect := FMonitorRect;
  result.BaseWindowRect := FBaseWindowRect;
  result.BaseImageRect := FBaseImageRect;
  result.X := x;
  result.Y := y;
  result.Width := width;
  result.Height := height;
  result.WidthZoomed := widthZoomed;
  result.HeightZoomed := heightZoomed;
  result.DraggingFile := FDraggingFile;
end;

function TItemManager.InteractionSnapshot: TDockInteractionSnapshot;
begin
  result.HoverItem := FHoverItemId;
  result.SelectedItem := FSelectedItemId;
  result.DraggedItem := FDragItemId;
  result.DraggingItem := FDraggingItem;
  result.DraggingFile := FDraggingFile;
  result.Zooming := FZooming;
  result.DropDistance := FDropDistance;
  result.DropPlace := FDropPlace;
  result.DropTarget := FDropPlaceEx;
end;

function TItemManager.AdoptItem(Item: TCustomItem; Update: boolean): THandle;
var scope: TItemHostScope;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    result := 0;
    if assigned(Item) then result := AddItem(Item.Handle, Update);
  finally
    EndItemHostOperation(scope);
  end;
end;

constructor TItemManager.Create(Handle: THandle; const Settings: TItemManagerSettings;
  Repaint: TItemRepaintEvent);
begin
  Create(Handle, nil, Settings.ItemSize, Settings.BigItemSize,
    Settings.ZoomWidth, Settings.ZoomTime, Settings.ItemSpacing,
    Settings.ZoomEnabled, Settings.ReflectionEnabled,
    Settings.ReflectionSize, Settings.LaunchInterval, Settings.ItemAnimationType,
    Settings.SeparatorAlpha, Settings.ActivateRunning, Settings.UseShellContextMenus,
    Settings.LockDragging, Settings.StackAnimationEnabled, Settings.AeroPeekEnabled,
    Settings.TaskLivePreviews, Settings.TaskGrouping, Settings.TaskSystemMenus,
    Settings.TaskThumbSize, Settings.TaskSpot, Settings.ShowHint, Settings.Font);
  FOnRepaint := Repaint;
  ApplySettings(Settings);
end;

procedure TItemManager.ApplySetting(Key: TDParam; Value: integer);
var scope: TItemHostScope;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    if (Key <= gpMin) or (Key >= gpMax) then
      raise ERangeError.Create('Invalid item setting identifier');
    SetParam(Key, Value);
  finally
    EndItemHostOperation(scope);
  end;
end;

procedure TItemManager.ApplySettings(const Settings: TItemManagerSettings);
var scope: TItemHostScope; font: TDFontData;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    ApplySetting(gpMonitor, Settings.Monitor);
    ApplySetting(gpSite, Ord(Settings.Site));
    ApplySetting(gpCenterOffsetPercent, Settings.CenterOffsetPercent);
    ApplySetting(gpEdgeOffset, Settings.EdgeOffset);
    ApplySetting(gpOccupyFullMonitor, Ord(Settings.OccupyFullMonitor));
    ApplySetting(gpItemSize, Settings.ItemSize);
    ApplySetting(gpBigItemSize, Settings.BigItemSize);
    ApplySetting(gpZoomEnabled, Ord(Settings.ZoomEnabled));
    ApplySetting(gpZoomWidth, Settings.ZoomWidth);
    ApplySetting(gpZoomTime, Settings.ZoomTime);
    ApplySetting(gpItemSpacing, Settings.ItemSpacing);
    ApplySetting(gpReflectionEnabled, Ord(Settings.ReflectionEnabled));
    ApplySetting(gpReflectionSize, Settings.ReflectionSize);
    ApplySetting(gpLaunchInterval, Settings.LaunchInterval);
    ApplySetting(gpActivateRunning, Ord(Settings.ActivateRunning));
    ApplySetting(gpUseShellContextMenus, Ord(Settings.UseShellContextMenus));
    ApplySetting(gpItemAnimationType, Settings.ItemAnimationType);
    ApplySetting(gpLockDragging, Ord(Settings.LockDragging));
    ApplySetting(gpShowRunningIndicator, Ord(Settings.ShowRunningIndicator));
    ApplySetting(gpStackAnimationEnabled, Ord(Settings.StackAnimationEnabled));
    ApplySetting(gpTaskSameMonitor, Ord(Settings.TaskSameMonitor));
    ApplySetting(gpAeroPeekEnabled, Ord(Settings.AeroPeekEnabled));
    ApplySetting(gpTaskLivePreviews, Ord(Settings.TaskLivePreviews));
    ApplySetting(gpTaskThumbSize, Settings.TaskThumbSize);
    ApplySetting(gpTaskGrouping, Ord(Settings.TaskGrouping));
    ApplySetting(gpTaskSystemMenus, Ord(Settings.TaskSystemMenus));
    ApplySetting(gpTaskSpot, Settings.TaskSpot);
    ApplySetting(gpSeparatorAlpha, Settings.SeparatorAlpha);
    ApplySetting(gpShowHint, Ord(Settings.ShowHint));
    ApplySetting(gpDropDistance, Settings.DropDistance);
    ApplySetting(gpLockMouseEffect, Ord(Settings.LockMouseEffect));
    font := Settings.Font;
    SetFont(font);
  finally
    EndItemHostOperation(scope);
  end;
end;

//------------------------------------------------------------------------------
function TItemManager.GetCursorPoint(out pt: Windows.TPoint): boolean;
begin
  pt := Default(Windows.TPoint);
  result := Windows.GetCursorPos(pt);
end;
//------------------------------------------------------------------------------
function TItemManager.GetLayoutCount: integer;
begin
  result := FItems.ViewCount;
end;
//------------------------------------------------------------------------------
function TItemManager.GetItemCount: integer;
begin
  result := FItems.Count;
end;
//------------------------------------------------------------------------------
function TItemManager.GetDeletedCount: integer;
begin
  result := FItems.DeletedCount;
end;
//------------------------------------------------------------------------------
procedure TItemManager.SyncDropPlace;
begin
  FDropPlace := FItems.PreviewIndex;
  if FDropPlace = NO_ITEM_INDEX then FDropPlace := NOT_AN_ITEM;
end;
//------------------------------------------------------------------------------
procedure TItemManager.ActivateItem(wnd: HWND; Update: boolean);
var identity: TItemIdentity; item: TCustomItem;
begin
  identity := ItemRegistry.IdentityOf(wnd);
  if not PinManagedItem(identity, item) then exit;
  try
    item.State := imsActive;
    EnableWindow(wnd, true);
    ItemCmd(wnd, icFree, 0);
    if item.Freed or not FItems.Contains(ItemViews.ItemIdOf(wnd)) then exit;
    ItemDock(wnd);
    if item.Freed or not FItems.Contains(ItemViews.ItemIdOf(wnd)) then exit;
    SetWindowPos(wnd, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE + SWP_NOSIZE + SWP_NOSENDCHANGING);
    SyncDropPlace;
    SetDropPlaceEx(NOT_AN_ITEM);
    if Update then ItemsChanged(true);
  finally
    ItemRegistry.Unpin(identity);
  end;
end;
//------------------------------------------------------------------------------
constructor TItemManager.Create(Handle: THandle; ABaseCmd: TDBaseCmd;
      ItemSize, BigItemSize, ZoomWidth, ZoomTime, ItemSpacing: integer;
      ZoomItems, Reflection: boolean;
      ReflectionSize, LaunchInterval, ItemAnimation, SeparatorAlpha: integer;
      ActivateRunning, UseShellContextMenus, LockDragging, StackAnimationEnabled: boolean;
      AeroPeekEnabled, TaskLivePreviews, TaskGrouping, TaskSystemMenus: boolean;
      TaskThumbSize, TaskSpot: integer;
      ShowHint: boolean; Font: TDFontData);
begin
  inherited Create;

  // creation parameters
  FEnabled := false;
  FVisible := false;
  FParentHWnd := Handle;
  FBaseCmd := ABaseCmd;
  FItemSize := ItemSize;
  FBigItemSize := BigItemSize;
  FZoomWidth := ZoomWidth;
  FZoomTime := ZoomTime;
  if FZoomTime < 1 then FZoomTime := 1;
  FItemSpacing := ItemSpacing;
  FZoomItems := ZoomItems;
  FReflection := Reflection;
  FReflectionSize := ReflectionSize;
  FLaunchInterval := LaunchInterval;
  FItemAnimation := ItemAnimation;
  FSeparatorAlpha := SeparatorAlpha;
  FActivateRunning := ActivateRunning;
  FUseShellContextMenus := UseShellContextMenus;
  FLockDragging := LockDragging;
  FStackAnimationEnabled := StackAnimationEnabled;
  FAeroPeekEnabled := AeroPeekEnabled;
  FTaskLivePreviews := TaskLivePreviews;
  FTaskGrouping := TaskGrouping;
  FTaskSystemMenus := TaskSystemMenus;
  FTaskThumbSize := TaskThumbSize;
  FTaskSpot := TaskSpot;
  FShowHint := ShowHint;
  CopyFontData(Font, FFont);

  // init
  FItems := TItemCollection.Create;
  FModels := TItemStore.Create;
  FModels.OnRemoved := ForgetOwnedItem;
  ItemViews.BindStore(FParentHWnd, FModels);
  FZooming := false;
  ZoomItemSizeDiff := 0;
  FMonitor := 0;
  FDropDistance := 80;
  FDropPlace := NOT_AN_ITEM;
  FDropPlaceEx := NOT_AN_ITEM;
  FHoverItemId := 0;
  FSelectedItemId := 0;
  FDraggingItem := false;
  FDragItemId := 0;
  FDraggingFile := false;
  FLockMouseEffect := false;
  FCenterOffsetPercent := 50;
  FEdgeOffset := 0;
  FWndOffset := 0;
end;
//------------------------------------------------------------------------------
destructor TItemManager.Destroy;
begin
  FEnabled := false;
  try
    Clear;
  finally
    try
      ClearDeleted;
    finally
      if assigned(FModels) then
      begin
        ItemViews.UnbindStore(FParentHWnd, FModels);
        FModels.OnRemoved := nil;
      end;
      try FreeAndNil(FModels);
      finally FreeAndNil(FItems); end;
      inherited;
    end;
  end;
end;
//------------------------------------------------------------------------------
procedure TItemManager.Enable(value: boolean);
begin
  FEnabled := value;
end;
//------------------------------------------------------------------------------
procedure TItemManager.err(where: string; e: Exception; Critical: boolean = false);
var
  msg: WideString;
begin
  if assigned(e) then where := where + ' ' + LineEnding + e.Message else where := where + ' ' + LineEnding + 'Error';
  if Critical then
  begin
    msg := UTF8Decode(XErrorCritical + ' ' + XErrorContactDeveloper) + LineEnding + LineEnding + where;
    messageboxw(FParentHWnd, pwchar(msg), PROGRAM_NAME, MB_ICONERROR);
    halt;
  end else
    raise Exception.Create(where);
end;
//------------------------------------------------------------------------------
procedure TItemManager.notify(message: string);
begin
  dockh.notify(0, pchar(message));
end;
//------------------------------------------------------------------------------
procedure TItemManager.SetParam(id: TDParam; value: PtrInt);
var scope: TItemHostScope;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    try
      AllItemCmd(id, value);

      case id of
        gpItemSize:
          begin
            FItemSize := value;
            RetargetZoom;
            ItemsChanged(true);
          end;
        gpBigItemSize:
          begin
            FBigItemSize := value;
            RetargetZoom;
          end;
        gpZoomWidth:
          begin
            FZoomWidth := value;
            WHMouseMove(classes.point(-100, -100));
          end;
        gpItemSpacing:
          begin
            FItemSpacing := value;
            ItemsChanged(true);
          end;
        gpZoomEnabled:
          begin
            FZoomItems := boolean(value);
            if not FZoomItems then UnZoom(true);
            ItemsChanged(true);
          end;
        gpMonitor:
          begin
            FMonitor := value;
            ItemsChanged(true);
            Unzoom(true);
          end;
        gpSite:
          begin
            FSite := TBaseSite(value);
            FSiteVertical := (FSite = bsLeft) or (FSite = bsRight);
            ItemsChanged(true);
            Unzoom(true);
          end;
        gpCenterOffsetPercent:
          begin
            FCenterOffsetPercent := value;
            ItemsChanged;
          end;
        gpEdgeOffset:
          begin
            FEdgeOffset := value;
            ItemsChanged;
          end;
        gpDropDistance:           FDropDistance := value;
        gpLockDragging:           FLockDragging := boolean(value);
        gpReflectionEnabled:
          begin
            FReflection := boolean(value);
            ItemsChanged(true);
          end;
        gpReflectionSize:         FReflectionSize := value;
        gpAeroPeekEnabled:        FAeroPeekEnabled := boolean(value);
        gpTaskbar:                if value = 0 then ClearTaskbar;
        gpTaskLivePreviews:
          begin
            ClearTaskbar;
            FTaskLivePreviews := value <> 0;
          end;
        gpTaskThumbSize:          FTaskThumbSize := value;
        gpTaskSpot:               FTaskSpot := value;
        gpTaskGrouping:
          begin
            ClearTaskbar;
            FTaskGrouping := value <> 0;
          end;
        gpTaskSystemMenus:        FTaskSystemMenus := value <> 0;
        gpShowRunningIndicator:   FShowRunningIndicator := value <> 0;
        gpTaskSameMonitor:        FTaskSameMonitor := value <> 0;
        gpItemAnimationType:      FItemAnimation := value;
        gpLaunchInterval:         FLaunchInterval := value;
        gpActivateRunning:        FActivateRunning := value <> 0;
        gpUseShellContextMenus:   FUseShellContextMenus := value <> 0;
        gpShowHint:               FShowHint := value <> 0;
        gpStackAnimationEnabled:  FStackAnimationEnabled := value <> 0;
        gpZoomTime:
          begin
            FZoomTime := value;
            if FZoomTime < 1 then FZoomTime := 1;
            RetargetZoom;
          end;
        gpLockMouseEffect:        FLockMouseEffect := value <> 0;
        gpSeparatorAlpha:         FSeparatorAlpha := value;
        gpOccupyFullMonitor:      FOccupyFullMonitor := value <> 0;
      end;
    except
      on e: Exception do err('ItemManager.SetParam', e);
    end;
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
procedure TItemManager.command(cmd, params: string);
var scope: TItemHostScope;
  data: string;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    if FEnabled then
    try
      if cmd = 'clear' then Clear;
      if cmd = 'load' then
        if params <> '' then Load(params);
      if cmd = 'shortcut' then AddItem(CreateItemFromString(TShortcutItem.Make()), true);
      if cmd = 'separator' then AddItem(CreateItemFromString(TSeparatorItem.Make()), true);
      if cmd = 'plugin' then AddItem(CreateItemFromString(TPluginItem.Make(params)), true);
      if cmd = 'stack' then
      begin
        if params = '' then
        begin
          AddItem(CreateItemFromString(TStackItem.Make()), true);
        end else begin
          AddItem(CreateItemFromString(TStackItem.Make('::::', '', params)), true);
        end;
      end;
    except
      on e: Exception do err('ItemManager.Command::' + cmd + '(' + params + ')', e);
    end;
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
procedure TItemManager.UpdateDock(forceDraw: boolean);
begin
  if assigned(FOnRepaint) then FOnRepaint(forceDraw)
  else if assigned(FBaseCmd) then FBaseCmd(tcRepaintBase, ifthen(forceDraw, 1, 0));
end;
//------------------------------------------------------------------------------
//
//
//
//
//
//
//
//------------------------------------------------------------------------------
// clears the entire items array //
procedure TItemManager.Clear;
var scope: TItemHostScope; ids: TItemIds; index: integer; model: TItemModel;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  inc(FRebuildDepth);
  try
    if not assigned(FItems) then exit;
    ids := FModels.Snapshot;
    FItems.Clear;
    FTaskRefreshPending := false;
    FTaskSnapshotPending := false;
    FPendingTaskWindows := nil;
    FUnknownItems := nil;
    FDraggingItem := false;
    FDraggingFile := false;
    FDragItemId := 0;
    FDropPlace := NOT_AN_ITEM;
    FDropPlaceEx := NOT_AN_ITEM;
    FHoverItemId := 0;
    FSelectedItemId := 0;
    for index := 0 to High(ids) do
    begin
      model := FModels.Find(ids[index]);
      if assigned(model) and (model.State <> imsDeleted) then
        DisposeOwnedItem(model, 'ItemManager.Clear');
    end;
  finally
    dec(FRebuildDepth);
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
// clears the "deleted items" array //
procedure TItemManager.ClearDeleted;
var scope: TItemHostScope; ids: TItemIds; index: integer; item: TCustomItem;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  inc(FRebuildDepth);
  try
    if not assigned(FItems) then exit;
    SetLength(ids, FItems.DeletedCount);
    for index := 0 to High(ids) do ids[index] := FItems.DeletedId(index);
    FItems.ClearDeleted;
    for index := 0 to High(ids) do
      if TryGetItemById(ids[index], item) then
        DisposeOwnedItem(item, 'ItemManager.ClearDeleted');
  finally
    dec(FRebuildDepth);
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
// restore deleted item in FILO order //
procedure TItemManager.UnDelete;
var scope: TItemHostScope; wnd: THandle;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    try
      CheckDeleted;
      wnd := ItemViews.HandleOf(FItems.RestoreLast);
      if wnd <> 0 then ActivateItem(wnd, true);
    except
      on e: Exception do err('ItemManager.UnDelete', e);
    end;
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
// clears out unwanted items from "deleted items" array //
procedure TItemManager.CheckDeleted;
var scope: TItemHostScope; ids: TItemIds; index: integer; item: TCustomItem;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    SetLength(ids, FItems.DeletedCount);
    for index := 0 to High(ids) do ids[index] := FItems.DeletedId(index);
    for index := High(ids) downto 0 do
      if TryGetItemById(ids[index], item) and
        (item is TTaskItem) then
      begin
          FItems.Forget(ids[index]);
        DisposeOwnedItem(item, 'ItemManager.CheckDeleted');
      end;
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
function TItemManager.ItemIndex(HWnd: THandle): integer;
begin
  result := FItems.IndexOf(ItemViews.ItemIdOf(HWnd));
  if result = NO_ITEM_INDEX then result := NOT_AN_ITEM;
end;
//------------------------------------------------------------------------------
function TItemManager.ItemHWnd(index: integer): THandle;
begin
  result := 0;
  if (index >= 0) and (index < LayoutCount) then result := ItemViews.HandleOf(FItems[index]^.Id);
end;
//------------------------------------------------------------------------------
procedure TItemManager.Load(fsets: string);
var scope: TItemHostScope;
  idx: integer;
  ini: TIniFile;
  list, Names: TStrings;
  ItemType: TItemType;
  Section, ClassName: string;
  KnownCount: integer;
  procedure PreserveSection;
  var Entry, ValueIndex: integer;
  begin
    Entry := Length(FUnknownItems);
    SetLength(FUnknownItems, Entry + 1);
    FUnknownItems[Entry].BeforeItem := KnownCount;
    Names.Clear;
    ini.ReadSection(Section, Names);
    SetLength(FUnknownItems[Entry].Values, Names.Count);
    for ValueIndex := 0 to Names.Count - 1 do
    begin
      FUnknownItems[Entry].Values[ValueIndex].Name := Names[ValueIndex];
      FUnknownItems[Entry].Values[ValueIndex].Value :=
        ReadIniStringW(FSetsFilename, Section, Names[ValueIndex], '');
    end;
  end;

begin
  scope := BeginItemHostOperation(FParentHWnd);
  inc(FLoadDepth);
  try
    if fsets = '' then exit;
    if FItems.CancelDrag <> 0 then ItemDock(ItemViews.HandleOf(FDragItemId));
    FItems.ClearPreview;
    SyncDropPlace;
    FDropPlaceEx := NOT_AN_ITEM;
    FDraggingItem := false;
    FDraggingFile := false;
    FDragItemId := 0;

    try
      FSetsFilename := fsets;
      ini  := TIniFile.Create(FSetsFilename);
      list := TStringList.Create;
      Names := TStringList.Create;
      ini.ReadSections(list);
    except
      on e: Exception do err('ItemManager.Load.ReadIni', e, true);
    end;
    {$ifdef EXT_DEBUG} AddLog('TItemManager.Load.ReadIni'); {$endif}

    // read items //
    try
      idx := 0;
      KnownCount := 0;
      FUnknownItems := nil;
      while idx < list.count do
      begin
        Section := list[idx];
        if Pos('item', LowerCase(Section)) = 1 then
        begin
          ClassName := LowerCase(Trim(ReadIniStringW(FSetsFilename, Section, 'class', 'shortcut')));
          if not ItemTypes.Find(ClassName, ItemType) or not ItemType.Persistent then PreserveSection
          else
          try
            if AddItem(CreateItemFromIni(FSetsFilename, Section), False) = 0 then PreserveSection
            else Inc(KnownCount);
          except
            on E: Exception do
            begin
              AddLog('Cannot load ' + Section + ': ' + E.Message);
              PreserveSection;
            end;
          end;
        end;
        {$ifdef EXT_DEBUG} AddLog(list.strings[idx]); {$endif}
        inc(idx);
      end;
      Names.Free;
      ini.free;
      list.free;
    except
      on e: Exception do err('ItemManager.Load.ReadItems', e, true);
    end;
    {$ifdef EXT_DEBUG} AddLog('TItemManager.Load.ReadItems'); {$endif}

    if (ItemCount = 0) and (Length(FUnknownItems) = 0) then LoadDefault; // create default items if nothing loaded //

    ItemsChanged;
    {$ifdef EXT_DEBUG} AddLog('TItemManager.Load.ItemsChanged'); {$endif}
  finally
    dec(FLoadDepth);
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
procedure TItemManager.LoadDefault;
var
  stack: TStackItem;
  wnd: HWND;
  id: TItemId;
begin
  try
      // "end session" stack //
      wnd := AddItem(CreateItemFromString(TStackItem.Make('End session')));
      stack := TStackItem(GetManagedItem(wnd));
      if (stack is TStackItem) and stack.Pin then
      begin
        id := stack.ItemId;
        try
          {$ifdef EXT_DEBUG} AddLog('TItemManager.Load.Default.Stack is TStackItem'); {$endif}
          stack.AddSubitem(TShortcutItem.Make('Shutdown', '/shutdown', '', '', 'images\default\shutdown.png'));
          if not stack.Freed then stack.AddSubitem(TShortcutItem.Make('Reboot', '/reboot', '', '', 'images\default\reboot.png'));
          if not stack.Freed then stack.AddSubitem(TShortcutItem.Make('Suspend', '/suspend', '', '', 'images\default\suspend.png'));
          if not stack.Freed then stack.AddSubitem(TShortcutItem.Make('Hibernate', '/hibernate', '', '', 'images\default\hibernate.png'));
        finally ReleaseItemModel(id); end;
      end;
      {$ifdef EXT_DEBUG} AddLog('TItemManager.Load.Default.Stack'); {$endif}
      // basic items //
      AddItem(CreateItemFromString(TShortcutItem.Make(UTF8Decode(XStartButtonText), '/startmenu', '', '', 'images\default\start.png')));
      AddItem(CreateItemFromString(TShortcutItem.Make('Computer', 'CSIDL_DRIVES', '', '', '')));
      AddItem(CreateItemFromString(TShortcutItem.Make('Control panel', 'CSIDL_CONTROLS', '', '', '')));
      AddItem(CreateItemFromString(TShortcutItem.Make('Parameters', 'ms-settings:', '', '', '%sysdir%\shell32.dll,315')));
      AddItem(CreateItemFromString(TShortcutItem.Make('Documents', '%doc%', '', '', '')));
      AddItem(CreateItemFromString(TShortcutItem.Make('Recycle bin', 'CSIDL_BITBUCKET', '', '', '')));
      AddItem(CreateItemFromString(TShortcutItem.Make('Dock settings', '/sets', '', '', 'images\default\settings.png')));
      AddItem(CreateItemFromString(TShortcutItem.Make('Theme', '/theme', '', '', 'images\default\theme.png')));
      AddItem(CreateItemFromString(TSeparatorItem.Make));
      AddItem(CreateItemFromString(TShortcutItem.Make('Tray', '/tray', '', '', 'images\default\tray.png')));
      AddItem(CreateItemFromString(TShortcutItem.Make('', '', '', '', 'images\default\{LANGID}.png')));
      AddItem(CreateItemFromString(TShortcutItem.Make('', '/networks', '', '', 'images\default\network-{NETWORK}.png')));
      AddItem(CreateItemFromString(TShortcutItem.Make('', '/volume', '', '', 'images\default\audio-volume-{VOLUME}.png')));
      {$ifdef EXT_DEBUG} AddLog('TItemManager.Load.Default.basic items'); {$endif}
  except
      on e: Exception do err('ItemManager.LoadDefault', e);
  end;
  {$ifdef EXT_DEBUG} AddLog('TItemManager.LoadDefault.done'); {$endif}
end;
//------------------------------------------------------------------------------
procedure TItemManager.Save(fsets: string);
var scope: TItemHostScope;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    try
      if fsets <> '' then FSetsFilename := toolu.UnzipPath(fsets);
      SaveItems;
    except
      on e: Exception do err('ItemManager.Save', e);
    end;
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
procedure TItemManager.SaveItems;
begin
  if FEnabled then SaveItemsTo(FSetsFilename);
end;
//------------------------------------------------------------------------------
procedure TItemManager.SaveTo(const Filename: string);
var scope: TItemHostScope;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    if not FEnabled or (FLoadDepth <> 0) or (FRebuildDepth <> 0) then
      raise Exception.Create('Item snapshot is unavailable during initialization or rebuild');
    SaveItemsTo(Filename);
  finally
    EndItemHostOperation(scope);
  end;
end;

procedure TItemManager.SaveItemsTo(const Filename: string);
var scope: TItemHostScope; identities: TItemIdentities; Index, SectionIndex: integer;
  Item: TCustomItem; Entry: TItemType; Unknown: TLegacyItemSections;
  NextUnknown, KnownCount: integer;
  procedure ClearPreviousSections;
  var Ini: TIniFile; Sections: TStringList; Section: string;
  begin
    Sections := TStringList.Create;
    try
      Ini := TIniFile.Create(Filename);
      try Ini.ReadSections(Sections); finally Ini.Free; end;
      for Section in Sections do
        if Pos('item', LowerCase(Section)) = 1 then ClearIniSectionW(Filename, Section);
    finally Sections.Free; end;
  end;
  procedure SaveUnknown;
  var Value: TLegacyItemValue; Section: string;
  begin
    Inc(SectionIndex);
    Section := 'item' + IntToStr(SectionIndex);
    ClearIniSectionW(Filename, Section);
    for Value in Unknown[NextUnknown].Values do
      WriteIniStringW(Filename, Section, Value.Name, Value.Value);
    Inc(NextUnknown);
  end;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    identities := CaptureItems(True);
    Unknown := FUnknownItems;
    ClearPreviousSections;
    SectionIndex := 0;
    NextUnknown := 0;
    KnownCount := 0;
    for Index := 0 to High(identities) do
      if (FItems.SaveIndexOf(identities[Index].ItemId) <> NO_ITEM_INDEX) and
        PinManagedItem(identities[Index], Item) then
      try
        if ItemTypes.FindClass(TCustomItemClass(Item.ClassType), Entry) and not Entry.Persistent then Continue;
        while (NextUnknown < Length(Unknown)) and
          (Unknown[NextUnknown].BeforeItem <= KnownCount) do SaveUnknown;
        Inc(SectionIndex);
        Item.Save(Filename, 'item' + IntToStr(SectionIndex));
        Inc(KnownCount);
      finally ItemRegistry.Unpin(identities[Index]); end;
    while NextUnknown < Length(Unknown) do SaveUnknown;
  finally EndItemHostOperation(scope); end;
end;
//------------------------------------------------------------------------------
procedure TItemManager.SaveItem(wnd: HWND);
var scope: TItemHostScope;
  index: integer;
  Inst: TCustomItem; identity: TItemIdentity;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    try
      index := FItems.SaveIndexOf(ItemViews.ItemIdOf(wnd));
      if index = NO_ITEM_INDEX then exit;
      identity := ItemRegistry.IdentityOf(wnd);
      if PinManagedItem(identity, Inst) then
      try
        Inst.Save(FSetsFilename, 'item' + inttostr(index + 1));
      finally
        ItemRegistry.Unpin(identity);
      end;
    except
      on e: Exception do raise Exception.Create('ItemManager.SaveItem::' + inttostr(index) + LineEnding + e.message);
    end;
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
// insert a list of Files at DropPlace position
// if DropPlace not exists, then insert at the end of the items array
procedure TItemManager.InsertFiles(list: TStrings);
var
  i, dplace: integer;
begin
  if not FEnabled then exit;
  dplace := FDropPlace;
  try
    for i := 0 to list.Count - 1 do
    begin
      if InsertFile(list.strings[i]) <> 0 then
        if dplace <> NOT_AN_ITEM then inc(dplace);
      if (dplace <> NOT_AN_ITEM) and (i < list.Count - 1) then
      begin
        SetDropPlace(dplace);
        SetDropPlaceEx(dplace);
      end;
    end;
  finally
    if not FDraggingItem then SetDropPlace(NOT_AN_ITEM);
  end;
end;
//------------------------------------------------------------------------------
function TItemManager.InsertTaskbarLauncher(const Data: TShortcutDtoV1): Boolean;
begin
  Result := InsertItem(WriteShortcutText(Data)) <> 0;
end;

function IsImportedShortcut(const Command: string; const StorageRoot: UnicodeString): Boolean;
var Path, Root, Relative, Stage: UnicodeString; Slash: Integer; Id: TGUID;
begin
  Result := False;
  if StorageRoot = '' then Exit;
  Path := ShellUTF16(UnzipPath(Command));
  Root := ExcludeTrailingPathDelimiter(StorageRoot) + '\';
  if UnicodeLowerCase(Copy(Path, 1, Length(Root))) <> UnicodeLowerCase(Root) then Exit;
  if not SameText(ExtractFileExt(Command), '.lnk') then Exit;
  Relative := Copy(Path, Length(Root) + 1, MaxInt);
  Slash := Pos(UnicodeString('\'), Relative);
  if Slash = 0 then Exit;
  Stage := Copy(Relative, 1, Slash - 1);
  if Copy(Stage, 1, 7) <> 'import-' then Exit;
  try Id := StringToGUID(ShellUTF8(Copy(Stage, 8, MaxInt)));
  except Exit; end;
  Result := True;
end;

function TItemManager.RepointTaskbarLauncher(const Data: TShortcutDtoV1): Boolean;
var Identities: TItemIdentities; Identity: TItemIdentity; Item: TCustomItem;
  Shortcut: TShortcutItem; Draft: TShortcutDtoV1; Key, Previous: string;
begin
  Result := False;
  Key := TaskbarLauncherKey(Data);
  Identities := CaptureItems(True);
  for Identity in Identities do
    if PinManagedItem(Identity, Item) then
    try
      if not (Item is TShortcutItem) then Continue;
      Shortcut := TShortcutItem(Item);
      if not IsImportedShortcut(Shortcut.Command, FTaskbarImportStorage) then Continue;
      Draft := ReadShortcutText(Shortcut.ToString);
      if TaskbarLauncherKey(Draft) <> Key then Continue;
      Previous := Shortcut.Command;
      Draft.Command := Data.Command;
      WriteShortcutText(Draft);
      try
        Shortcut.Command := Draft.Command;
        Shortcut.Update;
      except
        Shortcut.Command := Previous;
        try Shortcut.Update; except end;
        raise;
      end;
      Result := True;
    finally ItemRegistry.Unpin(Identity); end;
end;

function TItemManager.ImportTaskbar(const StorageRoot: UnicodeString;
  Source: TTaskbarSource; Mode: TTaskbarImportMode): TTaskbarImportResult;
var Scope: TItemHostScope; Identities: TItemIdentities; Identity: TItemIdentity;
  Item: TCustomItem; Keys: TStringList; OwnSource: Boolean;
begin
  Result := Default(TTaskbarImportResult);
  if not FEnabled or FDraggingItem or FDraggingFile or FTaskbarImporting or
    (FLoadDepth <> 0) or (FRebuildDepth <> 0) then
  begin
    Result.Warning := XTaskbarImportBusy;
    Exit;
  end;
  Scope := BeginItemHostOperation(FParentHWnd);
  Keys := TStringList.Create;
  OwnSource := Source = nil;
  FTaskbarImporting := True;
  FTaskbarImportStorage := StorageRoot;
  try
    if OwnSource then Source := TTaskbarSource.Create;
    Identities := CaptureItems(True);
    for Identity in Identities do
      if PinManagedItem(Identity, Item) then
      try
        if Item is TShortcutItem then
          Keys.Add(TaskbarLauncherKey(ReadShortcutText(Item.ToString)));
      finally ItemRegistry.Unpin(Identity); end;
    SetDropPlace(NOT_AN_ITEM);
    Result := ImportTaskbarPins(Source.ReadPins, StorageRoot, Keys, InsertTaskbarLauncher,
      Mode, RepointTaskbarLauncher);
  finally
    FTaskbarImporting := False;
    FTaskbarImportStorage := '';
    SetDropPlace(NOT_AN_ITEM);
    if OwnSource then Source.Free;
    Keys.Free;
    EndItemHostOperation(Scope);
  end;
end;
//------------------------------------------------------------------------------
procedure TItemManager.ImportDropFiles(Batch: TDropImportBatch; wndItem: HWND; pt: windows.TPoint);
var I, Place: Integer; Single: TStringList; Accepted, Targeted: Boolean;
begin
  Place := FDropPlace;
  // Capture the destination before handlers can remove or replace their windows.
  Targeted := IsItem(wndItem) <> 0;
  Single := TStringList.Create;
  try
    for I := 0 to Batch.Count - 1 do
    begin
      Single.Clear;
      Single.Add(Batch[I]);
      Accepted := FEnabled and ItemDropFiles(wndItem, pt, Single);
      if not Accepted and FEnabled and not Targeted then
      begin
        Accepted := InsertFile(Batch[I]) <> 0;
        if Accepted and (Place <> NOT_AN_ITEM) then
        begin
          Inc(Place);
          if I < Batch.Count - 1 then
          begin SetDropPlace(Place); SetDropPlaceEx(Place); end;
        end;
      end;
      Batch.Decide(I, Accepted);
    end;
  finally
    Single.Free;
    if not FDraggingItem then SetDropPlace(NOT_AN_ITEM);
  end;
end;
//------------------------------------------------------------------------------
// insert a File at current DropPlace
// or at the end of array if DropPlace does not exist (e.g. DropPlace = NOT_AN_ITEM)
function TItemManager.InsertFile(Filename: string): THandle;
begin
  result := 0;
  if FEnabled then result := InsertItem(TShortcutItem.MakeFromFilename(Filename));
end;
//------------------------------------------------------------------------------
// insert item at current DropPlace
// or at the end of array if DropPlace does not exist (e.g. DropPlace = NOT_AN_ITEM)
function TItemManager.InsertItem(AData: string): THandle;
begin
  result := 0;
  if FEnabled then result := AddItem(CreateItemFromString(AData), true);
end;
//------------------------------------------------------------------------------
// put an Item onto dock
function TItemManager.AddItem(wnd: HWND; Update: boolean = false): THandle;
var scope: TItemHostScope; item: TCustomItem; identity: TItemIdentity;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    result := 0;
    identity := ItemRegistry.IdentityOf(wnd);
    if not PinManagedItem(identity, item) then exit;
    try
      try
        AllItemCmd(icHover, 0);
        AllItemCmd(icSelect, 0);
        if item.Freed then exit;
        if not FModels.Add(item) then exit;
        if FItems.Add(item.ItemId, FItemSize) then
        begin

          ActivateItem(wnd, Update);
          if not item.Freed and FItems.Contains(ItemViews.ItemIdOf(wnd)) then result := wnd;
        end;
      except
        if not FItems.Contains(ItemViews.ItemIdOf(wnd)) then DisposeOwnedItem(item, 'ItemManager.AddItem');
        raise;
      end;
    finally
      ItemRegistry.Unpin(identity);
    end;
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
function TItemManager.CreateItemFromIni(IniFile, IniSection: string): THandle;
begin
  try
    result := CreateItem(IniFile, IniSection, '');
  except
    on e: Exception do raise Exception.Create('ItemManager.CreateItemFromIni ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
function TItemManager.CreateItemFromString(value: string): THandle;
begin
  try
    result := CreateItem('', '', value);
  except
    on e: Exception do raise Exception.Create('ItemManager.CreateItemFromString ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
function TItemManager.CreateTaskItem: THandle;
begin
  try
    result := CreateItem('', '', TTaskItem.Make);
  except
    on e: Exception do raise Exception.Create('ItemManager.CreateTaskItem ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
function TItemManager.CreatePluginItem(var Params: TDItemCreateParams): TCustomItem;
begin
  result := TPluginItem.Create(FParentHWnd, Params);
end;

function TItemManager.CreateItem(IniFile, IniSection, Parameter: string): THandle;
var scope: TItemHostScope;
  ClassName: string;
  ItemType: TItemType;
  icp: TDItemCreateParams;
  Inst: TCustomItem; identity: TItemIdentity; pinned: boolean; failure: string;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  FModels.BeginCreation;
  try
    result := 0;
    Inst := nil;
    pinned := false;
    try
      icp := Default(TDItemCreateParams);
      icp.ItemSize              := FItemSize;
      icp.BigItemSize           := FBigItemSize;
      icp.ItemSpacing           := FItemSpacing;
      icp.LaunchInterval        := FLaunchInterval;
      icp.ActivateRunning       := FActivateRunning;
      icp.UseShellContextMenus  := FUseShellContextMenus;
      icp.Site                  := integer(FSite);
      icp.Reflection            := FReflection;
      icp.ReflectionSize        := FReflectionSize;
      icp.ShowHint              := FShowHint;
      icp.AnimationType         := FItemAnimation;
      icp.LockDragging          := FLockDragging;
      icp.StackAnimationEnabled := FStackAnimationEnabled;
      icp.SeparatorAlpha        := FSeparatorAlpha;
      icp.AeroPeekEnabled       := FAeroPeekEnabled;
      icp.TaskLivePreviews      := FTaskLivePreviews;
      icp.TaskThumbSize         := FTaskThumbSize;
      icp.TaskGrouping          := FTaskGrouping;
      icp.TaskSystemMenus       := FTaskSystemMenus;
      CopyFontData(FFont, icp.Font);
      if IniFile <> '' then
      begin
        icp.IniFile := IniFile;
        icp.IniSection := IniSection;
        icp.Parameter := '';
        ClassName := LowerCase(Trim(ReadIniStringW(IniFile, IniSection, 'class', 'shortcut')));
      end else begin
        icp.IniFile := '';
        icp.IniSection := '';
        icp.Parameter := Parameter;
        ClassName := LegacyItemClass(Parameter);
      end;

      if ItemTypes.Find(ClassName, ItemType) then
      begin
        if Assigned(ItemType.Validate) then ItemType.Validate(icp);
        if ItemType.Plugin then Inst := CreatePluginItem(icp)
        else Inst := ItemType.ItemClass.Create(FParentHWnd, icp);
      end;
      if assigned(Inst) then
      begin
        if Inst.State = imsRetiring then exit;
        if not FModels.Add(Inst) then raise Exception.Create('Item belongs to another model store');
        identity := ItemRegistry.IdentityOf(Inst.Handle);
        pinned := PinManagedItem(identity, Inst);
        if not pinned then exit;
        if Inst is TPluginItem then TPluginItem(Inst).CallCreate;
      end;
    except
      on e: Exception do
      begin
        failure := 'ItemManager.CreateItem.' + ClassName + LineEnding + e.Message;
        if assigned(Inst) then DisposeOwnedItem(Inst, 'ItemManager.CreateItem');
        raise Exception.Create(failure);
      end;
    end;

    try
      if assigned(Inst) then
        if Inst.Freed then DisposeOwnedItem(Inst, 'ItemManager.CreateItem.Fin') else result := Inst.Handle;
    except
      on e: Exception do raise Exception.Create('ItemManager.CreateItem.Fin ' + LineEnding + e.message);
    end;
  finally
    try
      if pinned then ItemRegistry.Unpin(identity);
    finally
      try
        try FModels.EndCreation;
        except on E: Exception do AddLog('ItemManager.CreationCleanup' + LineEnding + E.Message); end;
      finally EndItemHostOperation(scope); end;
    end;
  end;
end;
//------------------------------------------------------------------------------
// do not call directly !!!
// items call this using DockH.DockDeleteItem
// use TCustomItem.Delete instead
procedure TItemManager.DeleteItem(HWnd: THandle);
begin DeleteItemById(ItemViews.ItemIdOf(HWnd)); end;

procedure TItemManager.DeleteItemById(Id: TItemId);
var scope: TItemHostScope; index: integer; item: TCustomItem; deleted: boolean;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    if FEnabled and TryGetItemById(Id, item) and item.Pin then
    try
      index := FItems.IndexOf(Id);
      deleted := FItems.Delete(Id);
      if not deleted and (item.State = imsPending) then deleted := FItems.DeletePending(Id, FItemSize);
      if deleted then
      begin
        item.State := imsDeleted;
        item.Freed := true;
        EnableWindow(item.Handle, false);
        ShowWindow(item.Handle, SW_HIDE);
        try item.PrepareDeletion;
        finally
          ItemViews.ForgetMouseLocks(Id);
          SyncDropPlace;
          FDraggingItem := FItems.DraggedId <> 0;
          FDragItemId := FItems.DraggedId;
          if not FDraggingItem then FDropPlaceEx := NOT_AN_ITEM;
          if (index <> NOT_AN_ITEM) and (FDropPlaceEx <> NOT_AN_ITEM) then
          begin
            if FDropPlaceEx = index then FDropPlaceEx := NOT_AN_ITEM
            else if FDropPlaceEx > index then dec(FDropPlaceEx);
          end;
          if FHoverItemId = Id then FHoverItemId := 0;
          if FSelectedItemId = Id then FSelectedItemId := 0;
          ItemsChanged;
          if assigned(FOnItemRemoved) then FOnItemRemoved(Id);
          FlushPendingTasks;
        end;
      end;
    finally
      ReleaseItemModel(Id);
    end;
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
//
//
//
//
//
//
//
//------------------------------------------------------------------------------
function TItemManager.ZOrder(InsertAfter: THandle): THandle;
var scope: TItemHostScope; identities: TItemIdentities; index: integer; item: TCustomItem;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    result := 0;
    if not FEnabled then exit;
    identities := CaptureItems(false);
    if Length(identities) > 0 then result := identities[0].Handle;
    for index := 0 to High(identities) do
      if PinActiveItem(identities[index], item) then
      try
        SetWindowPos(identities[index].Handle, InsertAfter, 0, 0, 0, 0, SWP_NO_FLAGS);
      finally
        ItemRegistry.Unpin(identities[index]);
      end;
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
// entry point for a timer event
// preferrably > 10 times per second
procedure TItemManager.ForegroundChanged(wnd: HWND);
var scope: TItemHostScope; identities: TItemIdentities; index: integer; item: TCustomItem;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    if not FEnabled then exit;
    identities := CaptureItems(false);
    for index := 0 to High(identities) do
      if PinActiveItem(identities[index], item) then
      try
        item.ForegroundChanged(wnd);
      finally
        ItemRegistry.Unpin(identities[index]);
      end;
  finally
    EndItemHostOperation(scope);
  end;
end;

function TItemManager.ClockNow: QWord;
begin Result := GetTickCount64; end;

function TItemManager.MotionNow: Double;
begin Result := AnimationTimeMs; end;

function TItemManager.FinishPositionBatch(Batch: HDWP): boolean;
begin Result := EndDeferWindowPos(Batch); end;

function TItemManager.NeedsFrames: boolean;
var scope: TItemHostScope; identities: TItemIdentities; index: integer; item: TCustomItem;
begin
  Result := false;
  scope := BeginItemHostOperation(FParentHWnd);
  try
    if not FEnabled then exit;
    if FWndOffsetQueued or FZoomLayoutDirty or FZoomAnimation.ActiveAt(MotionNow) then exit(true);
    identities := CaptureItems(false);
    for index := 0 to High(identities) do
      if PinActiveItem(identities[index], item) then
      try
        if item.NeedsFrame then exit(true);
      finally
        ItemRegistry.Unpin(identities[index]);
      end;
  finally
    EndItemHostOperation(scope);
  end;
end;

procedure TItemManager.Timer;
var scope: TItemHostScope; SamplingComplete: Boolean;
  procedure FlushFrame;
  begin
    if FFrameLayoutDirty then ItemsChanged(FFrameFullUpdate)
    else if FFrameItemsDirty then UpdateItems(false);
  end;
begin
  if FFrameRunning then exit;
  FFrameRunning := true;
  scope := Default(TItemHostScope);
  try
    scope := BeginItemHostOperation(FParentHWnd);
    BeginAnimationFrame;
    try
    if FEnabled then
    begin
      FFrameItemsDirty := false;
      FFrameLayoutDirty := false;
      FFrameFullUpdate := false;
      FSamplingFrames := true;
      SamplingComplete := false;
      try
        if FWndOffsetQueued then SetWndOffset(FQueuedWndOffset);
        ZoomInOut;
        AllItemTimer;
        SamplingComplete := true;
      finally
        FSamplingFrames := false;
        if SamplingComplete then FlushFrame
        else
          try FlushFrame;
          except on E: Exception do AddLog('Item frame cleanup: ' + E.Message); end;
      end;
    end;
    finally EndAnimationFrame; end;
  finally
    FFrameRunning := false;
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
procedure TItemManager.SetTheme;
var scope: TItemHostScope;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    AllItemCmd(tcThemeChanged, 0);
    ItemsChanged(true);
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
procedure TItemManager.ItemsChanged(FullUpdate: boolean = false);
var scope: TItemHostScope;
begin
  if FSamplingFrames then
  begin
    FFrameLayoutDirty := true;
    FFrameFullUpdate := FFrameFullUpdate or FullUpdate;
    exit;
  end;
  scope := BeginItemHostOperation(FParentHWnd);
  try
    if FEnabled then
    try
      inc(FLayoutRevision);
      RecalcItems;
      RecalcDock;
      UpdateItems(FullUpdate);
      UpdateDock(FullUpdate);
    except
      on e: Exception do err('ItemManager.ItemsChanged', e);
    end;
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
procedure TItemManager.SetVisible(value: boolean);
var scope: TItemHostScope;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    if FVisible <> value then
    begin
      UnZoom(true);
      AllItemCmd(icHover, 0);
      AllItemCmd(icSelect, 0);
      AllItemCmd(icVisible, PtrInt(value));
      FHoverItemId := 0;
      FSelectedItemId := 0;
    end;
    FVisible := value;
    ItemsChanged;
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
procedure TItemManager.RecalcItems;
var items: TDockLayoutItems; i: integer;
begin
  if not FEnabled then exit;
  items := CalculateItemLayout(GetLayoutInput, GetLayoutItems);
  for i := 0 to High(items) do
  begin
    FItems[i]^.x := items[i].X;
    FItems[i]^.y := items[i].Y;
    FItems[i]^.s := items[i].Size;
    FItems[i]^.xe := items[i].ExactX;
    FItems[i]^.ye := items[i].ExactY;
    FItems[i]^.se := items[i].ExactSize;
  end;
end;
//------------------------------------------------------------------------------
procedure TItemManager.RecalcDock;
var geometry: TDockGeometry;
begin
  if not FEnabled then exit;
  geometry := CalculateDockGeometry(GetLayoutInput, GetLayoutItems);
  x := geometry.X;
  y := geometry.Y;
  width := geometry.Width;
  height := geometry.Height;
  widthZoomed := geometry.WidthZoomed;
  heightZoomed := geometry.HeightZoomed;
  FBaseImageRect := geometry.BaseImageRect;
  FBaseWindowRect := geometry.BaseWindowRect;
end;
//------------------------------------------------------------------------------
function TItemManager.GetRect: windows.TRect;
begin
  result := DockBounds(GetLayoutInput, GetDockGeometry);
end;
//------------------------------------------------------------------------------
function TItemManager.GetZoomEdge: integer;
begin
  result := 0;
  case FSite of
    bsLeft: result := FBaseWindowRect.X + x + widthZoomed;
    bsTop: result := FBaseWindowRect.Y + y + heightZoomed;
    bsRight: result := FBaseWindowRect.X + x + width - widthZoomed;
    bsBottom: result := FBaseWindowRect.Y + y + height - heightZoomed;
  end;
end;
//------------------------------------------------------------------------------
procedure TItemManager.SetWndOffset(value: integer);
begin
  FWndOffsetQueued := false;
  if FWndOffset <> value then
  begin
    FWndOffset := value;
    ItemsChanged;
  end;
end;

procedure TItemManager.QueueWndOffset(Value: Integer);
begin
  FQueuedWndOffset := Value;
  FWndOffsetQueued := Value <> FWndOffset;
end;
//------------------------------------------------------------------------------
procedure TItemManager.UpdateItems(forceDraw: boolean);
var scope: TItemHostScope; identities: TItemIdentities; geometry: TItemArray; index: integer;
  item: TCustomItem; wpi: HDWP; showItems: uint;
  revision: QWord; registered: TObject;
  batchStarted, batchSucceeded: boolean;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    if not FEnabled then exit;
    revision := FLayoutRevision;
    SetLength(geometry, LayoutCount);
    for index := 0 to High(geometry) do geometry[index] := FItems[index]^;
    SetLength(identities, Length(geometry));
    for index := 0 to High(geometry) do
      identities[index] := ItemViews.IdentityForId(geometry[index].Id);
    wpi := BeginDeferWindowPos(Length(identities));
    batchStarted := wpi <> 0;
    showItems := SWP_HIDEWINDOW;
    if FVisible then showItems := SWP_SHOWWINDOW;
    try
      for index := 0 to High(identities) do
      begin
        if PinActiveItem(identities[index], item) then
        try
          item.SetDockTarget(geometry[index].x, geometry[index].y);
          if item is TCustomDrawItem then
            TCustomDrawItem(item).DrawInPositionBatch(geometry[index].x,
              geometry[index].y, geometry[index].s,
              item.TakeFrameDrawForce or forceDraw, wpi, showItems)
          else
            item.Draw(geometry[index].x, geometry[index].y, geometry[index].s,
              item.TakeFrameDrawForce or forceDraw, wpi, showItems);
        finally
          ItemRegistry.Unpin(identities[index]);
        end;
        if revision <> FLayoutRevision then break;
      end;
    finally
      if batchStarted then
      begin
        batchSucceeded := false;
        if wpi <> 0 then batchSucceeded := FinishPositionBatch(wpi);
        // A failed batch can discard positions for earlier items.
        if not batchSucceeded then
          for index := 0 to High(identities) do
            if PinActiveItem(identities[index], item) then
            try
              if item is TCustomDrawItem then
                TCustomDrawItem(item).InvalidateNativePresentation;
            finally
              ItemRegistry.Unpin(identities[index]);
            end;
      end;
    end;
    if revision <> FLayoutRevision then
    begin
      for index := 0 to High(identities) do
        if (FItems.IndexOf(identities[index].ItemId) = NO_ITEM_INDEX) and
          ItemRegistry.TryResolve(identities[index], FParentHWnd, registered) then
          ShowWindow(identities[index].Handle, SW_HIDE);
      UpdateItems(true);
    end;
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
//
//
//     Misc
//
//
//------------------------------------------------------------------------------
// calculate and set DropPlace and DropPlaceEx
procedure TItemManager.SetDropPlaceFromPoint(pt: windows.TPoint);
var
  tmp: extended;
  prevDropPlace, prevDropPlaceEx: integer;
begin
  prevDropPlace := FDropPlace;
  prevDropPlaceEx := FDropPlaceEx;

  if FEnabled then
  try
    // FDropPlace //
    tmp := ItemFromPoint(pt.x, pt.y, FDropDistance);
    if tmp = NOT_AN_ITEM then
    begin
      FDropPlace := NOT_AN_ITEM;
    end else begin
      if FDropPlace = NOT_AN_ITEM then FDropPlace := round(tmp)
      else
      if (abs(FDropPlace + 0.5 - tmp) > 1.2) or (tmp = -1) then FDropPlace := round(tmp - 0.5);
      // "+0.5" to count from the center of the FDropPlace. And "-0.5" to compensate the "+0.5"
    end;

    if FDropPlace <> NOT_AN_ITEM then
    begin
      if FDropPlace < 0 then FDropPlace := 0;
      if LayoutCount < 1 then FDropPlace := 0
      else begin
        if FDraggingFile then
        begin
          if prevDropPlace = NOT_AN_ITEM then
          begin
            if FDropPlace > LayoutCount then FDropPlace := NOT_AN_ITEM;
          end else begin
            if FDropPlace >= LayoutCount then FDropPlace := NOT_AN_ITEM;
          end;
        end else
        if prevDropPlace = NOT_AN_ITEM then
        begin
          if FDropPlace > LayoutCount then FDropPlace := LayoutCount;
        end else begin
          if FDropPlace >= LayoutCount then FDropPlace := LayoutCount - 1;
        end;
      end;
    end;
    if prevDropPlace <> FDropPlace then SetDropPlace(FDropPlace);

    // FDropPlaceEx //
    tmp := ItemRectFromPoint(pt.x, pt.y);
    if tmp = NOT_AN_ITEM then tmp := FDropPlace;
    if tmp = NOT_AN_ITEM then FDropPlaceEx := NOT_AN_ITEM else FDropPlaceEx := round(tmp);
    if FDropPlaceEx <> NOT_AN_ITEM then
    begin
      if FDropPlaceEx < 0 then FDropPlaceEx := 0;
      if FDropPlaceEx > LayoutCount - 1 then FDropPlaceEx := NOT_AN_ITEM;
    end;
    if prevDropPlaceEx <> FDropPlaceEx then SetDropPlaceEx(FDropPlaceEx);
  except
    on e: Exception do err('ItemManager.CalcDropPlace', e);
  end;
end;
//------------------------------------------------------------------------------
// create, move, or remove the separate drag preview
procedure TItemManager.SetDropPlace(index: integer);
var previous: integer;
begin
  try
    AllItemCmd(icDropIndicator, 0);
    previous := FItems.PreviewIndex;
    if index = NOT_AN_ITEM then FItems.ClearPreview
    else FItems.SetPreview(index, FItemSize);
    SyncDropPlace;
    if previous <> FItems.PreviewIndex then
      ItemsChanged((previous = NO_ITEM_INDEX) or (FItems.PreviewIndex = NO_ITEM_INDEX));
  except
    on e: Exception do err('ItemManager.SetDropPlace', e);
  end;
end;
//------------------------------------------------------------------------------
// set appropriate indicator for an item at DropPlaceEx
procedure TItemManager.SetDropPlaceEx(index: integer);
var
  DragInst, Inst: TCustomItem;
  indicatorType: integer;
begin
  try
    if (index < 0) or (index >= LayoutCount) then index := NOT_AN_ITEM;
    FDropPlaceEx := index;
    indicatorType := DII_NONE;

    // correct invalid drop cases //
    if FDropPlaceEx <> NOT_AN_ITEM then
      if FDraggingItem then
      begin
        Inst := GetModel(FItems[FDropPlaceEx]^.Id);
        DragInst := GetModel(FDragItemId);

        if ((Inst is TStackItem) and (DragInst is TStackItem)) or
            ((Inst is TStackItem) and (DragInst is TShortcutItem)) or
            ((Inst is TShortcutItem) and (DragInst is TShortcutItem)) then
          indicatorType := DII_ADD;

        if indicatorType = DII_NONE then
          FDropPlaceEx := FDropPlace;
      end;

    if FDraggingItem then
    begin
      AllItemCmd(icDropIndicator, 0);
      if (indicatorType > 0) and (FDropPlaceEx >= 0) and (FDropPlaceEx < LayoutCount) then
        ItemCmd(ItemViews.HandleOf(FItems[FDropPlaceEx]^.Id), icDropIndicator, indicatorType);
    end;
  except
    on e: Exception do err('ItemManager.SetDropPlaceEx', e);
  end;
end;
//------------------------------------------------------------------------------
// items area width or height //
function TItemManager.IASize: integer;
begin
  result := LayoutCount * (FItemSize + FItemSpacing);
end;
//------------------------------------------------------------------------------
// calculate item index based on mouse position
// do not care of the current items positions
function TItemManager.ItemFromPoint(Ax, Ay, distance: integer): extended;
var emptyBounds: Windows.TRect;
begin
  result := NOT_AN_ITEM;
  if not FEnabled then exit;
  emptyBounds := Default(Windows.TRect);
  if LayoutCount = 0 then emptyBounds := DockGetRect;
  result := ItemPositionFromPoint(GetLayoutInput, GetDockGeometry,
    LayoutCount, Ax, Ay, distance, emptyBounds);
end;
//------------------------------------------------------------------------------
// calculate item index based on mouse position and items positions
function TItemManager.ItemRectFromPoint(Ax, Ay: integer): integer;
var rects: array of Windows.TRect; i: integer; item: TCustomItem;
  emptyBounds: Windows.TRect;
begin
  result := NOT_AN_ITEM;
  if not FEnabled then exit;
  emptyBounds := Default(Windows.TRect);
  if LayoutCount = 0 then emptyBounds := DockGetRect;
  SetLength(rects, LayoutCount);
  for i := 0 to High(rects) do
    if TryGetItemById(FItems[i]^.Id, item) then rects[i] := item.ScreenRect;
  result := ItemRectIndexFromPoint(rects, Ax, Ay, emptyBounds);
end;
//------------------------------------------------------------------------------
// enter/exit zooming mode, maintain zooming
procedure TItemManager.Zoom(x, y: integer);
var
  item: extended;
begin
  if FEnabled and not FDraggingFile then
  try
    item := NOT_AN_ITEM;
    if FZooming or CheckMouseOn or FDraggingItem then
    begin
      item := ItemFromPoint(x, y, ifthen(FDraggingItem, FDropDistance, 0));
      if item <> NOT_AN_ITEM then
      begin
        if item < 0 then item := NOT_AN_ITEM;
        if item >= LayoutCount then item := NOT_AN_ITEM;
      end;
    end;

    // enter FZooming mode //
    if not FZooming and (item <> NOT_AN_ITEM) then
    begin
      FZoomAnimation.Retarget(MotionNow, FBigItemSize - FItemSize, FZoomTime);
      FZoomInOutItem := item;
      FZooming := true;
    end;

    if FZooming then
    begin
      if item = NOT_AN_ITEM then Unzoom
      else begin
          if FZoomInOutItem <> item then
          begin
            FZoomInOutItem := item;
            FZoomLayoutDirty := true;
          end;
      end;
    end;
  except
    on e: Exception do err('ItemManager.Zoom', e);
  end;
end;
//------------------------------------------------------------------------------
// exit zooming mode
procedure TItemManager.UnZoom(do_now: boolean = false);
begin
  if FEnabled and (FZooming or do_now) then
  begin
    FZooming := false;
    FZoomAnimation.Retarget(MotionNow, 0, FZoomTime);
    if (LayoutCount <= 0) or do_now then
    begin
      ZoomItemSizeDiff := 0;
      FZoomAnimation.Reset(MotionNow, 0);
      FZoomLayoutDirty := false;
      ItemsChanged;
    end;
  end;
end;
//------------------------------------------------------------------------------
// meant to be called from a timer event handler
procedure TItemManager.RetargetZoom;
var target, limit: integer;
begin
  limit := Max(0, FBigItemSize - FItemSize);
  if FZooming and FZoomItems then target := limit else target := 0;
  FZoomAnimation.Retarget(MotionNow, target, FZoomTime);
  if FZoomAnimation.StartValue < 0 then FZoomAnimation.StartValue := 0;
  if FZoomAnimation.StartValue > limit then FZoomAnimation.StartValue := limit;
  ZoomInOut;
end;

procedure TItemManager.ZoomInOut;
var nextSize: integer;
begin
  if not FZoomItems and (ZoomItemSizeDiff = 0) then exit;
  // Round only displayed pixels. Preserve continuous position and velocity.
  nextSize := Round(FZoomAnimation.ValueAt(MotionNow));
  nextSize := EnsureRange(nextSize, 0, Max(0, FBigItemSize - FItemSize));
  if (nextSize = ZoomItemSizeDiff) and not FZoomLayoutDirty then exit;
  ZoomItemSizeDiff := nextSize;
  FZoomLayoutDirty := false;
  ItemsChanged;
end;
//------------------------------------------------------------------------------
// check mouse is over the dock
function TItemManager.CheckMouseOn: boolean;
var
  pt: windows.TPoint;
  wnd: THandle;
  item: integer;
begin
  result := false;
  if FEnabled then
  try
    if not GetCursorPoint(pt) then exit(false);
    wnd := WindowFromPoint(pt);
    if FDraggingItem or FDraggingFile or FZooming then
      item := trunc(ItemFromPoint(pt.x, pt.y, ifthen(FDraggingItem or FDraggingFile, FDropDistance, 0)))
    else
      item := ItemIndex(wnd);
    result := (item <> NOT_AN_ITEM) or (wnd = FParentHWnd);
  except
    on e: Exception do err('ItemManager.CheckMouseOn', e);
  end;
end;
//------------------------------------------------------------------------------
// entry point for MouseMove events
procedure TItemManager.WHMouseMove(pt: windows.Tpoint; allow_zoom: boolean = true);
var
  wnd: THandle;
begin
  if FEnabled and FVisible then
  try
    if LayoutCount > 0 then
    begin
      // hint //
      wnd := WindowFromPoint(pt);
      if ItemIndex(wnd) = NOT_AN_ITEM then wnd := 0;
      if ItemViews.ItemIdOf(wnd) <> FHoverItemId then
      begin
        if FHoverItemId <> 0 then ItemCmd(ItemViews.HandleOf(FHoverItemId), icHover, 0);
        if wnd <> 0 then ItemCmd(wnd, icHover, 1);
      end;
      FHoverItemId := ItemViews.ItemIdOf(wnd);
    end;

    if FDraggingItem or FDraggingFile then SetDropPlaceFromPoint(pt);

    if (LayoutCount > 0) and allow_zoom and FZoomItems then Zoom(pt.x, pt.y);
  except
    on e: Exception do raise Exception.Create('ItemManager.WHMouseMove ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
procedure TItemManager.DragEnter;
begin
  FDraggingItem := false;
  FDraggingFile := true;
  DragOver;
end;
//------------------------------------------------------------------------------
procedure TItemManager.DragLeave;
begin
  if FDraggingItem or FDraggingFile then
  begin
    FDraggingItem := FItems.DraggedId <> 0;
    if not FDraggingItem then FDragItemId := 0;
    FDraggingFile := false;
    SetDropPlaceEx(NOT_AN_ITEM);
    SetDropPlace(NOT_AN_ITEM);
    ItemsChanged;
    ItemCmd(ItemViews.HandleOf(FSelectedItemId), icDragLeave, 0);
    ItemCmd(ItemViews.HandleOf(FSelectedItemId), icSelect, 0);
    FSelectedItemId := 0;
    AllItemCmd(icHover, 0);
  end;
end;
//------------------------------------------------------------------------------
procedure TItemManager.DragOver;
var
  pt: windows.TPoint;
  wnd: THandle;
begin
  if FEnabled then
  try
    if not GetCursorPoint(pt) then exit;
    if not FLockMouseEffect then WHMouseMove(pt);
    wnd := WindowFromPoint(pt);
    wnd := IsItem(wnd);
    if ItemViews.ItemIdOf(wnd) <> FSelectedItemId then
    begin
      ItemCmd(ItemViews.HandleOf(FSelectedItemId), icSelect, 0);
      ItemCmd(ItemViews.HandleOf(FSelectedItemId), icDragLeave, 0);
      FSelectedItemId := ItemViews.ItemIdOf(wnd);
      ItemCmd(ItemViews.HandleOf(FSelectedItemId), icSelect, 1);
      ItemCmd(ItemViews.HandleOf(FSelectedItemId), icDragEnter, 0);
    end;
    ItemCmd(wnd, icDragOver, 0);
  except
    on e: Exception do err('ItemManager.DragOver', e);
  end;
end;
//------------------------------------------------------------------------------
procedure TItemManager.WMDeactivateApp;
var
  idx: integer;
begin
  if not CheckMouseOn then
  begin
    Unzoom;
    AllItemCmd(icHover, 0);
  end;

  if FEnabled then
  try
    idx := 0;
    while idx < LayoutCount do
    begin
      if FItems[idx]^.Id <> 0 then postmessage(ItemViews.HandleOf(FItems[idx]^.Id), WM_ACTIVATEAPP, 0, 0);
      inc(idx);
    end;
  except
    on e: Exception do err('ItemManager.WMDeactivate', e);
  end;
end;
//------------------------------------------------------------------------------
//
//
//
//   Window Item Procs
//
//
//
//------------------------------------------------------------------------------
// detach the item
procedure TItemManager.Undock(wnd: HWND);
var scope: TItemHostScope; item: TCustomItem; identity: TItemIdentity;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    if FEnabled and not FDraggingItem then
    try
      identity := ItemRegistry.IdentityOf(wnd);
      if not PinManagedItem(identity, item) then exit;
      try
        if not FItems.BeginDrag(ItemViews.ItemIdOf(wnd), FItemSize) then exit;
        item.State := imsDragging;

        FDraggingFile := false;
        FDraggingItem := true;
        FDragItemId := item.ItemId;
        SyncDropPlace;
        SetDropPlaceEx(FDropPlace);
        ItemsChanged(true);
      finally
        ItemRegistry.Unpin(identity);
      end;
    except
      on e: Exception do err('ItemManager.Undock', e);
    end;
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
// put the item to dock
// if necessary create a new stack or put into existing one
procedure TItemManager.Dock(wnd: HWND);
var scope: TItemHostScope; idx: integer;
  DragInst, Inst, NewInst: TCustomItem; NewItemWnd: THandle;
  MergeData: TStringList;
  dragIdentity, targetIdentity, newIdentity: TItemIdentity;
  pt: windows.TPoint;
  procedure Redock;
  begin
    if FItems.DropDragged <> 0 then ItemDock(wnd);
    SyncDropPlace;
  end;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    if not FEnabled or (FItems.DraggedId <> ItemViews.ItemIdOf(wnd)) then exit;
    dragIdentity := ItemRegistry.IdentityOf(wnd);
    if not PinManagedItem(dragIdentity, DragInst) then exit;
    try
      try
        try
          SetWindowPos(wnd, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE + SWP_NOSIZE + SWP_NOSENDCHANGING);
          if not GetCursorPoint(pt) then exit;
          SetDropPlaceFromPoint(pt);
          if DragInst.Freed or (FItems.DraggedId <> DragInst.ItemId) then exit;
          if FItems.PreviewIndex = NO_ITEM_INDEX then DragInst.Delete
          else if (FDropPlaceEx < 0) or (FDropPlaceEx >= LayoutCount) or
            (FDropPlace = FDropPlaceEx) then Redock
          else begin
            targetIdentity := ItemViews.IdentityForId(FItems[FDropPlaceEx]^.Id);
            if not PinActiveItem(targetIdentity, Inst) then
            begin
              Redock;
              exit;
            end;
            try
              if (DragInst is TShortcutItem) and (Inst is TStackItem) then
              begin
                if TStackItem(Inst).AddSubitem(TShortcutItem(DragInst).ToString) then
                begin
                  if not DragInst.Freed then DragInst.Delete;
                end else Redock;
              end else if (DragInst is TStackItem) and (Inst is TStackItem) then
              begin
                MergeData := TStringList.Create;
                try
                  for idx := 0 to TStackItem(DragInst).ItemCount - 1 do
                    MergeData.Add(TStackItem(DragInst).SubitemToString(idx));
                  if TStackItem(Inst).AddSubitems(MergeData) then
                  begin
                    if not DragInst.Freed then DragInst.Delete;
                  end else Redock;
                finally MergeData.Free; end;
              end else if (DragInst is TShortcutItem) and (Inst is TShortcutItem) then
              begin
                NewItemWnd := CreateItemFromString(TStackItem.Make);
                newIdentity := ItemRegistry.IdentityOf(NewItemWnd);
                if PinManagedItem(newIdentity, NewInst) then
                try
                  try
                    if not TStackItem(NewInst).AddSubitem(TShortcutItem(Inst).ToString) then
                      raise ERangeError.Create('Cannot copy the first shortcut');
                    if NewInst.Freed or DragInst.Freed then exit;
                    if not TStackItem(NewInst).AddSubitem(TShortcutItem(DragInst).ToString) then
                      raise ERangeError.Create('Cannot copy the second shortcut');
                    if AddItem(NewItemWnd) = 0 then raise Exception.Create('Cannot insert the new stack');
                  except
                    if not FItems.Contains(ItemViews.ItemIdOf(NewItemWnd)) then
                      DisposeOwnedItem(NewInst, 'ItemManager.Dock.NewStack');
                    raise;
                  end;
                  if not DragInst.Freed then DragInst.Delete;
                  if not Inst.Freed then Inst.Delete;
                finally
                  ItemRegistry.Unpin(newIdentity);
                end;
              end else Redock;
            finally
              ItemRegistry.Unpin(targetIdentity);
            end;
          end;
        except
          on e: Exception do err('ItemManager.Dock', e);
        end;
      finally
        if FItems.CancelDrag <> 0 then ItemDock(wnd);
        FDraggingItem := false;
        FDragItemId := 0;
        SetDropPlaceEx(NOT_AN_ITEM);
        SetDropPlace(NOT_AN_ITEM);
        ItemsChanged(true);
        FlushPendingTasks;
      end;
    finally
      ItemRegistry.Unpin(dragIdentity);
    end;
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
// search all items and their subitems for a given HWnd
// if item is found - result is HWnd
// if subitem is found - result is its parent item HWnd
// if no match found result is 0
function TItemManager.IsItem(wnd: HWND): HWND;
var scope: TItemHostScope; identities: TItemIdentities; index: integer; item: TCustomItem; candidate: PtrInt;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    result := 0;
    if not FEnabled then exit;
    identities := CaptureItems(false);
    for index := 0 to High(identities) do
      if PinActiveItem(identities[index], item) then
      try
        if identities[index].Handle = wnd then exit(wnd);
        candidate := item.cmd(icIsItem, PtrInt(wnd));
        if (candidate <> 0) and ResolveActiveItem(identities[index], item) then
          exit(HWND(candidate));
      finally
        ItemRegistry.Unpin(identities[index]);
      end;
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
function TItemManager.ItemDropFile(wndItem: HWND; pt: windows.TPoint; filename: string): boolean;
var scope: TItemHostScope;
  Inst: TCustomItem;
  wndChild: HWND; identity: TItemIdentity;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    try
      result := false;
      wndChild := wndItem;
      wndItem := IsItem(wndItem);
      if wndItem <> THandle(0) then
      begin
        identity := ItemRegistry.IdentityOf(wndItem);
        if PinManagedItem(identity, Inst) then
        try
          result := Inst.DropFile(wndChild, pt, filename);
        finally
          ItemRegistry.Unpin(identity);
        end;
      end;
    except
      on e: Exception do err('ItemManager.ItemDrop', e);
    end;
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
function TItemManager.ItemDropFiles(wndItem: HWND; pt: windows.TPoint; files: TStrings): boolean;
var scope: TItemHostScope; index: integer; item: TCustomItem; wndChild: HWND;
  identity: TItemIdentity; dropped: boolean;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    result := false;
    wndChild := wndItem;
    wndItem := IsItem(wndItem);
    identity := ItemRegistry.IdentityOf(wndItem);
    for index := 0 to files.Count - 1 do
      if PinManagedItem(identity, item) then
      try
        dropped := item.DropFile(wndChild, pt, files[index]);
        result := result or dropped;
      finally
        ItemRegistry.Unpin(identity);
      end;
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
procedure TItemManager.ItemDock(wnd: HWND);
var scope: TItemHostScope;
  Inst: TCustomItem; identity: TItemIdentity;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    try
      identity := ItemRegistry.IdentityOf(wnd);
      if PinManagedItem(identity, Inst) then
      try
        ApplyCurrentSettings(wnd);
        if not Inst.Freed then
        begin
          if FItems.IndexOf(Inst.ItemId) <> NO_ITEM_INDEX then Inst.State := imsActive;
          Inst.Dock;
        end;
      finally
        ItemRegistry.Unpin(identity);
      end;
    except
      on e: Exception do err('ItemManager.ItemDock', e);
    end;
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
function TItemManager.ItemCmd(wnd: HWND; id: TDParam; param: PtrInt): PtrInt;
var scope: TItemHostScope;
  Inst: TCustomItem; identity: TItemIdentity;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    try
      result := 0;
      identity := ItemRegistry.IdentityOf(wnd);
      if PinManagedItem(identity, Inst) then
      try
        result := Inst.cmd(id, param);
      finally
        ItemRegistry.Unpin(identity);
      end;
    except
      on e: Exception do err('ItemManager.ItemCmd', e);
    end;
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
function TItemManager.AllItemCmd(id: TDParam; param: PtrInt): PtrInt;
var scope: TItemHostScope; identities: TItemIdentities; index: integer; item: TCustomItem;
  ItemResult: PtrInt;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    result := 0;
    if not FEnabled then exit;
    identities := CaptureItems(false);
    for index := 0 to High(identities) do
      if PinActiveItem(identities[index], item) then
      try
        ItemResult := item.cmd(id, param);
        if id = icFlashTaskWindow then
        begin
          if ItemResult <> 0 then Result := 1;
        end
        else Result := ItemResult;
      finally
        ItemRegistry.Unpin(identities[index]);
      end;
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
procedure TItemManager.AllItemTimer;
var scope: TItemHostScope; identities: TItemIdentities; index: integer; item: TCustomItem;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    identities := CaptureItems(false);
    for index := 0 to High(identities) do
      if PinActiveItem(identities[index], item) then
      try
        if item.NeedsFrame then
        begin
          item.BeginMotionFrame;
          try item.Timer;
          finally
            item.EndMotionFrame;
            FFrameItemsDirty := FFrameItemsDirty or item.FrameRedrawPending;
          end;
        end;
      finally
        ItemRegistry.Unpin(identities[index]);
      end;
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
procedure TItemManager.SetFont(var Value: TDFontData);
var scope: TItemHostScope; identities: TItemIdentities; index: integer; item: TCustomItem;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    CopyFontData(Value, FFont);
    identities := CaptureItems(false);
    for index := 0 to High(identities) do
      if PinActiveItem(identities[index], item) then
      try
        item.SetFont(Value);
      finally
        ItemRegistry.Unpin(identities[index]);
      end;
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
function TItemManager.GetPluginFile(wnd: HWND): string;
var
  Inst: TCustomItem;
begin
  try
    result := '';
    Inst := GetManagedItem(wnd);
    if Inst is TPluginItem then result := TPluginItem(Inst).Filename;
  except
    on e: Exception do err('ItemManager.GetPluginFile', e);
  end;
end;
//------------------------------------------------------------------------------
procedure TItemManager.SetPluginImage(wnd: HWND; lpImageNew: Pointer; AutoDelete: boolean);
var Inst: TCustomItem; identity: TItemIdentity; scope: TItemHostScope;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    identity := ItemRegistry.IdentityOf(wnd);
    if not PinManagedItem(identity, Inst) then exit;
    try
      try
        if Inst is TPluginItem then TPluginItem(Inst).UpdateImage(lpImageNew, AutoDelete);
      except
        on e: Exception do err('ItemManager.SetPluginImage', e);
      end;
    finally
      ItemRegistry.Unpin(identity);
    end;
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
procedure TItemManager.SetPluginOverlay(wnd: HWND; lpOverlayNew: Pointer; AutoDelete: boolean);
var Inst: TCustomItem; identity: TItemIdentity; scope: TItemHostScope;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    identity := ItemRegistry.IdentityOf(wnd);
    if not PinManagedItem(identity, Inst) then exit;
    try
      try
        if Inst is TPluginItem then TPluginItem(Inst).UpdateOverlay(lpOverlayNew, AutoDelete);
      except
        on e: Exception do err('ItemManager.SetPluginOverlay', e);
      end;
    finally
      ItemRegistry.Unpin(identity);
    end;
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
procedure TItemManager.PluginAnimate(wnd: HWND);
var Inst: TCustomItem; identity: TItemIdentity; scope: TItemHostScope;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    identity := ItemRegistry.IdentityOf(wnd);
    if not PinManagedItem(identity, Inst) then exit;
    try
      try
        if FItemAnimation > 0 then Inst.Animate;
      except
        on e: Exception do err('ItemManager.PluginAnimate', e);
      end;
    finally
      ItemRegistry.Unpin(identity);
    end;
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
function TItemManager.SetPluginCaption(wnd: HWND; NewCaption: string): integer;
var Inst: TCustomItem; identity: TItemIdentity; scope: TItemHostScope;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    result := 0;
    identity := ItemRegistry.IdentityOf(wnd);
    if not PinManagedItem(identity, Inst) then exit;
    try
      try
        Inst.Caption := NewCaption;
        result := Length(Inst.Caption);
      except
        on e: Exception do err('ItemManager.SetPluginCaption', e);
      end;
    finally
      ItemRegistry.Unpin(identity);
    end;
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
function TItemManager.GetPluginCaption(wnd: HWND): string;
var
  Inst: TCustomItem;
begin
  try
    result := '';
    Inst := GetManagedItem(wnd);
    if Inst is TCustomItem then result := Inst.Caption;
  except
    on e: Exception do err('ItemManager.GetPluginCaption', e);
  end;
end;
//------------------------------------------------------------------------------
function TItemManager.GetPluginRect(wnd: HWND; var r: windows.TRect): boolean;
var
  Inst: TCustomItem;
begin
  try
    result := Visible;
    r := classes.Rect(0, 0, 0, 0);
    Inst := GetManagedItem(wnd);
    if Inst is TCustomItem then r := Inst.ScreenRect;
  except
    on e: Exception do err('ItemManager.GetPluginRect', e);
  end;
end;
//------------------------------------------------------------------------------
function TItemManager.IsPluginUndocked(wnd: HWND): boolean;
var
  Inst: TCustomItem;
begin
  try
    result := false;
    Inst := GetManagedItem(wnd);
    if Inst is TCustomItem then result := Inst.Undocked;
  except
    on e: Exception do err('ItemManager.IsPluginUndocked', e);
  end;
end;
//------------------------------------------------------------------------------
function TItemManager.IsSeparator(wnd: HWND): boolean;
begin
  try
    result := GetManagedItem(wnd) is TSeparatorItem;
  except
    on e: Exception do err('ItemManager.IsSeparator', e);
  end;
end;
//------------------------------------------------------------------------------
//
//
//
//   Task Item Procs
//
//
//
//------------------------------------------------------------------------------
procedure TItemManager.Taskbar;
var scope: TItemHostScope; windows: TTaskWindows; index: integer;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    if FDraggingItem then
    begin
      FTaskRefreshPending := true;
      FTaskSnapshotPending := false;
      FPendingTaskWindows := nil;
      exit;
    end;
    if not assigned(ProcessHelper) then exit;
    SetLength(windows, ProcessHelper.GetAppWindowsCount);
    for index := 0 to High(windows) do
    begin
      windows[index].Handle := ProcessHelper.GetAppWindowHandle(index);
      windows[index].Executable := ProcessHelper.GetWindowProcessName(windows[index].Handle);
      windows[index].Visible := IsWindowVisible(windows[index].Handle);
    end;
    SynchronizeTasks(windows);
  finally
    EndItemHostOperation(scope);
  end;
end;

procedure TItemManager.SynchronizeTasks(const AppWindows: TTaskWindows);
var scope: TItemHostScope; input: TTaskSyncInput; plan: TTaskSyncPlan; identities, created: TItemIdentities;
  index, sourceIndex: integer; item: TCustomItem; action: TTaskSyncAction;
  identity: TItemIdentity; wnd: HWND;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    if FDraggingItem then
    begin
      FTaskRefreshPending := true;
      FTaskSnapshotPending := true;
      FPendingTaskWindows := Copy(AppWindows);
      exit;
    end;
    FTaskRefreshPending := false;
    FTaskSnapshotPending := false;
    FPendingTaskWindows := nil;
    identities := CaptureItems(false);
    SetLength(input.Entries, Length(identities));
    for index := 0 to High(identities) do
    begin
      input.Entries[index].ItemId := identities[index].ItemId;
      if PinActiveItem(identities[index], item) then
      try
        if item is TTaskItem then input.Entries[index] := TTaskItem(item).TaskSnapshot
        else input.Entries[index].RegisteredExecutable := item.Executable;
      finally
        ItemRegistry.Unpin(identities[index]);
      end;
    end;
    input.AppWindows := Copy(AppWindows);
    input.TaskSpot := FTaskSpot;
    input.Grouping := FTaskGrouping;
    input.Dragging := FDraggingItem;
    plan := ReconcileTasks(input);
    SetLength(created, Length(plan.Actions) + 1);
    for index := 0 to High(plan.Actions) do
    begin
      action := plan.Actions[index];
      if action.Kind = tsaCreateGroup then
      begin
        SetDropPlace(action.InsertIndex);
        wnd := AddItem(CreateTaskItem, true);
        if wnd = 0 then
        begin
          SetDropPlace(NOT_AN_ITEM);
          exit;
        end;
        created[action.NewGroupKey] := ItemRegistry.IdentityOf(wnd);
        if not PinActiveItem(created[action.NewGroupKey], item) then exit;
        try
          TTaskItem(item).UpdateTaskItem(action.Window);
        finally
          ItemRegistry.Unpin(created[action.NewGroupKey]);
        end;
        continue;
      end;
      identity := Default(TItemIdentity);
      if action.NewGroupKey > 0 then identity := created[action.NewGroupKey]
      else
        for sourceIndex := 0 to High(identities) do
          if identities[sourceIndex].ItemId = action.ItemId then
          begin
            identity := identities[sourceIndex];
            break;
          end;
      if not PinActiveItem(identity, item) then continue;
      try
        if not (item is TTaskItem) then continue;
        case action.Kind of
          tsaRemoveWindow: TTaskItem(item).RemoveSnapshotWindow(action.Window);
          tsaRefreshGroup: TTaskItem(item).RefreshSnapshotGroup;
          tsaAddWindow: TTaskItem(item).UpdateTaskItem(action.Window);
          tsaDeleteGroup: item.Delete;
          tsaUpdateGroup: TTaskItem(item).UpdateItem;
        end;
      finally
        ItemRegistry.Unpin(identity);
      end;
    end;
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
procedure TItemManager.FlushPendingTasks;
var windows: TTaskWindows; useSnapshot: boolean;
begin
  if not FTaskRefreshPending or FDraggingItem or not FEnabled or
    (FRebuildDepth > 0) then exit;
  useSnapshot := FTaskSnapshotPending;
  if not useSnapshot and not Assigned(ProcessHelper) then exit;
  windows := FPendingTaskWindows;
  FTaskRefreshPending := false;
  FTaskSnapshotPending := false;
  FPendingTaskWindows := nil;
  if useSnapshot then SynchronizeTasks(windows) else Taskbar;
end;

procedure TItemManager.ClearTaskbar;
var scope: TItemHostScope; identities: TItemIdentities; index: integer; item: TCustomItem;
begin
  scope := BeginItemHostOperation(FParentHWnd);
  try
    FTaskRefreshPending := false;
    FTaskSnapshotPending := false;
    FPendingTaskWindows := nil;
    identities := CaptureItems(false);
    for index := High(identities) downto 0 do
      if PinActiveItem(identities[index], item) then
      try
        if item is TTaskItem then item.Delete;
      finally
        ItemRegistry.Unpin(identities[index]);
      end;
  finally
    EndItemHostOperation(scope);
  end;
end;
//------------------------------------------------------------------------------
end.
