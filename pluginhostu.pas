unit pluginhostu;

{$mode delphi}

interface

uses Windows, SysUtils, declu, customitemu, itemmgru, itemmodelu, itemhostu;

type
  TPluginVisible = function: boolean of object;
  TPluginGetSite = function: TBaseSite of object;
  TPluginSetSite = procedure(site: TBaseSite) of object;
  TPluginGetOffset = function: integer of object;
  TPluginSetOffset = procedure(value: integer) of object;
  TPluginExecute = procedure(id: HWND; const exename, params, dir: string;
    showcmd: integer) of object;
  TPluginMenu = function(ParentMenu: THandle): THandle of object;
  TPluginNotify = procedure(message: WideString; silent: boolean) of object;
  TPluginActivateHint = procedure(id: THandle; caption: WideString; x, y: integer) of object;
  TPluginDeactivateHint = procedure(id: THandle) of object;
  TPluginLockMouseEffect = procedure(id: HWND; locked: boolean) of object;
  TPluginAddProgram = procedure(data: string) of object;
  TPluginExcludeFromPeek = procedure(id: HWND) of object;
  TPluginError = procedure(where: string; E: Exception) of object;

  TPluginHost = class
  private
    FManager: TItemManager;
    FThreadId: DWORD;
    function IsBound: boolean;
  public
    OnVisible: TPluginVisible;
    OnGetSite: TPluginGetSite;
    OnSetSite: TPluginSetSite;
    OnGetCenterOffset: TPluginGetOffset;
    OnSetCenterOffset: TPluginSetOffset;
    OnExecute: TPluginExecute;
    OnMenu: TPluginMenu;
    OnNotify: TPluginNotify;
    OnActivateHint: TPluginActivateHint;
    OnDeactivateHint: TPluginDeactivateHint;
    OnLockMouseEffect: TPluginLockMouseEffect;
    OnAddProgram: TPluginAddProgram;
    OnExcludeFromPeek: TPluginExcludeFromPeek;
    OnError: TPluginError;
    procedure Bind(Manager: TItemManager);
    procedure Unbind;
    function BeginUiOperation(out Scope: TItemHostScope): boolean;
    function TryGetItem(wnd: HWND; out Item: TCustomItem): boolean;
    function TryGetItemById(Id: TItemId; out Item: TCustomItem): boolean;
    function ItemIdFromWindow(wnd: HWND): TItemId;
    function WindowFromItemId(Id: TItemId): HWND;
    function CreateItemId(const Data: string): TItemId;
    function InsertItemId(Id: TItemId): TItemId;
    function DeleteItemId(Id: TItemId): boolean;
    function GetCaptionById(Id: TItemId; out Caption: WideString): boolean;
    function CopyCaptionById(Id: TItemId; Buffer: PWideChar; Capacity: Cardinal): Cardinal;
    function SetCaptionById(Id: TItemId; const Caption: WideString): boolean;
    function SetImageById(Id: TItemId; Image: Pointer; AutoDelete: boolean): boolean;
    function SetOverlayById(Id: TItemId; Image: Pointer; AutoDelete: boolean): boolean;
    function AnimateById(Id: TItemId): boolean;
    function DockById(Id: TItemId): boolean;
    function UndockById(Id: TItemId): boolean;
    function Visible: boolean;
    function IsUndocked(wnd: HWND): boolean;
    function GetItemRect(wnd: HWND; out r: Windows.TRect): boolean;
    function GetCaption(wnd: HWND): string;
    function SetCaption(wnd: HWND; const Caption: WideString): integer;
    function GetFile(wnd: HWND): string;
    procedure SetImage(wnd: HWND; Image: Pointer; AutoDelete: boolean);
    procedure SetOverlay(wnd: HWND; Image: Pointer; AutoDelete: boolean);
    procedure Animate(wnd: HWND);
    function QueryDockEdge: integer;
    function SetDockEdge(Edge: integer): integer;
    function QueryDockAlign: integer;
    function SetDockAlign(Offset: integer): integer;
    function DockRect: Windows.TRect;
    function RootFolder: string;
    function RelativeFolder(wnd: HWND): string;
    procedure Execute(id: HWND; const exename, params, dir: string; showcmd: integer);
    function AddMenu(ParentMenu: THandle): THandle;
    procedure Undock(wnd: HWND);
    procedure Dock(wnd: HWND);
    function CreateItem(const Data: string): HWND;
    procedure DeleteItem(wnd: HWND);
    procedure AddProgram(const Data: string);
    procedure Notify(const message: WideString);
    procedure ActivateHint(id: THandle; const Caption: WideString; x, y: integer);
    procedure DeactivateHint(id: THandle);
    procedure LockMouseEffect(id: HWND; Locked: boolean);
    procedure ExcludeFromPeek(id: HWND);
    procedure ReportError(const where: string; E: Exception);
  end;

