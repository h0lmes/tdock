unit DropTgtU;

interface

uses Windows, Classes, SysUtils, ActiveX, ShlObj, ShellAPI, PIDL, declu, loggeru, dropimportu;

type
  TDropTarget = class;

  TProc = procedure of object;
  TDropProc = procedure(list: TStrings; hWnd: THandle) of object;
  TDropImportBatch = dropimportu.TDropImportBatch;
  TImportDropProc = procedure(Batch: TDropImportBatch; hWnd: THandle) of object;
  TDropErrorProc = procedure(Message: WideString; Silent: Boolean) of object;

  // Life states //
  Tgwdt_ls = (gwdt_ls_start, gwdt_ls_exists, gwdt_ls_locked, gwdt_ls_regd);

  TDropManager = class
  protected
    FDropTarget: TDropTarget;
    FImportStorage: UnicodeString;
    FDragDataSupported: Boolean;
    FDragFeedbackActive: Boolean;
    procedure ResetDragFeedback;
    procedure  DropTarget_Forget;  // used by DropTarget.Destroy;
    function tymedToString(tymed: DWORD): string;
  public
    OnDragOver: TProc;
    OnDragLeave: TProc;
    OnDragReset: TProc;
    OnDrop: TImportDropProc;
    OnError: TDropErrorProc;
    OnDragEnter: TDropProc;
    property  DropTarget: TDropTarget read FDropTarget;
    property ImportStorage: UnicodeString read FImportStorage write FImportStorage;
    // Create in  OwnerForm.OnCreate, Destroy in OwnerForm.OnDestroy
    constructor Create(ADropHWnd: HWND); virtual;
    destructor  Destroy; override;
    function DropTarget_Create(ADropHWnd: HWND): HResult;
    function DropTarget_Exists: Boolean;
    function DropTarget_LifeState: Tgwdt_ls;
    // Borrows h. The caller must release its owning storage medium.
    procedure AddToListHDrop(h: HDROP; var List: TStrings);
    procedure AddToListHGlobalPIDL(h: HGLOBAL; var List: TStrings);
    procedure AddToListIStreamPIDL(h: Pointer; var List: TStrings);
    procedure MakeList(const dataObj: IDataObject; var List: TStrings);
    function DragEnter(const dataObj: IDataObject; grfKeyState: DWORD; pt: TPoint; var dwEffect: DWORD): HResult; virtual;
    function DragOver(grfKeyState: DWORD; pt: TPoint; var dwEffect: DWORD): HResult; virtual;
    function DragLeave: HResult; virtual;
    function Drop(const dataObj: IDataObject; grfKeyState: DWORD; pt: TPoint; var dwEffect: DWORD): HResult; virtual;
  end;

  TDropTarget = class(TObject, IUnknown, IDropTarget)
  private
    FDropHWND: HWND;
    FDropInterface: TDropManager;
    FLifeState: Tgwdt_ls;
    FEnable: boolean;
    FRefCount: Integer;
    procedure SetLifeState(Value: Tgwdt_ls);
  protected
    function QueryInterface(constref IID: TGUID; out Obj): longint; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
  public
    property DropHWND: HWND read FDropHWnd;
    property LifeState: Tgwdt_ls Read FLifeState Write SetLifeState;
    property Enable: Boolean Read FEnable     Write FEnable;
    property RefCount: Integer read FRefCount;

    constructor Create(ADropHWnd: HWND; ADropManager: TDropManager); virtual;
    destructor  Destroy; override;
    function ToState_Exists : HResult;
    function ToState_Locked : HResult;
    function ToState_Regd   : HResult;

    function DragEnter(const dataObj: IDataObject; grfKeyState: DWORD; pt: TPoint; var dwEffect: DWORD): HResult; stdcall;
    function DragOver(grfKeyState: DWORD; pt: TPoint; var dwEffect: DWORD): HResult; stdcall;
    function DragLeave: HResult; stdcall;
    function Drop(const dataObj: IDataObject; grfKeyState: DWORD; pt: TPoint; var dwEffect: DWORD): HResult; stdcall;
  end;

