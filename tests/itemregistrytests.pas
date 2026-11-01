unit itemregistrytests;

{$mode delphi}

interface

uses Windows, fpcunit, testregistry, itemregistryu, itemmodelu;

type
  TItemRegistryTests = class(TTestCase)
  private
    RemovedCount: integer;
    RemovedToken: QWord;
    procedure OwnerRemoved(const Identity: TItemIdentity);
  published
    procedure RegistersModelWithoutTakingOwnership;
    procedure RejectsUnknownAndForeignHandles;
    procedure UnregisterInvalidatesPreviousIdentity;
    procedure DispatchPinDefersOwnedDestruction;
    procedure UnregisterNotifiesTheCurrentOwner;
  end;

implementation

type
  TTrackedModel = class(TItemModel)
  public
    destructor Destroy; override;
  end;

var Destroyed: boolean;

procedure TItemRegistryTests.OwnerRemoved(const Identity: TItemIdentity);
begin
  inc(RemovedCount);
  RemovedToken := Identity.Token;
end;

destructor TTrackedModel.Destroy;
begin
  Destroyed := true;
  inherited;
end;

procedure TItemRegistryTests.RegistersModelWithoutTakingOwnership;
var registry: TItemRegistry; item: TItemModel; found: TObject;
begin
  Destroyed := false;
  registry := TItemRegistry.Create;
  item := TTrackedModel.Create;
  try
    AssertTrue('Registration must accept a live model', registry.RegisterItem(101, 7, item));
    AssertTrue(registry.TryGet(101, 7, found));
    AssertTrue(found = item);
    registry.Free;
    registry := nil;
    AssertFalse('Registry must not destroy caller-owned models', Destroyed);
  finally
    registry.Free;
    item.Free;
  end;
end;

procedure TItemRegistryTests.RejectsUnknownAndForeignHandles;
var registry: TItemRegistry; item: TItemModel; found: TObject;
begin
  registry := TItemRegistry.Create;
  item := TItemModel.Create;
  try
    AssertFalse(registry.RegisterItem(0, 7, item));
    AssertFalse(registry.RegisterItem(101, 7, nil));
    AssertTrue(registry.RegisterItem(101, 7, item));
    AssertFalse(registry.RegisterItem(101, 8, item));
    AssertFalse(registry.TryGet(0, 7, found));
    AssertTrue(found = nil);
    AssertFalse(registry.TryGet(999, 7, found));
    AssertTrue(found = nil);
    AssertFalse(registry.TryGet(101, 8, found));
    AssertTrue(found = nil);
  finally
    registry.Free;
    item.Free;
  end;
end;

procedure TItemRegistryTests.UnregisterInvalidatesPreviousIdentity;
var registry: TItemRegistry; item, replacement: TItemModel; found: TObject;
  identity: TItemIdentity;
begin
  registry := TItemRegistry.Create;
  item := TItemModel.Create;
  replacement := TItemModel.Create;
  try
    AssertTrue(registry.RegisterItem(101, 7, item));
    identity := registry.IdentityOf(101);
    registry.UnregisterItem(101, replacement);
    AssertTrue('A foreign object must not remove registration', registry.TryGet(101, 7, found));
    registry.UnregisterItem(101, item);
    AssertFalse('Unregister must remove the handle', registry.TryGet(101, 7, found));
    AssertTrue(registry.RegisterItem(101, 7, replacement));
    AssertFalse('Reused handles must reject old identities', registry.TryResolve(identity, 7, found));
    AssertTrue(registry.TryResolve(registry.IdentityOf(101), 7, found));
    AssertTrue(found = replacement);
  finally
    registry.Free;
    item.Free;
    replacement.Free;
  end;
end;

procedure TItemRegistryTests.DispatchPinDefersOwnedDestruction;
var registry: TItemRegistry; item: TItemModel; found: TObject; identity: TItemIdentity;
begin
  Destroyed := false;
  registry := TItemRegistry.Create;
  item := TTrackedModel.Create;
  try
    registry.RegisterItem(101, 7, item);
    identity := registry.IdentityOf(101);
    AssertTrue('Live dispatch must pin the registered identity', registry.Pin(identity));
    AssertTrue(registry.Pin(identity));
    AssertTrue('Owned destruction must wait for active dispatch', item.DeferDestruction);
    AssertFalse(Destroyed);
    AssertTrue(registry.TryGet(101, 7, found));
    AssertFalse('Pending destruction must reject new dispatch', registry.Pin(identity));
    registry.Unpin(identity);
    AssertFalse('Nested dispatch still retains the item', Destroyed);
    registry.Unpin(identity);
    AssertTrue('Final dispatch release must destroy the item', Destroyed);
    AssertFalse(registry.TryGet(101, 7, found));
    item := nil;
  finally
    registry.Free;
    item.Free;
  end;
end;

procedure TItemRegistryTests.UnregisterNotifiesTheCurrentOwner;
var registry: TItemRegistry; item: TItemModel; identity: TItemIdentity;
begin
  registry := TItemRegistry.Create;
  item := TItemModel.Create;
  try
    registry.RegisterItem(101, 7, item);
    identity := registry.IdentityOf(101);
    registry.SetOwner(identity, OwnerRemoved);
    registry.UnregisterItem(101, item);
    AssertEquals('Unregister must remove the previous ownership', 1, RemovedCount);
    AssertTrue(RemovedToken = identity.Token);
    registry.RegisterItem(101, 7, item);
    identity := registry.IdentityOf(101);
    registry.SetOwner(identity, OwnerRemoved);
    registry.ClearOwner(identity);
    registry.UnregisterItem(101, item);
    AssertEquals('Detached ownership must not call a released manager', 1, RemovedCount);
  finally
    registry.Free;
    item.Free;
  end;
end;

initialization
  RegisterTest(TItemRegistryTests);
end.
