unit runthreadu;

{$mode delphi}

interface

uses Windows, SysUtils, ShellAPI, shelltextu, launchresultu;

const
  MAX_RUN_TEXT_LENGTH = SHELL_TEXT_LIMIT;
  // FPC 3.2.2 exports this flag under its older name.
  SEE_MASK_NOASYNC = SEE_MASK_FLAG_DDEWAIT;

// False means thread creation failed. Oversized inputs raise ERangeError.
function StartDetachedRun(const exename, params, dir: WideString;
  showcmd: integer; const Reports: ILaunchResultQueue = nil): boolean;

{$ifdef RUNTHREAD_TESTS}
type
  TRunStartHook = function(worker: TThreadFunc; data: pointer): TThreadID;
  TRunExecuteHook = function(var info: TShellExecuteInfoW): boolean;
  TRunDisposeHook = procedure;
  TRunCloseHook = function(handle: THandle): boolean;
  TRunInitializeHook = function: HRESULT;
  TRunUninitializeHook = procedure;

var
  RunStartHook: TRunStartHook = nil;
  RunExecuteHook: TRunExecuteHook = nil;
  RunDisposeHook: TRunDisposeHook = nil;
  RunCloseHook: TRunCloseHook = nil;
  RunInitializeHook: TRunInitializeHook = nil;
  RunUninitializeHook: TRunUninitializeHook = nil;
{$endif}

implementation

uses ActiveX;

type
  PRunData = ^TRunData;
  TRunData = record
    exename, params, dir: WideString;
    showcmd: integer;
    Reports: ILaunchResultQueue;
    {$ifdef RUNTHREAD_TESTS}
    ExecuteHook: TRunExecuteHook;
    DisposeHook: TRunDisposeHook;
    InitializeHook: TRunInitializeHook;
    UninitializeHook: TRunUninitializeHook;
    {$endif}
  end;

procedure FreeRunData(data: PRunData);
begin
  {$ifdef RUNTHREAD_TESTS}
  if Assigned(data^.DisposeHook) then data^.DisposeHook;
  {$endif}
  Dispose(data);
end;

function RunThread(p: pointer): PtrInt;
var
  data: PRunData;
  info: TShellExecuteInfoW;
  Status: HRESULT;
  Executed: Boolean;
  Error: DWORD;
  Failure: TLaunchResult;
  Stage: TLaunchStage;
  procedure SendFailure(const Value: TLaunchResult);
  var Report: TLaunchResult;
  begin
    // Reporting must never bypass worker cleanup, including allocation failures.
    try
      if data^.Reports = nil then Exit;
      Report := Value;
      Report.Route := 'Threaded';
      if Pos(':', data^.exename) > 2 then Report.Route := 'Threaded URI';
      data^.Reports.Enqueue(Report);
    except end;
  end;
begin
  data := PRunData(p);
  result := 1;
  Stage := lsCOM;
  try
    try
      {$ifdef RUNTHREAD_TESTS}
      if Assigned(data^.InitializeHook) then Status := data^.InitializeHook
      else
      {$endif}
        Status := CoInitializeEx(nil, COINIT_APARTMENTTHREADED or COINIT_DISABLE_OLE1DDE);
      if Status < 0 then
      begin
        SendFailure(LaunchFailure(lsCOM, data^.exename, 0, Status));
        Exit;
      end;
      try
        Stage := lsShell;
        FillChar(info, SizeOf(info), 0);
        info.cbSize := SizeOf(info);
        info.fMask := SEE_MASK_NOASYNC or SEE_MASK_FLAG_NO_UI;
        info.lpFile := PWideChar(data^.exename);
        info.lpParameters := PWideChar(data^.params);
        info.lpDirectory := PWideChar(data^.dir);
        info.nShow := data^.showcmd;
        SetLastError(0);
        {$ifdef RUNTHREAD_TESTS}
        if Assigned(data^.ExecuteHook) then
          Executed := data^.ExecuteHook(info)
        else
        {$endif}
          Executed := ShellExecuteExW(@info);
        Error := GetLastError;
        if Executed then Result := 0
        else SendFailure(LaunchFailure(lsShell, data^.exename, Error, 0, PtrInt(info.hInstApp)));
      finally
        {$ifdef RUNTHREAD_TESTS}
        if Assigned(data^.UninitializeHook) then data^.UninitializeHook
        else
        {$endif}
          CoUninitialize;
      end;
    except on E: Exception do
    begin
      // Detached workers must not call the form or propagate exceptions.
      result := 1;
      try
        Failure := LaunchException(Stage, data^.exename, E);
        SendFailure(Failure);
      except end;
    end;
    end;
  finally
    FreeRunData(data);
  end;
end;

function StartDetachedRun(const exename, params, dir: WideString;
  showcmd: integer; const Reports: ILaunchResultQueue): boolean;
var
  data: PRunData;
  threadHandle: TThreadID;
  StartError: DWORD;
begin
  // Validate every input before allocation or copying.
  CheckShellText(exename);
  CheckShellText(params);
  CheckShellText(dir);

  New(data);
  {$ifdef RUNTHREAD_TESTS}
  data^.ExecuteHook := RunExecuteHook;
  data^.DisposeHook := RunDisposeHook;
  data^.InitializeHook := RunInitializeHook;
  data^.UninitializeHook := RunUninitializeHook;
  {$endif}
  try
    data^.exename := exename;
    data^.params := params;
    data^.dir := dir;
    data^.showcmd := showcmd;
    data^.Reports := Reports;
    SetLastError(0);
    {$ifdef RUNTHREAD_TESTS}
    if Assigned(RunStartHook) then
      threadHandle := RunStartHook(RunThread, data)
    else
    {$endif}
      threadHandle := BeginThread(RunThread, data);
    StartError := GetLastError;
    result := threadHandle <> 0;
    if result then
    begin
      // The worker can already have freed data. Change only the local pointer.
      data := nil;
      // Windows permits closure while the detached worker still runs.
      {$ifdef RUNTHREAD_TESTS}
      if Assigned(RunCloseHook) then
      begin
        if not RunCloseHook(THandle(threadHandle)) then
          raise ELaunchFailure.Create(LaunchFailure(lsHandleCleanup, exename, GetLastError));
      end
      else
      {$endif}
      if not Windows.CloseHandle(THandle(threadHandle)) then
        raise ELaunchFailure.Create(LaunchFailure(lsHandleCleanup, exename, GetLastError));
    end;
  finally
    if Assigned(data) then FreeRunData(data);
  end;
  if not Result then SetLastError(StartError);
end;

end.
