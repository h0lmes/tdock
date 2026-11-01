unit pluginhosttests;

{$mode delphi}

interface

uses Windows, Messages, Classes, SysUtils, Controls, fpcunit, testregistry, declu, customitemu,
  plgitemu, itemmgru, pluginhostu, itemhostu, itemregistryu, itemmodelu, DockH,
  itemviewu, dockstateu;

type
  TFixturePlugin = class(TPluginItem)
  protected
    function OpenPluginLibrary(const Filename: string): THandle; override;
    procedure DestroyPluginData; override;
    function CopyPluginImage(Image: Pointer; AutoDelete: boolean;
      var ImageWidth, ImageHeight: UINT): Pointer; override;
    procedure ReleasePluginImage(Image: Pointer); override;
  public
    ClearOnDraw: boolean;
    procedure Draw(Ax, Ay, ASize: integer; AForce: boolean; wpi: HDWP; AShowItem: UINT); override;
    procedure SetCreationArguments(const Ini, Section: string);
    function AuxiliaryWindow: HWND;
    function PluginData: Pointer;
    procedure ViewDestroyed; override;
    procedure InstallScopeCallbacks;
    procedure InstallClearCallbacks;
    procedure PrepareVisibleHint;
  end;

  TFixtureItemManager = class(TItemManager)
  protected
    function CreatePluginItem(var Params: TDItemCreateParams): TCustomItem; override;
  end;

  TPluginHostTests = class(TTestCase)
  private
    Host: TPluginHost;
    Manager: TItemManager;
    ParentWindow: HWND;
    InitialDirectory: string;
    Site: TBaseSite;
    Offset: integer;
    ServiceTrace: string;
    MouseLockState: TDockState;
    procedure TrackMouseLock(wnd: HWND; Locked: boolean);
    procedure ReleaseRemovedView(const Identity: TItemIdentity);
    procedure CheckNativeLossMouseLock(UseSavedWindow: boolean);
    function ServiceVisible: boolean;
    procedure ServiceExecute(id: HWND; const exename, params, dir: string; showcmd: integer);
    function ServiceMenu(ParentMenu: THandle): THandle;
    procedure ServiceNotify(message: WideString; silent: boolean);
    procedure ServiceActivateHint(id: THandle; caption: WideString; x, y: integer);
    procedure ServiceDeactivateHint(id: THandle);
    procedure ServiceLock(id: HWND; locked: boolean);
    procedure ServiceAddProgram(data: string);
    procedure ServiceExclude(id: HWND);
    function GetSite: TBaseSite;
    procedure SetSite(value: TBaseSite);
    function GetOffset: integer;
    procedure SetOffset(value: integer);
    function NewPlugin: TFixturePlugin;
    procedure EnterOperation;
    procedure LeaveOperation;
    procedure BindScopeProbe;
    procedure FailHostEntryAfterClear;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ConvertsEverySdkEdgeOnce;
    procedure RejectsForeignWindowObject;
    procedure PendingPluginCanQueryHostDuringCreate;
    procedure UnboundHostReturnsEmptyValues;
    procedure ArgumentCopyPreservesGuardBytes;
    procedure LoadingRestoresCurrentDirectory;
    procedure DestroyFailureStillReleasesWindowsAndImages;
    procedure SourceOwnershipAndHostCopiesRemainSeparate;
    procedure AlignChangesUseSettingsCallback;
    procedure RejectsWorkerThreadSettingsChanges;
    procedure RoutesHostServicesSynchronously;
    procedure AlignInputCannotOverflow;
    procedure CreateCallbackReceivesBoundedArguments;
    procedure FailedImageCopyPreservesExistingHostImage;
    procedure CreateFailureClosesCallbackScope;
    procedure SaveFailureClosesCallbackScope;
    procedure MessageFailureClosesCallbackScope;
    procedure DestroyFailureClosesCallbackScope;
    procedure DirectSaveKeepsItemAliveUntilCallbackReturns;
    procedure DirectMessageFailureReleasesDeferredItem;
    procedure PendingCreateFailureReleasesDeferredItem;
    procedure DirectSaveFailureKeepsErrorContextAndReleasesItem;
    procedure HostCaptionKeepsItemAliveDuringHintCallback;
    procedure HostImageKeepsItemAliveDuringRedraw;
    procedure HostOverlayKeepsItemAliveDuringRedraw;
    procedure FactoryCreateRetainsAdoptedItemAfterCallbackClear;
    procedure FactoryCreateFailureReleasesAdoptedItemOnce;
    procedure EnabledLoadRejectsCreationSnapshot;
    procedure DirectConfigureKeepsItemAliveUntilCallbackReturns;
    procedure DirectClickKeepsItemAliveUntilCallbackReturns;
    procedure StableApiSeparatesIdsFromNativeWindows;
    procedure StableApiRetainsAllIdBits;
    procedure StableApiRejectsForeignAndStaleIds;
    procedure LegacyDeleteHidesAndDisablesWindowUntilUndo;
    procedure VersionedSdkWrappersAllowLegacyHosts;
    procedure VersionedCaptionUsesBoundedUtf16Buffer;
    procedure VersionedDeleteReportsRejectedManagerMutation;
    procedure NativePluginTimerSurvivesLegacyUndo;
    procedure PluginWindowRecreationRejectsIdentityChange;
    procedure CallbackEntryFailurePreservesOriginalError;
    procedure ModalOperationsRequireBoundUiThread;
    procedure DestroyCallbackCannotReacquireRetiredMouseLock;
    procedure NativeMouseLockArgumentsRemainCompatible;
    procedure NativeRemovalCallbackCanRetireModel;
    procedure DestroyedSubclassCannotResolveLegacyWindow;
    procedure StableWindowLookupRejectsReplacedNativeContext;
    procedure TimerSnapshotSurvivesSubclassWindowLoss;
    procedure NativeLossRejectsZeroDestroyMouseLock;
    procedure NativeLossRejectsSavedDestroyMouseLock;
    procedure ContextLossRejectsDeferredDestroyMouseLock;
  end;

function OnCreate(id: HWND; Instance: THandle; Ini, Section: PChar): Pointer; stdcall;
procedure ActivateHint(id: HWND; Caption: PWideChar; x, y: integer); stdcall;
function ProbeItemInsertV1(Id: TDockItemId): TDockItemId; stdcall;
function ProbeItemFromWindowV1(Window: HWND): TDockItemId; stdcall;

implementation

uses sepitemu;

var callbackHost: TPluginHost;
  creationRegistered, failDestroy, failImageCopy: boolean;
  creationStableRegistered: boolean;
  releasedImages: TStringList;
  destroyCalls: integer;
  creationIni, creationSection: string;
  scopeDepth, scopeEntered, scopeLeft, observedScopeDepth: integer;
  failScopedCreate: boolean;
  callbackManager: TItemManager;
  callbackWindow: HWND;
  callbackItemAlive: boolean;
  destructionScopeDepth: integer;
  deleteScopedCreate: boolean;
  callbackDestructionDeferred: boolean;
  failClearSave: boolean;
  adoptAndClearOnCreate: boolean;
  saveDuringCreateStage: string;
  saveDuringCreateRejected: boolean;
  wrapperWindow: HWND;
  timerWindow: HWND;
  lockFromDestroy: boolean;
  viewDestroyedCalls: integer;
  subclassPrevious: Pointer;
  destroyLockWindow: HWND;
  destroyLockWindowValid: boolean;

type
  PEdgeRequest = ^TEdgeRequest;
  TEdgeRequest = record
    Host: TPluginHost;
    Result: integer;
  end;
  PUiRequest = ^TUiRequest;
  TUiRequest = record
    Host: TPluginHost;
    Allowed: boolean;
  end;

function ChangeEdgeFromWorker(Parameter: Pointer): PtrInt;
begin
  PEdgeRequest(Parameter)^.Result := PEdgeRequest(Parameter)^.Host.SetDockEdge(0);
  result := 0;
end;

function BeginUiOperationFromWorker(Parameter: Pointer): PtrInt;
var scope: TItemHostScope;
begin
  PUiRequest(Parameter)^.Allowed := PUiRequest(Parameter)^.Host.BeginUiOperation(scope);
  EndItemHostOperation(scope);
  result := 0;
end;

function ProbeItemInsertV1(Id: TDockItemId): TDockItemId; stdcall;
begin
  result := Id;
