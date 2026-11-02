unit itemmanagertests;

{$mode delphi}

interface

uses Windows, Classes, SysUtils, fpcunit, testregistry,
  declu, itemmgru, customitemu, sepitemu, scitemu, stackitemu, themeu, itemsettingsu, docklayoutu, itemhostu, itemregistryu, iniproc, dropimportu;

type
  TTestItemManager = class(TItemManager)
  protected
    function GetCursorPoint(out pt: Windows.TPoint): boolean; override;
  public
    MousePoint: Windows.TPoint;
    MouseAvailable: boolean;
  end;

  TItemManagerTests = class(TTestCase)
  private
    Manager: TItemManager;
    FixtureTheme: TDTheme;
    FixtureFile: string;
    HostDeletes, HostLocks, HostNotifications, HostEntered, HostLeft, HostDocks: integer;
    HostMessage: WideString;
    procedure HostDelete(wnd: HWND);
    procedure HostDock(wnd: HWND);
    procedure HostLock(wnd: HWND; lock: boolean);
    procedure HostNotify(message: WideString; silent: boolean);
    procedure HostEnter;
    procedure HostLeave;
    procedure BindTestHost;
    function NewManager: TItemManager;
    function Populate(count: integer): THandle;
    procedure WriteSettings(count: integer);
    procedure ConfigureDockAtPoint(offset: integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure CreationAbove128DoesNotChangeCount;
    procedure InvalidCreationDoesNotChangeCount;
    procedure Loads129SettingsSections;
    procedure SaveAndReload129Items;
    procedure DeleteAndRestoreBeyond128;
    procedure DragDeletionRemainsRestorable;
    procedure FailedCreationPreservesDragPreview;
    procedure SavingDuringDragKeepsEveryItem;
    procedure Redocks129thItem;
    procedure DropOutsideMovesDraggedItemToUndo;
    procedure UnavailableCursorCancelsDrag;
    procedure CombinesShortcutsAbove128IntoStack;
    procedure PendingItemLookupPreservesOwnership;
    procedure LookupRejectsForeignWindowData;
    procedure RestoredItemReceivesCurrentSettings;
    procedure RedockedItemReceivesCurrentSettings;
    procedure TypedConstructorAppliesLayoutSettings;
    procedure TypedSettingRejectsCommands;
    procedure DeletedDragClearsInteractionState;
    procedure CommandBroadcastSurvivesItemDeletion;
    procedure AttentionBroadcastRetainsEarlierAcceptance;
    procedure TimerBroadcastSurvivesItemDeletion;
    procedure FontBroadcastSurvivesItemDeletion;
    procedure SavingSurvivesItemDeletion;
    procedure ClearingSurvivesDestructionCallback;
    procedure DrawingSkipsDestroyedItem;
    procedure ItemQuerySurvivesItemDeletion;
    procedure DrawingMutationKeepsCurrentGeometry;
    procedure BoundHostRoutesItemRequests;
    procedure BoundHostBalancesDispatchException;
    procedure BoundHostScopesWindowMessages;
    procedure CleanupContinuesAfterDestructorFailure;
    procedure ClearingDefersExecutingItemDestruction;
    procedure MultiFileDropCallsEveryFile;
    procedure ReusedRegistrationDoesNotAcquireOwnership;
    procedure SaveToPreservesCanonicalFilename;
    procedure SaveToRejectsUnavailableSnapshot;
    procedure ManagerCommandRetainsExecutingItem;
    procedure ManagerDrawRetainsExecutingItem;
    procedure ManagerFontRetainsExecutingItem;
    procedure ManagerDropRetainsExecutingItem;
    procedure DiscardingDeletedTasksKeepsUndoRecords;
    procedure SaveToRejectsDestructiveRebuild;
    procedure ExternalPinSurvivesManagerDestruction;
    procedure PendingDragReceivesOwnershipTracking;
    procedure FullStackDropPreservesSource;
    procedure OverflowingStackMergePreservesBothStacks;
    procedure StackCopyKeepsSortedAndChildren;
    procedure UnknownIniItemsSurviveSaving;
    procedure OnlyUnknownItemsDoNotCreateDefaults;
    procedure MalformedStackRemainsInTheFile;
    procedure SaveRemovesOldSectionsWithoutRemovingSettings;
    procedure FullStackRejectsFileDrop;
    procedure ImportedTargetsReportInsertionAndReload;
    procedure UnlaunchableImportedTargetsSurviveReload;
    procedure ImportedTargetsReportDisabledRejection;
    procedure ImportedTargetsStopAtStackCapacity;

  end;

procedure DockDeleteItem(wnd: HWND); stdcall;

implementation

var currentManager: TItemManager;
  WatchedItem: TCustomItem;
  WatchedDestroyed, DestroyedInsideCallback: boolean;
  SaveStagePath: string;
  SnapshotRejected: boolean;

type
  PStackSearch = ^TStackSearch;
  TStackSearch = record
    Manager: TItemManager;
    Stack: TStackItem;
  end;

  TProbeItem = class(TCustomItem)
  public
    AttentionResult: PtrInt;
    CommandCalls, TimerCalls, FontCalls, SaveCalls: integer;
    DeleteOnCommand, DeleteOnTimer, DeleteOnFont, DeleteOnSave: boolean;
    DeleteOnDestroy: TCustomItem;
    FreeOnDraw: TCustomItem;
    QueryTarget: HWND;
    DeleteOnQuery: boolean;
    DeleteOnDraw: boolean;
    RaiseOnCommand: boolean;
    RaiseOnDestroy: boolean;
    ClearOnMessage: boolean;
    ClearOnCommand, ClearOnDraw, ClearOnFont, ClearOnDrop: boolean;
    SaveOnDestroy: boolean;
    DropCalls: integer;
    destructor Destroy; override;
    function DraggingLocked: boolean;
    function FontSize: integer;
    procedure Draw(Ax, Ay, ASize: integer; AForce: boolean; wpi: HDWP; AShowItem: uint); override;
    function ToString: string; override;
    procedure WndMessage(var msg: TMessage); override;
    procedure WMCommand(wParam: WPARAM; lParam: LPARAM; var Result: LRESULT); override;
    procedure Save(ini, section: string); override;
    function cmd(id: TDParam; param: PtrInt): PtrInt; override;
    function NeedsFrame: boolean; override;
    procedure Timer; override;
    procedure SetFont(var Value: TDFontData); override;
    procedure EmitNotification;
    function DropFile(wnd: HWND; pt: Windows.TPoint; filename: string): boolean; override;
  end;

function TProbeItem.DraggingLocked: boolean;
begin
  result := FLockDragging;
end;

destructor TProbeItem.Destroy;
begin
  if self = WatchedItem then WatchedDestroyed := true;
  FFreed := true;
  try
    if SaveOnDestroy then
      try currentManager.SaveTo(SaveStagePath);
      except on Exception do SnapshotRejected := true; end;
    if assigned(DeleteOnDestroy) then DeleteOnDestroy.Delete;
    if RaiseOnDestroy then raise Exception.Create('Probe destruction failed');
  finally
    inherited;
  end;
end;

function TProbeItem.FontSize: integer;
begin
  result := FFont.size;
end;

procedure TProbeItem.Draw(Ax, Ay, ASize: integer; AForce: boolean; wpi: HDWP; AShowItem: uint);
var victim: TCustomItem;
begin
  FX := Ax;
  FY := Ay;
  FSize := ASize;
  if ClearOnDraw then
  begin
    currentManager.command('clear', '');
    DestroyedInsideCallback := WatchedDestroyed;
    exit;
  end;
  victim := FreeOnDraw;
  FreeOnDraw := nil;
  if assigned(victim) then victim.Free;
  if DeleteOnDraw then
  begin
    DeleteOnDraw := false;
    Delete;
  end;
end;

function TProbeItem.ToString: string;
begin
  result := TSeparatorItem.Make;
end;

procedure TProbeItem.WndMessage(var msg: TMessage);
begin
  if ClearOnMessage and (msg.msg = WM_APP + 43) then
  begin
    currentManager.command('clear', '');
    DestroyedInsideCallback := WatchedDestroyed;
  end;
  msg.Result := 0;
end;

procedure TProbeItem.WMCommand(wParam: WPARAM; lParam: LPARAM; var Result: LRESULT);
begin
  Result := 0;
end;

procedure TProbeItem.Save(ini, section: string);
begin
  inc(SaveCalls);
  WritePrivateProfileString(PChar(section), 'class', 'separator', PChar(ini));
  if DeleteOnSave then Delete;
end;

function TProbeItem.cmd(id: TDParam; param: PtrInt): PtrInt;
begin
  result := inherited cmd(id, param);
  if id = icFlashTaskWindow then result := AttentionResult;
  if id = icIsItem then
  begin
    if DeleteOnQuery then Delete;
    if (QueryTarget <> 0) and (HWND(param) = QueryTarget) then result := PtrInt(Handle);
  end;
  if id = icUpdateRunning then
  begin
    inc(CommandCalls);
    if ClearOnCommand then
    begin
      currentManager.command('clear', '');
      DestroyedInsideCallback := WatchedDestroyed;
      exit;
    end;
    if RaiseOnCommand then raise Exception.Create('Probe command failed');
    if DeleteOnCommand then Delete;
  end;
end;

procedure TProbeItem.EmitNotification;
begin
  notify('Item notification');
end;

function TProbeItem.DropFile(wnd: HWND; pt: Windows.TPoint; filename: string): boolean;
begin
  inc(DropCalls);
  if ClearOnDrop then
  begin
    currentManager.command('clear', '');
    DestroyedInsideCallback := WatchedDestroyed;
  end;
  result := true;
end;

function TProbeItem.NeedsFrame: boolean;
begin Result := true; end;

procedure TProbeItem.Timer;
begin
  inc(TimerCalls);
  if DeleteOnTimer then Delete;
end;

procedure TProbeItem.SetFont(var Value: TDFontData);
begin
  inherited;
  inc(FontCalls);
  if ClearOnFont then
  begin
    currentManager.command('clear', '');
    DestroyedInsideCallback := WatchedDestroyed;
  end;
  if DeleteOnFont then Delete;
end;

function NewProbe(manager: TItemManager): TProbeItem;
var params: TDItemCreateParams;
begin
  params := Default(TDItemCreateParams);
  params.ItemSize := 32;
  params.BigItemSize := 32;
  result := TProbeItem.Create(0, params);
  manager.Enable(true);
  manager.AdoptItem(result);
end;

function FindManagedStack(wnd: HWND; data: LPARAM): BOOL; stdcall;
var search: PStackSearch; item: TCustomItem;
begin
  result := true;
  search := PStackSearch(data);
  if search^.Manager.ItemIndex(wnd) = NOT_AN_ITEM then exit;
  if not search^.Manager.TryGetManagedItem(wnd, item) then exit;
  if item is TStackItem then
  begin
    search^.Stack := TStackItem(item);
    result := false;
  end;
end;

function TTestItemManager.GetCursorPoint(out pt: Windows.TPoint): boolean;
begin
  pt := MousePoint;
  result := MouseAvailable;
end;

procedure DockDeleteItem(wnd: HWND); stdcall;
begin
  if assigned(currentManager) then currentManager.DeleteItem(wnd);
end;

function TItemManagerTests.NewManager: TItemManager;
var font: TDFontData;
begin
  font := Default(TDFontData);
  result := TTestItemManager.Create(0, nil,
    32, 32, 4, 100, 0, false, false,
    0, 0, 0, 255, false, false, false, false,
    false, false, false, false, 0, -1, false, font);
  TTestItemManager(result).MouseAvailable := true;
end;

procedure TItemManagerTests.SetUp;
var id: TGUID;
begin
  Manager := NewManager;
  WatchedItem := nil;
  WatchedDestroyed := false;
  DestroyedInsideCallback := false;
  SaveStagePath := '';
  SnapshotRejected := false;
  FixtureTheme := nil;
  currentManager := Manager;
  CreateGUID(id);
  FixtureFile := ExtractFilePath(ParamStr(0)) + GUIDToString(id) + '.ini';
end;

procedure TItemManagerTests.TearDown;
begin
  UnbindItemHost(0);
  Manager.Free;
  currentManager := nil;
  if assigned(FixtureTheme) then
  begin
    theme := nil;
    FixtureTheme.Free;
  end;
  if FileExists(FixtureFile) then DeleteFile(FixtureFile);
end;

procedure TItemManagerTests.HostDelete(wnd: HWND);
begin
  inc(HostDeletes);
  Manager.DeleteItem(wnd);
end;

procedure TItemManagerTests.HostDock(wnd: HWND);
begin
  inc(HostDocks);
end;

procedure TItemManagerTests.HostLock(wnd: HWND; lock: boolean);
begin
  if lock then inc(HostLocks);
end;

procedure TItemManagerTests.HostNotify(message: WideString; silent: boolean);
begin
  inc(HostNotifications);
  HostMessage := message;
end;

procedure TItemManagerTests.HostEnter;
begin
  inc(HostEntered);
end;

procedure TItemManagerTests.HostLeave;
begin
  inc(HostLeft);
end;

procedure TItemManagerTests.BindTestHost;
var services: TItemHostServices;
begin
  services := Default(TItemHostServices);
  services.OnDelete := HostDelete;
  services.OnDock := HostDock;
  services.OnLockMouseEffect := HostLock;
  services.OnNotify := HostNotify;
  services.OnEnter := HostEnter;
  services.OnLeave := HostLeave;
  BindItemHost(0, services);
end;

function TItemManagerTests.Populate(count: integer): THandle;
var i: integer;
begin
  result := 0;
  Manager.Enable(true);
  for i := 1 to count do
  begin
    result := Manager.InsertItem(TSeparatorItem.Make);
    AssertTrue('Created item ' + IntToStr(i), IsWindow(result));
  end;
end;

procedure TItemManagerTests.WriteSettings(count: integer);
var lines: TStringList; i: integer;
begin
  lines := TStringList.Create;
  try
    for i := 1 to count do
    begin
      lines.Add('[item' + IntToStr(i) + ']');
      lines.Add('class=separator');
    end;
    lines.SaveToFile(FixtureFile);
  finally
    lines.Free;
  end;
end;

procedure TItemManagerTests.ConfigureDockAtPoint(offset: integer);
var pt: Windows.TPoint; configuration: TDockLayoutConfiguration;
begin
  pt.x := 2048;
  pt.y := 1024;
  TTestItemManager(Manager).MousePoint := pt;
  configuration := Default(TDockLayoutConfiguration);
  configuration.MonitorRect.Left := pt.x - offset;
  configuration.MonitorRect.Top := pt.y - 1000;
  configuration.MonitorRect.Right := pt.x - offset + 10000;
  configuration.MonitorRect.Bottom := pt.y + 32;
  Manager.ConfigureLayout(configuration);
  Manager.SetParam(gpSite, Ord(bsBottom));
  Manager.SetParam(gpCenterOffsetPercent, 0);
end;

procedure TItemManagerTests.CreationAbove128DoesNotChangeCount;
var wnd: THandle; item: TCustomItem;
begin
  Populate(129);
  wnd := Manager.CreateItemFromString(TSeparatorItem.Make);
  AssertTrue(IsWindow(wnd));
  AssertTrue(Manager.TryGetManagedItem(wnd, item));
  try
    AssertEquals(129, Manager.ItemCount);
    AssertEquals(NOT_AN_ITEM, Manager.ItemIndex(wnd));
  finally
    item.Freed := true;
    item.Free;
  end;
end;

procedure TItemManagerTests.InvalidCreationDoesNotChangeCount;
begin
  Populate(128);
  AssertEquals(int64(0), int64(Manager.InsertItem('class="unknown";')));
  AssertEquals(128, Manager.ItemCount);
end;

procedure TItemManagerTests.Loads129SettingsSections;
begin
  WriteSettings(129);
  Manager.Load(FixtureFile);
  AssertEquals(129, Manager.ItemCount);
end;

procedure TItemManagerTests.SaveAndReload129Items;
var restored: TItemManager;
begin
  Populate(129);
  Manager.Save(FixtureFile);
  restored := NewManager;
  try
    restored.Load(FixtureFile);
    AssertEquals(129, restored.ItemCount);
  finally
    restored.Free;
  end;
end;

procedure TItemManagerTests.DeleteAndRestoreBeyond128;
var wnd: THandle;
begin
  wnd := Populate(128);
  Manager.DeleteItem(wnd);
  AssertEquals(127, Manager.ItemCount);
  AssertEquals(1, Manager.DeletedCount);
  Populate(2);
  Manager.UnDelete;
  AssertEquals(130, Manager.ItemCount);
  AssertEquals(0, Manager.DeletedCount);
  AssertTrue(Manager.ItemIndex(wnd) <> NOT_AN_ITEM);
end;

procedure TItemManagerTests.DragDeletionRemainsRestorable;
var wnd: THandle;
begin
  wnd := Populate(129);
  Manager.Undock(wnd);
  AssertEquals(128, Manager.ItemCount);
  Manager.DeleteItem(wnd);
  AssertEquals(1, Manager.DeletedCount);
  Manager.DragLeave;
  Manager.UnDelete;
  AssertEquals(129, Manager.ItemCount);
  AssertEquals(0, Manager.DeletedCount);
  AssertTrue(Manager.ItemIndex(wnd) <> NOT_AN_ITEM);
end;

procedure TItemManagerTests.FailedCreationPreservesDragPreview;
var wnd: THandle; dropPlace: integer;
begin
  wnd := Populate(128);
  Manager.Undock(wnd);
  dropPlace := Manager.InteractionSnapshot.DropPlace;
  AssertEquals(int64(0), int64(Manager.InsertItem('class="unknown";')));
  AssertEquals(127, Manager.ItemCount);
  AssertEquals(dropPlace, Manager.InteractionSnapshot.DropPlace);
  AssertEquals(int64(ItemRegistry.IdentityOf(wnd).ItemId), int64(Manager.InteractionSnapshot.DraggedItem));
end;

procedure TItemManagerTests.SavingDuringDragKeepsEveryItem;
var wnd: THandle; restored: TItemManager;
begin
  wnd := Populate(129);
  Manager.Undock(wnd);
  Manager.Save(FixtureFile);
  restored := NewManager;
  try
    restored.Load(FixtureFile);
    AssertEquals(129, restored.ItemCount);
  finally
    restored.Free;
  end;
end;

procedure TItemManagerTests.Redocks129thItem;
var wnd: THandle;
begin
  wnd := Populate(129);
  ConfigureDockAtPoint(64 * 32 + 16);
  Manager.Undock(wnd);
  Manager.Dock(wnd);
  AssertEquals(129, Manager.ItemCount);
  AssertEquals(0, Manager.DeletedCount);
  AssertEquals(64, Manager.ItemIndex(wnd));
  AssertEquals(NOT_AN_ITEM, Manager.InteractionSnapshot.DropPlace);
  AssertFalse(Manager.InteractionSnapshot.DraggingItem);
end;

procedure TItemManagerTests.DropOutsideMovesDraggedItemToUndo;
var wnd: THandle;
begin
  wnd := Populate(129);
  ConfigureDockAtPoint(-20000);
  Manager.Undock(wnd);
  Manager.Dock(wnd);
  AssertEquals(128, Manager.ItemCount);
  AssertEquals(1, Manager.DeletedCount);
  AssertEquals(NOT_AN_ITEM, Manager.ItemIndex(wnd));
  AssertFalse(Manager.InteractionSnapshot.DraggingItem);
  Manager.UnDelete;
  AssertEquals(129, Manager.ItemCount);
  AssertEquals(0, Manager.DeletedCount);
end;

procedure TItemManagerTests.UnavailableCursorCancelsDrag;
var wnd: THandle;
begin
  wnd := Populate(129);
  Manager.Undock(wnd);
  TTestItemManager(Manager).MouseAvailable := false;
  Manager.Dock(wnd);
  AssertEquals(129, Manager.ItemCount);
  AssertEquals(0, Manager.DeletedCount);
  AssertEquals(128, Manager.ItemIndex(wnd));
  AssertFalse(Manager.InteractionSnapshot.DraggingItem);
end;

procedure TItemManagerTests.CombinesShortcutsAbove128IntoStack;
var source, target: THandle; search: TStackSearch;
begin
  Populate(127);
  target := Manager.InsertItem(TShortcutItem.Make('target'));
  source := Manager.InsertItem(TShortcutItem.Make('source'));
  AssertTrue(IsWindow(target));
  AssertTrue(IsWindow(source));
  ConfigureDockAtPoint(127 * 32 + 16);
  Manager.Undock(source);
  // Initialize empty theme fields without extracting application resources.
  FixtureTheme := TDTheme(TDTheme.NewInstance);
  theme := FixtureTheme;
  Manager.Dock(source);
  AssertEquals(128, Manager.ItemCount);
  AssertEquals(2, Manager.DeletedCount);
  AssertEquals(NOT_AN_ITEM, Manager.ItemIndex(source));
  AssertEquals(NOT_AN_ITEM, Manager.ItemIndex(target));
  search := Default(TStackSearch);
  search.Manager := Manager;
  EnumThreadWindows(GetCurrentThreadId, @FindManagedStack, LPARAM(@search));
  AssertTrue(assigned(search.Stack));
  AssertEquals(2, search.Stack.ItemCount);
end;

procedure TItemManagerTests.PendingItemLookupPreservesOwnership;
var wnd: HWND; item, found: TCustomItem;
begin
  wnd := Manager.CreateItemFromString(TSeparatorItem.Make);
  AssertTrue(Manager.TryGetManagedItem(wnd, item));
  try
    AssertTrue('Pending item must support checked lookup', Manager.TryGetManagedItem(wnd, found));
    AssertTrue(found = item);
    AssertEquals('Lookup must not adopt the pending item', 0, Manager.ItemCount);
  finally
    item.Free;
  end;
  AssertFalse('Destruction must unregister the item', Manager.TryGetManagedItem(wnd, found));
  AssertTrue(found = nil);
end;

procedure TItemManagerTests.LookupRejectsForeignWindowData;
var wnd: HWND; found: TCustomItem;
begin
  wnd := CreateWindowEx(0, 'STATIC', nil, WS_POPUP, 0, 0, 1, 1, 0, 0, hInstance, nil);
  try
    SetWindowLongPtr(wnd, GWL_USERDATA, 1);
    AssertFalse(Manager.TryGetManagedItem(wnd, found));
    AssertTrue(found = nil);
    AssertFalse(Manager.TryGetManagedItem(0, found));
  finally
    DestroyWindow(wnd);
  end;
end;

procedure TItemManagerTests.RestoredItemReceivesCurrentSettings;
var params: TDItemCreateParams; item: TProbeItem; font: TDFontData;
begin
  params := Default(TDItemCreateParams);
  params.ItemSize := 32;
  params.BigItemSize := 32;
  item := TProbeItem.Create(0, params);
  Manager.Enable(true);
  Manager.AdoptItem(item);
  item.Delete;
  Manager.SetParam(gpLockDragging, 1);
  font := Default(TDFontData);
  font.size := 19;
  Manager.SetFont(font);
  Manager.UnDelete;
  AssertTrue('Restored item must use the current drag lock', item.DraggingLocked);
  AssertEquals('Restored item must use the current font', 19, item.FontSize);
end;

procedure TItemManagerTests.RedockedItemReceivesCurrentSettings;
var params: TDItemCreateParams; item: TProbeItem; font: TDFontData;
begin
  Populate(1);
  params := Default(TDItemCreateParams);
  params.ItemSize := 32;
  params.BigItemSize := 32;
  item := TProbeItem.Create(0, params);
  Manager.AdoptItem(item);
  ConfigureDockAtPoint(16);
  Manager.Undock(item.Handle);
  Manager.SetParam(gpLockDragging, 1);
  font := Default(TDFontData);
  font.size := 21;
  Manager.SetFont(font);
  Manager.Dock(item.Handle);
  AssertTrue('Redocked item must use the current drag lock', item.DraggingLocked);
  AssertEquals('Redocked item must use the current font', 21, item.FontSize);
end;

procedure TItemManagerTests.TypedConstructorAppliesLayoutSettings;
var settings: TItemManagerSettings; created: TItemManager;
begin
  settings := Default(TItemManagerSettings);
  settings.ItemSize := 32;
  settings.BigItemSize := 32;
  settings.ZoomWidth := 4;
  settings.ZoomTime := 100;
  settings.DropDistance := 123;
  settings.Site := bsBottom;
  settings.CenterOffsetPercent := 50;
  created := TItemManager.Create(0, settings, nil);
  try
    AssertEquals('Typed constructor must apply drag geometry settings', 123, created.InteractionSnapshot.DropDistance);
  finally
    created.Free;
  end;
end;

procedure TItemManagerTests.TypedSettingRejectsCommands;
var rejected: boolean;
begin
  rejected := false;
  try
    Manager.ApplySetting(tcRepaintBase, 1);
  except
    on ERangeError do rejected := true;
  end;
  AssertTrue('Settings API must reject command identifiers', rejected);
end;

procedure TItemManagerTests.DeletedDragClearsInteractionState;
var wnd: HWND;
begin
  wnd := Populate(1);
  Manager.Undock(wnd);
  Manager.DeleteItem(wnd);
  AssertFalse('Deleting a drag must clear its active flag', Manager.InteractionSnapshot.DraggingItem);
  AssertEquals(int64(0), int64(Manager.InteractionSnapshot.DraggedItem));
  AssertEquals(NOT_AN_ITEM, Manager.InteractionSnapshot.DropPlace);
end;

procedure TItemManagerTests.CommandBroadcastSurvivesItemDeletion;
var first, second: TProbeItem;
begin
  first := NewProbe(Manager);
  second := NewProbe(Manager);
  first.DeleteOnCommand := true;
  Manager.AllItemCmd(icUpdateRunning, 0);
  AssertEquals('Next item must receive the command after deletion', 1, second.CommandCalls);
end;

procedure TItemManagerTests.TimerBroadcastSurvivesItemDeletion;
var first, second: TProbeItem;
begin
  first := NewProbe(Manager);
  second := NewProbe(Manager);
  first.DeleteOnTimer := true;
  Manager.Timer;
  AssertEquals('Next item must receive its timer after deletion', 1, second.TimerCalls);
end;

procedure TItemManagerTests.FontBroadcastSurvivesItemDeletion;
var first, second: TProbeItem; font: TDFontData;
begin
  first := NewProbe(Manager);
  second := NewProbe(Manager);
  first.FontCalls := 0;
  second.FontCalls := 0;
  first.DeleteOnFont := true;
  font := Default(TDFontData);
  font.size := 22;
  Manager.SetFont(font);
  AssertEquals('Next item must receive its font after deletion', 1, second.FontCalls);
end;

procedure TItemManagerTests.SavingSurvivesItemDeletion;
var first, second: TProbeItem; succeeded: boolean;
begin
  first := NewProbe(Manager);
  second := NewProbe(Manager);
  first.DeleteOnSave := true;
  succeeded := true;
  try
    Manager.Save(FixtureFile);
  except
    on Exception do succeeded := false;
  end;
  AssertTrue('Saving must survive deletion from an item callback', succeeded);
  AssertEquals('Next item must be saved after deletion', 1, second.SaveCalls);
end;

procedure TItemManagerTests.ClearingSurvivesDestructionCallback;
var first, second, found: TCustomItem; wnd: HWND; succeeded: boolean;
begin
  first := NewProbe(Manager);
  second := NewProbe(Manager);
  wnd := second.Handle;
  TProbeItem(first).DeleteOnDestroy := second;
  succeeded := true;
  try
    Manager.command('clear', '');
  except
    on Exception do succeeded := false;
  end;
  AssertTrue('Clear must survive deletion from a destructor', succeeded);
  AssertFalse('Clear must release every original owned item', Manager.TryGetManagedItem(wnd, found));
end;

procedure TItemManagerTests.DrawingSkipsDestroyedItem;
var first, second: TProbeItem; succeeded: boolean;
begin
  first := NewProbe(Manager);
  second := NewProbe(Manager);
  first.FreeOnDraw := second;
  succeeded := true;
  try
    Manager.WndOffset := 1;
  except
    on Exception do succeeded := false;
  end;
  AssertTrue('Drawing must skip items destroyed by earlier callbacks', succeeded);
end;

procedure TItemManagerTests.ItemQuerySurvivesItemDeletion;
var first, second: TProbeItem;
begin
  first := NewProbe(Manager);
  second := NewProbe(Manager);
  first.DeleteOnQuery := true;
  second.QueryTarget := 777;
  AssertEquals('Query must inspect later items after deletion',
    int64(second.Handle), int64(Manager.IsItem(777)));
end;

procedure TItemManagerTests.DrawingMutationKeepsCurrentGeometry;
var first, second: TProbeItem;
begin
  first := NewProbe(Manager);
  second := NewProbe(Manager);
  ConfigureDockAtPoint(0);
  first.DeleteOnDraw := true;
  Manager.WndOffset := 1;
  AssertEquals('An old frame must not overwrite recalculated positions',
    Manager.LayoutSnapshot.MonitorRect.Left, second.X);
end;

procedure TItemManagerTests.BoundHostRoutesItemRequests;
var item: TProbeItem;
begin
  item := NewProbe(Manager);
  BindTestHost;
  item.LME(true);
  item.EmitNotification;
  SendMessage(item.Handle, WM_EXITSIZEMOVE, 0, 0);
  item.Delete;
  AssertEquals('Bound host must handle deletion directly', 1, HostDeletes);
  AssertEquals(1, HostLocks);
  AssertEquals(1, HostNotifications);
  AssertEquals('Item notification', string(HostMessage));
  AssertEquals(1, HostDocks);
end;

procedure TItemManagerTests.BoundHostBalancesDispatchException;
var item: TProbeItem; raised: boolean;
begin
  item := NewProbe(Manager);
  BindTestHost;
  item.RaiseOnCommand := true;
  raised := false;
  try
    Manager.AllItemCmd(icUpdateRunning, 0);
  except
    on Exception do raised := true;
  end;
  AssertTrue(raised);
  AssertTrue('Manager must enter a host operation', HostEntered > 0);
  AssertEquals('Dispatch failures must balance host scopes', HostEntered, HostLeft);
end;

procedure TItemManagerTests.BoundHostScopesWindowMessages;
var item: TProbeItem;
begin
  item := NewProbe(Manager);
  BindTestHost;
  SendMessage(item.Handle, WM_APP + 42, 0, 0);
  AssertTrue('Window messages must enter a host operation', HostEntered > 0);
  AssertEquals(HostEntered, HostLeft);
end;

procedure TItemManagerTests.CleanupContinuesAfterDestructorFailure;
var first, second: TProbeItem; firstWnd, secondWnd: HWND;
  found: TCustomItem; succeeded: boolean;
begin
  first := NewProbe(Manager);
  second := NewProbe(Manager);
  firstWnd := first.Handle;
  secondWnd := second.Handle;
  first.RaiseOnDestroy := true;
  succeeded := true;
  try
    Manager.command('clear', '');
  except
    on Exception do succeeded := false;
  end;
  AssertTrue('One destructor failure must not stop cleanup', succeeded);
  AssertFalse(Manager.TryGetManagedItem(firstWnd, found));
  AssertFalse('Later owned items must still be disposed', Manager.TryGetManagedItem(secondWnd, found));
  AssertEquals(0, Manager.ItemCount);
end;

procedure TItemManagerTests.ClearingDefersExecutingItemDestruction;
var item: TProbeItem; wnd: HWND;
begin
  item := NewProbe(Manager);
  WatchedItem := item;
  wnd := item.Handle;
  item.ClearOnMessage := true;
  SendMessage(wnd, WM_APP + 43, 0, 0);
  AssertFalse('Clear must retain Self until its window callback returns', DestroyedInsideCallback);
  AssertTrue('The item must be disposed after dispatch returns', WatchedDestroyed);
  AssertFalse(IsWindow(wnd));
  WatchedItem := nil;
end;

procedure TItemManagerTests.MultiFileDropCallsEveryFile;
var item: TProbeItem; files: TStringList;
begin
  item := NewProbe(Manager);
  files := TStringList.Create;
  try
    files.Add('first.txt');
    files.Add('second.txt');
    files.Add('third.txt');
    AssertTrue(Manager.ItemDropFiles(item.Handle, Point(0, 0), files));
    AssertEquals('A successful drop must not skip later files', 3, item.DropCalls);
  finally
    files.Free;
  end;
end;

procedure TItemManagerTests.ReusedRegistrationDoesNotAcquireOwnership;
var item, found: TCustomItem; wnd: HWND; identity: TItemIdentity;
begin
  wnd := Manager.CreateItemFromString(TSeparatorItem.Make);
  Manager.TryGetManagedItem(wnd, item);
  Manager.Enable(true);
  Manager.AdoptItem(item);
  identity := ItemRegistry.IdentityOf(wnd);
  item.RecreateWindow;
  wnd := item.Handle;
  AssertEquals('View recreation preserves stable model ownership', 1, Manager.ItemCount);
  AssertTrue('A new view has a new registration generation',
    ItemRegistry.IdentityOf(wnd).Token <> identity.Token);
  AssertTrue('A new view keeps the model ID',
    ItemRegistry.IdentityOf(wnd).ItemId = identity.ItemId);
  Manager.command('clear', '');
  AssertFalse('Clear releases the owned model after view recreation', Manager.TryGetManagedItem(wnd, found));
end;

procedure TItemManagerTests.SaveToPreservesCanonicalFilename;
var stage: string;
begin
  Populate(1);
  Manager.Save(FixtureFile);
  stage := FixtureFile + '.stage';
  try
    Manager.SaveTo(stage);
    DeleteFile(FixtureFile);
    Manager.Save('');
    AssertTrue('SaveTo must preserve the canonical save path', FileExists(FixtureFile));
  finally
    DeleteFile(stage);
  end;
end;

procedure TItemManagerTests.SaveToRejectsUnavailableSnapshot;
var stage: string; rejected: boolean;
begin
  Populate(1);
  Manager.Save(FixtureFile);
  Manager.Enable(false);
  stage := FixtureFile + '.stage';
  rejected := false;
  try
    try Manager.SaveTo(stage);
    except on Exception do rejected := true; end;
    AssertTrue('An unavailable snapshot must fail the atomic save', rejected);
    Manager.Enable(true);
    DeleteFile(FixtureFile);
    Manager.Save('');
    AssertTrue('Rejected SaveTo must preserve the canonical path', FileExists(FixtureFile));
  finally
    DeleteFile(stage);
  end;
end;

procedure TItemManagerTests.ManagerCommandRetainsExecutingItem;
var item: TProbeItem;
begin
  item := NewProbe(Manager);
  WatchedItem := item;
  item.ClearOnCommand := true;
  Manager.AllItemCmd(icUpdateRunning, 0);
  AssertFalse('A command must retain its executing item', DestroyedInsideCallback);
  AssertTrue('The final command frame must release the item', WatchedDestroyed);
  WatchedItem := nil;
end;

procedure TItemManagerTests.ManagerDrawRetainsExecutingItem;
var item: TProbeItem;
begin
  item := NewProbe(Manager);
  WatchedItem := item;
  item.ClearOnDraw := true;
  Manager.Visible := true;
  AssertFalse('A draw must retain its executing item', DestroyedInsideCallback);
  AssertTrue('The final draw frame must release the item', WatchedDestroyed);
  WatchedItem := nil;
end;

procedure TItemManagerTests.ManagerFontRetainsExecutingItem;
var item: TProbeItem; font: TDFontData;
begin
  item := NewProbe(Manager);
  WatchedItem := item;
  item.ClearOnFont := true;
  font := Default(TDFontData);
  Manager.SetFont(font);
  AssertFalse('A font callback must retain its executing item', DestroyedInsideCallback);
  AssertTrue('The final font frame must release the item', WatchedDestroyed);
  WatchedItem := nil;
end;

procedure TItemManagerTests.ManagerDropRetainsExecutingItem;
var item: TProbeItem;
begin
  item := NewProbe(Manager);
  WatchedItem := item;
  item.ClearOnDrop := true;
  Manager.ItemDropFile(item.Handle, Point(0, 0), 'first.txt');
  AssertFalse('A drop must retain its executing item', DestroyedInsideCallback);
  AssertTrue('The final drop frame must release the item', WatchedDestroyed);
  WatchedItem := nil;
end;

procedure TItemManagerTests.DiscardingDeletedTasksKeepsUndoRecords;
var separator, task: TCustomItem;
begin
  Manager.TryGetManagedItem(Populate(2), separator);
  Manager.TryGetManagedItem(Manager.CreateTaskItem, task);
  Manager.AdoptItem(task);
  separator.Delete;
  task.Delete;
  Manager.UnDelete;
  AssertEquals('Discarding tasks must preserve ordinary undo records', 2, Manager.ItemCount);
  AssertEquals(0, Manager.DeletedCount);
end;

procedure TItemManagerTests.SaveToRejectsDestructiveRebuild;
var item: TProbeItem;
begin
  item := NewProbe(Manager);
  item.SaveOnDestroy := true;
  SaveStagePath := FixtureFile + '.stage';
  try
    Manager.command('clear', '');
    AssertTrue('SaveTo must reject a callback during destructive rebuild', SnapshotRejected);
    AssertFalse(FileExists(SaveStagePath));
  finally
    DeleteFile(SaveStagePath);
  end;
end;

procedure TItemManagerTests.ExternalPinSurvivesManagerDestruction;
var item: TProbeItem; identity: TItemIdentity; found: TObject;
begin
  item := NewProbe(Manager);
  WatchedItem := item;
  identity := ItemRegistry.IdentityOf(item.Handle);
  AssertTrue(ItemRegistry.Pin(identity));
  FreeAndNil(Manager);
  currentManager := nil;
  AssertFalse('Manager disposal must retain an external item pin', WatchedDestroyed);
  ItemRegistry.Unpin(identity);
  AssertTrue('The final pin must dispose the retained item', WatchedDestroyed);
  AssertFalse(ItemRegistry.TryResolve(identity, 0, found));
  WatchedItem := nil;
end;

procedure TItemManagerTests.PendingDragReceivesOwnershipTracking;
var item: TCustomItem; wnd: HWND; interaction: TDockInteractionSnapshot;
begin
  wnd := Manager.CreateItemFromString(TSeparatorItem.Make);
  Manager.TryGetManagedItem(wnd, item);
  Manager.Enable(true);
  Manager.Undock(wnd);
  AssertTrue(Manager.InteractionSnapshot.DraggingItem);
  item.Free;
  interaction := Manager.InteractionSnapshot;
  AssertFalse('Destroyed pending drag must leave no ownership state', interaction.DraggingItem);
  AssertEquals(0, PtrInt(interaction.DraggedItem));
  AssertEquals(0, Manager.ItemCount);
end;

procedure TItemManagerTests.FullStackDropPreservesSource;
var Target, Source: HWND; Item: TCustomItem; Stack: TStackItem; Index: integer;
begin
  Populate(0);
  FixtureTheme := TDTheme(TDTheme.NewInstance);
  theme := FixtureTheme;
  Target := Manager.InsertItem(TStackItem.Make('Full stack'));
  AssertTrue(Manager.TryGetManagedItem(Target, Item));
  Stack := TStackItem(Item);
  for Index := 1 to MAX_SUBITEMS do AssertTrue(Stack.AddSubitem(TShortcutItem.Make('Child')));
  Source := Manager.InsertItem(TShortcutItem.Make('Source'));
  ConfigureDockAtPoint(16);
  Manager.Undock(Source);
  Manager.Dock(Source);
  AssertEquals(2, Manager.ItemCount);
  AssertEquals(0, Manager.DeletedCount);
  AssertTrue(Manager.ItemIndex(Source) >= 0);
  AssertEquals(MAX_SUBITEMS, Stack.ItemCount);
end;

procedure TItemManagerTests.OverflowingStackMergePreservesBothStacks;
var Target, Source: HWND; Item: TCustomItem; A, B: TStackItem; Index: integer;
begin
  Populate(0);
  FixtureTheme := TDTheme(TDTheme.NewInstance);
  theme := FixtureTheme;
  Target := Manager.InsertItem(TStackItem.Make('Target'));
  AssertTrue(Manager.TryGetManagedItem(Target, Item)); A := TStackItem(Item);
  for Index := 1 to MAX_SUBITEMS - 1 do AssertTrue(A.AddSubitem(TShortcutItem.Make('Target child')));
  Source := Manager.InsertItem(TStackItem.Make('Source'));
  AssertTrue(Manager.TryGetManagedItem(Source, Item)); B := TStackItem(Item);
  AssertTrue(B.AddSubitem(TShortcutItem.Make('First')));
  AssertTrue(B.AddSubitem(TShortcutItem.Make('Second')));
  ConfigureDockAtPoint(16);
  Manager.Undock(Source);
  Manager.Dock(Source);
  AssertEquals(2, Manager.ItemCount);
  AssertEquals(0, Manager.DeletedCount);
  AssertEquals(MAX_SUBITEMS - 1, A.ItemCount);
  AssertEquals(2, B.ItemCount);
end;

procedure TItemManagerTests.StackCopyKeepsSortedAndChildren;
var Wnd: HWND; Item: TCustomItem; Original, Copy: TStackItem;
begin
  Populate(0);
  FixtureTheme := TDTheme(TDTheme.NewInstance);
  theme := FixtureTheme;
  Wnd := Manager.InsertItem(TStackItem.Make('Sorted'));
  AssertTrue(Manager.TryGetManagedItem(Wnd, Item)); Original := TStackItem(Item);
  Original.Sorted := True;
  AssertTrue(Original.AddSubitem(TShortcutItem.Make('Child')));
  Wnd := Manager.InsertItem(Original.ToStringFullCopy);
  AssertTrue(Manager.TryGetManagedItem(Wnd, Item)); Copy := TStackItem(Item);
  AssertTrue(Copy.Sorted);
  AssertEquals(1, Copy.ItemCount);
  AssertEquals('Child', UTF8Encode(Copy.GetSubitemCaption(0)));
end;

procedure TItemManagerTests.UnknownIniItemsSurviveSaving;
var Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := '[item1]' + LineEnding + 'class=separator' + LineEnding +
      '[ITEM2]' + LineEnding + 'class=future-type' + LineEnding + 'payload=keep me' + LineEnding +
      '[item3]' + LineEnding + 'class=separator' + LineEnding;
    Lines.SaveToFile(FixtureFile);
  finally Lines.Free; end;
  Manager.Enable(True);
  Manager.Load(FixtureFile);
  AssertEquals(2, Manager.ItemCount);
  Manager.Save(FixtureFile);
  AssertEquals('separator', ReadIniStringW(FixtureFile, 'item1', 'class', ''));
  AssertEquals('future-type', ReadIniStringW(FixtureFile, 'item2', 'class', ''));
  AssertEquals('keep me', ReadIniStringW(FixtureFile, 'item2', 'payload', ''));
  AssertEquals('separator', ReadIniStringW(FixtureFile, 'item3', 'class', ''));
end;

procedure TItemManagerTests.OnlyUnknownItemsDoNotCreateDefaults;
begin
  WriteIniStringW(FixtureFile, 'item1', 'class', 'future-type');
  Manager.Enable(True);
  Manager.Load(FixtureFile);
  AssertEquals(0, Manager.ItemCount);
  Manager.Save(FixtureFile);
  AssertEquals('future-type', ReadIniStringW(FixtureFile, 'item1', 'class', ''));
end;

procedure TItemManagerTests.MalformedStackRemainsInTheFile;
begin
  WriteIniStringW(FixtureFile, 'item1', 'class', 'stack');
  WriteIniStringW(FixtureFile, 'item1', 'subitem1', 'class="plugin";file="invalid.dll";');
  Manager.Enable(True);
  Manager.Load(FixtureFile);
  AssertEquals(0, Manager.ItemCount);
  Manager.Save(FixtureFile);
  AssertEquals('stack', ReadIniStringW(FixtureFile, 'item1', 'class', ''));
  AssertEquals('class="plugin";file="invalid.dll";', ReadIniStringW(FixtureFile, 'item1', 'subitem1', ''));
end;

procedure TItemManagerTests.SaveRemovesOldSectionsWithoutRemovingSettings;
var Wnd: HWND;
begin
  Wnd := Populate(2);
  WriteIniStringW(FixtureFile, 'base', 'Theme', 'Legacy theme');
  Manager.Save(FixtureFile);
  Manager.DeleteItem(Wnd);
  Manager.Save(FixtureFile);
  AssertEquals('Legacy theme', ReadIniStringW(FixtureFile, 'base', 'Theme', ''));
  AssertEquals('separator', ReadIniStringW(FixtureFile, 'item1', 'class', ''));
  AssertEquals('', ReadIniStringW(FixtureFile, 'item2', 'class', ''));
end;

procedure TItemManagerTests.FullStackRejectsFileDrop;
var Target: HWND; Item: TCustomItem; Stack: TStackItem; Index: integer;
begin
  Populate(0);
  FixtureTheme := TDTheme(TDTheme.NewInstance);
  theme := FixtureTheme;
  Target := Manager.InsertItem(TStackItem.Make('Full stack'));
  AssertTrue(Manager.TryGetManagedItem(Target, Item));
  Stack := TStackItem(Item);
  for Index := 1 to MAX_SUBITEMS do AssertTrue(Stack.AddSubitem(TShortcutItem.Make('Child')));
  AssertFalse(Stack.DropFile(Target, Classes.Point(0, 0), 'C:\missing\new.txt'));
  AssertEquals(MAX_SUBITEMS, Stack.ItemCount);
end;

procedure TItemManagerTests.ImportedTargetsReportInsertionAndReload;
var Batch: TDropImportBatch; Restored: TItemManager;
begin
  Populate(0);
  Batch := TDropImportBatch.Create('');
  try
    Batch.Add('https://example.invalid/first');
    Batch.Add('https://example.invalid/second');
    Batch.Expose;
    Manager.ImportDropFiles(Batch, 0, Point(0, 0));
    AssertEquals(2, Batch.AcceptedCount);
    AssertEquals(2, Manager.ItemCount);
    Manager.Save(FixtureFile);
    AssertEquals(Batch[0], ReadIniStringW(FixtureFile, 'item1', 'command', ''));
    AssertEquals(Batch[1], ReadIniStringW(FixtureFile, 'item2', 'command', ''));
    Restored := NewManager;
    try Restored.Load(FixtureFile); AssertEquals(2, Restored.ItemCount);
    finally Restored.Free; end;
  finally Batch.Free; end;
end;

procedure TItemManagerTests.UnlaunchableImportedTargetsSurviveReload;
var Batch: TDropImportBatch; Restored: TItemManager;
begin
  Populate(0);
  Batch := TDropImportBatch.Create('');
  try
    Batch.Add('tdock-unregistered-wo18:kept');
    Batch.Add('C:\tdock-wo18-missing\not-installed.exe');
    Batch.Expose;
    Manager.ImportDropFiles(Batch, 0, Point(0, 0));
    AssertEquals('Launchability must not control insertion', 2, Batch.AcceptedCount);
    Manager.Save(FixtureFile);
    AssertEquals(Batch[0], ReadIniStringW(FixtureFile, 'item1', 'command', ''));
    AssertEquals(Batch[1], ReadIniStringW(FixtureFile, 'item2', 'command', ''));
    Restored := NewManager;
    try Restored.Load(FixtureFile); AssertEquals(2, Restored.ItemCount);
    finally Restored.Free; end;
  finally Batch.Free; end;
end;

procedure TItemManagerTests.ImportedTargetsReportDisabledRejection;
var Batch: TDropImportBatch;
begin
  Batch := TDropImportBatch.Create('');
  try
    Batch.Add('https://example.invalid/'); Batch.Expose;
    Manager.ImportDropFiles(Batch, 0, Point(0, 0));
    AssertEquals(0, Batch.AcceptedCount);
    AssertEquals(0, Manager.ItemCount);
  finally Batch.Free; end;
end;

procedure TItemManagerTests.ImportedTargetsStopAtStackCapacity;
var Batch: TDropImportBatch; Target: HWND; Item: TCustomItem; Stack: TStackItem; I: Integer;
begin
  Populate(0);
  FixtureTheme := TDTheme(TDTheme.NewInstance); theme := FixtureTheme;
  Target := Manager.InsertItem(TStackItem.Make('Imported'));
  AssertTrue(Manager.TryGetManagedItem(Target, Item)); Stack := TStackItem(Item);
  for I := 1 to MAX_SUBITEMS - 1 do AssertTrue(Stack.AddSubitem(TShortcutItem.Make('Child')));
  Batch := TDropImportBatch.Create('');
  try
    Batch.Add('https://example.invalid/in-stack');
    Batch.Add('https://example.invalid/in-dock'); Batch.Expose;
    Manager.ImportDropFiles(Batch, Target, Point(0, 0));
    AssertEquals('Full stack must reject the remaining target', 1, Batch.AcceptedCount);
    AssertEquals(MAX_SUBITEMS, Stack.ItemCount);
    AssertEquals('Stack overflow must not create a dock launcher', 1, Manager.ItemCount);
    Manager.Save(FixtureFile);
    AssertEquals('', ReadIniStringW(FixtureFile, 'item2', 'command', ''));
  finally Batch.Free; end;
end;

procedure TItemManagerTests.AttentionBroadcastRetainsEarlierAcceptance;
var First, Last: TProbeItem;
begin
  First := NewProbe(Manager);
  Last := NewProbe(Manager);
  First.AttentionResult := 1;
  AssertEquals('A later unrelated item cannot erase a new attention event', 1,
    Manager.AllItemCmd(icFlashTaskWindow, 0));
  First.AttentionResult := 0;
  AssertEquals(0, Manager.AllItemCmd(icFlashTaskWindow, 0));
  Last.AttentionResult := 1;
  AssertEquals(1, Manager.AllItemCmd(icFlashTaskWindow, 0));
end;

initialization
  RegisterTest(TItemManagerTests);
end.
