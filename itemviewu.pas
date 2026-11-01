unit itemviewu;

{$mode delphi}

interface

uses Windows, itemmodelu, docktimingu;

type
  TItemIdentity = record
    Handle: HWND;
    Token: QWord;
    ItemId: TItemId;
  end;
  TItemIdentities = array of TItemIdentity;
  TItemOwnershipEvent = procedure(const Identity: TItemIdentity) of object;

  { Owns native bindings. Model leases do not depend on those bindings. }
  TItemViewAdapter = class
  private
    type
      TContext = class
        Identity: TItemIdentity;
      end;
      TEntry = record
        Identity: TItemIdentity;
        Parent: HWND;
        Auxiliary: boolean;
        Context: TContext;
        OnUnregister: TItemOwnershipEvent;
      end;
      THost = record
        Window: HWND;
        Store: TItemStore;
      end;
      TMouseLock = record
        Window: HWND;
        Id: TItemId;
        Count: integer;
        ModelBound: boolean;
      end;
      TItemTimer = record
        Id: TItemId;
        TimerId: UINT_PTR;
        Interval: UINT;
        Deadline: TDeadline;
      end;
      TDetachedWindow = record
        Window: HWND;
        Id: TItemId;
      end;
    var FEntries: array of TEntry;
    FHosts: array of THost;
    FMouseLocks: array of TMouseLock;
    FDetachingWindows: array of TDetachedWindow;
    FTimers: array of TItemTimer;
    FNextToken: QWord;
    function IndexOf(wnd: HWND): integer;
    function IndexForId(Id: TItemId): integer;
    function ObjectAt(index: integer): TObject;
    procedure Remove(index: integer);
    function OwnsNative(index: integer): boolean;
    function ValidateNative(index: integer): boolean;
    procedure AttachNative(wnd: HWND; Auxiliary: boolean);
    procedure ForgetTimers(Id: TItemId);
  protected
    function TimerNow: QWord; virtual;
    function SetNativeTimer(Window: HWND; TimerId: UINT_PTR; Interval: UINT): UINT_PTR; virtual;
    function CreateNativeWindow(const ClassName: string; ExStyle: DWORD;
      Parent: HWND; X, Y, Size: integer): HWND; virtual;
  public
    destructor Destroy; override;
    procedure BindStore(parent: HWND; Store: TItemStore);
    procedure UnbindStore(parent: HWND; Store: TItemStore);
    procedure AdoptPending(Model: TItemModel; parent: HWND; Subitem: boolean = false);
    function CreateWindow(Model: TItemModel; parent: HWND; const ClassName: string;
      WindowProc: Pointer; ExStyle: DWORD; X, Y, Size: integer): HWND;
    function CreateAuxiliaryWindow(Model: TItemModel; const ClassName: string;
      ExStyle: DWORD): HWND;
    procedure DestroyWindow(var wnd: HWND; Id: TItemId);
    procedure NativeDestroyed(wnd: HWND);
    procedure CompleteModelCleanup(Id: TItemId);
    procedure ReparentChildren(ParentId: TItemId; NewParent: HWND);
    function SetItemTimer(Id: TItemId; TimerId: UINT_PTR; Interval: UINT): UINT_PTR;
    function KillItemTimer(Id: TItemId; TimerId: UINT_PTR): boolean;
    procedure RestoreItemTimers(Id: TItemId);
    function ConsumeItemTimer(Id: TItemId; TimerId: UINT_PTR; Now: QWord): boolean;
    procedure CancelInternalTimers(Id: TItemId);
    function ItemIdOf(wnd: HWND): TItemId;
    function HandleOf(Id: TItemId): HWND;
    function IdentityForId(Id: TItemId): TItemIdentity;
    function AcquireMouseLock(wnd: HWND): TItemId;
    function ReleaseMouseLock(wnd: HWND): TItemId;
    procedure ForgetMouseLocks(Id: TItemId);
    function RegisterItem(wnd, parent: HWND; Item: TItemModel): boolean;
    procedure UnregisterItem(wnd: HWND; Item: TObject);
    function TryGet(wnd, parent: HWND; out Item: TObject): boolean;
    function TryGetAny(wnd: HWND; out Item: TObject): boolean;
    function IdentityOf(wnd: HWND): TItemIdentity;
    function TryResolve(const Identity: TItemIdentity; parent: HWND; out Item: TObject): boolean;
    function Pin(const Identity: TItemIdentity): boolean;
    procedure Unpin(const Identity: TItemIdentity);
    procedure SetOwner(const Identity: TItemIdentity; Callback: TItemOwnershipEvent);
    procedure ClearOwner(const Identity: TItemIdentity);
  end;

