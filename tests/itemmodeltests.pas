unit itemmodeltests;

{$mode delphi}

interface
uses SysUtils, fpcunit, testregistry, itemmodelu;
type
  TTrackedModel = class(TItemModel)
    destructor Destroy; override;
  end;
  TFailingModel = class(TTrackedModel)
    FailureMessage: string;
    destructor Destroy; override;
  end;
  TItemModelTests = class(TTestCase)
  private
    procedure FreeDuringRemoval(Id: TItemId);
    procedure ReleaseDuringRemoval(Id: TItemId);
  published
    procedure IdentifiersAreUniqueAndNeverReused;
    procedure StoreOwnsPendingModels;
    procedure StoreDestructionRetainsExecutingModel;
    procedure RetiringModelRejectsNewLeases;
    procedure OwnershipCannotBeAcquiredTwice;
    procedure RetirementCallbackCannotDestroyModelTwice;
    procedure RetirementCallbackCanReleaseLastExternalLease;
    procedure NestedCreationRetainsRetiredModelsUntilOuterScopeEnds;
    procedure CreationCleanupDrainsAllModelsAndReportsFirstFailure;
    procedure CreationRejectsModelsThatCannotBeLeased;
  end;
implementation
var Destroyed: integer;
procedure TItemModelTests.FreeDuringRemoval(Id: TItemId);
var model: TItemModel;
begin
  model := FindItemModel(Id);
  if assigned(model) then model.Free;
end;
procedure TItemModelTests.ReleaseDuringRemoval(Id: TItemId);
begin ReleaseItemModel(Id); end;
destructor TTrackedModel.Destroy;
begin inc(Destroyed); inherited; end;
destructor TFailingModel.Destroy;
begin
  try raise Exception.Create(FailureMessage);
  finally inherited; end;
end;
procedure TItemModelTests.IdentifiersAreUniqueAndNeverReused;
var first, second: TItemModel; oldId: TItemId;
begin
  first := TItemModel.Create;
  oldId := first.ItemId;
  first.Free;
  second := TItemModel.Create;
  try
    AssertTrue('IDs must be nonzero', oldId <> NO_ITEM_ID);
    AssertTrue('New models cannot reuse a retired ID', second.ItemId <> oldId);
    AssertTrue(FindItemModel(oldId) = nil);
    AssertTrue(FindItemModel(second.ItemId) = second);
  finally second.Free; end;
end;
procedure TItemModelTests.StoreOwnsPendingModels;
var store: TItemStore; model: TTrackedModel;
begin
  Destroyed := 0;
  store := TItemStore.Create;
  model := TTrackedModel.Create;
  AssertTrue('A pending model must enter the owning store', store.Add(model));
  AssertEquals(Ord(imsPending), Ord(model.State));
  AssertEquals(1, store.Count);
  store.Free;
  AssertEquals('Store disposal must release its pending model', 1, Destroyed);
end;
procedure TItemModelTests.StoreDestructionRetainsExecutingModel;
var store: TItemStore; model, leased: TItemModel; id: TItemId;
begin
  Destroyed := 0;
  store := TItemStore.Create;
  model := TTrackedModel.Create;
  store.Add(model);
  id := model.ItemId;
  AssertTrue(AcquireItemModel(id, leased));
  store.Free;
  AssertEquals('The callback must retain its model after store disposal', 0, Destroyed);
  AssertTrue(model.Owner = nil);
  ReleaseItemModel(id);
  AssertEquals(1, Destroyed);
  AssertTrue(FindItemModel(id) = nil);
end;
procedure TItemModelTests.RetiringModelRejectsNewLeases;
var model, leased: TItemModel; id: TItemId;
begin
  Destroyed := 0;
  model := TTrackedModel.Create;
  id := model.ItemId;
  AssertTrue(AcquireItemModel(id, leased));
  model.Free;
  AssertFalse('Retirement must reject new callback frames', AcquireItemModel(id, leased));
  AssertEquals(0, Destroyed);
  ReleaseItemModel(id);
  AssertEquals(1, Destroyed);
end;
procedure TItemModelTests.OwnershipCannotBeAcquiredTwice;
var first, second: TItemStore; model: TItemModel;
begin
  first := TItemStore.Create;
  second := TItemStore.Create;
  model := TItemModel.Create;
  try
    AssertTrue(first.Add(model));
    AssertFalse('A model must have one owner', second.Add(model));
    AssertTrue(model.Owner = first);
  finally second.Free; first.Free; end;
end;

procedure TItemModelTests.RetirementCallbackCannotDestroyModelTwice;
var store: TItemStore; model: TItemModel; failed: boolean;
begin
  Destroyed := 0;
  store := TItemStore.Create;
  model := TTrackedModel.Create;
  store.Add(model);
  store.OnRemoved := FreeDuringRemoval;
  try
    failed := false;
    try model.Free;
    except on E: TObject do failed := true; end;
    AssertFalse('Reentrant retirement must not access released memory', failed);
    AssertEquals('Reentrant retirement destroys the model exactly once', 1, Destroyed);
  finally store.Free; end;