end;

function ProbeItemFromWindowV1(Window: HWND): TDockItemId; stdcall;
begin
  wrapperWindow := Window;
  result := TDockItemId(QWord($FEDCBA9876543210));
end;

function OnCreate(id: HWND; Instance: THandle; Ini, Section: PChar): Pointer; stdcall;
var item: TCustomItem;
begin
  observedScopeDepth := scopeDepth;
  if saveDuringCreateStage <> '' then
  begin
    try callbackManager.SaveTo(saveDuringCreateStage);
    except on E: Exception do saveDuringCreateRejected := true; end;
  end;
  if deleteScopedCreate and callbackHost.TryGetItem(id, item) then
  begin
    callbackDestructionDeferred := item.DeferDestruction;
    callbackItemAlive := IsWindow(id);
  end;
  if adoptAndClearOnCreate then
  begin
    callbackWindow := id;
    creationRegistered := callbackHost.TryGetItem(id, item);
    if creationRegistered then callbackManager.AdoptItem(item, false);
    callbackManager.command('clear', '');
    callbackItemAlive := IsWindow(id);
  end;
  if failScopedCreate then raise Exception.Create('Controlled scoped creation failure');
  creationStableRegistered := assigned(callbackHost) and
    callbackHost.TryGetItemById(callbackHost.ItemIdFromWindow(id), item);
  if not adoptAndClearOnCreate then
    creationRegistered := assigned(callbackHost) and callbackHost.TryGetItem(id, item);
  if Ini <> nil then creationIni := StrPas(Ini) else creationIni := '';
  if Section <> nil then creationSection := StrPas(Section) else creationSection := '';
  result := Pointer(1234);
end;

function TFixturePlugin.OpenPluginLibrary(const Filename: string): THandle;
begin
  result := GetModuleHandle(nil);
end;

function TFixtureItemManager.CreatePluginItem(var Params: TDItemCreateParams): TCustomItem;
begin
  result := TFixturePlugin.Create(ParentWindow, Params);
end;

procedure TFixturePlugin.DestroyPluginData;
begin
  observedScopeDepth := scopeDepth;
  destructionScopeDepth := scopeDepth;
  inc(destroyCalls);
  if lockFromDestroy and assigned(callbackHost) then
  begin
    if destroyLockWindow = 0 then destroyLockWindow := FHWnd;
    destroyLockWindowValid := IsWindow(destroyLockWindow);
    callbackHost.LockMouseEffect(destroyLockWindow, true);
  end;
  if failDestroy then raise Exception.Create('Controlled plugin destruction failure');
end;

function TFixturePlugin.CopyPluginImage(Image: Pointer; AutoDelete: boolean;
  var ImageWidth, ImageHeight: UINT): Pointer;
begin
  if failImageCopy then raise Exception.Create('Controlled image copy failure');
  ImageWidth := 32;
  ImageHeight := 32;
  result := nil;
  if Image = nil then exit;
  result := Pointer(PtrUInt(Image) + 1000);
  if AutoDelete then ReleasePluginImage(Image);
end;

procedure TFixturePlugin.ReleasePluginImage(Image: Pointer);
begin
  if Image <> nil then releasedImages.Add(IntToStr(PtrUInt(Image)));
end;

procedure TFixturePlugin.Draw(Ax, Ay, ASize: integer; AForce: boolean; wpi: HDWP; AShowItem: UINT);
begin
  if ClearOnDraw then
  begin
    ClearOnDraw := false;
    callbackManager.command('clear', '');
    callbackItemAlive := IsWindow(callbackWindow);
  end;
end;

procedure TFixturePlugin.PrepareVisibleHint;
begin
  FShowHint := true;
  FHideHint := false;
  FLockMouseEffect := false;
  MouseHover(true);
end;

procedure ActivateHint(id: HWND; Caption: PWideChar; x, y: integer); stdcall;
begin
  callbackManager.command('clear', '');
  callbackItemAlive := IsWindow(id);
end;

procedure TFixturePlugin.SetCreationArguments(const Ini, Section: string);
begin
  FIniFile := Ini;
  FIniSection := Section;
end;

function TFixturePlugin.AuxiliaryWindow: HWND;
begin
  result := hwnd2;
end;

function TFixturePlugin.PluginData: Pointer;
begin
  result := lpData;
end;

procedure TFixturePlugin.ViewDestroyed;
begin
  inc(viewDestroyedCalls);
  inherited;
end;

procedure FailScopedSave(Data: Pointer; Ini, Section: PChar; ForExport: boolean); stdcall;
begin
  observedScopeDepth := scopeDepth;
  raise Exception.Create('Controlled scoped save failure');
end;

procedure FailScopedMessage(Data: Pointer; Window: HWND; Message: UINT;
  WParam: WPARAM; LParam: LPARAM); stdcall;
begin
  observedScopeDepth := scopeDepth;
  raise Exception.Create('Controlled scoped message failure');
end;

procedure TFixturePlugin.InstallScopeCallbacks;
begin
  OnSave := FailScopedSave;
  OnWndMessage := FailScopedMessage;
end;

procedure ClearFromSave(Data: Pointer; Ini, Section: PChar; ForExport: boolean); stdcall;
begin
  callbackManager.command('clear', '');
  callbackItemAlive := IsWindow(callbackWindow);
  if failClearSave then raise Exception.Create('Controlled save failure after clear');
end;

procedure ClearFromMessage(Data: Pointer; Window: HWND; Message: UINT;
  WParam: WPARAM; LParam: LPARAM); stdcall;
begin
  callbackManager.command('clear', '');
  callbackItemAlive := IsWindow(Window);
  raise Exception.Create('Controlled message failure after clear');
end;

procedure TFixturePlugin.InstallClearCallbacks;
begin
  OnSave := ClearFromSave;
  OnWndMessage := ClearFromMessage;
end;

procedure ClearFromConfigure(Data: Pointer); stdcall;
begin
  observedScopeDepth := scopeDepth;
  callbackManager.command('clear', '');
  callbackItemAlive := IsWindow(callbackWindow);
end;

function ClearFromClick(Data: Pointer; Point: PPoint; Size: PSize): boolean; stdcall;
begin
  ClearFromConfigure(Data);
  result := true;
end;

procedure TPluginHostTests.SetUp;
var font: TDFontData;
begin
  InitialDirectory := GetCurrentDir;
  ParentWindow := CreateWindowEx(0, 'STATIC', nil, WS_POPUP, 0, 0, 1, 1, 0, 0, hInstance, nil);
  font := Default(TDFontData);
  Manager := TFixtureItemManager.Create(ParentWindow, nil,
    32, 32, 4, 100, 0, false, false,
    0, 0, 0, 255, false, false, false, false,
    false, false, false, false, 0, -1, false, font);
  Host := TPluginHost.Create;
  Host.Bind(Manager);
  Host.OnGetSite := GetSite;
  Host.OnSetSite := SetSite;
  Host.OnGetCenterOffset := GetOffset;
  Host.OnSetCenterOffset := SetOffset;
  callbackHost := Host;
  releasedImages := TStringList.Create;
  failDestroy := false;
  failImageCopy := false;
  destroyCalls := 0;
  creationRegistered := false;
  creationStableRegistered := false;
  lockFromDestroy := false;
  destroyLockWindow := 0;
  destroyLockWindowValid := false;
  viewDestroyedCalls := 0;
  MouseLockState := nil;
  Site := bsBottom;
  Offset := 50;
  scopeDepth := 0;
  scopeEntered := 0;
  scopeLeft := 0;
  observedScopeDepth := -1;
  failScopedCreate := false;
  callbackManager := Manager;
  callbackWindow := 0;
  callbackItemAlive := false;
  destructionScopeDepth := -1;
  deleteScopedCreate := false;
  callbackDestructionDeferred := false;
  failClearSave := false;
  adoptAndClearOnCreate := false;
  saveDuringCreateStage := '';
  saveDuringCreateRejected := false;
end;

procedure TPluginHostTests.TearDown;
begin
  callbackHost := nil;
  UnbindItemHost(ParentWindow);
  Host.Unbind;
  Manager.Free;
  Host.Free;
  DestroyWindow(ParentWindow);
  releasedImages.Free;
  SetCurrentDir(InitialDirectory);
end;

function TPluginHostTests.GetSite: TBaseSite;
begin
  result := Site;
