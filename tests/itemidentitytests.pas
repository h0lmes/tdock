unit itemidentitytests;

{$mode delphi}

interface

uses Windows, Messages, SysUtils, fpcunit, testregistry, declu,
  customitemu, itemmgru, itemsettingsu, itemregistryu, itemhostu, pluginhostu,
  itemmodelu, itemviewu, dockstateu;

type
  TIdentityProbe = class(TCustomItem)
  public
    Draws, Ticks: integer;
    destructor Destroy; override;
    procedure Draw(Ax, Ay, ASize: integer; AForce: boolean; wpi: HDWP; AShowItem: UINT); override;
    procedure WndMessage(var msg: TMessage); override;
    procedure WMCommand(wParam: WPARAM; lParam: LPARAM; var Result: LRESULT); override;
    function ToString: string; override;
    procedure Save(ini, section: string); override;
  end;

  TFailedIdentityProbe = class(TIdentityProbe)
  protected
    function CreateViewWindow: HWND; override;
  end;

  TItemIdentityTests = class(TTestCase)
  private
    Manager: TItemManager;
    Host: TPluginHost;
    procedure DeleteThroughHost(wnd: HWND);
    procedure FailRemoval(Id: TItemId);
    function NewProbe(Adopt: boolean): TIdentityProbe;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure NativeDestructionInvalidatesLookup;
    procedure NativeDestructionKeepsExecutingLease;
    procedure PluginDeletionHidesAndDisablesItem;
    procedure PendingDeletionEntersUndo;
    procedure ViewRecreationPreservesModelIdentity;
    procedure ClearDisposesPendingModels;
    procedure FailedNativeCreationReleasesPendingOwnership;
    procedure RetiringModelReleasesEveryMouseLock;
    procedure ViewReplacementPreservesMouseLockIdentity;
    procedure ViewReplacementRestoresRenderingAndTimers;
    procedure RemovalFailureStillClearsMembership;
    procedure DeletionFailureStillClearsInteraction;
  end;

implementation

var DestroyedCount: integer;

function TFailedIdentityProbe.CreateViewWindow: HWND;
begin Result := 0; end;

destructor TIdentityProbe.Destroy;
begin
  inc(DestroyedCount);
  inherited;
end;

procedure TIdentityProbe.Draw(Ax, Ay, ASize: integer; AForce: boolean;
  wpi: HDWP; AShowItem: UINT);
begin
  if FFreed then exit;
  inc(Draws);
  FShowItem := AShowItem;
  if AShowItem = SWP_SHOWWINDOW then ShowWindow(Handle, SW_SHOWNOACTIVATE);
end;

procedure TIdentityProbe.WndMessage(var msg: TMessage);
begin
  if (msg.Msg = WM_TIMER) and (msg.WParam = 77) then inc(Ticks);
  msg.Result := 0;
end;
procedure TIdentityProbe.WMCommand(wParam: WPARAM; lParam: LPARAM; var Result: LRESULT);
begin Result := 0; end;
function TIdentityProbe.ToString: string;
begin Result := 'class="separator";'; end;
procedure TIdentityProbe.Save(ini, section: string);
begin end;

procedure TItemIdentityTests.SetUp;
var settings: TItemManagerSettings; services: TItemHostServices;
begin
  DestroyedCount := 0;
  settings := Default(TItemManagerSettings);
  settings.ItemSize := 32;
  settings.BigItemSize := 32;
  settings.ZoomTime := 1;
  Manager := TItemManager.Create(0, settings, nil);
  Manager.Enable(true);
  Host := TPluginHost.Create;
  Host.Bind(Manager);
  services := Default(TItemHostServices);
  services.OnDelete := DeleteThroughHost;
  BindItemHost(0, services);
end;

procedure TItemIdentityTests.TearDown;
begin
  UnbindItemHost(0);
  Host.Unbind;
  Host.Free;
  Manager.Free;
end;

procedure TItemIdentityTests.DeleteThroughHost(wnd: HWND);
begin Manager.DeleteItem(wnd); end;

procedure TItemIdentityTests.FailRemoval(Id: TItemId);
begin raise Exception.Create('Removal callback failure'); end;