var PluginHost: TPluginHost;

implementation

uses Classes, DockH, plgitemu, toolu, itemviewu, loggeru;

type
  TPluginMutationScope = record
    HostScope: TItemHostScope;
    ItemId: TItemId;
    Pinned: boolean;
  end;

procedure EndPluginMutation(var Scope: TPluginMutationScope);
begin
  try
    if Scope.Pinned then
    begin
      Scope.Pinned := false;
      try ReleaseItemModel(Scope.ItemId);
      except on E: Exception do
        try AddLog('PluginHost.DeferredDestroy' + LineEnding + E.Message); except end;
      end;
    end;
  finally
    EndItemHostOperation(Scope.HostScope);
  end;
end;

function BeginPluginMutationById(Host: TPluginHost; Id: TItemId; out Item: TCustomItem;
  out Scope: TPluginMutationScope): boolean;
var model: TItemModel;
begin
  result := false;
  Scope := Default(TPluginMutationScope);
  if not Host.TryGetItemById(Id, Item) then exit;
  Scope.ItemId := Id;
  Scope.Pinned := AcquireItemModel(Id, model);
  if not Scope.Pinned then exit;
  try
    Scope.HostScope := BeginItemHostOperation(Host.FManager.ParentWindow);
    result := true;
  except
    EndPluginMutation(Scope);
    raise;
  end;
end;

function BeginPluginMutation(Host: TPluginHost; wnd: HWND; out Item: TCustomItem;
  out Scope: TPluginMutationScope): boolean;
begin
  Item := nil;
  Scope := Default(TPluginMutationScope);
  if not Host.IsBound then exit(false);
  result := BeginPluginMutationById(Host, ItemViews.ItemIdOf(wnd), Item, Scope);
end;

function TPluginHost.TryGetItemById(Id: TItemId; out Item: TCustomItem): boolean;
begin
  Item := nil;
  result := false;
  if not IsBound or (Id = NO_ITEM_ID) then exit;
  if not FManager.TryGetItemById(Id, Item) then exit;
  result := (Item.State in [imsPending, imsActive, imsDragging]) and not Item.Freed;
  if not result then Item := nil;
end;

function TPluginHost.ItemIdFromWindow(wnd: HWND): TItemId;
var item: TCustomItem; scope: TPluginMutationScope;
begin
  result := NO_ITEM_ID;
  if not BeginPluginMutation(self, wnd, item, scope) then exit;
  try result := item.ItemId;
  finally EndPluginMutation(scope); end;
end;

function TPluginHost.WindowFromItemId(Id: TItemId): HWND;
var item: TCustomItem; scope: TPluginMutationScope;
begin
  result := 0;
  if not BeginPluginMutationById(self, Id, item, scope) then exit;
  try result := ItemViews.HandleOf(Id);
  finally EndPluginMutation(scope); end;
end;

function TPluginHost.CreateItemId(const Data: string): TItemId;
begin
  result := NO_ITEM_ID;
  if IsBound then result := FManager.CreateItemId(Data);
end;