{$undef DEBUG_DROPTGT}
implementation
uses itemhostu, shelltextu;
//------------------------------------------------------------------------------
//
//
//
//    TDropManager
//
//
//
//------------------------------------------------------------------------------
constructor TDropManager.Create(ADropHWnd: HWND);
begin
  inherited Create;
  FDropTarget := nil;
  DropTarget_Create(ADropHWnd);
end;
//------------------------------------------------------------------------------
destructor TDropManager.Destroy;
begin
  if Assigned(FDropTarget) then FDropTarget.Destroy;
  inherited Destroy;
end;
//------------------------------------------------------------------------------
function TDropManager.DropTarget_Create(ADropHWnd: HWND): HResult;
begin
  result := E_UNEXPECTED;
  FDropTarget := TDropTarget.Create(ADropHWnd, Self);
  if Assigned(FDropTarget) then result := DropTarget.ToState_Regd;
end;
//------------------------------------------------------------------------------
function TDropManager.DropTarget_Exists: Boolean;
begin
  result := Assigned(FDropTarget);
end;
//------------------------------------------------------------------------------
procedure TDropManager.DropTarget_Forget;
begin
  FDropTarget := nil;
end;
//------------------------------------------------------------------------------
function TDropManager.DropTarget_LifeState: Tgwdt_ls;
begin
  if DropTarget_Exists then result := DropTarget.LifeState
  else result := gwdt_ls_Start;
end;
//------------------------------------------------------------------------------
function ValidHDrop(Handle: HDROP): Boolean;
var Data: Pointer; Size, Position, Start, Width: SizeUInt; Header: TDropFiles;
  Count: Integer; Ch: Word;
  function CharacterAt(Offset: SizeUInt): Word;
  begin
    Result := 0;
    if Width = 2 then Move(PByte(Data)[Offset], Result, 2)
    else Result := PByte(Data)[Offset];
  end;
begin
  Result := False; Size := GlobalSize(Handle);
  if (Size < SizeOf(Header) + 2) or (Size > SHELL_DATA_LIMIT) then Exit;
  Data := GlobalLock(Handle);
  if Data = nil then Exit;
  try
    Move(Data^, Header, SizeOf(Header));
    if Header.fWide then Width := 2 else Width := 1;
    Position := Header.pFiles;
    if (Position < SizeOf(Header)) or (Position > Size) or
      (Size - Position < Width * 2) or ((Position mod Width) <> 0) then Exit;
    Count := 0;
    while Position <= Size - Width do
    begin
      Ch := CharacterAt(Position);
      if Ch = 0 then Exit(Count > 0);
      Start := Position;
      repeat
        Inc(Position, Width);
        if Position > Size - Width then Exit;
      until CharacterAt(Position) = 0;
      if (Position - Start) div Width > SHELL_TEXT_LIMIT then Exit;
      Inc(Count);
      if Count > SHELL_ITEM_LIMIT then Exit;
      Inc(Position, Width);
    end;
  finally GlobalUnlock(Handle); end;
end;

procedure CheckImportedTarget(const Value: UnicodeString);
begin
  CheckShellText(Value);
  if (Value = '') or (Length(Value) > DROP_TARGET_LENGTH) then
    raise EDropTransferError.Create('Imported target exceeds 1023 UTF-16 units or is empty');
end;

procedure TDropManager.AddToListHDrop(h: HDROP; var List: TStrings);
var I, Count, Required, Copied: UINT; Buffer: array of WideChar;
  Value: UnicodeString; Candidate: TStringList;
