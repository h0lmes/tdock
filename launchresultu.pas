unit launchresultu;
{$mode delphi}
interface
uses Windows, SysUtils, SyncObjs;
type
  TLaunchStage = (lsPreparation, lsThreadCreation, lsCOM, lsShell, lsActivation, lsHandleCleanup);
  TLaunchResult = record
    Stage: TLaunchStage;
    Target, Detail, Route: UnicodeString;
    Win32Code: DWORD;
    ShellCode: PtrInt;
    Status: HRESULT;
  end;
  ELaunchFailure = class(Exception)
  public
    Outcome: TLaunchResult;
    constructor Create(const Value: TLaunchResult);
  end;
  ILaunchResultQueue = interface
    ['{DC3543A7-4912-4777-B201-C989ABFF31B9}']
    procedure Enqueue(const Value: TLaunchResult);
    function TryTake(out Value: TLaunchResult): Boolean;
    procedure Close;
  end;
function LaunchFailure(Stage: TLaunchStage; const Target: UnicodeString;
  Win32Code: DWORD = 0; Status: HRESULT = 0; ShellCode: PtrInt = 0): TLaunchResult;
function LaunchException(Stage: TLaunchStage; const Target: UnicodeString; E: Exception): TLaunchResult;
function LaunchResultMessage(const Value: TLaunchResult): UnicodeString;
function NewLaunchResultQueue: ILaunchResultQueue;
implementation
uses ComObj;
type
  PLaunchNode = ^TLaunchNode;
  TLaunchNode = record
    Value: TLaunchResult;
    Next: PLaunchNode;
  end;
  TLaunchResultQueue = class(TInterfacedObject, ILaunchResultQueue)
  private
    FLock: TCriticalSection;
    FHead, FTail: PLaunchNode;
    FClosed: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Enqueue(const Value: TLaunchResult);
    function TryTake(out Value: TLaunchResult): Boolean;
    procedure Close;
  end;
function LaunchFailure(Stage: TLaunchStage; const Target: UnicodeString;
  Win32Code: DWORD; Status: HRESULT; ShellCode: PtrInt): TLaunchResult;
begin
  Result := Default(TLaunchResult);
  Result.Stage := Stage;
  Result.Target := Target;
  Result.Win32Code := Win32Code;
  Result.Status := Status;
  Result.ShellCode := ShellCode;
end;
function LaunchException(Stage: TLaunchStage; const Target: UnicodeString; E: Exception): TLaunchResult;
begin
  if E is ELaunchFailure then Result := ELaunchFailure(E).Outcome
  else if E is EOSError then Result := LaunchFailure(Stage, Target, EOSError(E).ErrorCode)
  else if E is EOleSysError then Result := LaunchFailure(Stage, Target, 0, EOleSysError(E).ErrorCode)
  else begin
    Result := LaunchFailure(Stage, Target);
    Result.Detail := UTF8Decode(E.Message);
  end;
  if Result.Target = '' then Result.Target := Target;
end;
function SystemMessage(Code: DWORD): UnicodeString;
var Buffer: PWideChar; Count: DWORD;
begin
  Result := '';
  Buffer := nil;
  Count := FormatMessageW(FORMAT_MESSAGE_ALLOCATE_BUFFER or FORMAT_MESSAGE_FROM_SYSTEM or
    FORMAT_MESSAGE_IGNORE_INSERTS, nil, Code, 0, @Buffer, 0, nil);
  if Count <> 0 then
    try SetString(Result, Buffer, Count); Result := Trim(Result);
    finally LocalFree(HLOCAL(Buffer)); end;
end;
function ShellMessage(Code: PtrInt): UnicodeString;
begin
  case Code of
    2: Result := 'Target file was not found';
    3: Result := 'Target directory was not found';
    5: Result := 'Access was denied';
    8: Result := 'Windows has insufficient memory';
    26: Result := 'A sharing violation prevented launch';
    27: Result := 'The file association is incomplete';
    28: Result := 'The handler timed out';
    29: Result := 'The handler failed its DDE request';
    30: Result := 'The handler is busy';
    31: Result := 'No application handles this target';
    32: Result := 'A required library was not found';
    else Result := '';
  end;