end;

procedure TPluginHostTests.SetSite(value: TBaseSite);
begin
  Site := value;
end;

function TPluginHostTests.GetOffset: integer;
begin
  result := Offset;
end;

procedure TPluginHostTests.SetOffset(value: integer);
begin
  if value < 0 then value := 0;
  if value > 100 then value := 100;
  Offset := value;
end;

function TPluginHostTests.NewPlugin: TFixturePlugin;
var params: TDItemCreateParams;
begin
  params := Default(TDItemCreateParams);
  params.ItemSize := 32;
  params.BigItemSize := 32;
  params.Parameter := TPluginItem.Make(ExtractFilePath(ParamStr(0)) + 'fixtures\fixture.dll');
  result := TFixturePlugin.Create(ParentWindow, params);
end;

procedure TPluginHostTests.ConvertsEverySdkEdgeOnce;
const expected: array[0..3] of TBaseSite = (bsBottom, bsTop, bsLeft, bsRight);
var edge: integer;
begin
  for edge := 0 to 3 do
  begin
    AssertEquals('SDK edge round-trip', edge, Host.SetDockEdge(edge));
    AssertEquals('Internal edge conversion', Ord(expected[edge]), Ord(Site));
  end;
end;

procedure TPluginHostTests.RejectsForeignWindowObject;
var params: TDItemCreateParams; foreign: TSeparatorItem;
begin
  params := Default(TDItemCreateParams);
  params.ItemSize := 32;
  params.BigItemSize := 32;
  foreign := TSeparatorItem.Create(0, params);
  try
    foreign.Caption := 'Foreign object';
    AssertEquals('A different owner cannot enter this plugin host', '', Host.GetCaption(foreign.Handle));
  finally
    foreign.Free;
  end;
end;

procedure TPluginHostTests.PendingPluginCanQueryHostDuringCreate;
var item: TFixturePlugin;
begin
  item := NewPlugin;
  try
    item.CallCreate;
    AssertTrue('OnCreate must find its pending item', creationRegistered);
    AssertTrue('OnCreate must resolve the stable pending identity', creationStableRegistered);
    AssertEquals(0, Manager.ItemCount);
  finally
    item.Free;
  end;
end;

procedure TPluginHostTests.UnboundHostReturnsEmptyValues;
var r: Windows.TRect; item: TCustomItem;
begin
  Host.Unbind;
  AssertFalse(Host.TryGetItem(ParentWindow, item));
  AssertTrue(item = nil);
  AssertFalse(Host.GetItemRect(ParentWindow, r));
  AssertEquals(0, r.Right);
  AssertEquals('', Host.GetCaption(ParentWindow));
end;

procedure TPluginHostTests.ArgumentCopyPreservesGuardBytes;
var buffer: array[0..1023] of char;
begin
  FillChar(buffer, SizeOf(buffer), Ord('#'));
  CopyPluginArgument(StringOfChar('x', 512), @buffer, 261);
  AssertEquals('Argument length follows destination capacity', 260, Length(StrPas(@buffer)));
  AssertEquals('The first guard byte remains unchanged', Ord('#'), Ord(buffer[261]));
end;

procedure TPluginHostTests.LoadingRestoresCurrentDirectory;
var before: string; item: TFixturePlugin;
begin
  before := GetCurrentDir;
  item := NewPlugin;
  try
    AssertEquals('Loading must restore the process directory', before, GetCurrentDir);
  finally
    item.Free;
  end;
end;

procedure TPluginHostTests.DestroyFailureStillReleasesWindowsAndImages;
var item: TFixturePlugin; wnd, auxiliary: HWND; released: boolean;
begin
  item := NewPlugin;
  wnd := item.Handle;
  auxiliary := item.AuxiliaryWindow;
  item.UpdateImage(Pointer(101), false);
  item.UpdateOverlay(Pointer(202), false);
  failDestroy := true;
  try item.Free;
  except on E: Exception do ; end;
  released := not IsWindow(wnd) and not IsWindow(auxiliary);
  if IsWindow(wnd) then
  begin
    SetWindowLongPtr(wnd, GWL_USERDATA, 0);
    DestroyWindow(wnd);
  end;
  if IsWindow(auxiliary) then DestroyWindow(auxiliary);
  AssertTrue('Plugin callback failure cannot skip native cleanup', released);
  AssertEquals(1, destroyCalls);
  AssertEquals(2, releasedImages.Count);
end;

procedure TPluginHostTests.SourceOwnershipAndHostCopiesRemainSeparate;
var item: TFixturePlugin;
begin
  item := NewPlugin;
  item.UpdateImage(Pointer(101), false);
  AssertEquals('Borrowed source remains caller-owned', 0, releasedImages.Count);
  item.UpdateImage(Pointer(202), true);
  AssertEquals('Old host copy and transferred source are released', 2, releasedImages.Count);
  AssertTrue(releasedImages.IndexOf('1101') >= 0);
  AssertTrue(releasedImages.IndexOf('202') >= 0);
  item.Free;
  AssertEquals('Final host copy is released once', 3, releasedImages.Count);
  AssertTrue(releasedImages.IndexOf('1202') >= 0);
end;

procedure TPluginHostTests.AlignChangesUseSettingsCallback;
begin
  AssertEquals(2, Host.SetDockAlign(2));
  AssertEquals(100, Offset);
  AssertEquals(0, Host.SetDockAlign(-1));
  AssertEquals(0, Offset);
end;

procedure TPluginHostTests.RejectsWorkerThreadSettingsChanges;
var request: TEdgeRequest; worker: TThreadID;
begin
  Site := bsTop;
  request.Host := Host;
  request.Result := -1;
  worker := BeginThread(ChangeEdgeFromWorker, @request);
  AssertTrue(worker <> 0);
  try
    AssertEquals(WAIT_OBJECT_0, WaitForSingleObject(worker, 5000));
    AssertEquals('A worker cannot change UI settings', Ord(bsTop), Ord(Site));
  finally
    CloseHandle(worker);
  end;
end;

function TPluginHostTests.ServiceVisible: boolean;
begin
  result := true;
end;

procedure TPluginHostTests.ServiceExecute(id: HWND; const exename, params, dir: string; showcmd: integer);
begin
  ServiceTrace := ServiceTrace + Format('execute:%d:%s:%s:%s:%d;', [id, exename, params, dir, showcmd]);
end;

function TPluginHostTests.ServiceMenu(ParentMenu: THandle): THandle;
begin
  result := ParentMenu + 1;
end;

procedure TPluginHostTests.ServiceNotify(message: WideString; silent: boolean);
begin
  ServiceTrace := ServiceTrace + 'notify:' + message + ':' + BoolToStr(silent, true) + ';';
end;

procedure TPluginHostTests.ServiceActivateHint(id: THandle; caption: WideString; x, y: integer);
begin
  ServiceTrace := ServiceTrace + Format('hint:%d:%s:%d:%d;', [id, caption, x, y]);
end;

procedure TPluginHostTests.ServiceDeactivateHint(id: THandle);
begin
  ServiceTrace := ServiceTrace + Format('unhint:%d;', [id]);
end;

procedure TPluginHostTests.ServiceLock(id: HWND; locked: boolean);
begin
  ServiceTrace := ServiceTrace + Format('lock:%d:%s;', [id, BoolToStr(locked, true)]);
end;

procedure TPluginHostTests.ServiceAddProgram(data: string);
begin
  ServiceTrace := ServiceTrace + 'program:' + data + ';';
end;

procedure TPluginHostTests.ServiceExclude(id: HWND);
begin
  ServiceTrace := ServiceTrace + Format('exclude:%d;', [id]);
end;

procedure TPluginHostTests.RoutesHostServicesSynchronously;
begin
  Host.OnVisible := ServiceVisible;
  Host.OnExecute := ServiceExecute;
  Host.OnMenu := ServiceMenu;
  Host.OnNotify := ServiceNotify;
  Host.OnActivateHint := ServiceActivateHint;
  Host.OnDeactivateHint := ServiceDeactivateHint;
  Host.OnLockMouseEffect := ServiceLock;
  Host.OnAddProgram := ServiceAddProgram;
  Host.OnExcludeFromPeek := ServiceExclude;
  ServiceTrace := '';
  AssertTrue(Host.Visible);
  AssertEquals(int64($100000001), int64(Host.AddMenu(THandle($100000000))));
  Host.Execute(7, 'tool.exe', '/test', 'C:\work', 1);
  Host.Notify('message');
  Host.ActivateHint(7, 'caption', 10, 20);
  Host.DeactivateHint(7);
  Host.LockMouseEffect(7, true);
  Host.AddProgram('program.exe');
  Host.ExcludeFromPeek(7);
  AssertEquals('Callbacks finish before their methods return',
    'execute:7:tool.exe:/test:C:\work:1;notify:message:False;hint:7:caption:10:20;' +
    'unhint:7;lock:7:True;program:program.exe;exclude:7;', ServiceTrace);