function ItemViews: TItemViewAdapter;

implementation
uses SysUtils, loggeru;
var Views: TItemViewAdapter;

function TItemViewAdapter.TimerNow: QWord;
begin Result := GetTickCount64; end;

function TItemViewAdapter.SetNativeTimer(Window: HWND; TimerId: UINT_PTR; Interval: UINT): UINT_PTR;
begin Result := Windows.SetTimer(Window, TimerId, Interval, nil); end;

function ItemViews: TItemViewAdapter;
begin Result := Views; end;

function TItemViewAdapter.IndexOf(wnd: HWND): integer;
var index: integer;
begin
  Result := -1;
  if wnd = 0 then exit;
  for index := 0 to High(FEntries) do
    if FEntries[index].Identity.Handle = wnd then exit(index);
end;

function TItemViewAdapter.ObjectAt(index: integer): TObject;
begin
  Result := nil;
  if (index < 0) or (index > High(FEntries)) or FEntries[index].Auxiliary then exit;
  if not ValidateNative(index) then exit;
  Result := FindItemModel(FEntries[index].Identity.ItemId);
end;

function TItemViewAdapter.RegisterItem(wnd, parent: HWND; Item: TItemModel): boolean;
var index: integer;
begin
  Result := false;
  if (wnd = 0) or not assigned(Item) or (IndexOf(wnd) >= 0) then exit;
  if FNextToken = High(QWord) then raise EOverflow.Create('View generations are exhausted');
  index := Length(FEntries);
  SetLength(FEntries, index + 1);
  inc(FNextToken);
  FEntries[index].Identity.Handle := wnd;
  FEntries[index].Identity.Token := FNextToken;
  FEntries[index].Identity.ItemId := Item.ItemId;
  FEntries[index].Parent := parent;
  Result := true;
end;

function TItemViewAdapter.OwnsNative(index: integer): boolean;
begin
  Result := assigned(FEntries[index].Context) and IsWindow(FEntries[index].Identity.Handle) and
    (Windows.GetWindowLongPtr(FEntries[index].Identity.Handle, GWL_USERDATA) = PtrInt(FEntries[index].Context));
end;

function TItemViewAdapter.IndexForId(Id: TItemId): integer;
var index: integer;
begin
  Result := -1;
  if Id = NO_ITEM_ID then exit;
  for index := High(FEntries) downto 0 do
    if (FEntries[index].Identity.ItemId = Id) and not FEntries[index].Auxiliary then
      exit(index);
end;

function TItemViewAdapter.ValidateNative(index: integer): boolean;
begin
  Result := (index >= 0) and (index <= High(FEntries));
  if not Result then exit;
  if not assigned(FEntries[index].Context) then exit;
  Result := OwnsNative(index);
  if not Result then NativeDestroyed(FEntries[index].Identity.Handle);
end;

procedure TItemViewAdapter.Remove(index: integer);
var next: integer; identity: TItemIdentity; callback: TItemOwnershipEvent; context: TContext;
  auxiliary: boolean;
begin
  identity := FEntries[index].Identity;
  auxiliary := FEntries[index].Auxiliary;
  callback := FEntries[index].OnUnregister;
  context := FEntries[index].Context;
  if OwnsNative(index) then Windows.SetWindowLongPtr(identity.Handle, GWL_USERDATA, 0);
  for next := index to High(FEntries) - 1 do FEntries[next] := FEntries[next + 1];
  SetLength(FEntries, Length(FEntries) - 1);
  context.Free;
  if not auxiliary and (IndexForId(identity.ItemId) < 0) then ForgetTimers(identity.ItemId);
  if assigned(callback) then
    try callback(identity);
    except on E: Exception do
      try AddLog('ItemView.UnregisterOwner' + LineEnding + E.Message); except end;
    end;