begin
  if not ValidHDrop(h) then Exit;
  Count := DragQueryFileW(h, $FFFFFFFF, nil, 0);
  if (Count = 0) or (Count > SHELL_ITEM_LIMIT) then Exit;
  Candidate := TStringList.Create;
  try
    for I := 0 to Count - 1 do
    begin
      Required := DragQueryFileW(h, I, nil, 0);
      if (Required = 0) or (Required > SHELL_TEXT_LIMIT) then
        raise EDropTransferError.Create('Unsupported dropped path size');
      SetLength(Buffer, Required + 1);
      FillChar(Buffer[0], Length(Buffer) * SizeOf(WideChar), $FF);
      Copied := DragQueryFileW(h, I, @Buffer[0], Length(Buffer));
      if (Copied <> Required) or (Buffer[Required] <> #0) then
        raise EDropTransferError.Create('Incomplete dropped path');
      SetString(Value, PWideChar(@Buffer[0]), Copied);
      CheckImportedTarget(Value);
      Candidate.Add(ShellUTF8(Value));
    end;
    List.AddStrings(Candidate);
  finally Candidate.Free; end;
end;
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
procedure AddCIDA(Data: Pointer; Capacity: SizeUInt; List: TStrings);
var I, Count, Size: Integer; IDList: PItemIDList; Target: string; Candidate: TStringList;
begin
  Count := PIDL_CountFromCIDA(Data, Capacity);
  if Count = 0 then Exit;
  Candidate := TStringList.Create;
  try
    for I := 0 to Count - 1 do
    begin
      Size := Capacity; IDList := PIDL_FromCIDA(I, Data, Size);
      if IDList = nil then raise EOutOfMemory.Create('Cannot allocate imported Shell identity');
      try Target := PIDL_GetDisplayName2(IDList);
      finally PIDL_Free(IDList); end;
      CheckImportedTarget(ShellUTF16(Target));
      Candidate.Add(Target);
    end;
    List.AddStrings(Candidate);
  finally Candidate.Free; end;
end;

procedure TDropManager.AddToListHGlobalPIDL(h: HGLOBAL; var List: TStrings);
var Data: Pointer; Size: SizeUInt;
begin
  Size := GlobalSize(h);
  if (Size < 8) or (Size > SHELL_DATA_LIMIT) then Exit;
  Data := GlobalLock(h);
  if Data = nil then Exit;
  try AddCIDA(Data, Size, List);
  finally GlobalUnlock(h); end;
end;
//------------------------------------------------------------------------------
procedure TDropManager.AddToListIStreamPIDL(h: Pointer; var List: TStrings);
var Stream: IStream; Data: TBytes; Chunk: array[0..4095] of Byte;
  ReadCount, Request: ULONG; N: SizeUInt; Status: HRESULT;
begin
  Stream := IStream(h);
  if Stream = nil then Exit;
  Data := nil;
  repeat
    Request := SizeOf(Chunk);
    if Request > SHELL_DATA_LIMIT - Length(Data) + 1 then
      Request := SHELL_DATA_LIMIT - Length(Data) + 1;
    ReadCount := 0; Status := Stream.Read(@Chunk[0], Request, @ReadCount);
    if Failed(Status) then raise EDropTransferError.Create('Cannot read Shell identity stream');
    if (ReadCount > Request) or (SizeUInt(Length(Data)) + ReadCount > SHELL_DATA_LIMIT) then
      raise EDropTransferError.Create('Shell identity stream exceeds supported size');
    N := Length(Data); SetLength(Data, N + ReadCount);
    if ReadCount > 0 then Move(Chunk[0], Data[N], ReadCount);
  until (ReadCount = 0) or (Status = S_FALSE);
  if Length(Data) > 0 then AddCIDA(@Data[0], Length(Data), List);
end;
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
function TDropManager.tymedToString(tymed: DWORD): string;
begin
  result := '';
  if tymed and TYMED_HGLOBAL  = TYMED_HGLOBAL then  result += 'TYMED_HGLOBAL ';
  if tymed and TYMED_FILE     = TYMED_FILE then     result += 'TYMED_FILE ';
  if tymed and TYMED_ISTREAM  = TYMED_ISTREAM then  result += 'TYMED_ISTREAM ';
  if tymed and TYMED_ISTORAGE = TYMED_ISTORAGE then result += 'TYMED_ISTORAGE ';
  if tymed and TYMED_GDI      = TYMED_GDI then      result += 'TYMED_GDI ';
  if tymed and TYMED_MFPICT   = TYMED_MFPICT then   result += 'TYMED_MFPICT ';
  if tymed and TYMED_ENHMF    = TYMED_ENHMF then    result += 'TYMED_ENHMF ';
end;
//------------------------------------------------------------------------------
procedure TDropManager.MakeList(const dataObj: IDataObject; var List: TStrings);
var
  Medium: TStgMedium;
  Batch: TDropImportBatch;
  Kind: DWORD;
  I: Integer;
begin
  if dataObj = nil then Exit;
  if GetDropMedium(dataObj, CF_HDROP, TYMED_HGLOBAL, -1, Medium) then
  try
    AddToListHDrop(Medium.hGlobal, List);
  finally ReleaseStgMedium(Medium); end;
  if List.Count > 0 then Exit;
  for Kind in [DWORD(TYMED_HGLOBAL), DWORD(TYMED_ISTREAM)] do
    if GetDropMedium(dataObj, RegisterClipboardFormat('Shell IDList Array'), Kind, -1, Medium) then
    try
      if Kind = TYMED_HGLOBAL then AddToListHGlobalPIDL(Medium.hGlobal, List)
      else AddToListIStreamPIDL(Medium.pstm, List);
      if List.Count > 0 then Exit;
    finally ReleaseStgMedium(Medium); end;
  if List is TDropImportBatch then
    ImportAdditionalFormats(dataObj, TDropImportBatch(List))
  else
  begin
    Batch := TDropImportBatch.Create(FImportStorage);
    try
      if ImportAdditionalFormats(dataObj, Batch) then
      begin
        Batch.Expose;
        for I := 0 to Batch.Count - 1 do
        begin List.Add(Batch[I]); Batch.Decide(I, True); end;
      end;
    finally Batch.Free; end;
  end;
end;
//------------------------------------------------------------------------------
procedure TDropManager.ResetDragFeedback;
begin
  FDragFeedbackActive := False;
  if Assigned(OnDragReset) then
    try OnDragReset;
    except on E: Exception do AddLog('DropManager.ResetDragFeedback: ' + E.Message); end;
end;
//------------------------------------------------------------------------------
function SelectDropEffect(Allowed, Keys: DWORD): DWORD;
const ALT_KEY = $20;
begin
  // A launcher import never authorizes deletion of the source.
  if (((Keys and (MK_CONTROL or MK_SHIFT)) = (MK_CONTROL or MK_SHIFT)) or
    ((Keys and ALT_KEY) <> 0)) and ((Allowed and DROPEFFECT_LINK) <> 0) then
    Exit(DROPEFFECT_LINK);
  if (Allowed and DROPEFFECT_COPY) <> 0 then Exit(DROPEFFECT_COPY);
  if (Allowed and DROPEFFECT_LINK) <> 0 then Exit(DROPEFFECT_LINK);
  Result := DROPEFFECT_NONE;
end;
//------------------------------------------------------------------------------
function TDropManager.DragEnter(const dataObj: IDataObject; grfKeyState: DWORD; pt: TPoint; var dwEffect: DWORD): HResult;
begin
  FDragDataSupported := Assigned(OnDrop) and SupportsDropData(dataObj);
  if FDragDataSupported then dwEffect := SelectDropEffect(dwEffect, grfKeyState)
  else dwEffect := DROPEFFECT_NONE;
  result := S_OK;
  if dwEffect <> DROPEFFECT_NONE then
  begin
    FDragFeedbackActive := True;
    if Assigned(OnDragEnter) then OnDragEnter(nil, WindowFromPoint(pt));
  end
  else ResetDragFeedback;
end;
//------------------------------------------------------------------------------
function TDropManager.DragOver(grfKeyState : DWORD; pt: TPoint; var dwEffect: DWORD): HResult;
begin
  if FDragDataSupported and Assigned(OnDrop) then dwEffect := SelectDropEffect(dwEffect, grfKeyState)
  else dwEffect := DROPEFFECT_NONE;
  result := S_OK;
  if dwEffect = DROPEFFECT_NONE then
  begin
    if FDragFeedbackActive then ResetDragFeedback;
    Exit;
  end;
  if not FDragFeedbackActive then
  begin
    FDragFeedbackActive := True;
    if Assigned(OnDragEnter) then OnDragEnter(nil, WindowFromPoint(pt));
  end;
  if Assigned(OnDragOver) then OnDragOver;
end;
//------------------------------------------------------------------------------
function TDropManager.DragLeave: HResult;
begin
  FDragDataSupported := False;
  FDragFeedbackActive := False;
  if assigned(OnDragLeave) then OnDragLeave;
  result := S_OK;
end;
//------------------------------------------------------------------------------
function TDropManager.Drop(const dataObj: IDataObject; grfKeyState: DWORD; pt: TPoint; var dwEffect: DWORD): HResult;
var Batch, Empty: TDropImportBatch; List: TStrings; CallbackStarted: Boolean;
  Allowed: DWORD;
  procedure Report(const Message: string);
  begin
    AddLog('DropManager.Drop: ' + Message);
    if Assigned(OnError) then
      try OnError(UTF8Decode(Message), False); except end;
  end;
begin
  Allowed := dwEffect;
  dwEffect := DROPEFFECT_NONE;
  Result := S_OK;
  Batch := nil;
  CallbackStarted := False;
  try
    if not Assigned(OnDrop) then Exit;
    Batch := TDropImportBatch.Create(FImportStorage);
    try
      List := Batch;
      MakeList(dataObj, List);
      if Batch.Count = 0 then
      begin
        if Batch.RejectionReason <> '' then raise EInvalidDropFormat.Create(Batch.RejectionReason);
        raise EInvalidDropFormat.Create('The dropped data has no supported targets');
      end;
      // Expose records durable ownership before any consumer sees a copied path.
      Batch.Expose;
      CallbackStarted := True;
      OnDrop(Batch, WindowFromPoint(pt));
      if Batch.UndecidedCount > 0 then
        raise EDropTransferError.Create(Format(
          'Imported %d of %d dropped targets; %d outcomes remain unknown.',
          [Batch.AcceptedCount, Batch.Count, Batch.UndecidedCount]));
      if Batch.AcceptedCount > 0 then dwEffect := SelectDropEffect(Allowed, grfKeyState);
      if Batch.RejectedCount > 0 then
        Report(Format('Imported %d of %d dropped targets; %d were rejected.',
          [Batch.AcceptedCount, Batch.Count, Batch.RejectedCount]));
    except
      on E: Exception do
      begin
        if CallbackStarted and (Batch.AcceptedCount > 0) then
          Report(Format('Drop stopped after importing %d of %d targets. %s',
            [Batch.AcceptedCount, Batch.Count, E.Message]))
        else Report('Cannot import dropped data: ' + E.Message);
        // An empty callback still clears the drag state after extraction failure.
        if not CallbackStarted then
        begin
          Empty := TDropImportBatch.Create('');
          try
            Empty.Expose;
            try OnDrop(Empty, WindowFromPoint(pt)); except end;
          finally Empty.Free; end;
        end;
        Result := E_FAIL;
      end;
    end;
  finally
    FDragDataSupported := False;
    ResetDragFeedback;
    Batch.Free;
  end;
end;
//------------------------------------------------------------------------------
//
//
//
//   DropTarget
//
//
//
//------------------------------------------------------------------------------
function TDropTarget.QueryInterface(constref IID: TGUID; out Obj): longint; stdcall;
begin
  if GetInterface(IID, Obj) then result := 0 else result := longint(E_NOINTERFACE);
end;
//------------------------------------------------------------------------------
function TDropTarget._AddRef: Integer;
begin
  inc(FRefCount);
  result:= FRefCount;
end;
//------------------------------------------------------------------------------
function TDropTarget._Release: Integer;
begin
  dec(FRefCount);
  if FRefCount = 0 then
  begin
    Destroy;
    result:= 0;
  end else result:= FRefCount;
end;
//------------------------------------------------------------------------------
constructor TDropTarget.Create(ADropHWnd: HWND; ADropManager: TDropManager);
begin
  inherited Create;
  FDropHWND      := ADropHWnd;
  FDropInterface := ADropManager;
  FLifeState     := gwdt_ls_exists;
  FEnable        := true;
end;
//------------------------------------------------------------------------------
destructor TDropTarget.Destroy;
begin
  if Assigned(FDropInterface) then FDropInterface.DropTarget_Forget;
  if FLifeState > gwdt_ls_Locked then
  begin
    while RefCount < 2 do _AddRef;   // avoid retriggering destroy
    ActiveX.RevokeDragDrop(FDropHWND);
    FLifeState := gwdt_ls_Locked;
  end;

  if FLifeState > gwdt_ls_Exists then
  begin
    while RefCount < 2 do _AddRef;   // avoid retriggering destroy
    ActiveX.CoLockObjectExternal(IDropTarget(self), false, false);
    FLifeState := gwdt_ls_Exists;
  end;

  inherited Destroy;
end;
//------------------------------------------------------------------------------
function TDropTarget.ToState_Exists : HResult;
begin
  result := S_OK;
  if LifeState = gwdt_ls_Regd then result := ToState_Locked;

  if LifeState = gwdt_ls_Locked then
  begin
    LifeState := gwdt_ls_Exists;
    result := ActiveX.CoLockObjectExternal(IDropTarget(self), false, true);
  end;
end;
//------------------------------------------------------------------------------
function TDropTarget.ToState_Locked : HResult;
begin
  result := S_OK;

  if LifeState = gwdt_ls_Exists then
  begin
    result := ActiveX.CoLockObjectExternal(IDropTarget(self), true, false);
    if result = S_OK then LifeState := gwdt_ls_Locked;
  end;

  if LifeState = gwdt_ls_Regd then
  begin
    while RefCount < 2 do _AddRef;
    result := ActiveX.RevokeDragDrop(FDropHWND);
    if Result = S_OK then LifeState := gwdt_ls_Locked;
  end;
end;
//------------------------------------------------------------------------------
function TDropTarget.ToState_Regd: HResult;
begin
  result := S_OK;
  if LifeState = gwdt_ls_Exists then result := ToState_Locked;
  if LifeState = gwdt_ls_Locked then
  begin
    result := ActiveX.RegisterDragDrop(FDropHWND, IDropTarget(self));
    if result = S_OK then LifeState := gwdt_ls_Regd;
  end;
end;
//------------------------------------------------------------------------------
procedure TDropTarget.SetLifeState(Value: Tgwdt_ls);
begin
  FLifeState := Value;
end;
//------------------------------------------------------------------------------
function TDropTarget.DragEnter(const dataObj: IDataObject; grfKeyState: DWORD; pt: TPoint; var dwEffect: DWORD): HResult;
var Scope: TItemHostScope;
begin
  Scope := BeginItemHostOperation(FDropHWND);
  try
  if enable then Result := FDropInterface.DragEnter(dataObj, grfKeyState, pt, dwEffect)
  else
  begin
    dwEffect := DROPEFFECT_NONE;
    FDropInterface.FDragDataSupported := False;
    FDropInterface.ResetDragFeedback;
    result := S_OK;
  end;
  finally EndItemHostOperation(Scope); end;
end;
//------------------------------------------------------------------------------
function TDropTarget.DragOver(grfKeyState : DWORD; pt: TPoint; var dwEffect: DWORD): HResult;
var Scope: TItemHostScope;
begin
  Scope := BeginItemHostOperation(FDropHWND);
  try
  if Enable then result := FDropInterface.DragOver(grfKeyState, pt, dwEffect)
  else
  begin
    dwEffect := DROPEFFECT_NONE;
    FDropInterface.FDragDataSupported := False;
    FDropInterface.ResetDragFeedback;
    result := S_OK;
  end;
  finally EndItemHostOperation(Scope); end;
end;
//------------------------------------------------------------------------------
function TDropTarget.DragLeave: HResult;
var Scope: TItemHostScope;
begin
  Scope := BeginItemHostOperation(FDropHWND);
  try
  result := FDropInterface.DragLeave;
  finally EndItemHostOperation(Scope); end;
end;
//------------------------------------------------------------------------------
function TDropTarget.Drop(const dataObj: IDataObject; grfKeyState: DWORD; pt: TPoint; var dwEffect: DWORD): HResult;
var Scope: TItemHostScope;
begin
  Scope := BeginItemHostOperation(FDropHWND);
  try
  if Enable then result := FDropInterface.Drop(dataObj, grfKeyState, pt, dwEffect)
  else
  begin
    dwEffect := DROPEFFECT_NONE;
    FDropInterface.FDragDataSupported := False;
    FDropInterface.ResetDragFeedback;
    result := S_OK;
  end;
  finally EndItemHostOperation(Scope); end;
end;
//------------------------------------------------------------------------------
initialization
  OleInitialize(nil);
//------------------------------------------------------------------------------
finalization
  OleUninitialize;
//------------------------------------------------------------------------------
end.