end;

procedure TPluginHostTests.AlignInputCannotOverflow;
begin
  AssertEquals('Oversized SDK alignment clamps before multiplication', 2, Host.SetDockAlign(MaxInt));
  AssertEquals(100, Offset);
end;

procedure TPluginHostTests.CreateCallbackReceivesBoundedArguments;
var item: TFixturePlugin;
begin
  item := NewPlugin;
  try
    item.SetCreationArguments(StringOfChar('i', 512), StringOfChar('s', 512));
    item.CallCreate;
    AssertEquals(260, Length(creationIni));
    AssertEquals(260, Length(creationSection));
  finally
    item.Free;
  end;
end;

procedure TPluginHostTests.FailedImageCopyPreservesExistingHostImage;
var item: TFixturePlugin; raised: boolean;
begin
  item := NewPlugin;
  try
    item.UpdateImage(Pointer(101), false);
    failImageCopy := true;
    raised := false;
    try item.UpdateImage(Pointer(202), false);
    except on E: Exception do raised := true; end;
    AssertTrue('The controlled copy failed', raised);
    AssertEquals('Failure keeps the existing host image owned', 0, releasedImages.Count);
  finally
    failImageCopy := false;
    item.Free;
  end;
  AssertEquals('The preserved image is released once', 1, releasedImages.Count);
end;

procedure TPluginHostTests.EnterOperation;
begin
  inc(scopeDepth);
  inc(scopeEntered);
end;

procedure TPluginHostTests.LeaveOperation;
begin
  dec(scopeDepth);
  inc(scopeLeft);
end;

procedure TPluginHostTests.BindScopeProbe;
var services: TItemHostServices;
begin
  services := Default(TItemHostServices);
  services.OnEnter := EnterOperation;
  services.OnLeave := LeaveOperation;
  BindItemHost(ParentWindow, services);
  scopeDepth := 0;
  scopeEntered := 0;
  scopeLeft := 0;
  observedScopeDepth := -1;
end;

procedure TPluginHostTests.CreateFailureClosesCallbackScope;
var item: TFixturePlugin; raised: boolean;
begin
  item := NewPlugin;
  BindScopeProbe;
  failScopedCreate := true;
  try
    raised := false;
    try item.CallCreate;
    except on E: Exception do raised := true; end;
    AssertTrue('The controlled creation callback failed', raised);
    AssertEquals('Creation callback runs inside a scope', 1, observedScopeDepth);
    AssertEquals('Failure closes the creation scope', 0, scopeDepth);
    AssertEquals(1, scopeEntered);
    AssertEquals(scopeEntered, scopeLeft);
  finally
    failScopedCreate := false;
    item.Free;
  end;
end;

procedure TPluginHostTests.SaveFailureClosesCallbackScope;
var item: TFixturePlugin; raised: boolean; fixtureIni: string;
begin
  item := NewPlugin;
  item.InstallScopeCallbacks;
  BindScopeProbe;
  fixtureIni := ExtractFilePath(ParamStr(0)) + 'scope-save.ini';
  try
    raised := false;
    try item.Save(fixtureIni, 'plugin');
    except on E: Exception do raised := true; end;
    AssertTrue('The controlled save callback failed', raised);
    AssertEquals('Save callback runs inside a scope', 1, observedScopeDepth);
    AssertEquals('Failure closes the save scope', 0, scopeDepth);
    AssertEquals(1, scopeEntered);
    AssertEquals(scopeEntered, scopeLeft);
  finally
    item.Free;
    if FileExists(fixtureIni) then DeleteFile(fixtureIni);
  end;
end;

procedure TPluginHostTests.MessageFailureClosesCallbackScope;
var item: TFixturePlugin; raised: boolean; message: TMessage;
begin
  item := NewPlugin;
  item.InstallScopeCallbacks;
  BindScopeProbe;
  message := Default(TMessage);
  message.Msg := WM_APP;
  try
    raised := false;
    try item.WndMessage(message);
    except on E: Exception do raised := true; end;
    AssertTrue('The controlled message callback failed', raised);
    AssertEquals('Message callback runs inside a scope', 1, observedScopeDepth);
    AssertEquals('Failure closes the message scope', 0, scopeDepth);
    AssertEquals(1, scopeEntered);
    AssertEquals(scopeEntered, scopeLeft);
  finally
    item.Free;
  end;
end;

procedure TPluginHostTests.DestroyFailureClosesCallbackScope;
var item: TFixturePlugin; raised: boolean;
begin
  item := NewPlugin;
  BindScopeProbe;
  failDestroy := true;
  raised := false;
  try item.Free;
  except on E: Exception do raised := true; end;
  AssertTrue('The controlled destruction callback failed', raised);
  AssertEquals('Destruction callback runs inside a scope', 1, observedScopeDepth);
  AssertEquals('Failure closes the destruction scope', 0, scopeDepth);
  AssertTrue('Destruction enters its callback scope', scopeEntered >= 1);
  AssertEquals(scopeEntered, scopeLeft);
end;

procedure TPluginHostTests.DirectSaveKeepsItemAliveUntilCallbackReturns;
var item: TFixturePlugin; fixtureIni: string;
begin
  Manager.Enable(true);
  item := NewPlugin;
  callbackWindow := Manager.AdoptItem(item, false);
  AssertTrue(callbackWindow <> 0);
  item.InstallClearCallbacks;
  BindScopeProbe;
  fixtureIni := ExtractFilePath(ParamStr(0)) + 'pin-save.ini';
  try
    item.Save(fixtureIni, 'plugin');
    AssertTrue('Clear must retain the executing save callback', callbackItemAlive);
    AssertFalse('The final pin releases the deleted item', IsWindow(callbackWindow));
    AssertEquals('Deferred cleanup occurs once', 1, destroyCalls);
    AssertTrue('Deferred cleanup keeps the application scope', destructionScopeDepth > 0);
    AssertEquals(0, scopeDepth);
    AssertEquals(scopeEntered, scopeLeft);
  finally
    if FileExists(fixtureIni) then DeleteFile(fixtureIni);
  end;
end;

procedure TPluginHostTests.DirectMessageFailureReleasesDeferredItem;
var item: TFixturePlugin; message: TMessage; raised: boolean;
begin
  Manager.Enable(true);
  item := NewPlugin;
  callbackWindow := Manager.AdoptItem(item, false);
  AssertTrue(callbackWindow <> 0);
  item.InstallClearCallbacks;
  BindScopeProbe;
  message := Default(TMessage);
  message.Msg := WM_APP;
  raised := false;
  try item.WndMessage(message);
  except on E: Exception do raised := true; end;
  AssertTrue('The controlled message callback failed', raised);
  AssertTrue('Clear must retain the executing message callback', callbackItemAlive);
  AssertFalse('Failure still releases the final item pin', IsWindow(callbackWindow));
  AssertEquals('Deferred cleanup occurs once', 1, destroyCalls);
  AssertTrue('Deferred cleanup keeps the application scope', destructionScopeDepth > 0);
  AssertEquals(0, scopeDepth);
  AssertEquals(scopeEntered, scopeLeft);
end;

procedure TPluginHostTests.PendingCreateFailureReleasesDeferredItem;
var item: TFixturePlugin; raised: boolean;
begin
  item := NewPlugin;
  callbackWindow := item.Handle;
  BindScopeProbe;
  deleteScopedCreate := true;
  failScopedCreate := true;
  raised := false;
  try item.CallCreate;
  except on E: Exception do raised := true; end;
  AssertTrue('The controlled creation callback failed', raised);
  AssertTrue('Pending creation keeps a registry pin', callbackDestructionDeferred);
  AssertTrue('Pending item survives the active creation callback', callbackItemAlive);
  AssertFalse('Failure releases the final pending item pin', IsWindow(callbackWindow));
  AssertEquals('Deferred cleanup occurs once', 1, destroyCalls);
  AssertTrue('Deferred cleanup keeps the application scope', destructionScopeDepth > 0);
  AssertEquals(0, scopeDepth);
  AssertEquals(scopeEntered, scopeLeft);