end;

procedure TItemViewAdapter.UnregisterItem(wnd: HWND; Item: TObject);
var index: integer;
begin
  index := IndexOf(wnd);
  if (index >= 0) and (ObjectAt(index) = Item) then Remove(index);
end;

function TItemViewAdapter.TryGetAny(wnd: HWND; out Item: TObject): boolean;
begin Item := ObjectAt(IndexOf(wnd)); Result := assigned(Item); end;

function TItemViewAdapter.TryGet(wnd, parent: HWND; out Item: TObject): boolean;
var index: integer;
begin
  Item := nil;
  index := IndexOf(wnd);
  if index >= 0 then
    if FEntries[index].Parent = parent then Item := ObjectAt(index);
  Result := assigned(Item);
end;

function TItemViewAdapter.IdentityOf(wnd: HWND): TItemIdentity;
var index: integer;
begin
  Result := Default(TItemIdentity);
  index := IndexOf(wnd);
  if (index >= 0) and not FEntries[index].Auxiliary and ValidateNative(index) then
    Result := FEntries[index].Identity;
end;

function TItemViewAdapter.TryResolve(const Identity: TItemIdentity; parent: HWND; out Item: TObject): boolean;
var current: TItemIdentity;
begin
  current := IdentityOf(Identity.Handle);
  Result := (Identity.Token <> 0) and (current.Token = Identity.Token) and
    (current.ItemId = Identity.ItemId) and TryGet(Identity.Handle, parent, Item);
  if not Result then Item := nil;
end;

function TItemViewAdapter.Pin(const Identity: TItemIdentity): boolean;
var index: integer; model: TItemModel;
begin
  Result := false;
  index := IndexOf(Identity.Handle);
  if (index < 0) or (Identity.Token = 0) then exit;
  if (FEntries[index].Identity.Token <> Identity.Token) or
    (FEntries[index].Identity.ItemId <> Identity.ItemId) then exit;
  if not ValidateNative(index) then exit;
  Result := AcquireItemModel(Identity.ItemId, model);
end;

procedure TItemViewAdapter.Unpin(const Identity: TItemIdentity);
begin
  try ReleaseItemModel(Identity.ItemId);
  except on E: Exception do
    try AddLog('ItemView.DeferredDestroy' + LineEnding + E.Message); except end;
  end;
end;

procedure TItemViewAdapter.SetOwner(const Identity: TItemIdentity; Callback: TItemOwnershipEvent);
var index: integer;
begin
  index := IndexOf(Identity.Handle);
  if (index >= 0) and (FEntries[index].Identity.Token = Identity.Token) then FEntries[index].OnUnregister := Callback;
end;
procedure TItemViewAdapter.ClearOwner(const Identity: TItemIdentity);
begin SetOwner(Identity, nil); end;

procedure TItemViewAdapter.BindStore(parent: HWND; Store: TItemStore);
var index: integer;
begin
  for index := 0 to High(FHosts) do
    if FHosts[index].Window = parent then begin FHosts[index].Store := Store; exit; end;
  index := Length(FHosts);
  SetLength(FHosts, index + 1);
  FHosts[index].Window := parent;
  FHosts[index].Store := Store;
end;

procedure TItemViewAdapter.UnbindStore(parent: HWND; Store: TItemStore);
var index, next: integer;
begin
  for index := 0 to High(FHosts) do
    if (FHosts[index].Window = parent) and (FHosts[index].Store = Store) then
    begin
      for next := index to High(FHosts) - 1 do FHosts[next] := FHosts[next + 1];
      SetLength(FHosts, Length(FHosts) - 1);
      exit;
    end;
end;

procedure TItemViewAdapter.AdoptPending(Model: TItemModel; parent: HWND; Subitem: boolean);
var index: integer; owner: TItemModel; store: TItemStore;
begin
  store := nil;
  if Subitem then
  begin
    owner := FindItemModel(ItemIdOf(parent));
    if assigned(owner) then begin Model.ParentItemId := owner.ItemId; store := owner.ChildStore; end;
  end
  else
    for index := 0 to High(FHosts) do
      if FHosts[index].Window = parent then begin store := FHosts[index].Store; break; end;
  if assigned(store) and not store.Add(Model) then raise Exception.Create('Cannot acquire pending item ownership');
