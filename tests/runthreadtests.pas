unit runthreadtests;

{$mode delphi}

interface

uses Windows, SysUtils, ShellAPI, fpcunit, testregistry, runthreadu, launchresultu;

type
  TRunThreadTests = class(TTestCase)
  private
    procedure CompleteDeferredWorker;
    procedure CheckOriginalHandleClosed;
    procedure CheckOversizedInput(field: integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure WorkerOwnsCopiedParameters;
    procedure CreationFailureFreesParameters;
    procedure CreationExceptionFreesParameters;
    procedure ImmediateCompletionClosesHandleOnce;
    procedure WorkerExceptionFreesParameters;
    procedure ShellFailureFreesParameters;
    procedure ShellFailureReachesIndependentQueue;
    procedure WorkerUsesNoAsyncWithoutProcessHandle;
    procedure AcceptsMaximumLengthInputs;
    procedure AcceptsPreviouslyOversizedInputs;
    procedure RejectsOversizedFilename;
    procedure RejectsOversizedParameters;
    procedure RejectsOversizedDirectory;
    procedure WorkerCompletesAfterHostWindowDestruction;
    procedure RepeatedWorkersDoNotLeakHandles;
    procedure BoundaryInputsPreserveAllFields;
    procedure InvalidUnicodeAndNullRejectBeforeCreation;
    procedure CreationFailurePreservesNativeError;
    procedure HandleCleanupFailureKeepsWorkerOwnership;
    procedure COMFailureReportsWithoutUninitializing;
    procedure COMSuccessBalancesUninitialization;
    procedure WorkerExceptionReportsWithoutEscaping;
    procedure ClosedQueueOutlivesItsCaller;
    procedure ParallelFailuresRetainEveryResult;
  end;

implementation

type
  TStartMode = (smDeferred, smFailure, smException, smImmediate, smReal);
  EThreadCreationFailure = class(Exception);

var
  StartMode: TStartMode;
  StartCount, DisposeCount, ExecuteCount, CloseCount: longint;
  SavedWorker: TThreadFunc;
  SavedData: pointer;
  OriginalHandle, WaitHandle, WorkerEntered, WorkerRelease, HostWindow: THandle;
  WorkerResult: PtrInt;
  RaiseInShell, FailInShell, BlockInShell, WorkerSawDestroyedHost: boolean;
  CapturedExe, CapturedParams, CapturedDir: WideString;
  CapturedMask, CapturedSize: DWORD;
  CapturedShow: integer;
  CapturedWindow, CapturedProcess: THandle;
  ClosedHandle: THandle;
  CloseSucceeded: boolean;
  OverwriteLastErrorOnDispose: Boolean;
  COMStatus: HRESULT;
  UninitializeCount: Integer;

function GetProcessHandleCount(process: THandle; var count: DWORD): BOOL;
  stdcall; external 'kernel32.dll' name 'GetProcessHandleCount';

procedure RecordDisposal;
begin
  InterlockedIncrement(DisposeCount);
  if OverwriteLastErrorOnDispose then SetLastError(ERROR_INVALID_HANDLE);
end;

function CloseWorkerHandle(handle: THandle): boolean;
begin
  Inc(CloseCount);
  ClosedHandle := handle;
  result := Windows.CloseHandle(handle);
  CloseSucceeded := result;
end;

function ExecuteShell(var info: TShellExecuteInfoW): boolean;
begin
  InterlockedIncrement(ExecuteCount);
  if BlockInShell then
  begin
    SetEvent(WorkerEntered);
    if WaitForSingleObject(WorkerRelease, 5000) <> WAIT_OBJECT_0 then
      raise Exception.Create('Worker release timed out');
    WorkerSawDestroyedHost := not IsWindow(HostWindow);
  end;
  CapturedExe := info.lpFile;
  CapturedParams := info.lpParameters;
  CapturedDir := info.lpDirectory;
  CapturedMask := info.fMask;
  CapturedSize := info.cbSize;
  CapturedShow := info.nShow;
  CapturedWindow := info.wnd;
  CapturedProcess := info.hProcess;
  if RaiseInShell then raise Exception.Create('Simulated Shell failure');
  result := not FailInShell;
  if not Result then SetLastError(ERROR_ACCESS_DENIED);
end;

function StartWorker(worker: TThreadFunc; data: pointer): TThreadID;
begin
  Inc(StartCount);
  if StartMode = smFailure then begin SetLastError(ERROR_NOT_ENOUGH_MEMORY); exit(0); end;
  if StartMode = smException then
    raise EThreadCreationFailure.Create('Simulated thread creation failure');

  if StartMode = smReal then
  begin
    result := BeginThread(worker, data);
    OriginalHandle := THandle(result);
    if result <> 0 then
      DuplicateHandle(GetCurrentProcess, OriginalHandle, GetCurrentProcess,
        @WaitHandle, 0, false, DUPLICATE_SAME_ACCESS);
    exit;
  end;

  OriginalHandle := CreateEventW(nil, true, false, nil);
  if OriginalHandle = 0 then RaiseLastOSError;
  result := TThreadID(OriginalHandle);
  if StartMode = smImmediate then
    WorkerResult := worker(data)
  else
  begin
    SavedWorker := worker;
    SavedData := data;
  end;
end;

procedure TRunThreadTests.SetUp;
begin
  StartMode := smDeferred;
  OverwriteLastErrorOnDispose := False;
  RunInitializeHook := nil; RunUninitializeHook := nil; UninitializeCount := 0;
  StartCount := 0;
  DisposeCount := 0;
  ExecuteCount := 0;
  CloseCount := 0;
  ClosedHandle := 0;
  CloseSucceeded := false;
  SavedWorker := nil;
  SavedData := nil;
  OriginalHandle := 0;
  WaitHandle := 0;
  HostWindow := 0;
  WorkerResult := -1;
  RaiseInShell := false;
  FailInShell := false;
  BlockInShell := false;
  WorkerSawDestroyedHost := false;
  CapturedExe := '';
  CapturedParams := '';
  CapturedDir := '';
  CapturedMask := 0;
  CapturedSize := 0;
  CapturedShow := 0;
  CapturedWindow := 0;
  CapturedProcess := 0;
  WorkerEntered := CreateEventW(nil, true, false, nil);
  WorkerRelease := CreateEventW(nil, true, false, nil);
  if (WorkerEntered = 0) or (WorkerRelease = 0) then RaiseLastOSError;
  RunStartHook := StartWorker;
  RunExecuteHook := ExecuteShell;
  RunDisposeHook := RecordDisposal;
  RunCloseHook := CloseWorkerHandle;
end;

procedure TRunThreadTests.CompleteDeferredWorker;
var worker: TThreadFunc; data: pointer;
begin
  AssertTrue('Deferred worker exists', Assigned(SavedWorker));
  worker := SavedWorker;
  data := SavedData;
  SavedWorker := nil;
  SavedData := nil;
  WorkerResult := worker(data);
end;

procedure TRunThreadTests.TearDown;
begin
  SetEvent(WorkerRelease);
  if Assigned(SavedWorker) then CompleteDeferredWorker;
  if WaitHandle <> 0 then
  begin
    AssertEquals('Worker finishes', int64(WAIT_OBJECT_0),
      int64(WaitForSingleObject(WaitHandle, 10000)));
    CloseHandle(WaitHandle);
    WaitHandle := 0;
  end;
  if IsWindow(HostWindow) then DestroyWindow(HostWindow);
  CloseHandle(WorkerEntered);
  CloseHandle(WorkerRelease);
  RunStartHook := nil;
  RunExecuteHook := nil;
  RunDisposeHook := nil;
  RunCloseHook := nil;
  RunInitializeHook := nil;
  RunUninitializeHook := nil;
end;

procedure TRunThreadTests.BoundaryInputsPreserveAllFields;
const Lengths: array[0..3] of Integer = (1023, 1024, 32765, 32766);
var N, Field: Integer; Text, Exe, Params, Dir: WideString;
begin
  for N in Lengths do
    for Field := 0 to 2 do
    begin
      Text := WideString(StringOfChar('x', N - 2)) + WideChar($D83D) + WideChar($DE80);
      Exe := 'app.exe'; Params := ''; Dir := '';
      case Field of 0: Exe := Text; 1: Params := Text; 2: Dir := Text; end;
      AssertTrue(StartDetachedRun(Exe, Params, Dir, SW_SHOWNORMAL));
      CompleteDeferredWorker;
      AssertTrue(CapturedExe = Exe);
      AssertTrue(CapturedParams = Params);
      AssertTrue(CapturedDir = Dir);
    end;
  AssertEquals(12, DisposeCount);
end;
procedure TRunThreadTests.InvalidUnicodeAndNullRejectBeforeCreation;
var Field, Kind: Integer; Text, Exe, Params, Dir: WideString; Raised: Boolean;
begin
  for Kind := 0 to 1 do
    for Field := 0 to 2 do
    begin
      if Kind = 0 then Text := 'a' + #0 + 'b' else Text := WideChar($D800);
      Exe := 'app.exe'; Params := ''; Dir := '';
      case Field of 0: Exe := Text; 1: Params := Text; 2: Dir := Text; end;
      Raised := False;
      try StartDetachedRun(Exe, Params, Dir, SW_SHOWNORMAL);
      except on ERangeError do Raised := True; on EConvertError do Raised := True; end;
      AssertTrue(Raised);
    end;
  AssertEquals(0, StartCount); AssertEquals(0, DisposeCount);
end;
procedure TRunThreadTests.CreationFailurePreservesNativeError;
begin
  StartMode := smFailure; OverwriteLastErrorOnDispose := True;
  AssertFalse(StartDetachedRun('app.exe', '', '', SW_SHOWNORMAL));
  AssertEquals(ERROR_NOT_ENOUGH_MEMORY, GetLastError);
  AssertEquals(1, DisposeCount);
end;
function FailHandleClose(Handle: THandle): Boolean;
begin CloseWorkerHandle(Handle); SetLastError(ERROR_INVALID_HANDLE); Result := False; end;
procedure TRunThreadTests.HandleCleanupFailureKeepsWorkerOwnership;
var Raised: Boolean;
begin
  RunCloseHook := FailHandleClose;
  Raised := False;
  try StartDetachedRun('app.exe', '', '', SW_SHOWNORMAL);
  except on E: ELaunchFailure do
  begin
    Raised := True;
    AssertEquals(Ord(lsHandleCleanup), Ord(E.Outcome.Stage));
    AssertEquals(ERROR_INVALID_HANDLE, E.Outcome.Win32Code);
  end; end;
  AssertTrue(Raised);
  AssertEquals('Worker still owns pending data', 0, DisposeCount);
  CompleteDeferredWorker;
  AssertEquals(1, DisposeCount);
  CheckOriginalHandleClosed;
end;
function InitializeCOM: HRESULT;
begin Result := COMStatus; end;
procedure UninitializeCOM;
begin Inc(UninitializeCount); end;
procedure TRunThreadTests.COMFailureReportsWithoutUninitializing;
var Reports: ILaunchResultQueue; Value: TLaunchResult;
begin
  Reports := NewLaunchResultQueue;
  RunInitializeHook := InitializeCOM; RunUninitializeHook := UninitializeCOM;
  COMStatus := HRESULT($80010106);
  AssertTrue(StartDetachedRun('app.exe', '', '', SW_SHOWNORMAL, Reports));
  CompleteDeferredWorker;
  AssertTrue(Reports.TryTake(Value));
  AssertEquals(Ord(lsCOM), Ord(Value.Stage));
  AssertEquals(Int64(COMStatus), Int64(Value.Status));
  AssertEquals(0, ExecuteCount); AssertEquals(0, UninitializeCount); AssertEquals(1, DisposeCount);
end;
procedure TRunThreadTests.COMSuccessBalancesUninitialization;
var I: Integer; Reports: ILaunchResultQueue; Value: TLaunchResult;
begin
  Reports := NewLaunchResultQueue;
  RunInitializeHook := InitializeCOM; RunUninitializeHook := UninitializeCOM;
  for I := 0 to 1 do
  begin
    COMStatus := I;
    AssertTrue(StartDetachedRun('app.exe', '', '', SW_SHOWNORMAL, Reports));
    CompleteDeferredWorker;
  end;
  AssertEquals(2, ExecuteCount); AssertEquals(2, UninitializeCount); AssertEquals(2, DisposeCount);
  AssertFalse('Successful workers queue no error', Reports.TryTake(Value));
end;
procedure TRunThreadTests.WorkerExceptionReportsWithoutEscaping;
var Reports: ILaunchResultQueue; Value: TLaunchResult;
begin
  Reports := NewLaunchResultQueue;
  RaiseInShell := True;
  RunInitializeHook := InitializeCOM; RunUninitializeHook := UninitializeCOM; COMStatus := 0;
  AssertTrue(StartDetachedRun('app.exe', '', '', SW_SHOWNORMAL, Reports));
  CompleteDeferredWorker;
  AssertTrue(Reports.TryTake(Value));
  AssertTrue(Pos('Simulated Shell failure', Value.Detail) > 0);
  AssertEquals(1, UninitializeCount); AssertEquals(1, DisposeCount);
end;
procedure TRunThreadTests.ClosedQueueOutlivesItsCaller;
var Reports: ILaunchResultQueue;
begin
  Reports := NewLaunchResultQueue;
  StartMode := smReal; BlockInShell := True; FailInShell := True;
  AssertTrue(StartDetachedRun('app.exe', '', '', SW_SHOWNORMAL, Reports));
  AssertEquals(Int64(WAIT_OBJECT_0), Int64(WaitForSingleObject(WorkerEntered, 5000)));
  Reports.Close;
  Reports := nil;
  SetEvent(WorkerRelease);
  AssertEquals(Int64(WAIT_OBJECT_0), Int64(WaitForSingleObject(WaitHandle, 5000)));
  AssertEquals(1, DisposeCount);
end;
function ParallelFailure(var Info: TShellExecuteInfoW): Boolean;
begin
  InterlockedIncrement(ExecuteCount);
  Info.hInstApp := HINST(5);
  SetLastError(ERROR_ACCESS_DENIED);
  Result := False;
end;
procedure TRunThreadTests.ParallelFailuresRetainEveryResult;
var Reports: ILaunchResultQueue; Value: TLaunchResult; Handles: array[0..15] of THandle;
    I, Count: Integer;
begin
  Reports := NewLaunchResultQueue;
  StartMode := smReal; FailInShell := True;
  RunExecuteHook := ParallelFailure;
  FillChar(Handles, SizeOf(Handles), 0);
  try
    for I := 0 to High(Handles) do
    begin
      AssertTrue(StartDetachedRun('app.exe', WideString(IntToStr(I)), '', SW_SHOWNORMAL, Reports));
      Handles[I] := WaitHandle; WaitHandle := 0;
    end;
    for I := 0 to High(Handles) do
      AssertEquals(Int64(WAIT_OBJECT_0), Int64(WaitForSingleObject(Handles[I], 5000)));
    Count := 0;
    while Reports.TryTake(Value) do
    begin Inc(Count); AssertEquals(ERROR_ACCESS_DENIED, Value.Win32Code); end;
    AssertEquals(16, Count); AssertEquals(16, DisposeCount);
  finally
    for I := 0 to High(Handles) do if Handles[I] <> 0 then CloseHandle(Handles[I]);
  end;
end;

procedure TRunThreadTests.CheckOriginalHandleClosed;
begin
  AssertEquals('Close the original handle exactly once', 1, CloseCount);
  AssertEquals('Close the returned handle', QWord(OriginalHandle), QWord(ClosedHandle));
  AssertTrue('Windows accepted handle closure', CloseSucceeded);
end;

procedure TRunThreadTests.WorkerOwnsCopiedParameters;
var exename, params, dir: WideString;
begin
  exename := WideString(WideChar($0416)) + ' program.exe';
  params := '--name "two words"';
  dir := 'C:\launch directory';
  AssertTrue(StartDetachedRun(exename, params, dir, SW_SHOWMINIMIZED));
  AssertEquals('Worker owns pending data', 0, DisposeCount);
  CheckOriginalHandleClosed;
  exename := 'changed';
  params := 'changed';
  dir := 'changed';
  CompleteDeferredWorker;
  AssertTrue(CapturedExe = WideString(WideChar($0416)) + ' program.exe');
  AssertTrue(CapturedParams = '--name "two words"');
  AssertTrue(CapturedDir = 'C:\launch directory');
  AssertEquals(SW_SHOWMINIMIZED, CapturedShow);
  AssertEquals(1, ExecuteCount);
  AssertEquals(1, DisposeCount);
  AssertEquals(int64(0), int64(WorkerResult));
end;

procedure TRunThreadTests.CreationFailureFreesParameters;
begin
  StartMode := smFailure;
  AssertFalse(StartDetachedRun('app.exe', '', '', SW_SHOWNORMAL));
  AssertEquals(1, StartCount);
  AssertEquals(0, ExecuteCount);
  AssertEquals(1, DisposeCount);
  AssertFalse(Assigned(SavedWorker));
end;

procedure TRunThreadTests.CreationExceptionFreesParameters;
var raised: boolean;
begin
  StartMode := smException;
  raised := false;
  try
    StartDetachedRun('app.exe', '', '', SW_SHOWNORMAL);
  except
    on EThreadCreationFailure do raised := true;
  end;
  AssertTrue(raised);
  AssertEquals(1, DisposeCount);
  AssertEquals(0, ExecuteCount);
end;

procedure TRunThreadTests.ImmediateCompletionClosesHandleOnce;
begin
  StartMode := smImmediate;
  AssertTrue(StartDetachedRun('app.exe', '', '', SW_SHOWNORMAL));
  AssertEquals(1, DisposeCount);
  AssertEquals(1, ExecuteCount);
  AssertEquals(int64(0), int64(WorkerResult));
  CheckOriginalHandleClosed;
end;

procedure TRunThreadTests.WorkerExceptionFreesParameters;
begin
  RaiseInShell := true;
  AssertTrue(StartDetachedRun('app.exe', '', '', SW_SHOWNORMAL));
  CompleteDeferredWorker;
  AssertEquals(1, DisposeCount);
  AssertEquals(int64(1), int64(WorkerResult));
end;

procedure TRunThreadTests.ShellFailureFreesParameters;
begin
  FailInShell := true;
  AssertTrue(StartDetachedRun('app.exe', '', '', SW_SHOWNORMAL));
  CompleteDeferredWorker;
  AssertEquals(1, DisposeCount);
  AssertEquals(int64(1), int64(WorkerResult));
end;

procedure TRunThreadTests.ShellFailureReachesIndependentQueue;
var Reports: ILaunchResultQueue; Value: TLaunchResult;
begin
  Reports := NewLaunchResultQueue;
  FailInShell := True;
  AssertTrue(StartDetachedRun('missing.exe', '', '', SW_SHOWNORMAL, Reports));
  AssertFalse('Creation does not report successful activation', Reports.TryTake(Value));
  CompleteDeferredWorker;
  AssertTrue('Worker returns its launch failure', Reports.TryTake(Value));
  AssertEquals(ERROR_ACCESS_DENIED, Value.Win32Code);
  AssertEquals('missing.exe', UTF8Encode(Value.Target));
  AssertEquals(Ord(lsShell), Ord(Value.Stage));
  AssertFalse('Report appears once', Reports.TryTake(Value));
  AssertEquals(1, DisposeCount);
end;

procedure TRunThreadTests.WorkerUsesNoAsyncWithoutProcessHandle;
begin
  AssertTrue(StartDetachedRun('app.exe', '', '', SW_SHOWNORMAL));
  CompleteDeferredWorker;
  AssertTrue(CapturedMask and SEE_MASK_NOASYNC <> 0);
  AssertTrue(CapturedMask and SEE_MASK_NOCLOSEPROCESS = 0);
  AssertEquals(int64(SizeOf(TShellExecuteInfoW)), int64(CapturedSize));
  AssertEquals(int64(0), int64(CapturedWindow));
  AssertEquals(int64(0), int64(CapturedProcess));
end;

procedure TRunThreadTests.AcceptsMaximumLengthInputs;
var text: WideString;
begin
  text := WideString(StringOfChar('x', MAX_RUN_TEXT_LENGTH));
  AssertTrue(StartDetachedRun(text, text, text, SW_SHOWNORMAL));
  CompleteDeferredWorker;
  AssertTrue(CapturedExe = text);
  AssertTrue(CapturedParams = text);
  AssertTrue(CapturedDir = text);
  AssertEquals(1, DisposeCount);
end;

procedure TRunThreadTests.AcceptsPreviouslyOversizedInputs;
var Text: WideString; Accepted: Boolean;
begin
  Text := WideString(StringOfChar('x', 1024)) + WideChar($0416);
  Accepted := False;
  try Accepted := StartDetachedRun(Text, Text, Text, SW_SHOWNORMAL);
  except on ERangeError do ; end;
  AssertTrue('Worker accepts complete text beyond 1023 units', Accepted);
  CompleteDeferredWorker;
  AssertTrue(CapturedExe = Text);
  AssertTrue(CapturedParams = Text);
  AssertTrue(CapturedDir = Text);
  AssertEquals(1, DisposeCount);
end;

procedure TRunThreadTests.CheckOversizedInput(field: integer);
var exename, params, dir, oversized: WideString; raised: boolean;
begin
  exename := 'app.exe';
  params := '';
  dir := '';
  oversized := WideString(StringOfChar('x', MAX_RUN_TEXT_LENGTH + 1));
  case field of
    0: exename := oversized;
    1: params := oversized;
    2: dir := oversized;
  end;
  raised := false;
  try
    StartDetachedRun(exename, params, dir, SW_SHOWNORMAL);
  except
    on ERangeError do raised := true;
  end;
  AssertTrue('Oversized input is rejected', raised);
  AssertEquals('No thread starts', 0, StartCount);
  AssertEquals('No data was allocated', 0, DisposeCount);
  AssertEquals('No Shell call', 0, ExecuteCount);
end;

procedure TRunThreadTests.RejectsOversizedFilename;
begin
  CheckOversizedInput(0);
end;

procedure TRunThreadTests.RejectsOversizedParameters;
begin
  CheckOversizedInput(1);
end;

procedure TRunThreadTests.RejectsOversizedDirectory;
begin
  CheckOversizedInput(2);
end;

procedure TRunThreadTests.WorkerCompletesAfterHostWindowDestruction;
begin
  HostWindow := CreateWindowExW(0, 'STATIC', 'Launch test', WS_POPUP,
    0, 0, 1, 1, 0, 0, HInstance, nil);
  AssertTrue(HostWindow <> 0);
  StartMode := smReal;
  BlockInShell := true;
  AssertTrue(StartDetachedRun('app.exe', 'shutdown', '', SW_SHOWNORMAL));
  AssertTrue('Test owns a separate wait handle', WaitHandle <> 0);
  AssertEquals(int64(WAIT_OBJECT_0),
    int64(WaitForSingleObject(WorkerEntered, 5000)));
  CheckOriginalHandleClosed;
  AssertEquals('Worker still owns data', 0, DisposeCount);
  AssertTrue(DestroyWindow(HostWindow));
  // Clear caller hooks before completion. The worker uses its own snapshot.
  RunStartHook := nil;
  RunExecuteHook := nil;
  RunDisposeHook := nil;
  SetEvent(WorkerRelease);
  AssertEquals(int64(WAIT_OBJECT_0), int64(WaitForSingleObject(WaitHandle, 5000)));
  AssertTrue(WorkerSawDestroyedHost);
  AssertTrue(CapturedParams = 'shutdown');
  AssertEquals(1, DisposeCount);
end;

procedure TRunThreadTests.RepeatedWorkersDoNotLeakHandles;
var beforeCount, afterCount: DWORD; i: integer;
begin
  StartMode := smReal;
  // Warm up COM and the Windows thread runtime before counting handles.
  AssertTrue(StartDetachedRun('app.exe', '', '', SW_SHOWNORMAL));
  AssertTrue(WaitHandle <> 0);
  AssertEquals(int64(WAIT_OBJECT_0), int64(WaitForSingleObject(WaitHandle, 5000)));
  CloseHandle(WaitHandle);
  WaitHandle := 0;
  AssertTrue(GetProcessHandleCount(GetCurrentProcess, beforeCount));
  for i := 1 to 32 do
  begin
    AssertTrue(StartDetachedRun('app.exe', '', '', SW_SHOWNORMAL));
    AssertTrue(WaitHandle <> 0);
    AssertEquals(int64(WAIT_OBJECT_0), int64(WaitForSingleObject(WaitHandle, 5000)));
    CloseHandle(WaitHandle);
    WaitHandle := 0;
  end;
  AssertTrue(GetProcessHandleCount(GetCurrentProcess, afterCount));
  AssertEquals(int64(beforeCount), int64(afterCount));
  AssertEquals(33, ExecuteCount);
  AssertEquals(33, DisposeCount);
  AssertEquals('Each worker handle closes once', 33, CloseCount);
end;

initialization
  RegisterTest(TRunThreadTests);
end.