end;

procedure TPluginHostTests.DirectSaveFailureKeepsErrorContextAndReleasesItem;
var item: TFixturePlugin; fixtureIni, failureMessage: string;
begin
  Manager.Enable(true);
  item := NewPlugin;
  callbackWindow := Manager.AdoptItem(item, false);
  AssertTrue(callbackWindow <> 0);
  item.InstallClearCallbacks;
  BindScopeProbe;
  failClearSave := true;
  fixtureIni := ExtractFilePath(ParamStr(0)) + 'pin-failed-save.ini';
  failureMessage := '';
  try
    try item.Save(fixtureIni, 'plugin');
    except on E: Exception do failureMessage := E.Message; end;
    AssertTrue('Failure preserves plugin context', Pos('fixture.dll', failureMessage) > 0);
    AssertTrue('Clear retains the failing save callback', callbackItemAlive);
    AssertFalse('Failure releases the final save pin', IsWindow(callbackWindow));
    AssertEquals('Deferred cleanup occurs once', 1, destroyCalls);
    AssertTrue('Deferred cleanup keeps the application scope', destructionScopeDepth > 0);
    AssertEquals(0, scopeDepth);
    AssertEquals(scopeEntered, scopeLeft);
  finally
    if FileExists(fixtureIni) then DeleteFile(fixtureIni);
  end;
end;

procedure TPluginHostTests.HostCaptionKeepsItemAliveDuringHintCallback;
var item: TFixturePlugin; captionLength: integer;
begin
  Manager.Enable(true);
  item := NewPlugin;
  callbackWindow := Manager.AdoptItem(item, false);
  AssertTrue(callbackWindow <> 0);
  item.PrepareVisibleHint;
  BindScopeProbe;
  captionLength := Host.SetCaption(callbackWindow, 'caption');
  AssertTrue('Hint callback retains the item', callbackItemAlive);
  AssertEquals('The host reads caption before final destruction', 7, captionLength);
  AssertFalse('Host caption scope releases deferred item', IsWindow(callbackWindow));
  AssertEquals(1, destroyCalls);
  AssertTrue(destructionScopeDepth > 0);
  AssertEquals(0, scopeDepth);
  AssertEquals(scopeEntered, scopeLeft);
end;

procedure TPluginHostTests.HostImageKeepsItemAliveDuringRedraw;
var item: TFixturePlugin;
begin
  Manager.Enable(true);
  item := NewPlugin;
  callbackWindow := Manager.AdoptItem(item, false);
  AssertTrue(callbackWindow <> 0);
  BindScopeProbe;
  item.ClearOnDraw := true;
  Host.SetImage(callbackWindow, Pointer(1), false);
  AssertTrue('Image redraw retains the item', callbackItemAlive);
  AssertFalse('Host image scope releases deferred item', IsWindow(callbackWindow));
  AssertEquals(1, destroyCalls);
  AssertEquals('Owned image copy is released once', 1, releasedImages.Count);
  AssertTrue(destructionScopeDepth > 0);
  AssertEquals(0, scopeDepth);
  AssertEquals(scopeEntered, scopeLeft);
end;

procedure TPluginHostTests.HostOverlayKeepsItemAliveDuringRedraw;
var item: TFixturePlugin;
begin
  Manager.Enable(true);
  item := NewPlugin;
  callbackWindow := Manager.AdoptItem(item, false);
  AssertTrue(callbackWindow <> 0);
  BindScopeProbe;
  item.ClearOnDraw := true;
  Host.SetOverlay(callbackWindow, Pointer(1), false);
  AssertTrue('Overlay redraw retains the item', callbackItemAlive);
  AssertFalse('Host overlay scope releases deferred item', IsWindow(callbackWindow));
  AssertEquals(1, destroyCalls);
  AssertEquals('Owned overlay copy is released once', 1, releasedImages.Count);
  AssertTrue(destructionScopeDepth > 0);
  AssertEquals(0, scopeDepth);
  AssertEquals(scopeEntered, scopeLeft);
end;

procedure TPluginHostTests.FactoryCreateRetainsAdoptedItemAfterCallbackClear;
var wnd: HWND;
begin
  Manager.Enable(true);
  BindScopeProbe;
  adoptAndClearOnCreate := true;
  wnd := Manager.CreateItemFromString(TPluginItem.Make(
    ExtractFilePath(ParamStr(0)) + 'fixtures\fixture.dll'));
  AssertTrue('Creation callback can access the pending item', creationRegistered);
  AssertTrue('Clear retains the executing factory callback', callbackItemAlive);
  AssertEquals('Cleared creation cannot return a dead handle', int64(0), int64(wnd));
  AssertFalse('Factory release destroys the cleared item', IsWindow(callbackWindow));
  AssertEquals('Factory and plugin release only one object', 1, destroyCalls);
  AssertEquals(0, Manager.ItemCount);
  AssertEquals(0, scopeDepth);
  AssertEquals(scopeEntered, scopeLeft);
end;

procedure TPluginHostTests.FactoryCreateFailureReleasesAdoptedItemOnce;
var raised: boolean;
begin
  Manager.Enable(true);
  BindScopeProbe;
  adoptAndClearOnCreate := true;
  failScopedCreate := true;
  raised := false;
  try
    Manager.CreateItemFromString(TPluginItem.Make(
      ExtractFilePath(ParamStr(0)) + 'fixtures\fixture.dll'));
  except on E: Exception do raised := true; end;
  AssertTrue('Factory preserves creation failure', raised);
  AssertTrue('Clear retains the failing factory callback', callbackItemAlive);
  AssertFalse('Factory failure destroys the cleared item', IsWindow(callbackWindow));
  AssertEquals('Failed factory releases the object once', 1, destroyCalls);
  AssertEquals(0, Manager.ItemCount);
  AssertEquals(0, scopeDepth);
  AssertEquals(scopeEntered, scopeLeft);
end;

procedure TPluginHostTests.EnabledLoadRejectsCreationSnapshot;
var source, stage: string;
begin
  Manager.Enable(true);
  BindScopeProbe;
  source := ExtractFilePath(ParamStr(0)) + 'pin-load.ini';
  stage := ExtractFilePath(ParamStr(0)) + 'pin-load-stage.ini';
  WritePrivateProfileString('item1', 'class', 'plugin', PChar(source));
  WritePrivateProfileString('item1', 'file', 'fixtures\fixture.dll', PChar(source));
  saveDuringCreateStage := stage;
  try
    Manager.Load(source);
    AssertTrue('Enabled Load rejects its incomplete item snapshot', saveDuringCreateRejected);
    AssertFalse('Rejected Load snapshot creates no stage file', FileExists(stage));
    AssertEquals(1, Manager.ItemCount);
    AssertTrue(DeleteFile(source));
    Manager.Save('');
    AssertTrue('Rejected snapshot preserves the loaded source path', FileExists(source));
    AssertFalse('Canonical save cannot switch to the rejected stage', FileExists(stage));
    AssertEquals(0, scopeDepth);
    AssertEquals(scopeEntered, scopeLeft);
  finally
    saveDuringCreateStage := '';
    if FileExists(source) then DeleteFile(source);
    if FileExists(stage) then DeleteFile(stage);
  end;
end;

procedure TPluginHostTests.DirectConfigureKeepsItemAliveUntilCallbackReturns;
var item: TFixturePlugin;
begin
  Manager.Enable(true);
  item := NewPlugin;
  callbackWindow := Manager.AdoptItem(item, false);
  item.OnConfigure := ClearFromConfigure;
  BindScopeProbe;
  item.Configure;
  AssertTrue('Configure retains its model during clear', callbackItemAlive);
  AssertTrue('Configure retains an application operation', observedScopeDepth > 0);
  AssertFalse('Configure releases its final lease', IsWindow(callbackWindow));
  AssertEquals('Configure destroys once', 1, destroyCalls);
  AssertEquals(0, scopeDepth);
  AssertEquals(scopeEntered, scopeLeft);
end;