end;

function TItemViewAdapter.CreateNativeWindow(const ClassName: string; ExStyle: DWORD;
  Parent: HWND; X, Y, Size: integer): HWND;
begin
  Result := Windows.CreateWindowEx(ExStyle, PChar(ClassName), nil, WS_POPUP, X, Y, Size, Size, Parent, 0, hInstance, nil);
end;

procedure TItemViewAdapter.AttachNative(wnd: HWND; Auxiliary: boolean);
var index: integer; context: TContext;
begin
  index := IndexOf(wnd);
  FEntries[index].Auxiliary := Auxiliary;
  context := TContext.Create;
  context.Identity := FEntries[index].Identity;
  FEntries[index].Context := context;
  Windows.SetLastError(0);
  if (Windows.SetWindowLongPtr(wnd, GWL_USERDATA, PtrInt(context)) = 0) and (Windows.GetLastError <> 0) then
    RaiseLastOSError;
end;

function TItemViewAdapter.CreateWindow(Model: TItemModel; parent: HWND; const ClassName: string;
  WindowProc: Pointer; ExStyle: DWORD; X, Y, Size: integer): HWND;
var wc: Windows.TWndClass; index: integer;
begin
  wc := Default(Windows.TWndClass);
  wc.style := CS_DBLCLKS;
  wc.lpfnWndProc := WindowProc;
  wc.hInstance := hInstance;
  wc.hCursor := LoadCursor(0, IDC_ARROW);
  wc.lpszClassName := PChar(ClassName);
  Windows.RegisterClass(wc);
  Result := CreateNativeWindow(ClassName, ExStyle, parent, X, Y, Size);
  if Result = 0 then exit;
  try
    if not RegisterItem(Result, parent, Model) then raise Exception.Create('Cannot bind item window');
    AttachNative(Result, false);
  except
    index := IndexOf(Result);
    if index >= 0 then Remove(index);
    Windows.DestroyWindow(Result);
    raise;
  end;
end;

function TItemViewAdapter.CreateAuxiliaryWindow(Model: TItemModel; const ClassName: string; ExStyle: DWORD): HWND;
var index: integer;
begin
  Result := CreateNativeWindow(ClassName, ExStyle, 0, -100, -100, 32);
  if Result = 0 then RaiseLastOSError;
  try
    if not RegisterItem(Result, 0, Model) then raise Exception.Create('Cannot bind auxiliary window');
    AttachNative(Result, true);
  except
    index := IndexOf(Result);
    if index >= 0 then Remove(index);
    Windows.DestroyWindow(Result);
    raise;
  end;
end;

procedure TItemViewAdapter.DestroyWindow(var wnd: HWND; Id: TItemId);
var native: HWND; index: integer; destroy: boolean;
begin
  native := wnd;
  wnd := 0;
  index := IndexOf(native);
  if (index < 0) or (FEntries[index].Identity.ItemId <> Id) then exit;
  destroy := OwnsNative(index);
  Remove(index);
  if destroy then Windows.DestroyWindow(native);
end;

procedure TItemViewAdapter.NativeDestroyed(wnd: HWND);
var index, detachingIndex: integer; id: TItemId; model: TItemModel; auxiliary: boolean;
begin
  index := IndexOf(wnd);
  if index < 0 then exit;
  id := FEntries[index].Identity.ItemId;
  auxiliary := FEntries[index].Auxiliary;
  detachingIndex := Length(FDetachingWindows);
  SetLength(FDetachingWindows, detachingIndex + 1);
  FDetachingWindows[detachingIndex].Window := wnd;
  FDetachingWindows[detachingIndex].Id := id;
  try
    Remove(index);
    model := FindItemModel(id);
    if assigned(model) and not auxiliary then model.ViewDestroyed;
  finally
    model := FindItemModel(id);
    if not assigned(model) or (model.State <> imsRetiring) then CompleteModelCleanup(id);
  end;
end;

