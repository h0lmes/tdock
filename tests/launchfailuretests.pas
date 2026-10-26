unit launchfailuretests;
{$mode delphi}
interface
uses Windows, SysUtils, ActiveX, ComObj, ShellAPI, fpcunit, testregistry, setsu, launchserviceu,
  runthreadu, launchresultu, shelltextu;
type
  TControlledLaunch = class(TLaunchService)
  public
    ErrorCode: DWORD;
    ShellCode: PtrInt;
    Calls: Integer;
    Mask: DWORD;
    Succeed: Boolean;
    ThrowError: Boolean;
  protected
    function InvokeShell(var Info: TShellExecuteInfoW): Boolean; override;
  end;
  TObservedNativeLaunch = class(TLaunchService)
  public
    Accepted: Boolean;
    NativeError: DWORD;
    function InvokeShell(var Info: TShellExecuteInfoW): Boolean; override;
  end;
  TLaunchFailureTests = class(TTestCase)
  private
    Settings: TDSets;
    Service: TLaunchService;
    MessageText: UnicodeString;
    ReportCount: Integer;
    ReportThread: DWORD;
    CloseOnReport: Boolean;
    procedure Report(Message: WideString; Silent: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure CreationFailureContainsWindowsCode;
    procedure DirectFailureReportsWindowsCode;
    procedure KnownFailureCodesRemainDistinct;
    procedure PIDLFailureReportsAndSuppressesNativeErrorUI;
    procedure URIFailureReportsHandlerCode;
    procedure PackagedAppUnavailableReportsHRESULT;
    procedure AsyncFailureWaitsForMainThreadDrain;
    procedure ImmediateWorkerFailureIsReportedOnce;
    procedure WorkerCanFinishAfterServiceDestruction;
    procedure CloseDiscardsPendingFailures;
    procedure ReportCallbackCanCloseTheQueue;
    procedure SuccessfulShellCallProducesNoError;
    procedure ShellFallbackAndUnknownHRESULTKeepTheirCodes;
    procedure ShellExceptionPreservesStageAndCode;
    procedure NativeMissingFileReports;
    procedure NativeThreadedMissingFileReportsOnMainThread;
    procedure NativeURIReportsOnlyImmediateAPIFailure;
  end;
implementation
function TObservedNativeLaunch.InvokeShell(var Info: TShellExecuteInfoW): Boolean;
begin
  Result := inherited InvokeShell(Info);
  NativeError := GetLastError;
  Accepted := Result;
end;
function TControlledLaunch.InvokeShell(var Info: TShellExecuteInfoW): Boolean;
var Error: EOSError;
begin
  Inc(Calls); Mask := Info.fMask;
  if ThrowError then
  begin
    Error := EOSError.Create('Controlled Shell failure');
    Error.ErrorCode := ErrorCode;
    raise Error;
  end;
  Info.hInstApp := HINST(ShellCode); SetLastError(ErrorCode); Result := Succeed;
end;
var SavedWorker: TThreadFunc; SavedData: Pointer;
function DeferStart(Worker: TThreadFunc; Data: Pointer): TThreadID;
begin
  SavedWorker := Worker; SavedData := Data;
  Result := TThreadID(CreateEventW(nil, True, False, nil));
end;
procedure FinishWorker;
var Worker: TThreadFunc; Data: Pointer;
begin
  Worker := SavedWorker; Data := SavedData; SavedWorker := nil; SavedData := nil;
  if Assigned(Worker) then Worker(Data);
end;
function FailWorkerShell(var Info: TShellExecuteInfoW): Boolean;
begin Info.hInstApp := HINST(5); SetLastError(ERROR_ACCESS_DENIED); Result := False; end;
function ImmediateStart(Worker: TThreadFunc; Data: Pointer): TThreadID;
begin Worker(Data); Result := TThreadID(CreateEventW(nil, True, False, nil)); end;
function FailStart(Worker: TThreadFunc; Data: Pointer): TThreadID;
begin SetLastError(ERROR_ACCESS_DENIED); Result := 0; end;
procedure TLaunchFailureTests.SetUp;
begin
  OleCheck(OleInitialize(nil));
  SavedWorker := nil; SavedData := nil;
  ReportCount := 0; CloseOnReport := False;
  Settings := TDSets.Create('', '', 0);
  Settings.container.RunInThread := True;
  Settings.container.useShell := False;
  Service := TControlledLaunch.Create(Settings, Report);
  TControlledLaunch(Service).ErrorCode := ERROR_ACCESS_DENIED;
  TControlledLaunch(Service).ShellCode := 5;
  RunStartHook := FailStart;
end;
procedure TLaunchFailureTests.TearDown;
begin
  FinishWorker;
  RunStartHook := nil; RunExecuteHook := nil;
  Service.Free; Settings.Free; OleUninitialize;
end;
procedure TLaunchFailureTests.Report(Message: WideString; Silent: Boolean);
begin
  Inc(ReportCount); MessageText := Message; ReportThread := GetCurrentThreadId;
  if CloseOnReport then Service.Close;
end;
procedure TLaunchFailureTests.CreationFailureContainsWindowsCode;
begin
  Service.Run('missing-launch-test.exe');
  AssertTrue('Report retains Win32 error code', Pos('Win32 5', MessageText) > 0);
  AssertTrue('Report identifies thread creation', Pos('Thread creation', MessageText) > 0);
end;
procedure TLaunchFailureTests.KnownFailureCodesRemainDistinct;
const Codes: array[0..3] of DWORD = (ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND,
  ERROR_ACCESS_DENIED, ERROR_NO_ASSOCIATION);
var Code: DWORD;
begin
  Settings.container.RunInThread := False;
  for Code in Codes do
  begin
    TControlledLaunch(Service).ErrorCode := Code;
    Service.Run('missing-launch-test.exe');
    AssertTrue(Pos('Win32 ' + UnicodeString(IntToStr(Code)), MessageText) > 0);
  end;
  AssertEquals(4, ReportCount);
end;
procedure TLaunchFailureTests.PIDLFailureReportsAndSuppressesNativeErrorUI;
begin
  Service.Run('::{20D04FE0-3AEA-1069-A2D8-08002B30309D}');
  AssertEquals(1, TControlledLaunch(Service).Calls);
  AssertTrue(Pos('PIDL: Shell launch', MessageText) > 0);
  AssertTrue(Pos('Win32 5', MessageText) > 0);
  AssertTrue(TControlledLaunch(Service).Mask and SEE_MASK_IDLIST <> 0);
  AssertTrue(TControlledLaunch(Service).Mask and SEE_MASK_FLAG_NO_UI <> 0);
end;
procedure TLaunchFailureTests.URIFailureReportsHandlerCode;
begin
  Settings.container.RunInThread := False;
  TControlledLaunch(Service).ErrorCode := ERROR_NO_ASSOCIATION;
  Service.Run('tdock-test-missing://object');
  AssertTrue(Pos('URI: Shell launch', MessageText) > 0);
  AssertTrue(Pos('Win32 1155', MessageText) > 0);
end;
procedure TLaunchFailureTests.PackagedAppUnavailableReportsHRESULT;
begin
  Service.Run('TDOCK.Test_8wekyb3d8bbwe!Main');
  AssertTrue(Pos('Application activation', MessageText) > 0);
  AssertTrue(Pos('HRESULT 0x80004002', MessageText) > 0);
end;
procedure TLaunchFailureTests.AsyncFailureWaitsForMainThreadDrain;
begin
  RunStartHook := DeferStart; RunExecuteHook := FailWorkerShell;
  Service.Run('tdock-test-missing://object');
  AssertEquals('Creation is not activation success or failure', 0, ReportCount);
  FinishWorker;
  AssertEquals('Worker never calls the UI callback', 0, ReportCount);
  Service.DispatchPending;
  AssertEquals(1, ReportCount);
  AssertTrue(Pos('Threaded URI: Shell launch', MessageText) > 0);
  AssertTrue(Pos('Win32 5', MessageText) > 0);
  Service.DispatchPending;
  AssertEquals(1, ReportCount);
end;
procedure TLaunchFailureTests.ImmediateWorkerFailureIsReportedOnce;
begin
  RunStartHook := ImmediateStart; RunExecuteHook := FailWorkerShell;
  Service.Run('missing.exe');
  AssertEquals(0, ReportCount);
  Service.DispatchPending; Service.DispatchPending;
  AssertEquals(1, ReportCount);
end;
procedure TLaunchFailureTests.WorkerCanFinishAfterServiceDestruction;
begin
  RunStartHook := DeferStart; RunExecuteHook := FailWorkerShell;
  Service.Run('missing.exe');
  FreeAndNil(Service);
  FreeAndNil(Settings);
  FinishWorker;
  AssertEquals('Destroyed report owner receives no callback', 0, ReportCount);
end;
procedure TLaunchFailureTests.CloseDiscardsPendingFailures;
begin
  RunStartHook := ImmediateStart; RunExecuteHook := FailWorkerShell;
  Service.Run('missing.exe');
  Service.Close; Service.Close;
  Service.DispatchPending;
  Service.Run('another.exe');
  AssertEquals(0, ReportCount);
end;
procedure TLaunchFailureTests.ReportCallbackCanCloseTheQueue;
begin
  RunStartHook := ImmediateStart; RunExecuteHook := FailWorkerShell;
  Service.Run('first.exe'); Service.Run('second.exe');
  CloseOnReport := True;
  Service.DispatchPending;
  AssertEquals('Closing during reporting drops later reports', 1, ReportCount);
end;
procedure TLaunchFailureTests.SuccessfulShellCallProducesNoError;
begin
  Settings.container.RunInThread := False;
  TControlledLaunch(Service).Succeed := True;
  Service.Run('app.exe');
  AssertEquals(0, ReportCount);
  AssertTrue(TControlledLaunch(Service).Mask and SEE_MASK_FLAG_NO_UI <> 0);
end;
procedure TLaunchFailureTests.ShellFallbackAndUnknownHRESULTKeepTheirCodes;
var Value: TLaunchResult; Text: UnicodeString;
begin
  Value := LaunchFailure(lsShell, 'test', 0, 0, 31);
  Text := LaunchResultMessage(Value);
  AssertTrue(Pos('Shell 31', Text) > 0);
  AssertTrue(Pos('No application handles', Text) > 0);
  Value := LaunchFailure(lsActivation, 'test', 0, HRESULT($8FFF1234));
  Text := LaunchResultMessage(Value);
  AssertTrue(Pos('HRESULT 0x8FFF1234', Text) > 0);
  AssertTrue(Pos('Windows did not provide', Text) > 0);
end;
procedure TLaunchFailureTests.ShellExceptionPreservesStageAndCode;
begin
  Settings.container.RunInThread := False;
  TControlledLaunch(Service).ThrowError := True;
  Service.Run('app.exe');
  AssertTrue(Pos('Shell launch', MessageText) > 0);
  AssertTrue(Pos('Win32 5', MessageText) > 0);
end;
procedure TLaunchFailureTests.NativeMissingFileReports;
var ID: TGUID; Target: UnicodeString;
begin
  FreeAndNil(Service);
  Service := TLaunchService.Create(Settings, Report);
  Settings.container.RunInThread := False;
  CreateGUID(ID);
  Target := ShellUTF16(ExtractFilePath(ParamStr(0)) + 'missing-' + GUIDToString(ID)) + WideChar($0416) + '.exe';
  Service.Run(ShellUTF8(Target));
  AssertEquals(1, ReportCount);
  AssertTrue(Pos('Shell launch', MessageText) > 0);
  AssertTrue(Pos('Win32 2', MessageText) > 0);
  AssertTrue('Native failure retains Unicode target', Pos(Target, MessageText) > 0);
end;
procedure TLaunchFailureTests.NativeURIReportsOnlyImmediateAPIFailure;
var ID: TGUID; Scheme: string;
begin
  FreeAndNil(Service);
  Service := TObservedNativeLaunch.Create(Settings, Report);
  Settings.container.RunInThread := False;
  CreateGUID(ID);
  Scheme := 'tdock-wo19-' + Copy(GUIDToString(ID), 2, 36) + '://object';
  Service.Run(Scheme);
  if TObservedNativeLaunch(Service).Accepted then
  begin
    WriteLn('Native unregistered URI: Windows accepted the request; no immediate failure exists.');
    AssertEquals('Windows acceptance cannot be reclassified as handler failure', 0, ReportCount);
  end else begin
    WriteLn('Native unregistered URI: Win32 ', TObservedNativeLaunch(Service).NativeError);
    AssertEquals(1, ReportCount);
    AssertTrue(Pos('URI: Shell launch', MessageText) > 0);
    AssertTrue(Pos('Win32 ' + UnicodeString(IntToStr(TObservedNativeLaunch(Service).NativeError)), MessageText) > 0);
  end;
end;
procedure TLaunchFailureTests.NativeThreadedMissingFileReportsOnMainThread;
var ID: TGUID; Target: string; Deadline: QWord;
begin
  FreeAndNil(Service);
  Service := TLaunchService.Create(Settings, Report);
  RunStartHook := nil; RunExecuteHook := nil;
  Settings.container.RunInThread := True;
  CreateGUID(ID);
  Target := ExtractFilePath(ParamStr(0)) + 'missing-' + GUIDToString(ID) + '.exe';
  Service.Run(Target);
  AssertEquals('Worker creation cannot call the report owner', 0, ReportCount);
  Deadline := GetTickCount64 + 5000;
  repeat
    Service.DispatchPending;
    if ReportCount <> 0 then Break;
    Sleep(1);
  until GetTickCount64 >= Deadline;
  AssertEquals(1, ReportCount);
  AssertEquals(GetCurrentThreadId, ReportThread);
  AssertTrue(Pos('Threaded: Shell launch', MessageText) > 0);
  AssertTrue(Pos('Win32 2', MessageText) > 0);
end;
procedure TLaunchFailureTests.DirectFailureReportsWindowsCode;
begin
  Settings.container.RunInThread := False;
  Service.Run('missing-launch-test.exe');
  AssertTrue('Direct failure retains its code', Pos('Win32 5', MessageText) > 0);
  AssertTrue('Direct failure identifies the Shell', Pos('Shell launch', MessageText) > 0);
end;
initialization
  RegisterTest(TLaunchFailureTests);
end.