procedure TPluginHostTests.DirectClickKeepsItemAliveUntilCallbackReturns;
var item: TFixturePlugin;
begin
  Manager.Enable(true);
  item := NewPlugin;
  callbackWindow := Manager.AdoptItem(item, false);
  item.OnLeftButtonClick := ClearFromClick;
  BindScopeProbe;
  item.MouseClick(mbLeft, [], 0, 0);
  AssertTrue('Click retains its model during clear', callbackItemAlive);
  AssertTrue('Click retains an application operation', observedScopeDepth > 0);
  AssertFalse('Click releases its final lease', IsWindow(callbackWindow));
  AssertEquals('Click destroys once', 1, destroyCalls);
  AssertEquals(0, scopeDepth);
  AssertEquals(scopeEntered, scopeLeft);
end;

procedure TPluginHostTests.StableApiSeparatesIdsFromNativeWindows;
var id: TItemId; wnd: HWND; item: TCustomItem; caption: WideString;
begin
  Manager.Enable(true);
  id := Host.CreateItemId('class="separator";');
  AssertTrue('Creation returns a stable identity', id <> NO_ITEM_ID);
  wnd := Host.WindowFromItemId(id);
  AssertTrue('Creation keeps a real native window', IsWindow(wnd));
  AssertTrue('An item identity differs from its native window', QWord(id) <> QWord(wnd));
  AssertFalse('Native window bits cannot identify a model',
    Host.GetCaptionById(TItemId(QWord(wnd)), caption));
  AssertEquals('Window lookup returns the complete identity', QWord(id), QWord(Host.ItemIdFromWindow(wnd)));
  AssertTrue('Pending creation belongs to its host', Host.TryGetItemById(id, item));
  AssertEquals('Creation does not insert the pending item', 0, Manager.ItemCount);
  AssertTrue('Pending caption mutation succeeds', Host.SetCaptionById(id, 'stable caption'));
  AssertTrue('Pending caption lookup succeeds', Host.GetCaptionById(id, caption));
  AssertEquals('stable caption', string(caption));
  AssertEquals('Legacy lookup reaches the same model', 'stable caption', Host.GetCaption(wnd));
  AssertEquals('Insertion preserves identity', QWord(id), QWord(Host.InsertItemId(id)));
  AssertEquals('Insertion occurs once', 1, Manager.ItemCount);
end;

procedure TPluginHostTests.StableApiRetainsAllIdBits;
var id, highId: TItemId; caption: WideString;
begin
  AssertEquals('The plugin identity occupies eight bytes', 8, SizeOf(TItemId));
  id := Host.CreateItemId('class="separator";');
  AssertTrue('Creation returns a stable identity', id <> NO_ITEM_ID);
  highId := TItemId(QWord(id) or QWord($8000000000000000));
  AssertFalse('High bits cannot alias a live identity', Host.SetCaptionById(highId, 'aliased'));
  AssertTrue('The original identity remains live', Host.GetCaptionById(id, caption));
  AssertEquals('High-bit rejection preserves the live caption', '', string(caption));
  AssertEquals('A foreign high-bit identity has no window', QWord(0), QWord(Host.WindowFromItemId(highId)));
end;

procedure TPluginHostTests.StableApiRejectsForeignAndStaleIds;
var id, stale: TItemId; params: TDItemCreateParams; foreign: TSeparatorItem;
  caption: WideString; item: TCustomItem;
begin
  params := Default(TDItemCreateParams);
  params.ItemSize := 32;
  params.BigItemSize := 32;
  foreign := TSeparatorItem.Create(0, params);
  try
    id := foreign.ItemId;
    AssertFalse('A foreign identity cannot enter this host', Host.TryGetItemById(id, item));
    AssertFalse('A foreign caption cannot change', Host.SetCaptionById(id, 'foreign'));
    AssertEquals(QWord(0), QWord(Host.WindowFromItemId(id)));
    AssertEquals(QWord(0), QWord(Host.ItemIdFromWindow(foreign.Handle)));
  finally
    foreign.Free;
  end;
  Manager.Enable(true);
  stale := Host.CreateItemId('class="separator";');
  AssertTrue(stale <> NO_ITEM_ID);
  Host.InsertItemId(stale);
  Manager.command('clear', '');
  AssertFalse('A retired identity cannot resolve', Host.TryGetItemById(stale, item));
  AssertFalse('A retired caption cannot resolve', Host.GetCaptionById(stale, caption));
  AssertFalse('A retired identity cannot delete another item', Host.DeleteItemId(stale));
  AssertEquals(QWord(0), QWord(Host.InsertItemId(stale)));
end;

procedure TPluginHostTests.LegacyDeleteHidesAndDisablesWindowUntilUndo;
var item: TFixturePlugin; wnd: HWND; id: TItemId;
begin
  Manager.Enable(true);
  item := NewPlugin;
  wnd := Manager.AdoptItem(item, false);
  id := item.ItemId;
  ShowWindow(wnd, SW_SHOWNOACTIVATE);
  EnableWindow(wnd, true);
  Host.DeleteItem(wnd);
  AssertTrue('Undo retains the plugin native window', IsWindow(wnd));
  AssertFalse('Deleted plugin windows are hidden', IsWindowVisible(wnd));
  AssertFalse('Deleted plugin windows are disabled', IsWindowEnabled(wnd));
  AssertEquals('Deleted item APIs reject the identity', QWord(0), QWord(Host.WindowFromItemId(id)));
  Manager.UnDelete;
  AssertEquals('Undo preserves the model identity', QWord(id), QWord(Host.ItemIdFromWindow(wnd)));
  AssertEquals('Undo preserves the native window', QWord(wnd), QWord(Host.WindowFromItemId(id)));
  AssertTrue('Undo enables the native window', IsWindowEnabled(wnd));
end;

procedure TPluginHostTests.VersionedSdkWrappersAllowLegacyHosts;
const highId: TDockItemId = TDockItemId(QWord($FEDCBA9876543210));
var buffer: array[0..1] of WideChar;
begin
  AssertEquals('SDK identities occupy eight bytes', 8, SizeOf(TDockItemId));
  AssertEquals('This fixture omits the version export', 0, TDockApiVersion);
  AssertEquals(QWord(0), QWord(TDockItemCreateV1(nil)));
  AssertEquals('The dynamic insert wrapper preserves all identity bits',
    QWord(highId), QWord(TDockItemInsertV1(highId)));
  AssertFalse(TDockItemDeleteV1(highId));
  AssertEquals(QWord(0), QWord(TDockItemGetWindowV1(highId)));
  AssertEquals('The dynamic conversion wrapper preserves all identity bits',
    QWord(highId), QWord(TDockItemFromWindowV1(HWND($100000007))));
  AssertEquals('The dynamic conversion wrapper preserves native pointer width',
    QWord($100000007), QWord(wrapperWindow));
  buffer[0] := 'x';
  AssertEquals(0, TDockItemGetCaptionV1(highId, @buffer[0], Length(buffer)));
  AssertEquals('Unavailable APIs preserve caller buffers', Ord('x'), Ord(buffer[0]));
  AssertFalse(TDockItemSetCaptionV1(highId, nil));
  AssertFalse(TDockItemSetImageV1(highId, nil, false));
  AssertFalse(TDockItemSetOverlayV1(highId, nil, false));
  AssertFalse(TDockItemDockV1(highId));
  AssertFalse(TDockItemUndockV1(highId));
  AssertFalse(TDockItemAnimateV1(highId));
end;

procedure TPluginHostTests.VersionedCaptionUsesBoundedUtf16Buffer;
var item: TFixturePlugin; buffer: array[0..4] of WideChar;
  id: TItemId; caption: WideString;
begin
  item := NewPlugin;
  try
    id := item.ItemId;
    caption := WideString('A') + WideChar($0416) + WideChar($03A9);
    item.Caption := caption;
    AssertEquals('The required capacity includes the final zero', 4,
      Host.CopyCaptionById(id, nil, 0));
    buffer[0] := 'L';
    buffer[1] := 'x';
    buffer[4] := 'R';
    AssertEquals(4, Host.CopyCaptionById(id, @buffer[1], 0));
    AssertEquals('Zero capacity preserves the destination', Ord('x'), Ord(buffer[1]));
    AssertEquals(4, Host.CopyCaptionById(id, @buffer[1], 3));
    AssertEquals('UTF-16 characters remain intact', Ord($0416), Ord(buffer[2]));
    AssertEquals('A short buffer receives a final zero', 0, Ord(buffer[3]));
    AssertEquals('The left guard remains intact', Ord('L'), Ord(buffer[0]));
    AssertEquals('The right guard remains intact', Ord('R'), Ord(buffer[4]));
    item.Caption := '';
    AssertEquals('An empty caption requires one code unit', 1, Host.CopyCaptionById(id, nil, 0));
    AssertEquals('Invalid IDs require no capacity', 0, Host.CopyCaptionById(NO_ITEM_ID, nil, 0));
  finally
    item.Free;
  end;