function TPluginHost.InsertItemId(Id: TItemId): TItemId;
var item: TCustomItem; scope: TPluginMutationScope;
begin
  result := NO_ITEM_ID;
  if not BeginPluginMutationById(self, Id, item, scope) then exit;
  try result := FManager.InsertItemById(Id);
  finally EndPluginMutation(scope); end;
end;

function TPluginHost.DeleteItemId(Id: TItemId): boolean;
var item: TCustomItem; scope: TPluginMutationScope;
begin
  result := false;
  if not BeginPluginMutationById(self, Id, item, scope) then exit;
  try
    FManager.DeleteItemById(Id);
    result := item.State in [imsDeleted, imsRetiring];
  finally EndPluginMutation(scope); end;
end;

function TPluginHost.GetCaptionById(Id: TItemId; out Caption: WideString): boolean;
var item: TCustomItem; scope: TPluginMutationScope;
begin
  Caption := '';
  result := false;
  if not BeginPluginMutationById(self, Id, item, scope) then exit;
  try
    Caption := item.Caption;
    result := true;
  finally EndPluginMutation(scope); end;
end;

function TPluginHost.CopyCaptionById(Id: TItemId; Buffer: PWideChar; Capacity: Cardinal): Cardinal;
var caption: WideString; count: Cardinal;
begin
  result := 0;
  if not GetCaptionById(Id, caption) then exit;
  if QWord(Length(caption)) >= High(Cardinal) then exit;
  result := Cardinal(Length(caption)) + 1;
  if (Buffer = nil) or (Capacity = 0) then exit;
  count := result - 1;
  if count >= Capacity then count := Capacity - 1;
  if count > 0 then Move(PWideChar(caption)^, Buffer^, SizeUInt(count) * SizeOf(WideChar));
  Buffer[count] := #0;
end;

function TPluginHost.SetCaptionById(Id: TItemId; const Caption: WideString): boolean;
var item: TCustomItem; scope: TPluginMutationScope;
begin
  result := false;
  if not BeginPluginMutationById(self, Id, item, scope) then exit;
  try
    item.Caption := Caption;
    result := true;
  finally EndPluginMutation(scope); end;
end;

function TPluginHost.SetImageById(Id: TItemId; Image: Pointer; AutoDelete: boolean): boolean;
var item: TCustomItem; scope: TPluginMutationScope;
begin
  result := false;
  if not BeginPluginMutationById(self, Id, item, scope) then exit;
  try
    if item is TPluginItem then
    begin
      TPluginItem(item).UpdateImage(Image, AutoDelete);
      result := true;
    end;
  finally EndPluginMutation(scope); end;
end;

function TPluginHost.SetOverlayById(Id: TItemId; Image: Pointer; AutoDelete: boolean): boolean;
var item: TCustomItem; scope: TPluginMutationScope;
begin
  result := false;
  if not BeginPluginMutationById(self, Id, item, scope) then exit;
  try
    if item is TPluginItem then
    begin
      TPluginItem(item).UpdateOverlay(Image, AutoDelete);
      result := true;
    end;
  finally EndPluginMutation(scope); end;
end;

function TPluginHost.AnimateById(Id: TItemId): boolean;
var item: TCustomItem; scope: TPluginMutationScope;
begin
  result := false;
  if not BeginPluginMutationById(self, Id, item, scope) then exit;
  try
    FManager.PluginAnimateById(Id);
    result := true;
  finally EndPluginMutation(scope); end;
end;

function TPluginHost.DockById(Id: TItemId): boolean;
var item: TCustomItem; scope: TPluginMutationScope;
begin
  result := false;
  if not BeginPluginMutationById(self, Id, item, scope) then exit;
  try
    FManager.DockItemById(Id);
    result := true;
  finally EndPluginMutation(scope); end;
end;

