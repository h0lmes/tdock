unit objectactivationtests;
{$mode delphi}
interface
uses Windows, SysUtils, Classes, ActiveX, ComObj, ShlObj, ShellAPI, fpcunit, testregistry,
  launchserviceu, shellactivationu, setsu, PIDL, shelltextu, itemhostu, dockcommandu, toolu;
type
  TObjectActivationTests = class(TTestCase)
  private
    Settings: TDSets;
    Service: TLaunchService;
    Shell: TShellActivation;
    MessageText, Fixture: string;
    Calls, Entered, Left: Integer;
    Accept, FailCallback: Boolean;
    SeenCommand, SeenArgs, SeenDir, SeenDocument: string;
    procedure Report(Message: WideString; Silent: Boolean);
    procedure EnterHost;
    procedure LeaveHost;
    function ReceiveDocument(Command, Parameters, Directory, Document: string;
      ShowCommand: Integer; Caller: HWND): Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ApplicationArgumentsKeepUnicodeAndExpansion;
    procedure ApplicationDirectoryIsRejected;
    procedure ApplicationArgumentValidationPrecedesActivation;
    procedure FileRequestSelectsFileContract;
    procedure URIRequestSelectsProtocolContract;
    procedure UnsupportedContractRejectsWithoutActivation;
    procedure FailedActivationRejectsWithHRESULT;
    procedure MixedContractOptionsAreRejected;
    procedure MissingDocumentIsRejected;
    procedure ExecutableDropAppendsArguments;
    procedure ExecutableFailureRejectsDocumentRequest;
    procedure ExecutablePIDLReceivesParametersAndDirectory;
    procedure ExecutablePIDLDropRetainsIdentity;
    procedure NamespaceOptionsAreRejected;
    procedure NamespaceDocumentIsRejected;
    procedure PackagedPIDLDropUsesContract;
    procedure PackagedPIDLArgumentsUseApplicationContract;
    procedure PackagedPIDLEmptyArgumentsKeepShellRoute;
    procedure CloseRejectsDocumentRequests;
    procedure StandardShellNamesParse;
    procedure MalformedShellTargetsNeverFallBack;
    procedure BareGUIDReceivesNoInventedShellIdentity;
    procedure DocumentURIAndQuotingRules;
    procedure MultiCommandDocumentsKeepSeparatorsAndPartialAcceptance;
    procedure HostBalancesAcceptanceAndRejection;
    procedure HostBalancesCallbackException;
    procedure HostFindsStackOwner;
    procedure ProviderUsesEnabledOpenOffsetAndUnicode;
    procedure ProviderFallsBackToExplore;
    procedure NetworkProviderUsesDefaultStatusOnly;
    procedure UnsupportedProviderDefaultIsRejected;
    procedure ProviderFailurePreservesHRESULT;
  end;
implementation
const AppID = 'Microsoft.WindowsCalculator_8wekyb3d8bbwe!App';
type
  TControlledShell = class(TShellActivation)
    Kind: TShellTargetKind;
    Contract, Protocol: Boolean;
    Status: HRESULT;
    Calls: Integer;
    SeenApp, Document: UnicodeString;
    function Describe(List: PItemIDList): TShellTarget; override;
    function Executable(const Target: UnicodeString): Boolean; override;
    function HasContract(const ID, Source: UnicodeString; IsProtocol: Boolean): Boolean; override;
    function ActivateDocument(const ID, Source: UnicodeString; IsProtocol: Boolean): HRESULT; override;
  end;
  TRecordingService = class(TLaunchService)
    App, Arguments, Directory, Target, Identity: UnicodeString;
    AppCalls, ExecuteCalls, Show: Integer;
    procedure ActivatePackagedAppWithArguments(const ID, Args: UnicodeString); override;
    procedure ExecuteShellIDList(var Info: TShellExecuteInfoW); override;
    procedure ExecuteShellTarget(const Name, Params, Dir: WideString; ShowCommand: Integer); override;
  end;
  TMenuProbe = class(TInterfacedObject, IContextMenu)
    Verbs: array[0..2] of UnicodeString;
    Disabled: Integer;
    DefaultOffset, Invoked: Integer;
    Mask: DWORD;
    Owner: HWND;
    Status: HRESULT;
    function QueryContextMenu(Menu: HMENU; Position, First, Last, Flags: UINT): HRESULT; stdcall;
    function InvokeCommand(var Info: TCMINVOKECOMMANDINFO): HRESULT; stdcall;
    function GetCommandString(ID: UINT_PTR; Kind: UINT; Reserved: PUINT; Text: LPSTR; Capacity: UINT): HRESULT; stdcall;
  end;
  TProviderShell = class(TShellActivation)
    Menu: IContextMenu;
    Network: Boolean;
    function ContextMenu(List: PItemIDList; Owner: HWND; out Value: IContextMenu): HRESULT; override;
    function IsNetworkConnection(List: PItemIDList): Boolean; override;
  end;
  TFailingDocumentService = class(TLaunchService)
    function InvokeShell(var Info: TShellExecuteInfoW): Boolean; override;
  end;