procedure TItemViewAdapter.CompleteModelCleanup(Id: TItemId);
var index, next: integer;
begin
  for index := High(FDetachingWindows) downto 0 do
    if FDetachingWindows[index].Id = Id then
    begin
      for next := index to High(FDetachingWindows) - 1 do
        FDetachingWindows[next] := FDetachingWindows[next + 1];
      SetLength(FDetachingWindows, Length(FDetachingWindows) - 1);
    end;
end;

function TItemViewAdapter.ItemIdOf(wnd: HWND): TItemId;
begin Result := IdentityOf(wnd).ItemId; end;
function TItemViewAdapter.HandleOf(Id: TItemId): HWND;
begin Result := IdentityForId(Id).Handle; end;
function TItemViewAdapter.IdentityForId(Id: TItemId): TItemIdentity;
var index: integer;
begin
  Result := Default(TItemIdentity);
  index := IndexForId(Id);
  if (index >= 0) and ValidateNative(index) then Result := FEntries[index].Identity;
end;

procedure TItemViewAdapter.ReparentChildren(ParentId: TItemId; NewParent: HWND);
var index: integer; model: TItemModel;
begin
  for index := 0 to High(FEntries) do
  begin
    model := FindItemModel(FEntries[index].Identity.ItemId);
    if assigned(model) and (model.ParentItemId = ParentId) and OwnsNative(index) then
    begin
      Windows.SetLastError(0);
      if (Windows.SetWindowLongPtr(FEntries[index].Identity.Handle, GWL_HWNDPARENT, NewParent) = 0) and
        (Windows.GetLastError <> 0) then RaiseLastOSError;
      FEntries[index].Parent := NewParent;
    end;
  end;
end;

function TItemViewAdapter.SetItemTimer(Id: TItemId; TimerId: UINT_PTR; Interval: UINT): UINT_PTR;
var wnd: HWND; index: integer;
begin
  wnd := HandleOf(Id);
  result := 0;
  if wnd = 0 then exit;
  if Interval < 10 then Interval := 10;
  result := SetNativeTimer(wnd, TimerId, Interval);
  if result = 0 then exit;
  for index := 0 to High(FTimers) do
    if (FTimers[index].Id = Id) and (FTimers[index].TimerId = result) then
    begin
      FTimers[index].Interval := Interval;
      FTimers[index].Deadline.Schedule(TimerNow, Interval);
      exit;
    end;
  index := Length(FTimers);
  try SetLength(FTimers, index + 1);
  except Windows.KillTimer(wnd, result); raise; end;
  FTimers[index].Id := Id;
  FTimers[index].TimerId := result;
  FTimers[index].Interval := Interval;
  FTimers[index].Deadline.Schedule(TimerNow, Interval);
end;

function TItemViewAdapter.KillItemTimer(Id: TItemId; TimerId: UINT_PTR): boolean;
var wnd: HWND; index, next: integer;
begin
  wnd := HandleOf(Id);
  result := (wnd <> 0) and Windows.KillTimer(wnd, TimerId);
  for index := High(FTimers) downto 0 do
    if (FTimers[index].Id = Id) and (FTimers[index].TimerId = TimerId) then
    begin
      for next := index to High(FTimers) - 1 do FTimers[next] := FTimers[next + 1];
      SetLength(FTimers, Length(FTimers) - 1);
    end;
end;

procedure TItemViewAdapter.RestoreItemTimers(Id: TItemId);
var index: integer; wnd: HWND; delay: QWord;
begin
  wnd := HandleOf(Id);
  if wnd = 0 then exit;
  for index := 0 to High(FTimers) do
    if FTimers[index].Id = Id then
    begin
      delay := FTimers[index].Deadline.Remaining(TimerNow);
      if delay = 0 then delay := 1;
      if SetNativeTimer(wnd, FTimers[index].TimerId, UINT(delay)) = 0 then
        raise EOSError.Create('Cannot restore item timer');
    end;
end;

