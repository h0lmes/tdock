unit itemmodelu;

{$mode delphi}

interface

type
  TItemId = type QWord;
  TItemIds = array of TItemId;
  TItemState = (imsPending, imsActive, imsDragging, imsDeleted, imsRetiring);
  TItemModel = class;
  TItemStore = class;
  TItemRemovedEvent = procedure(Id: TItemId) of object;

  TItemModel = class
  private
    FItemId, FParentItemId: TItemId;
    FState: TItemState;
    FPins: integer;
    FDestroyRequested: boolean;
    FOwner: TItemStore;
    procedure DetachModel;
  protected
    procedure BeforeDestruction; override;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Free;
    function Pin: boolean;
    procedure Unpin;
    function DeferDestruction: boolean;
    procedure ViewDestroyed; virtual;
    function ChildStore: TItemStore; virtual;
    property ItemId: TItemId read FItemId;
    property ParentItemId: TItemId read FParentItemId write FParentItemId;
    property State: TItemState read FState write FState;
    property PinCount: integer read FPins;
    property Owner: TItemStore read FOwner;
  end;

  TItemStore = class
  private
    FModels: array of TItemModel;
    FOnRemoved: TItemRemovedEvent;
    FCreationDepth: integer;
    FCreationLeases: TItemIds;
    procedure Detach(Model: TItemModel);
    function GetCount: integer;
  public
    destructor Destroy; override;
    function Add(Model: TItemModel): boolean;
    function Find(Id: TItemId): TItemModel;
    function Contains(Id: TItemId): boolean;
    function Snapshot: TItemIds;
    procedure Retire(Id: TItemId);
    procedure Clear;
    procedure BeginCreation;
    procedure EndCreation;
    property Count: integer read GetCount;
    property OnRemoved: TItemRemovedEvent read FOnRemoved write FOnRemoved;
  end;

const NO_ITEM_ID: TItemId = 0;

function AllocateItemId: TItemId;
function FindItemModel(Id: TItemId): TItemModel;
function AcquireItemModel(Id: TItemId; out Model: TItemModel): boolean;
procedure ReleaseItemModel(Id: TItemId);

implementation

uses SysUtils;

var
  NextItemId: QWord;
  Models: array of TItemModel;

function AllocateItemId: TItemId;
begin
  if NextItemId = High(QWord) then
    raise EOverflow.Create('Item identifiers are exhausted');
  inc(NextItemId);
  Result := TItemId(NextItemId);
end;

function FindItemModel(Id: TItemId): TItemModel;
var index: integer;
begin
  Result := nil;
  if Id = NO_ITEM_ID then exit;
  for index := 0 to High(Models) do
    if Models[index].ItemId = Id then exit(Models[index]);
end;

function AcquireItemModel(Id: TItemId; out Model: TItemModel): boolean;
begin
  Model := FindItemModel(Id);
  Result := assigned(Model) and Model.Pin;
  if not Result then Model := nil;
end;

procedure ReleaseItemModel(Id: TItemId);
var model: TItemModel;
begin
  model := FindItemModel(Id);
  if assigned(model) then model.Unpin;
end;

constructor TItemModel.Create;
var index: integer;
begin
  inherited;
  FItemId := AllocateItemId;
  FState := imsPending;
  index := Length(Models);
  SetLength(Models, index + 1);
  Models[index] := Self;
end;
procedure TItemModel.DetachModel;
var index, next: integer;
begin
  FDestroyRequested := true;
  FState := imsRetiring;
  for index := 0 to High(Models) do
    if Models[index] = Self then
    begin
      for next := index to High(Models) - 1 do Models[next] := Models[next + 1];
      SetLength(Models, Length(Models) - 1);
      break;
    end;
  if assigned(FOwner) then FOwner.Detach(Self);
end;

procedure TItemModel.BeforeDestruction;
begin
  DetachModel;
  inherited;
end;

destructor TItemModel.Destroy;
begin
  try DetachModel;
  finally inherited; end;
end;
procedure TItemModel.Free;
begin
  if Self = nil then exit;
  if FDestroyRequested then exit;
  FDestroyRequested := true;
  FState := imsRetiring;
  inc(FPins); // retain the retirement frame through owner callbacks
  try
    if assigned(FOwner) then FOwner.Detach(Self);
  finally
    dec(FPins);
    if FPins = 0 then inherited Free;
  end;