function TFailingDocumentService.InvokeShell(var Info: TShellExecuteInfoW): Boolean;
begin SetLastError(ERROR_ACCESS_DENIED); Result := False; end;
function TControlledShell.Describe(List: PItemIDList): TShellTarget;
begin Result := Default(TShellTarget); Result.Kind := Kind; Result.AppID := AppID; end;
function TControlledShell.Executable(const Target: UnicodeString): Boolean;
begin Result := Kind = skExecutable; end;
function TControlledShell.HasContract(const ID, Source: UnicodeString; IsProtocol: Boolean): Boolean;
begin SeenApp := ID; Document := Source; Protocol := IsProtocol; Result := Contract; end;
function TControlledShell.ActivateDocument(const ID, Source: UnicodeString; IsProtocol: Boolean): HRESULT;
begin Inc(Calls); SeenApp := ID; Document := Source; Protocol := IsProtocol; Result := Status; end;
procedure TRecordingService.ActivatePackagedAppWithArguments(const ID, Args: UnicodeString);
begin Inc(AppCalls); App := ID; Arguments := Args; end;
procedure TRecordingService.ExecuteShellIDList(var Info: TShellExecuteInfoW);
begin
  Inc(ExecuteCalls); Identity := UTF8Decode(PIDL_ToString(Info.lpIDList));
  if Info.lpParameters <> nil then Arguments := Info.lpParameters;
  if Info.lpDirectory <> nil then Directory := Info.lpDirectory;
  Show := Info.nShow;
end;
procedure TRecordingService.ExecuteShellTarget(const Name, Params, Dir: WideString; ShowCommand: Integer);
begin Inc(ExecuteCalls); Target := Name; Arguments := Params; Directory := Dir; Show := ShowCommand; end;
function TMenuProbe.QueryContextMenu(Menu: HMENU; Position, First, Last, Flags: UINT): HRESULT; stdcall;
var I: Integer; State: UINT;
begin
  for I := 0 to 2 do begin
    State := MF_STRING;
    if Disabled = I then State := State or MF_GRAYED;
    AppendMenuW(Menu, State, First + I, PWideChar(Verbs[I]));
  end;
  if DefaultOffset >= 0 then SetMenuDefaultItem(Menu, First + DefaultOffset, 0);
  Result := 3;
end;
function TMenuProbe.InvokeCommand(var Info: TCMINVOKECOMMANDINFO): HRESULT; stdcall;
var Extended: PCMINVOKECOMMANDINFOEX;
begin
  Extended := PCMINVOKECOMMANDINFOEX(@Info);
  Invoked := PtrUInt(Extended.lpVerb); Mask := Extended.fMask; Owner := Extended.hwnd;
  if (Extended.cbSize <> SizeOf(Extended^)) or (PtrUInt(Extended.lpVerbW) <> PtrUInt(Invoked)) then Exit(E_INVALIDARG);
  Result := Status;