end;

procedure TPluginHostTests.VersionedDeleteReportsRejectedManagerMutation;
var item, resolved: TCustomItem;
begin
  item := NewPlugin;
  try
    AssertFalse('A disabled manager rejects deletion', Host.DeleteItemId(item.ItemId));
    AssertTrue('Rejected deletion retains the pending model', Host.TryGetItemById(item.ItemId, resolved));
    AssertEquals(Ord(imsPending), Ord(item.State));
  finally
    item.Free;
  end;
end;

procedure ObserveNativeTimer(Data: Pointer; Window: HWND; Message: UINT;
  WParam: WPARAM; LParam: LPARAM); stdcall;
begin
  if (Message = WM_TIMER) and (WParam = $C0DE) then timerWindow := Window;
end;

procedure TPluginHostTests.NativePluginTimerSurvivesLegacyUndo;
var item: TFixturePlugin; wnd: HWND; message: TMsg; deadline: QWord;
begin
  Manager.Enable(true);
  item := NewPlugin;
  wnd := Manager.AdoptItem(item, false);
  item.OnWndMessage := ObserveNativeTimer;
  timerWindow := 0;
  AssertTrue('A plugin receives a real native timer', SetTimer(wnd, $C0DE, 10, nil) <> 0);
  try
    Host.DeleteItem(wnd);
    Manager.UnDelete;
    deadline := GetTickCount64 + 1000;
    repeat
      while PeekMessage(message, wnd, WM_TIMER, WM_TIMER, PM_REMOVE) do
        DispatchMessage(message);
      if timerWindow <> 0 then break;
      Windows.Sleep(5);
    until GetTickCount64 >= deadline;
    AssertEquals('Undo preserves native timer delivery', QWord(wnd), QWord(timerWindow));
  finally
    KillTimer(wnd, $C0DE);
  end;
end;

procedure TPluginHostTests.PluginWindowRecreationRejectsIdentityChange;
var item: TFixturePlugin; wnd: HWND; id: TItemId; data: Pointer; rejected: boolean;
begin
  item := NewPlugin;
  try
    item.CallCreate;
    wnd := item.Handle;
    id := item.ItemId;
    data := item.PluginData;
    rejected := false;
    try item.RecreateWindow;
    except on E: Exception do rejected := true; end;
    AssertTrue('Plugin recreation rejects native identity changes', rejected);
    AssertTrue('Rejection keeps the real native window', IsWindow(wnd));
    AssertEquals(QWord(wnd), QWord(item.Handle));
    AssertEquals(QWord(id), QWord(item.ItemId));
    AssertEquals('Rejection keeps plugin callback data', PtrUInt(data), PtrUInt(item.PluginData));
  finally
    item.Free;
  end;
end;

procedure TPluginHostTests.FailHostEntryAfterClear;
begin
  UnbindItemHost(ParentWindow);
  Manager.command('clear', '');
  raise Exception.Create('Controlled host entry failure');
end;

procedure TPluginHostTests.CallbackEntryFailurePreservesOriginalError;
var item: TFixturePlugin; services: TItemHostServices; failure: string;
begin
  Manager.Enable(true);
  item := NewPlugin;
  callbackWindow := Manager.AdoptItem(item, false);
  services := Default(TItemHostServices);
  services.OnEnter := FailHostEntryAfterClear;
  services.OnLeave := LeaveOperation;
  BindItemHost(ParentWindow, services);
  failDestroy := true;
  failure := '';
  try
    try item.Configure;
    except on E: Exception do failure := E.Message; end;
  finally
    failDestroy := false;
  end;
  AssertTrue('Lease cleanup preserves the host entry error',
    Pos('Controlled host entry failure', failure) > 0);
  AssertFalse('Failed entry releases the retained native window', IsWindow(callbackWindow));
  AssertEquals('Failed entry destroys the model once', 1, destroyCalls);
end;

procedure TPluginHostTests.ModalOperationsRequireBoundUiThread;
var scope: TItemHostScope; request: TUiRequest; worker: TThreadID;
begin
  BindScopeProbe;
  AssertTrue('Bound UI operations enter the host scope', Host.BeginUiOperation(scope));
  AssertEquals(1, scopeDepth);
  EndItemHostOperation(scope);
  AssertEquals(0, scopeDepth);
  request.Host := Host;
  request.Allowed := true;
  worker := BeginThread(BeginUiOperationFromWorker, @request);
  AssertTrue(worker <> 0);
  try
    AssertEquals(WAIT_OBJECT_0, WaitForSingleObject(worker, 5000));
    AssertFalse('Worker threads cannot open modal host operations', request.Allowed);
    AssertEquals('Worker calls leave host scopes untouched', 1, scopeEntered);
  finally
    CloseHandle(worker);
  end;
  Host.Unbind;
  AssertFalse('Unbound calls cannot open modal host operations', Host.BeginUiOperation(scope));
  AssertFalse(scope.Active);
  AssertEquals(scopeEntered, scopeLeft);
end;

procedure TPluginHostTests.TrackMouseLock(wnd: HWND; Locked: boolean);
var id: TItemId;
begin
  if Locked then id := ItemViews.AcquireMouseLock(wnd)
  else id := ItemViews.ReleaseMouseLock(wnd);
  if id <> NO_ITEM_ID then MouseLockState.SetMouseEffectLock(id, Locked);
end;

procedure TPluginHostTests.DestroyCallbackCannotReacquireRetiredMouseLock;
var item: TFixturePlugin;
begin
  MouseLockState := TDockState.Create;
  Host.OnLockMouseEffect := TrackMouseLock;
  Manager.OnItemRemoved := MouseLockState.ReleaseItemLocks;
  item := NewPlugin;
  try
    Host.LockMouseEffect(item.Handle, true);
    AssertTrue('The live plugin can acquire a mouse lock', MouseLockState.MouseEffectLocked);
    lockFromDestroy := true;
    item.Free;
    item := nil;
    AssertFalse('Destroy callbacks cannot restore retired item locks', MouseLockState.MouseEffectLocked);
    AssertEquals('The retired plugin is destroyed once', 1, destroyCalls);
  finally
    lockFromDestroy := false;
    item.Free;
    Manager.OnItemRemoved := nil;
    Host.OnLockMouseEffect := nil;
    FreeAndNil(MouseLockState);
  end;
end;

procedure TPluginHostTests.NativeMouseLockArgumentsRemainCompatible;
begin
  MouseLockState := TDockState.Create;
  Host.OnLockMouseEffect := TrackMouseLock;
  try
    Host.LockMouseEffect(ParentWindow, true);
    Host.LockMouseEffect(ParentWindow, true);
    AssertTrue('An arbitrary native HWND can acquire nested locks', MouseLockState.MouseEffectLocked);
    Host.LockMouseEffect(ParentWindow, false);
    AssertTrue('The first release preserves the nested native lock', MouseLockState.MouseEffectLocked);
    Host.LockMouseEffect(ParentWindow, false);
    AssertFalse('The final native release clears the lock', MouseLockState.MouseEffectLocked);
  finally
    Host.OnLockMouseEffect := nil;
    FreeAndNil(MouseLockState);
  end;
end;

procedure TPluginHostTests.ReleaseRemovedView(const Identity: TItemIdentity);
var model: TItemModel;
begin
  model := FindItemModel(Identity.ItemId);
  if assigned(model) then model.Free;
end;