end;

procedure TItemModelTests.RetirementCallbackCanReleaseLastExternalLease;
var store: TItemStore; model: TItemModel; failed: boolean;
begin
  Destroyed := 0;
  store := TItemStore.Create;
  model := TTrackedModel.Create;
  store.Add(model);
  model.Pin;
  store.OnRemoved := ReleaseDuringRemoval;
  try
    failed := false;
    try model.Free;
    except on E: TObject do failed := true; end;
    AssertFalse('Removal callbacks must not release the active destruction frame', failed);
    AssertEquals('Removal keeps an internal lease through callback return', 1, Destroyed);
  finally store.Free; end;
end;

procedure TItemModelTests.NestedCreationRetainsRetiredModelsUntilOuterScopeEnds;
var store: TItemStore; first, second: TItemModel; firstId, secondId: TItemId;
begin
  Destroyed := 0;
  store := TItemStore.Create;
  first := TTrackedModel.Create;
  second := TTrackedModel.Create;
  firstId := first.ItemId;
  secondId := second.ItemId;
  try
    store.BeginCreation;
    AssertTrue(store.Add(first));
    store.BeginCreation;
    AssertTrue(store.Add(second));
    store.Clear;
    AssertEquals('Retired constructors must retain both models', 0, Destroyed);
    AssertEquals(0, store.Count);
    store.EndCreation;
    AssertEquals('The outer creation scope must retain nested models', 0, Destroyed);
    AssertTrue(FindItemModel(firstId) = first);
    AssertTrue(FindItemModel(secondId) = second);
    store.EndCreation;
    AssertEquals('The final scope releases every retired model', 2, Destroyed);
    AssertTrue(FindItemModel(firstId) = nil);
    AssertTrue(FindItemModel(secondId) = nil);
  finally
    store.EndCreation;
    store.EndCreation;
    store.Free;
    if FindItemModel(firstId) <> nil then first.Free;
    if FindItemModel(secondId) <> nil then second.Free;
  end;
end;

procedure TItemModelTests.CreationCleanupDrainsAllModelsAndReportsFirstFailure;
var store: TItemStore; first, second: TFailingModel;
  firstId, secondId: TItemId; failure: string;
begin
  Destroyed := 0;
  store := TItemStore.Create;
  first := TFailingModel.Create;
  first.FailureMessage := 'First model cleanup failed';
  second := TFailingModel.Create;
  second.FailureMessage := 'Second model cleanup failed';
  firstId := first.ItemId;
  secondId := second.ItemId;
  try
    store.BeginCreation;
    AssertTrue(store.Add(first));
    AssertTrue(store.Add(second));
    store.Clear;
    AssertEquals('Creation must defer both destructors', 0, Destroyed);
    failure := '';
    try store.EndCreation;
    except on E: Exception do failure := E.Message; end;
    AssertEquals('Cleanup must release later models after a destructor fails', 2, Destroyed);
    AssertEquals('Cleanup must report the first destructor failure',
      'First model cleanup failed', failure);
    AssertTrue(FindItemModel(firstId) = nil);
    AssertTrue(FindItemModel(secondId) = nil);
    store.EndCreation;
    AssertEquals('Repeated cleanup cannot destroy models twice', 2, Destroyed);
  finally
    try store.EndCreation; except end;
    if FindItemModel(firstId) <> nil then
      try ReleaseItemModel(firstId); except end;
    if FindItemModel(secondId) <> nil then
      try ReleaseItemModel(secondId); except end;
    try store.Free; except end;
  end;
end;

procedure TItemModelTests.CreationRejectsModelsThatCannotBeLeased;
var store: TItemStore; parent, child: TItemModel; childId: TItemId;
begin
  store := TItemStore.Create;
  parent := TItemModel.Create;
  child := TTrackedModel.Create;
  childId := child.ItemId;
  parent.State := imsDeleted;
  child.ParentItemId := parent.ItemId;
  try
    store.BeginCreation;
    AssertFalse('Creation cannot own a model without its required lease', store.Add(child));
    AssertEquals('Rejected creation must roll back store allocation', 0, store.Count);
    AssertTrue('Rejected creation must preserve caller ownership', child.Owner = nil);
    AssertEquals('Rejected creation cannot retain a lease', 0, child.PinCount);
    store.EndCreation;
    AssertTrue('Failed admission cannot retire the caller model', FindItemModel(childId) = child);
  finally
    store.EndCreation;
    store.Free;
    if FindItemModel(childId) <> nil then child.Free;
    parent.Free;
  end;
end;
initialization RegisterTest(TItemModelTests);
end.
