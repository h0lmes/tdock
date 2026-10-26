unit activationtests;
{$mode delphi}
interface
uses Windows, SysUtils, ActiveX, fpcunit, testregistry, uwp_tlb;
type
  TActivationTests = class(TTestCase)
  published
    procedure NativeFailureReturnsHRESULTWithoutException;
    procedure NativeSuccessReturnsHRESULTAndPID;
    procedure WrapperPreservesArgumentsAndErrorUIContract;
    procedure WrapperReturnsManagerCreationFailure;
    procedure WrapperRejectsMissingInterface;
    procedure NativeMissingApplicationReturnsFailure;
    procedure WrapperForwardsUnicodeLaunchArguments;
    procedure WrapperSelectsFileAndProtocolSlots;
    procedure ContractFailuresAndMissingArraysRemainFailures;
  end;
implementation
type
  INativeActivation = interface(IUnknown)
    ['{2E941141-7F97-4756-BA1D-9DECDE894A3D}']
    function ActivateApplication(ID, Args: LPCWSTR; Options: UInt32; out PID: UInt32): HRESULT; stdcall;
    function ActivateForFile(ID: LPCWSTR; Items: IShellItemArray; Verb: LPCWSTR; out PID: UInt32): HRESULT; stdcall;
    function ActivateForProtocol(ID: LPCWSTR; Items: IShellItemArray; out PID: UInt32): HRESULT; stdcall;
  end;
  TNativeActivation = class(TInterfacedObject, INativeActivation)
    Status: HRESULT;
    SeenID: UnicodeString;
    ArgumentsWereNil: Boolean;
    SeenArguments: UnicodeString;
    ContractKind: Integer;
    ItemsPresent, OpenVerb: Boolean;
    SeenOptions: UInt32;
    Calls: Integer;
    function ActivateApplication(ID, Args: LPCWSTR; Options: UInt32; out PID: UInt32): HRESULT; stdcall;
    function ActivateForFile(ID: LPCWSTR; Items: IShellItemArray; Verb: LPCWSTR; out PID: UInt32): HRESULT; stdcall;
    function ActivateForProtocol(ID: LPCWSTR; Items: IShellItemArray; out PID: UInt32): HRESULT; stdcall;
  end;
function TNativeActivation.ActivateApplication(ID, Args: LPCWSTR; Options: UInt32; out PID: UInt32): HRESULT; stdcall;
begin
  Inc(Calls); SeenID := ID; ArgumentsWereNil := Args = nil; SeenOptions := Options;
  if Args <> nil then SeenArguments := Args;
  PID := 0;
  if Status >= 0 then PID := 4321;
  Result := Status;
end;
function TNativeActivation.ActivateForFile(ID: LPCWSTR; Items: IShellItemArray; Verb: LPCWSTR; out PID: UInt32): HRESULT; stdcall;
begin
  Inc(Calls); ContractKind := 1; ItemsPresent := Items <> nil;
  OpenVerb := (Verb <> nil) and (UnicodeString(Verb) = 'open');
  PID := 0; if Status >= 0 then PID := 4321; Result := Status;
end;
function TNativeActivation.ActivateForProtocol(ID: LPCWSTR; Items: IShellItemArray; out PID: UInt32): HRESULT; stdcall;
begin Inc(Calls); ContractKind := 2; ItemsPresent := Items <> nil; PID := 0; if Status >= 0 then PID := 4321; Result := Status; end;
procedure TActivationTests.NativeFailureReturnsHRESULTWithoutException;
var Native: INativeActivation; API: IApplicationActivationManager; PID: UInt32;
    ObjectValue: TNativeActivation;
    Status: HRESULT; Raised: Boolean;
begin
  ObjectValue := TNativeActivation.Create;
  ObjectValue.Status := E_ACCESSDENIED;
  Native := ObjectValue;
  API := Native as IApplicationActivationManager;
  Raised := False;
  Status := S_OK;
  try Status := API.ActivateApplication('missing', nil, 0, PID);
  except on Exception do Raised := True; end;
  AssertFalse('Native HRESULT remains a result', Raised);
  AssertEquals(Int64(E_ACCESSDENIED), Int64(Status));
end;
procedure TActivationTests.NativeSuccessReturnsHRESULTAndPID;
var Native: INativeActivation; API: IApplicationActivationManager; PID: UInt32;
begin
  Native := TNativeActivation.Create;
  API := Native as IApplicationActivationManager;
  AssertEquals(Int64(S_OK), Int64(API.ActivateApplication('test', nil, 0, PID)));
  AssertEquals(4321, PID);
end;
procedure TActivationTests.WrapperPreservesArgumentsAndErrorUIContract;
var ObjectValue: TNativeActivation; Native: INativeActivation; API: IApplicationActivationManager;
    Manager: ApplicationActivationManager; PID: UInt32; ID: UnicodeString;