end;
function TItemModel.Pin: boolean;
var parent: TItemModel; parentId: TItemId; depth: integer;
begin
  Result := not FDestroyRequested and (FState <> imsRetiring);
  parentId := FParentItemId;
  depth := 0;
  while Result and (parentId <> NO_ITEM_ID) do
  begin
    parent := FindItemModel(parentId);
    inc(depth);
    Result := assigned(parent) and (depth <= Length(Models));
    if Result then
    begin
      Result := not (parent.State in [imsDeleted, imsRetiring]);
      parentId := parent.ParentItemId;
    end;
  end;
  if Result then inc(FPins);
end;
procedure TItemModel.Unpin;
begin
  if FPins <= 0 then exit;
  dec(FPins);
  if (FPins = 0) and FDestroyRequested then inherited Free;
end;
function TItemModel.DeferDestruction: boolean;
begin
  Result := FPins > 0;
  if Result then Free;
end;
procedure TItemModel.ViewDestroyed;
begin Free; end;
function TItemModel.ChildStore: TItemStore;
begin Result := nil; end;
destructor TItemStore.Destroy;
begin
  FOnRemoved := nil;
  try Clear;
  finally inherited; end;
end;
function TItemStore.GetCount: integer;
begin Result := Length(FModels); end;
procedure TItemStore.Detach(Model: TItemModel);
var index, next: integer; callback: TItemRemovedEvent;
begin
  for index := 0 to High(FModels) do
    if FModels[index] = Model then
    begin
      for next := index to High(FModels) - 1 do FModels[next] := FModels[next + 1];
      SetLength(FModels, Length(FModels) - 1);
      Model.FOwner := nil;
      callback := FOnRemoved;
      if assigned(callback) then callback(Model.ItemId);
      exit;
    end;
end;
function TItemStore.Add(Model: TItemModel): boolean;
var index, leaseIndex: integer;
begin
  Result := false;
  if not assigned(Model) or (Model.State = imsRetiring) then exit;
  if assigned(Model.FOwner) then exit(Model.FOwner = Self);
  index := Length(FModels);
  SetLength(FModels, index + 1);
  try
    if FCreationDepth > 0 then
    begin
      if not Model.Pin then
      begin
        SetLength(FModels, index);
        exit;
      end;
      try
        leaseIndex := Length(FCreationLeases);
        SetLength(FCreationLeases, leaseIndex + 1);
        FCreationLeases[leaseIndex] := Model.ItemId;
      except
        Model.Unpin;
        raise;
      end;
    end;
  except
    SetLength(FModels, index);
    raise;
  end;
  FModels[index] := Model;
  Model.FOwner := Self;
  Result := true;
end;

procedure TItemStore.BeginCreation;
begin inc(FCreationDepth); end;

procedure TItemStore.EndCreation;
var ids: TItemIds; index: integer; failed: boolean; failure: string;
begin
  if FCreationDepth <= 0 then exit;
  dec(FCreationDepth);
  if FCreationDepth <> 0 then exit;
  ids := FCreationLeases;
  FCreationLeases := nil;
  failed := false;
  failure := '';
  for index := 0 to High(ids) do
    try ReleaseItemModel(ids[index]);
    except on E: Exception do
      if not failed then
      begin
        failed := true;
        failure := E.Message;
      end;
    end;
  if failed then raise Exception.Create(failure);
end;
function TItemStore.Find(Id: TItemId): TItemModel;
var index: integer;
begin
  Result := nil;
  for index := 0 to High(FModels) do
    if FModels[index].ItemId = Id then exit(FModels[index]);
end;
function TItemStore.Contains(Id: TItemId): boolean;
begin Result := Find(Id) <> nil; end;
function TItemStore.Snapshot: TItemIds;
var index: integer;
begin
  SetLength(Result, Count);
  for index := 0 to High(Result) do Result[index] := FModels[index].ItemId;
end;
procedure TItemStore.Retire(Id: TItemId);
var model: TItemModel;
begin
  model := Find(Id);
  if assigned(model) then model.Free;
end;
procedure TItemStore.Clear;
var ids: TItemIds; index: integer; failure: string;
begin
  ids := Snapshot;
  failure := '';
  for index := 0 to High(ids) do
    try Retire(ids[index]);
    except on E: Exception do
      if failure = '' then failure := E.Message;
    end;
  if failure <> '' then raise Exception.Create(failure);
end;
end.