function TPluginHost.UndockById(Id: TItemId): boolean;
var item: TCustomItem; scope: TPluginMutationScope;
begin
  result := false;
  if not BeginPluginMutationById(self, Id, item, scope) then exit;
  try
    FManager.UndockItemById(Id);
    result := true;
  finally EndPluginMutation(scope); end;
end;

procedure TPluginHost.Bind(Manager: TItemManager);
begin
  // Bind and unbind on the UI thread. Other threads receive empty results.
  FManager := Manager;
  FThreadId := GetCurrentThreadId;
end;

procedure TPluginHost.Unbind;
begin
  FManager := nil;
  FThreadId := 0;
end;

function TPluginHost.BeginUiOperation(out Scope: TItemHostScope): boolean;
begin
  Scope := Default(TItemHostScope);
  result := false;
  if not IsBound then exit;
  Scope := BeginItemHostOperation(FManager.ParentWindow);
  result := true;
end;

function TPluginHost.IsBound: boolean;
begin
  result := assigned(FManager) and (GetCurrentThreadId = FThreadId);
end;

function TPluginHost.TryGetItem(wnd: HWND; out Item: TCustomItem): boolean;
begin
  Item := nil;
  if not IsBound then exit(false);
  result := TryGetItemById(ItemViews.ItemIdOf(wnd), Item);
end;

function TPluginHost.Visible: boolean;
begin
  result := IsBound;
  if result then
    if assigned(OnVisible) then result := OnVisible()
    else result := FManager.Visible;
end;

function TPluginHost.IsUndocked(wnd: HWND): boolean;
var item: TCustomItem; scope: TPluginMutationScope;
begin
  result := false;
  if not BeginPluginMutation(self, wnd, item, scope) then exit;
  try result := item.Undocked;
  finally EndPluginMutation(scope); end;
end;

function TPluginHost.GetItemRect(wnd: HWND; out r: Windows.TRect): boolean;
var item: TCustomItem; scope: TPluginMutationScope;
begin
  r := Classes.Rect(0, 0, 0, 0);
  result := false;
  if not BeginPluginMutation(self, wnd, item, scope) then exit;
  try
    r := item.ScreenRect;
    result := FManager.Visible;
  finally EndPluginMutation(scope); end;
end;

function TPluginHost.GetCaption(wnd: HWND): string;
var caption: WideString;
begin
  result := '';
  if not IsBound then exit;
  if GetCaptionById(ItemViews.ItemIdOf(wnd), caption) then result := caption;
end;

function TPluginHost.SetCaption(wnd: HWND; const Caption: WideString): integer;
var item: TCustomItem; scope: TPluginMutationScope;
begin
  result := 0;
  if not BeginPluginMutation(self, wnd, item, scope) then exit;
  try
    item.Caption := Caption;
    result := Length(item.Caption);
  finally
    EndPluginMutation(scope);
  end;
end;

function TPluginHost.GetFile(wnd: HWND): string;
var item: TCustomItem; scope: TPluginMutationScope;
begin
  result := '';
  if not BeginPluginMutation(self, wnd, item, scope) then exit;
  try
    if item is TPluginItem then result := TPluginItem(item).Filename;
  finally EndPluginMutation(scope); end;
end;

procedure TPluginHost.SetImage(wnd: HWND; Image: Pointer; AutoDelete: boolean);
var item: TCustomItem; scope: TPluginMutationScope;
begin
  if not BeginPluginMutation(self, wnd, item, scope) then exit;
  try
    if item is TPluginItem then TPluginItem(item).UpdateImage(Image, AutoDelete);
  finally
    EndPluginMutation(scope);
  end;
end;

procedure TPluginHost.SetOverlay(wnd: HWND; Image: Pointer; AutoDelete: boolean);
var item: TCustomItem; scope: TPluginMutationScope;
begin
  if not BeginPluginMutation(self, wnd, item, scope) then exit;
  try
    if item is TPluginItem then TPluginItem(item).UpdateOverlay(Image, AutoDelete);
  finally
    EndPluginMutation(scope);
  end;
end;