function TItemViewAdapter.ConsumeItemTimer(Id: TItemId; TimerId: UINT_PTR; Now: QWord): boolean;
var index: integer; wnd: HWND;
begin
  Result := false;
  for index := 0 to High(FTimers) do
    if (FTimers[index].Id = Id) and (FTimers[index].TimerId = TimerId) then
    begin
      if not FTimers[index].Deadline.IsDue(Now) then exit;
      wnd := HandleOf(Id);
      if wnd = 0 then exit;
      if SetNativeTimer(wnd, TimerId, FTimers[index].Interval) = 0 then
        raise EOSError.Create('Cannot renew item timer');
      FTimers[index].Deadline.Schedule(Now, FTimers[index].Interval);
      exit(true);
    end;
end;

procedure TItemViewAdapter.CancelInternalTimers(Id: TItemId);
var index: integer;
begin
  for index := High(FTimers) downto 0 do
    if FTimers[index].Id = Id then KillItemTimer(Id, FTimers[index].TimerId);
end;

procedure TItemViewAdapter.ForgetTimers(Id: TItemId);
var index, next: integer;
begin
  for index := High(FTimers) downto 0 do
    if FTimers[index].Id = Id then
    begin
      for next := index to High(FTimers) - 1 do FTimers[next] := FTimers[next + 1];
      SetLength(FTimers, Length(FTimers) - 1);
    end;
end;

function TItemViewAdapter.AcquireMouseLock(wnd: HWND): TItemId;
var index: integer; model: TItemModel;
begin
  Result := NO_ITEM_ID;
  if (wnd = 0) or not IsWindow(wnd) then exit;
  for index := 0 to High(FDetachingWindows) do
    if FDetachingWindows[index].Window = wnd then exit;
  index := IndexOf(wnd);
  if (index >= 0) and not ValidateNative(index) then exit;
  Result := ItemIdOf(wnd);
  if Result <> NO_ITEM_ID then
  begin
    model := FindItemModel(Result);
    if not assigned(model) or (model.State in [imsDeleted, imsRetiring]) then
      exit(NO_ITEM_ID);
  end;
  for index := 0 to High(FMouseLocks) do
    if ((Result <> NO_ITEM_ID) and FMouseLocks[index].ModelBound and (FMouseLocks[index].Id = Result)) or
      ((Result = NO_ITEM_ID) and not FMouseLocks[index].ModelBound and (FMouseLocks[index].Window = wnd)) then
    begin inc(FMouseLocks[index].Count); exit(FMouseLocks[index].Id); end;
  index := Length(FMouseLocks);
  SetLength(FMouseLocks, index + 1);
  FMouseLocks[index].ModelBound := Result <> NO_ITEM_ID;
  if Result = NO_ITEM_ID then Result := AllocateItemId;
  FMouseLocks[index].Window := wnd;
  FMouseLocks[index].Id := Result;
  FMouseLocks[index].Count := 1;
end;
function TItemViewAdapter.ReleaseMouseLock(wnd: HWND): TItemId;
var index, next: integer; id: TItemId;
begin
  Result := NO_ITEM_ID;
  id := ItemIdOf(wnd);
  for index := 0 to High(FMouseLocks) do
    if ((id <> NO_ITEM_ID) and FMouseLocks[index].ModelBound and (FMouseLocks[index].Id = id)) or
      ((id = NO_ITEM_ID) and not FMouseLocks[index].ModelBound and (FMouseLocks[index].Window = wnd)) then
    begin
      Result := FMouseLocks[index].Id;
      dec(FMouseLocks[index].Count);
      if FMouseLocks[index].Count = 0 then
      begin
        for next := index to High(FMouseLocks) - 1 do FMouseLocks[next] := FMouseLocks[next + 1];
        SetLength(FMouseLocks, Length(FMouseLocks) - 1);
      end;
      exit;
    end;
end;

destructor TItemViewAdapter.Destroy;
begin
  while Length(FEntries) > 0 do Remove(High(FEntries));
  inherited;
end;

procedure TItemViewAdapter.ForgetMouseLocks(Id: TItemId);
var index, next: integer;
begin
  for index := High(FMouseLocks) downto 0 do
    if FMouseLocks[index].Id = Id then
    begin
      for next := index to High(FMouseLocks) - 1 do FMouseLocks[next] := FMouseLocks[next + 1];
      SetLength(FMouseLocks, Length(FMouseLocks) - 1);
    end;
end;

initialization Views := TItemViewAdapter.Create;
finalization Views.Free;
end.