begin
  ObjectValue := TNativeActivation.Create;
  Native := ObjectValue;
  API := Native as IApplicationActivationManager;
  Manager := ApplicationActivationManager.Create(API, S_OK);
  try
    ID := 'test.' + WideChar($0416);
    AssertEquals(Int64(S_OK), Int64(Manager.ActivateApplication(PWideChar(ID), PID)));
    AssertTrue(ObjectValue.SeenID = ID);
    AssertTrue('WO-13 argument behavior stays unchanged', ObjectValue.ArgumentsWereNil);
    AssertEquals(ActivateOptionNoErrorUI, ObjectValue.SeenOptions);
    AssertEquals(4321, PID);
    ObjectValue.Status := E_ACCESSDENIED;
    AssertEquals(Int64(E_ACCESSDENIED), Int64(Manager.ActivateApplication('test', PID)));
  finally Manager.Free; end;
end;
procedure TActivationTests.WrapperReturnsManagerCreationFailure;
var Manager: ApplicationActivationManager; PID: UInt32;
begin
  Manager := ApplicationActivationManager.Create(nil, REGDB_E_CLASSNOTREG);
  try
    PID := 777;
    AssertEquals(Int64(REGDB_E_CLASSNOTREG), Int64(Manager.ActivateApplication('test', PID)));
    AssertEquals(0, PID);
  finally Manager.Free; end;
end;
procedure TActivationTests.WrapperRejectsMissingInterface;
var Manager: ApplicationActivationManager; PID: UInt32;
begin
  Manager := ApplicationActivationManager.Create(nil, S_OK);
  try
    AssertEquals(Int64(E_NOINTERFACE), Int64(Manager.ActivateApplication('test', PID)));
    AssertEquals(0, PID);
  finally Manager.Free; end;
end;
procedure TActivationTests.NativeMissingApplicationReturnsFailure;
var Manager: ApplicationActivationManager; PID: UInt32; Status: HRESULT;
begin
  Status := CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  AssertTrue(Status >= 0);
  try
    Manager := ApplicationActivationManager.Create;
    try
      Status := Manager.ActivateApplication('TDOCK.Missing_8wekyb3d8bbwe!Main', PID);
      AssertTrue('Native missing application returns a failed HRESULT', Status < 0);
      AssertEquals(0, PID);
    finally Manager.Free; end;
  finally CoUninitialize; end;
end;
type TArrayStub = class(TInterfacedObject, IShellItemArray) end;
procedure TActivationTests.WrapperForwardsUnicodeLaunchArguments;
var Native: INativeActivation; API: IApplicationActivationManager; Value: TNativeActivation;
  Manager: ApplicationActivationManager; PID: UInt32; Args: UnicodeString;
begin
  Value := TNativeActivation.Create; Native := Value; API := Native as IApplicationActivationManager;
  Manager := ApplicationActivationManager.Create(API, S_OK);
  try
    Args := 'launch-' + WideChar($0416) + WideChar($6587) + WideChar($D83D) + WideChar($DE80);
    AssertEquals(Int64(S_OK), Int64(Manager.ActivateApplication('app', PID, PWideChar(Args))));
    AssertTrue(Args = Value.SeenArguments); AssertFalse(Value.ArgumentsWereNil);
    AssertEquals(ActivateOptionNoErrorUI, Value.SeenOptions);
  finally Manager.Free; end;
end;
procedure TActivationTests.WrapperSelectsFileAndProtocolSlots;
var Native: INativeActivation; API: IApplicationActivationManager; Value: TNativeActivation;
  Manager: ApplicationActivationManager; PID: UInt32; Items: IShellItemArray;
begin
  Value := TNativeActivation.Create; Native := Value; API := Native as IApplicationActivationManager;
  Items := TArrayStub.Create; Manager := ApplicationActivationManager.Create(API, S_OK);
  try
    AssertEquals(Int64(S_OK), Int64(Manager.ActivateForFile('app', Items, PID)));
    AssertEquals(1, Value.ContractKind); AssertTrue(Value.ItemsPresent); AssertTrue(Value.OpenVerb); AssertEquals(4321, PID);
    AssertEquals(Int64(S_OK), Int64(Manager.ActivateForProtocol('app', Items, PID)));
    AssertEquals(2, Value.ContractKind); AssertTrue(Value.ItemsPresent); AssertEquals(4321, PID);
  finally Manager.Free; end;
end;
procedure TActivationTests.ContractFailuresAndMissingArraysRemainFailures;
var Native: INativeActivation; API: IApplicationActivationManager; Value: TNativeActivation;
  Manager: ApplicationActivationManager; PID: UInt32; Items: IShellItemArray;
begin
  Value := TNativeActivation.Create; Value.Status := E_ACCESSDENIED; Native := Value;
  API := Native as IApplicationActivationManager; Items := TArrayStub.Create;
  Manager := ApplicationActivationManager.Create(API, S_OK);
  try
    AssertEquals(Int64(E_ACCESSDENIED), Int64(Manager.ActivateForFile('app', Items, PID))); AssertEquals(0, PID);
    AssertEquals(Int64(E_ACCESSDENIED), Int64(Manager.ActivateForProtocol('app', Items, PID))); AssertEquals(0, PID);
    AssertEquals(Int64(E_INVALIDARG), Int64(Manager.ActivateForFile('app', nil, PID)));
    AssertEquals(Int64(E_INVALIDARG), Int64(Manager.ActivateForProtocol('app', nil, PID)));
    AssertEquals(2, Value.Calls);
  finally Manager.Free; end;
end;
initialization
  RegisterTest(TActivationTests);
end.