function TItemIdentityTests.NewProbe(Adopt: boolean): TIdentityProbe;
var params: TDItemCreateParams;
begin
  params := Default(TDItemCreateParams);
  params.ItemSize := 32;
  params.BigItemSize := 32;
  Result := TIdentityProbe.Create(0, params);
  if Adopt then AssertTrue(Manager.AdoptItem(Result, false) <> 0);
end;

procedure TItemIdentityTests.NativeDestructionInvalidatesLookup;
var item, found: TCustomItem; wnd: HWND;
begin
  item := NewProbe(true);
  wnd := item.Handle;
  try
    AssertTrue(DestroyWindow(wnd));
    AssertFalse('Destroyed native views must leave no item lookup', Manager.TryGetManagedItem(wnd, found));
    AssertEquals('Native loss removes active membership', 0, Manager.ItemCount);
    AssertEquals('Native loss disposes the model once', 1, DestroyedCount);
  finally
    if Manager.TryGetManagedItem(wnd, found) then found.Free;
  end;
end;

procedure TItemIdentityTests.NativeDestructionKeepsExecutingLease;
var item: TCustomItem; identity: TItemIdentity; found: TObject;
begin
  item := NewProbe(true);
  identity := ItemRegistry.IdentityOf(item.Handle);
  AssertTrue(ItemRegistry.Pin(identity));
  try
    AssertTrue(DestroyWindow(identity.Handle));
    AssertFalse('Native detachment invalidates the binding during dispatch',
      ItemRegistry.TryResolve(identity, 0, found));
    AssertEquals('The executing model lease survives detachment', 0, DestroyedCount);
  finally
    ItemRegistry.Unpin(identity);
  end;
  AssertEquals('The final model lease releases the detached item', 1, DestroyedCount);
end;

procedure TItemIdentityTests.PluginDeletionHidesAndDisablesItem;
var item: TCustomItem; wnd: HWND;
begin
  item := NewProbe(true);
  wnd := item.Handle;
  ShowWindow(wnd, SW_SHOWNOACTIVATE);
  AssertTrue(IsWindowVisible(wnd));
  Host.DeleteItem(wnd);
  AssertFalse('Plugin deletion must hide the retained undo window', IsWindowVisible(wnd));
  AssertTrue('Plugin deletion must disable item interaction', item.Freed);
  AssertEquals(1, Manager.DeletedCount);
  Manager.UnDelete;
  AssertFalse(item.Freed);
end;

procedure TItemIdentityTests.PendingDeletionEntersUndo;
var item: TCustomItem;
begin
  item := NewProbe(false);
  try
    item.Delete;
    AssertEquals('A pending copy must become an owned undo item', 1, Manager.DeletedCount);
    Manager.UnDelete;
    AssertEquals(1, Manager.ItemCount);
    item := nil;
  finally
    item.Free;
  end;
end;

procedure TItemIdentityTests.ViewRecreationPreservesModelIdentity;
var item, found: TCustomItem; identity: TItemIdentity; old: TObject;
begin
  item := NewProbe(true);
  identity := ItemRegistry.IdentityOf(item.Handle);
  item.RecreateWindow;
  AssertTrue(IsWindow(item.Handle));
  AssertTrue('A recreated view keeps the model ID', item.ItemId = identity.ItemId);
  AssertFalse('A replaced native binding rejects its old generation',
    ItemRegistry.TryResolve(identity, 0, old));
  AssertTrue(Manager.TryGetItemById(identity.ItemId, found));
  AssertTrue(found = item);
  AssertEquals(1, Manager.ItemCount);
end;

procedure TItemIdentityTests.ClearDisposesPendingModels;
var item: TCustomItem; id: TItemId;
begin
  item := NewProbe(false);
  id := item.ItemId;
  AssertTrue('Creation assigns an owner before insertion', item.Owner <> nil);
  AssertEquals(0, Manager.ItemCount);
  Manager.command('clear', '');
  AssertTrue('Clear also releases pending creation', FindItemModel(id) = nil);
  AssertEquals(1, DestroyedCount);
end;