end;
function LaunchResultMessage(const Value: TLaunchResult): UnicodeString;
const Names: array[TLaunchStage] of UnicodeString = ('Launch preparation', 'Thread creation',
  'COM initialization', 'Shell launch', 'Application activation', 'Thread handle cleanup');
var Description, Codes: UnicodeString;
begin
  Description := Value.Detail;
  Codes := '';
  if Value.Win32Code <> 0 then
  begin
    Codes := 'Win32 ' + UnicodeString(IntToStr(Value.Win32Code));
    if Description = '' then Description := SystemMessage(Value.Win32Code);
  end;
  if Value.Status <> 0 then
  begin
    if Codes <> '' then Codes := Codes + ', ';
    Codes := Codes + 'HRESULT 0x' + UnicodeString(IntToHex(DWORD(Value.Status), 8));
    if Description = '' then Description := SystemMessage(DWORD(Value.Status));
    if (Description = '') and ((DWORD(Value.Status) and $1FFF0000) = $00070000) then
      Description := SystemMessage(DWORD(Value.Status) and $FFFF);
  end;
  if (Value.ShellCode > 0) and (Value.ShellCode <= 32) then
  begin
    if Codes <> '' then Codes := Codes + ', ';
    Codes := Codes + 'Shell ' + UnicodeString(IntToStr(Value.ShellCode));
    if Description = '' then Description := ShellMessage(Value.ShellCode);
  end;
  if Description = '' then Description := 'Windows did not provide an error description';
  Result := Names[Value.Stage] + ' failed';
  if Value.Route <> '' then Result := Value.Route + ': ' + Result;
  if Codes <> '' then Result := Result + ' (' + Codes + ')';
  Result := Result + ': ' + Description;
  if Value.Target <> '' then Result := Result + UnicodeString(LineEnding) + Value.Target;
end;
constructor ELaunchFailure.Create(const Value: TLaunchResult);
begin
  Outcome := Value;
  inherited Create(UTF8Encode(LaunchResultMessage(Value)));
end;
constructor TLaunchResultQueue.Create;
begin inherited Create; FLock := TCriticalSection.Create; end;
destructor TLaunchResultQueue.Destroy;
begin if FLock <> nil then Close; FLock.Free; inherited Destroy; end;
procedure TLaunchResultQueue.Enqueue(const Value: TLaunchResult);
var Node: PLaunchNode;
begin
  New(Node);
  try
    Node^.Value := Value;
    Node^.Next := nil;
    FLock.Acquire;
    try
      if FClosed then Exit;
      if FTail = nil then FHead := Node else FTail^.Next := Node;
      FTail := Node;
      Node := nil;
    finally FLock.Release; end;
  finally if Node <> nil then Dispose(Node); end;
end;
function TLaunchResultQueue.TryTake(out Value: TLaunchResult): Boolean;
var Node: PLaunchNode;
begin
  Value := Default(TLaunchResult);
  FLock.Acquire;
  try
    Node := FHead;
    Result := Node <> nil;
    if not Result then Exit;
    FHead := Node^.Next;
    if FHead = nil then FTail := nil;
  finally FLock.Release; end;
  try Value := Node^.Value; finally Dispose(Node); end;
end;
procedure TLaunchResultQueue.Close;
var Node, Next: PLaunchNode;
begin
  FLock.Acquire;
  try
    FClosed := True;
    Node := FHead;
    FHead := nil;
    FTail := nil;
  finally FLock.Release; end;
  while Node <> nil do
  begin Next := Node^.Next; Dispose(Node); Node := Next; end;
end;
function NewLaunchResultQueue: ILaunchResultQueue;
begin Result := TLaunchResultQueue.Create; end;
end.