procedure TPluginHostTests.NativeRemovalCallbackCanRetireModel;
var item: TFixturePlugin; wnd: HWND; id: TItemId; failed: boolean;
begin
  item := NewPlugin;
  wnd := item.Handle;
  id := item.ItemId;
  ItemViews.SetOwner(ItemViews.IdentityOf(wnd), ReleaseRemovedView);
  failed := false;
  try
    try ItemViews.NativeDestroyed(wnd);
    except on E: Exception do failed := true; end;
    AssertFalse('Native removal cannot call a released model', failed);
    AssertEquals('A retired model receives no stale view callback', 0, viewDestroyedCalls);
    AssertTrue('The removal callback retires its model', FindItemModel(id) = nil);
    AssertEquals('The removal callback destroys the model once', 1, destroyCalls);
  finally
    if FindItemModel(id) <> nil then FindItemModel(id).Free;
    if IsWindow(wnd) then Windows.DestroyWindow(wnd);
  end;
end;

function SwallowNativeDestroy(wnd: HWND; Message: UINT; WParam: WPARAM;
  LParam: LPARAM): LRESULT; stdcall;
begin
  if Message = WM_NCDESTROY then exit(0);
  result := Windows.CallWindowProc(subclassPrevious, wnd, Message, WParam, LParam);
end;

procedure TPluginHostTests.DestroyedSubclassCannotResolveLegacyWindow;
var item, found: TCustomItem; wnd: HWND; id: TItemId; identity: TItemIdentity;
  borrowed: TObject; pinned: boolean;
begin
  item := NewPlugin;
  wnd := item.Handle;
  id := item.ItemId;
  identity := ItemViews.IdentityOf(wnd);
  subclassPrevious := Pointer(Windows.SetWindowLongPtr(wnd, GWL_WNDPROC,
    PtrInt(@SwallowNativeDestroy)));
  AssertTrue('The legacy plugin installs a native subclass', subclassPrevious <> nil);
  try
    AssertTrue(Windows.DestroyWindow(wnd));
    AssertFalse('The subclassed native window was destroyed', IsWindow(wnd));
    AssertFalse('A destroyed subclass cannot resolve its old HWND', Host.TryGetItem(wnd, found));
    AssertFalse('Native lookup rejects stale attached contexts', ItemViews.TryGetAny(wnd, borrowed));
    AssertEquals(QWord(NO_ITEM_ID), QWord(ItemViews.ItemIdOf(wnd)));
    AssertEquals(QWord(0), QWord(ItemViews.HandleOf(id)));
    pinned := ItemViews.Pin(identity);
    if pinned then ItemViews.Unpin(identity);
    AssertFalse('A stale native generation cannot acquire a model lease', pinned);
  finally
    if FindItemModel(id) <> nil then FindItemModel(id).Free;
    if IsWindow(wnd) then
    begin
      Windows.SetWindowLongPtr(wnd, GWL_WNDPROC, PtrInt(subclassPrevious));
      Windows.DestroyWindow(wnd);
    end;
  end;
end;

procedure TPluginHostTests.StableWindowLookupRejectsReplacedNativeContext;
var item: TFixturePlugin; wnd: HWND; id: TItemId;
begin
  item := NewPlugin;
  wnd := item.Handle;
  id := item.ItemId;
  Windows.SetWindowLongPtr(wnd, GWL_USERDATA, $5A5A);
  try
    AssertEquals('Stable lookup rejects a replaced native certificate',
      QWord(0), QWord(Host.WindowFromItemId(id)));
    AssertTrue('Invalidation preserves the foreign native window', IsWindow(wnd));
    AssertEquals('Invalidation preserves foreign window data', PtrInt($5A5A),
      Windows.GetWindowLongPtr(wnd, GWL_USERDATA));
    AssertTrue('Invalidation retires the previous model', FindItemModel(id) = nil);
    AssertEquals('Invalidation destroys the previous model once', 1, destroyCalls);
  finally
    if FindItemModel(id) <> nil then FindItemModel(id).Free;
    if IsWindow(wnd) then
    begin
      Windows.SetWindowLongPtr(wnd, GWL_USERDATA, 0);
      Windows.DestroyWindow(wnd);
    end;
  end;
end;

procedure TPluginHostTests.TimerSnapshotSurvivesSubclassWindowLoss;
var first: TFixturePlugin; wnd: HWND; id: TItemId; failed: boolean;
begin
  Manager.Enable(true);
  first := NewPlugin;
  wnd := Manager.AdoptItem(first, false);
  id := first.ItemId;
  AssertTrue(Manager.AdoptItem(NewPlugin, false) <> 0);
  subclassPrevious := Pointer(Windows.SetWindowLongPtr(wnd, GWL_WNDPROC,
    PtrInt(@SwallowNativeDestroy)));
  try
    AssertTrue(Windows.DestroyWindow(wnd));
    failed := false;
    try Manager.Timer;
    except on E: Exception do failed := true; end;
    AssertFalse('Stale view retirement cannot invalidate timer snapshot indices', failed);
    AssertEquals('The second plugin keeps active membership', 1, Manager.ItemCount);
    AssertTrue('The stale plugin retires during snapshot resolution', FindItemModel(id) = nil);
  finally
    if FindItemModel(id) <> nil then FindItemModel(id).Free;
    if IsWindow(wnd) then
    begin
      Windows.SetWindowLongPtr(wnd, GWL_WNDPROC, PtrInt(subclassPrevious));
      Windows.DestroyWindow(wnd);
    end;
  end;
end;

procedure TPluginHostTests.CheckNativeLossMouseLock(UseSavedWindow: boolean);
var item: TFixturePlugin; wnd: HWND; id: TItemId;
begin
  MouseLockState := TDockState.Create;
  Host.OnLockMouseEffect := TrackMouseLock;
  Manager.OnItemRemoved := MouseLockState.ReleaseItemLocks;
  item := NewPlugin;
  wnd := item.Handle;
  id := item.ItemId;
  try
    Host.LockMouseEffect(wnd, true);
    AssertTrue(MouseLockState.MouseEffectLocked);
    if UseSavedWindow then destroyLockWindow := wnd;
    lockFromDestroy := true;
    AssertTrue(Windows.DestroyWindow(wnd));
    AssertFalse('Native loss cannot retain a new lock (native valid=' +
      BoolToStr(destroyLockWindowValid, true) + ')', MouseLockState.MouseEffectLocked);
    AssertTrue(FindItemModel(id) = nil);
    AssertEquals(1, destroyCalls);
  finally
    lockFromDestroy := false;
    destroyLockWindow := 0;
    if FindItemModel(id) <> nil then FindItemModel(id).Free;
    Manager.OnItemRemoved := nil;
    Host.OnLockMouseEffect := nil;
    FreeAndNil(MouseLockState);
    if IsWindow(wnd) then Windows.DestroyWindow(wnd);
  end;
end;

procedure TPluginHostTests.NativeLossRejectsZeroDestroyMouseLock;
begin
  CheckNativeLossMouseLock(false);
end;

procedure TPluginHostTests.NativeLossRejectsSavedDestroyMouseLock;
begin
  CheckNativeLossMouseLock(true);
end;

procedure TPluginHostTests.ContextLossRejectsDeferredDestroyMouseLock;
var item: TFixturePlugin; wnd: HWND; id: TItemId;
begin
  MouseLockState := TDockState.Create;
  Host.OnLockMouseEffect := TrackMouseLock;
  Manager.OnItemRemoved := MouseLockState.ReleaseItemLocks;
  item := NewPlugin;
  wnd := item.Handle;
  id := item.ItemId;
  try
    Host.LockMouseEffect(wnd, true);
    lockFromDestroy := true;
    destroyLockWindow := wnd;
    Windows.SetWindowLongPtr(wnd, GWL_USERDATA, $6B6B);
    AssertEquals(QWord(0), QWord(Host.WindowFromItemId(id)));
    AssertFalse('Deferred destruction cannot reacquire the invalidated item window',
      MouseLockState.MouseEffectLocked);
    AssertTrue('The detached foreign window remains live', IsWindow(wnd));
    AssertTrue(FindItemModel(id) = nil);
  finally
    lockFromDestroy := false;
    destroyLockWindow := 0;
    if FindItemModel(id) <> nil then FindItemModel(id).Free;
    Manager.OnItemRemoved := nil;
    Host.OnLockMouseEffect := nil;
    FreeAndNil(MouseLockState);
    if IsWindow(wnd) then
    begin
      Windows.SetWindowLongPtr(wnd, GWL_USERDATA, 0);
      Windows.DestroyWindow(wnd);
    end;
  end;
end;

initialization
  RegisterTest(TPluginHostTests);
end.