procedure TItemIdentityTests.FailedNativeCreationReleasesPendingOwnership;
var anchor: TCustomItem; store: TItemStore; params: TDItemCreateParams; failed: boolean;
begin
  anchor := NewProbe(false);
  store := anchor.Owner;
  params := Default(TDItemCreateParams);
  params.ItemSize := 32;
  params.BigItemSize := 32;
  failed := false;
  try TFailedIdentityProbe.Create(0, params);
  except on E: EOSError do failed := true; end;
  AssertTrue('Native creation failure must reach the caller', failed);
  AssertEquals('Failed construction cannot retain ownership', 1, store.Count);
  AssertEquals('The failed object is destroyed once', 1, DestroyedCount);
  AssertTrue(FindItemModel(anchor.ItemId) = anchor);
end;

procedure TItemIdentityTests.RetiringModelReleasesEveryMouseLock;
var item, other: TCustomItem; state: TDockState;
begin
  item := NewProbe(true);
  other := NewProbe(true);
  state := TDockState.Create;
  try
    Manager.OnItemRemoved := state.ReleaseItemLocks;
    state.SetMouseEffectLock(item.ItemId, true);
    state.SetMouseEffectLock(other.ItemId, true);
    state.SetMouseEffectLock(item.ItemId, true);
    item.Free;
    AssertTrue('Other models keep their own locks', state.MouseEffectLocked);
    state.SetMouseEffectLock(other.ItemId, false);
    AssertFalse('Retirement releases every lock belonging to the model', state.MouseEffectLocked);
  finally
    Manager.OnItemRemoved := nil;
    state.Free;
  end;
end;

procedure TItemIdentityTests.ViewReplacementPreservesMouseLockIdentity;
var item: TCustomItem; id: TItemId;
begin
  item := NewProbe(true);
  id := ItemViews.AcquireMouseLock(item.Handle);
  AssertTrue(id = item.ItemId);
  item.RecreateWindow;
  AssertTrue('The replacement view must release the original model lock',
    ItemViews.ReleaseMouseLock(item.Handle) = id);
end;

procedure TItemIdentityTests.ViewReplacementRestoresRenderingAndTimers;
var item: TIdentityProbe; draws: integer; started: QWord; message: Windows.TMsg;
begin
  item := NewProbe(true);
  draws := item.Draws;
  AssertTrue(ItemViews.SetItemTimer(item.ItemId, 77, 10) <> 0);
  item.RecreateWindow;
  AssertTrue('Replacement must redraw unchanged cached geometry', item.Draws > draws);
  started := GetTickCount64;
  while (item.Ticks = 0) and (GetTickCount64 - started < 1000) do
  begin
    while PeekMessage(message, 0, 0, 0, PM_REMOVE) do
    begin TranslateMessage(message); DispatchMessage(message); end;
    Windows.Sleep(5);
  end;
  AssertTrue('The replacement native view must restore model timers', item.Ticks > 0);
end;

procedure TItemIdentityTests.RemovalFailureStillClearsMembership;
var item: TCustomItem; failed: boolean;
begin
  item := NewProbe(true);
  Manager.OnItemRemoved := FailRemoval;
  try
    failed := false;
    try item.Free;
    except on E: Exception do failed := true; end;
    AssertTrue('The callback failure must remain visible', failed);
    AssertEquals('Removal must clear membership before notification', 0, Manager.ItemCount);
    AssertEquals(1, DestroyedCount);
  finally Manager.OnItemRemoved := nil; end;
end;

procedure TItemIdentityTests.DeletionFailureStillClearsInteraction;
var item: TCustomItem; snapshot: TDockInteractionSnapshot;
begin
  item := NewProbe(true);
  Manager.UndockItemById(item.ItemId);
  AssertTrue(Manager.InteractionSnapshot.DraggedItem = item.ItemId);
  Manager.OnItemRemoved := FailRemoval;
  try
    try Manager.DeleteItemById(item.ItemId);
    except on E: Exception do ; end;
    snapshot := Manager.InteractionSnapshot;
    AssertTrue('Deletion clears the dragged model before notification', snapshot.DraggedItem = NO_ITEM_ID);
    AssertFalse('Deletion clears dragging before notification', snapshot.DraggingItem);
    AssertEquals(1, Manager.DeletedCount);
  finally Manager.OnItemRemoved := nil; end;
end;

initialization
  RegisterTest(TItemIdentityTests);
end.