procedure TPluginHost.Animate(wnd: HWND);
begin
  if IsBound then AnimateById(ItemViews.ItemIdOf(wnd));
end;

function TPluginHost.QueryDockEdge: integer;
begin
  result := 0;
  if IsBound and assigned(OnGetSite) then result := EdgeToSDK(Ord(OnGetSite()));
end;

function TPluginHost.SetDockEdge(Edge: integer): integer;
begin
  if IsBound and assigned(OnSetSite) and (Edge >= 0) and (Edge <= 3) then
    OnSetSite(TBaseSite(EdgeFromSDK(Edge)));
  result := QueryDockEdge;
end;

function TPluginHost.QueryDockAlign: integer;
begin
  result := 1;
  if IsBound and assigned(OnGetCenterOffset) then
    result := (OnGetCenterOffset() + 25) div 50;
end;

function TPluginHost.SetDockAlign(Offset: integer): integer;
begin
  if Offset < 0 then Offset := 0;
  if Offset > 2 then Offset := 2;
  if IsBound and assigned(OnSetCenterOffset) then
    OnSetCenterOffset(Offset * 50);
  result := QueryDockAlign;
end;

function TPluginHost.DockRect: Windows.TRect;
begin
  result := Classes.Rect(0, 0, 0, 0);
  if IsBound then result := FManager.Rect;
end;

function TPluginHost.RootFolder: string;
begin
  result := UnzipPath('%pp%\');
end;

function TPluginHost.RelativeFolder(wnd: HWND): string;
var filename: string;
begin
  filename := GetFile(wnd);
  result := '';
  if filename <> '' then
    result := cutafter(IncludeTrailingPathDelimiter(ExtractFilePath(filename)), RootFolder);
end;

procedure TPluginHost.Execute(id: HWND; const exename, params, dir: string; showcmd: integer);
begin
  if IsBound and assigned(OnExecute) then OnExecute(id, exename, params, dir, showcmd);
end;

function TPluginHost.AddMenu(ParentMenu: THandle): THandle;
begin
  result := 0;
  if IsBound and assigned(OnMenu) then result := OnMenu(ParentMenu);
end;

procedure TPluginHost.Undock(wnd: HWND);
begin
  if IsBound then UndockById(ItemViews.ItemIdOf(wnd));
end;

procedure TPluginHost.Dock(wnd: HWND);
begin
  if IsBound then DockById(ItemViews.ItemIdOf(wnd));
end;

function TPluginHost.CreateItem(const Data: string): HWND;
begin
  result := WindowFromItemId(CreateItemId(Data));
end;

procedure TPluginHost.DeleteItem(wnd: HWND);
begin
  if IsBound then DeleteItemId(ItemViews.ItemIdOf(wnd));
end;

procedure TPluginHost.AddProgram(const Data: string);
begin
  if IsBound and assigned(OnAddProgram) then OnAddProgram(Data);
end;

procedure TPluginHost.Notify(const message: WideString);
begin
  if IsBound and assigned(OnNotify) then OnNotify(message, false);
end;

procedure TPluginHost.ActivateHint(id: THandle; const Caption: WideString; x, y: integer);
begin
  if IsBound and assigned(OnActivateHint) then OnActivateHint(id, Caption, x, y);
end;

procedure TPluginHost.DeactivateHint(id: THandle);
begin
  if IsBound and assigned(OnDeactivateHint) then OnDeactivateHint(id);
end;

procedure TPluginHost.LockMouseEffect(id: HWND; Locked: boolean);
begin
  if IsBound and assigned(OnLockMouseEffect) then OnLockMouseEffect(id, Locked);
end;

procedure TPluginHost.ExcludeFromPeek(id: HWND);
begin
  if IsBound and assigned(OnExcludeFromPeek) then OnExcludeFromPeek(id);
end;

procedure TPluginHost.ReportError(const where: string; E: Exception);
begin
  if IsBound and assigned(OnError) then OnError(where, E);
end;

end.