end;
function TMenuProbe.GetCommandString(ID: UINT_PTR; Kind: UINT; Reserved: PUINT; Text: LPSTR; Capacity: UINT): HRESULT; stdcall;
begin
  if (ID > 2) or (Kind <> GCS_VERBW) or (Capacity <= UINT(Length(Verbs[ID]))) then Exit(E_INVALIDARG);
  Move(PWideChar(Verbs[ID])^, Text^, (Length(Verbs[ID]) + 1) * SizeOf(WideChar)); Result := S_OK;
end;
function TProviderShell.ContextMenu(List: PItemIDList; Owner: HWND; out Value: IContextMenu): HRESULT;
begin Value := Menu; Result := S_OK; end;
function TProviderShell.IsNetworkConnection(List: PItemIDList): Boolean;
begin Result := Network; end;
procedure TObjectActivationTests.Report(Message: WideString; Silent: Boolean);
begin MessageText := UTF8Encode(Message); end;
procedure TObjectActivationTests.EnterHost;
begin Inc(Entered); end;
procedure TObjectActivationTests.LeaveHost;
begin Inc(Left); end;
function TObjectActivationTests.ReceiveDocument(Command, Parameters, Directory, Document: string;
  ShowCommand: Integer; Caller: HWND): Boolean;
begin
  Inc(Calls); SeenCommand := Command; SeenArgs := Parameters; SeenDir := Directory; SeenDocument := Document;
  if FailCallback then raise Exception.Create('Controlled callback failure');
  Result := Accept or (Command = 'accept.exe');
end;
procedure TObjectActivationTests.SetUp;
var Stream: TFileStream; ID: TGUID;
begin
  OleCheck(OleInitialize(nil));
  Settings := TDSets.Create('', '', 0);
  Shell := TControlledShell.Create;
  TControlledShell(Shell).Contract := True;
  TControlledShell(Shell).Kind := skExecutable;
  Service := TRecordingService.Create(Settings, Report, Shell);
  CreateGUID(ID); Fixture := ExtractFilePath(ParamStr(0)) + GUIDToString(ID) + '.jpg';
  Stream := TFileStream.Create(Fixture, fmCreate); Stream.Free;
  MessageText := ''; Calls := 0; Entered := 0; Left := 0; Accept := False; FailCallback := False;
end;
procedure TObjectActivationTests.TearDown;
begin UnbindItemHost(0); Service.Free; Settings.Free; DeleteFile(Fixture); OleUninitialize; end;
procedure TObjectActivationTests.ApplicationArgumentsKeepUnicodeAndExpansion;
var Text: UnicodeString;
begin
  Text := 'argument-' + WideChar($0416) + WideChar($D83D) + WideChar($DE80);
  Service.Run(AppID, '%pp% ' + UTF8Encode(Text));
  AssertEquals(1, TRecordingService(Service).AppCalls);
  AssertTrue(ShellUTF16(UnzipPath('%pp%')) + ' ' + Text = TRecordingService(Service).Arguments);
  AssertEquals('', MessageText);
end;
procedure TObjectActivationTests.ApplicationDirectoryIsRejected;
begin Service.Run(AppID, '', 'C:\'); AssertEquals(0, TRecordingService(Service).AppCalls); AssertTrue(Pos('working directory', MessageText) > 0); end;
procedure TObjectActivationTests.ApplicationArgumentValidationPrecedesActivation;
begin Service.Run(AppID, 'x' + #0 + 'y'); AssertEquals(0, TRecordingService(Service).AppCalls); AssertTrue(MessageText <> ''); end;
procedure TObjectActivationTests.FileRequestSelectsFileContract;
begin AssertTrue(Service.OpenDocument(AppID, '', '', Fixture, 1, 0)); AssertFalse(TControlledShell(Shell).Protocol); AssertEquals(1, TControlledShell(Shell).Calls); AssertEquals(AppID, UTF8Encode(TControlledShell(Shell).SeenApp)); end;
procedure TObjectActivationTests.URIRequestSelectsProtocolContract;
begin AssertTrue(Service.OpenDocument(AppID, '', '', 'calculator:', 1, 0)); AssertTrue(TControlledShell(Shell).Protocol); AssertEquals('calculator:', UTF8Encode(TControlledShell(Shell).Document)); end;
procedure TObjectActivationTests.UnsupportedContractRejectsWithoutActivation;
begin TControlledShell(Shell).Contract := False; AssertFalse(Service.OpenDocument(AppID, '', '', Fixture, 1, 0)); AssertEquals(0, TControlledShell(Shell).Calls); AssertTrue(Pos('registered contract', MessageText) > 0); end;
procedure TObjectActivationTests.FailedActivationRejectsWithHRESULT;
begin TControlledShell(Shell).Status := E_ACCESSDENIED; AssertFalse(Service.OpenDocument(AppID, '', '', Fixture, 1, 0)); AssertTrue(Pos('80070005', MessageText) > 0); end;
procedure TObjectActivationTests.MixedContractOptionsAreRejected;
begin
  AssertFalse(Service.OpenDocument(AppID, '--extra', '', Fixture, 1, 0));
  AssertFalse(Service.OpenDocument(AppID, '', 'C:\', Fixture, 1, 0));
  AssertEquals(0, TControlledShell(Shell).Calls);
end;
procedure TObjectActivationTests.MissingDocumentIsRejected;
begin AssertFalse(Service.OpenDocument(AppID, '', '', Fixture + '.missing', 1, 0)); AssertEquals(0, TControlledShell(Shell).Calls); end;
procedure TObjectActivationTests.ExecutableDropAppendsArguments;
begin AssertTrue(Service.OpenDocument('example.exe', '--extra', 'C:\', Fixture, 2, 0)); AssertEquals('--extra "' + Fixture + '"', UTF8Encode(TRecordingService(Service).Arguments)); AssertEquals('C:\', UTF8Encode(TRecordingService(Service).Directory)); AssertEquals(2, TRecordingService(Service).Show); end;
procedure TObjectActivationTests.ExecutableFailureRejectsDocumentRequest;
var LocalService: TLaunchService; LocalShell: TControlledShell;
begin
  LocalShell := TControlledShell.Create; LocalShell.Kind := skExecutable;
  LocalService := TFailingDocumentService.Create(Settings, Report, LocalShell);
  try
    AssertFalse(LocalService.OpenDocument('example.exe', '', '', Fixture, 1, 0));
    AssertTrue(Pos('Win32 5', MessageText) > 0);
  finally LocalService.Free; end;
end;
procedure TObjectActivationTests.ExecutablePIDLReceivesParametersAndDirectory;
begin Service.Run('shell:Downloads', '--extra', 'C:\', 2); AssertEquals(1, TRecordingService(Service).ExecuteCalls); AssertEquals('--extra', UTF8Encode(TRecordingService(Service).Arguments)); AssertEquals('C:\', UTF8Encode(TRecordingService(Service).Directory)); end;
procedure TObjectActivationTests.ExecutablePIDLDropRetainsIdentity;
begin AssertTrue(Service.OpenDocument('shell:Downloads', '--extra', 'C:\', Fixture, 1, 0)); AssertTrue(TRecordingService(Service).Identity <> ''); AssertEquals('--extra "' + Fixture + '"', UTF8Encode(TRecordingService(Service).Arguments)); end;
procedure TObjectActivationTests.NamespaceOptionsAreRejected;
begin TControlledShell(Shell).Kind := skNamespace; Service.Run('shell:Downloads', '--extra'); AssertEquals(0, TRecordingService(Service).ExecuteCalls); AssertTrue(Pos('does not support', MessageText) > 0); end;
procedure TObjectActivationTests.NamespaceDocumentIsRejected;
begin TControlledShell(Shell).Kind := skFolder; AssertFalse(Service.OpenDocument('shell:Downloads', '', '', Fixture, 1, 0)); AssertEquals(0, TRecordingService(Service).ExecuteCalls); end;
procedure TObjectActivationTests.PackagedPIDLDropUsesContract;
begin TControlledShell(Shell).Kind := skPackaged; AssertTrue(Service.OpenDocument('shell:Downloads', '', '', Fixture, 1, 0)); AssertEquals(1, TControlledShell(Shell).Calls); end;
procedure TObjectActivationTests.PackagedPIDLArgumentsUseApplicationContract;
begin TControlledShell(Shell).Kind := skPackaged; Service.Run('shell:Downloads', '--extra'); AssertEquals(1, TRecordingService(Service).AppCalls); AssertEquals('--extra', UTF8Encode(TRecordingService(Service).Arguments)); end;
procedure TObjectActivationTests.PackagedPIDLEmptyArgumentsKeepShellRoute;
begin TControlledShell(Shell).Kind := skPackaged; Service.Run('shell:Downloads'); AssertEquals(1, TRecordingService(Service).ExecuteCalls); AssertEquals(0, TRecordingService(Service).AppCalls); end;
procedure TObjectActivationTests.CloseRejectsDocumentRequests;
begin Service.Close; AssertFalse(Service.OpenDocument(AppID, '', '', Fixture, 1, 0)); AssertEquals(0, TControlledShell(Shell).Calls); end;
procedure TObjectActivationTests.StandardShellNamesParse;
const Names: array[0..5] of string = ('::{20D04FE0-3AEA-1069-A2D8-08002B30309D}', '::{645FF040-5081-101B-9F08-00AA002F954E}', 'shell:ControlPanelFolder', 'shell:NetworkPlacesFolder', 'ShElL:AppsFolder', 'shell:Downloads');
var Name: string; List, Restored: PItemIDList;
begin for Name in Names do begin List := PIDL_ParseTarget(UTF8Decode(Name)); try AssertTrue(Name, List <> nil); Restored := PIDL_ParseTarget(UTF8Decode(PIDL_ToString(List))); PIDL_Free(Restored); finally PIDL_Free(List); end; end; end;
procedure TObjectActivationTests.MalformedShellTargetsNeverFallBack;
begin Service.Run('::::ZZZZ'); AssertTrue(MessageText <> ''); AssertEquals(0, TRecordingService(Service).ExecuteCalls); MessageText := ''; Service.Run('shell:tdock-unknown-alias'); AssertTrue(MessageText <> ''); AssertEquals(0, TRecordingService(Service).ExecuteCalls); end;
procedure TObjectActivationTests.BareGUIDReceivesNoInventedShellIdentity;
var List: PItemIDList;
begin List := PIDL_ParseTarget('{20D04FE0-3AEA-1069-A2D8-08002B30309D}'); AssertTrue(List = nil); end;
procedure TObjectActivationTests.DocumentURIAndQuotingRules;
begin AssertTrue(DocumentIsURI('calculator:')); AssertTrue(DocumentIsURI('https://example.invalid/')); AssertFalse(DocumentIsURI('C:\file.txt')); AssertFalse(DocumentIsURI('shell:Downloads')); AssertEquals('"a\"b\\"', UTF8Encode(QuoteDocumentArgument('a"b\'))); end;
procedure TObjectActivationTests.MultiCommandDocumentsKeepSeparatorsAndPartialAcceptance;
var Controller: TDockCommandController;
begin
  Controller := TDockCommandController.Create(nil, nil);
  try Controller.OnDocument := ReceiveDocument;
    AssertTrue(Controller.OpenDocument('reject.exe;accept.exe', 'one;two', 'C:\;D:\', Fixture, 1, 0));
    AssertEquals(2, Calls); AssertEquals('accept.exe', SeenCommand); AssertEquals('two', SeenArgs); AssertEquals('D:\', SeenDir); AssertEquals(Fixture, SeenDocument);
    AssertFalse(Controller.OpenDocument('/quit', '', '', Fixture, 1, 0)); AssertEquals(2, Calls);
  finally Controller.Free; end;
end;
procedure TObjectActivationTests.HostBalancesAcceptanceAndRejection;
var Services: TItemHostServices;
begin
  Services := Default(TItemHostServices); Services.OnEnter := EnterHost; Services.OnLeave := LeaveHost; Services.OnOpenDocument := ReceiveDocument; BindItemHost(0, Services);
  AssertFalse(ItemHostOpenDocument(0, 0, 'app.exe', '', '', Fixture, 1)); Accept := True;
  AssertTrue(ItemHostOpenDocument(0, 0, 'app.exe', '', '', Fixture, 1)); AssertEquals(2, Entered); AssertEquals(2, Left);
end;
procedure TObjectActivationTests.HostBalancesCallbackException;
begin
  HostBalancesAcceptanceAndRejection; FailCallback := True;
  try ItemHostOpenDocument(0, 0, 'app.exe', '', '', Fixture, 1); Fail('Expected controlled failure'); except on E: Exception do AssertEquals('Controlled callback failure', E.Message); end;
  AssertEquals(3, Entered); AssertEquals(3, Left);
end;
procedure TObjectActivationTests.HostFindsStackOwner;
var Window: HWND;
begin
  HostBalancesAcceptanceAndRejection;
  Window := CreateWindowExW(0, 'STATIC', 'stack', WS_POPUP, 0, 0, 0, 0, 0, 0, HInstance, nil);
  try AssertTrue(ItemHostOpenDocument(Window, 0, 'app.exe', '', '', Fixture, 1)); AssertEquals(3, Calls); finally DestroyWindow(Window); end;
end;
procedure CheckProvider(Open, Explore, StatusName: UnicodeString; Disabled, DefaultOffset: Integer;
  Network: Boolean; ExpectedOffset: Integer; ExpectedStatus: HRESULT = S_OK);
var Shell: TProviderShell; Probe: TMenuProbe; Hold: IContextMenu; Window: HWND; Status: HRESULT;
begin
  Shell := TProviderShell.Create; Probe := TMenuProbe.Create; Hold := Probe;
  Probe.Verbs[0] := Open; Probe.Verbs[1] := Explore; Probe.Verbs[2] := StatusName;
  Probe.Disabled := Disabled; Probe.DefaultOffset := DefaultOffset; Probe.Invoked := -1; Probe.Status := ExpectedStatus;
  Shell.Menu := Hold; Shell.Network := Network;
  Window := CreateWindowExW(0, 'STATIC', 'owner', WS_POPUP, 0, 0, 0, 0, 0, 0, HInstance, nil);
  try
    Status := Shell.InvokeNamespace(nil, Window, SW_SHOWNORMAL);
    if ExpectedOffset < 0 then TAssert.AssertTrue(Status < 0) else begin
      TAssert.AssertEquals(Int64(ExpectedStatus), Int64(Status)); TAssert.AssertEquals(ExpectedOffset, Probe.Invoked);
      TAssert.AssertTrue((Probe.Mask and CMIC_MASK_UNICODE) <> 0); TAssert.AssertEquals(QWord(Window), QWord(Probe.Owner));
    end;
  finally DestroyWindow(Window); Shell.Free; Hold := nil; end;
end;
procedure TObjectActivationTests.ProviderUsesEnabledOpenOffsetAndUnicode;
begin CheckProvider('delete', 'open', 'properties', -1, 2, False, 1); end;
procedure TObjectActivationTests.ProviderFallsBackToExplore;
begin CheckProvider('open', 'explore', 'properties', 0, 2, False, 1); end;
procedure TObjectActivationTests.NetworkProviderUsesDefaultStatusOnly;
begin CheckProvider('delete', 'disconnect', 'status', -1, 2, True, 2); CheckProvider('delete', 'disconnect', 'status', -1, 0, True, -1); CheckProvider('delete', 'disconnect', 'status', -1, 2, False, -1); end;
procedure TObjectActivationTests.UnsupportedProviderDefaultIsRejected;
begin CheckProvider('delete', 'disconnect', 'properties', -1, 0, False, -1); end;
procedure TObjectActivationTests.ProviderFailurePreservesHRESULT;
begin CheckProvider('open', 'delete', 'properties', -1, 0, False, 0, E_ACCESSDENIED); end;
initialization RegisterTest(TObjectActivationTests);
end.
