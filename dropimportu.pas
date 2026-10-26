unit dropimportu;

{$mode delphi}

interface

uses Windows, Classes, SysUtils, ActiveX, ShlObj;

const
  DROP_TEXT_LIMIT = 65536;
  DROP_TARGET_LIMIT = 64;
  DROP_TARGET_LENGTH = 1023;
  FD_ATTRIBUTES_FLAG = $00000004;
  FD_FILESIZE_FLAG = $00000040;

type
  EInvalidDropFormat = class(Exception);
  EDropTransferError = class(Exception);
  TImportDecision = (idUnknown, idAccepted, idRejected);
  TDropImportBatch = class(TStringList)
  private
    FRoot, FStage: UnicodeString;
    FOwned: TStringList;
    FMarker: THandle;
    FExposed: Boolean;
    FRejectionReason: string;
    FDecisions: array of TImportDecision;
    procedure EnsureStage;
  public
    constructor Create(const StorageRoot: UnicodeString);
    destructor Destroy; override;
    function NewFile(const Name: UnicodeString; out Handle: THandle): UnicodeString;
    procedure DiscardCandidate;
    procedure Expose;
    procedure Decide(Index: Integer; Accepted: Boolean);
    function AcceptedCount: Integer;
    function RejectedCount: Integer;
    function UndecidedCount: Integer;
    property RejectionReason: string read FRejectionReason;
  end;

function GetDropMedium(const Data: IDataObject; Format: Word; MediumType: DWORD;
  Index: Integer; out Medium: TStgMedium): Boolean;
function SupportsDropData(const Data: IDataObject): Boolean;
function ImportAdditionalFormats(const Data: IDataObject; Batch: TDropImportBatch): Boolean;
procedure CleanupIncompleteImports(const StorageRoot: UnicodeString);
procedure ValidateDropTarget(const Value: UnicodeString);

implementation

const
  STAGE_PREFIX: UnicodeString = 'import-';
  MARKER_NAME: UnicodeString = '\.tdock-import';
  MARKER_PENDING: AnsiString = 'TDOCK-IMPORT-1:P';
  MARKER_EXPOSED: AnsiString = 'TDOCK-IMPORT-1:E';

procedure CheckHR(Value: HRESULT; const Operation: string);
begin
  if Value <> S_OK then
    raise EDropTransferError.Create(Operation + ': ' + IntToHex(LongWord(Value), 8));
end;

function IsReparse(const Path: UnicodeString): Boolean;
var Attributes: DWORD;
begin
  Attributes := GetFileAttributesW(PWideChar(Path));
  Result := (Attributes <> INVALID_FILE_ATTRIBUTES) and
    ((Attributes and FILE_ATTRIBUTE_REPARSE_POINT) <> 0);
end;

procedure MakeDirectory(const Path: UnicodeString);
var Attributes: DWORD;
begin
  if CreateDirectoryW(PWideChar(Path), nil) then Exit;
  if GetLastError <> ERROR_ALREADY_EXISTS then RaiseLastOSError;
  Attributes := GetFileAttributesW(PWideChar(Path));
  if (Attributes = INVALID_FILE_ATTRIBUTES) or
    ((Attributes and FILE_ATTRIBUTE_DIRECTORY) = 0) or IsReparse(Path) then
    raise EDropTransferError.Create('Invalid import storage directory');
end;

procedure WriteHandle(Handle: THandle; Data: Pointer; Count: DWORD);
var Written: DWORD;
begin
  if Count = 0 then Exit;
  if not WriteFile(Handle, Data^, Count, Written, nil) then RaiseLastOSError;
  if Written <> Count then raise EDropTransferError.Create('Incomplete import write');
end;

procedure ValidateUTF16(const Value: UnicodeString);
var I: Integer; C: Word;
begin
  I := 1;
  while I <= Length(Value) do
  begin
    C := Ord(Value[I]);
    if (C >= $D800) and (C <= $DBFF) then
    begin
      Inc(I);
      if (I > Length(Value)) or (Ord(Value[I]) < $DC00) or
        (Ord(Value[I]) > $DFFF) then raise EInvalidDropFormat.Create('Invalid Unicode text');
    end
    else if (C >= $DC00) and (C <= $DFFF) then
      raise EInvalidDropFormat.Create('Invalid Unicode text');
    Inc(I);
  end;
end;

procedure ValidateDropTarget(const Value: UnicodeString);
var I: Integer;
begin
  ValidateUTF16(Value);
  if (Value = '') or (Length(Value) > DROP_TARGET_LENGTH) then
    raise EInvalidDropFormat.Create('Unsupported drop target length');
  for I := 1 to Length(Value) do
    if (Ord(Value[I]) < 32) or (Value[I] = ';') or (Value[I] = '"') then
      raise EInvalidDropFormat.Create('Unsupported character in drop target');
end;

procedure ValidateName(const Name: UnicodeString);
var I: Integer; Stem: UnicodeString;
begin
  ValidateDropTarget(Name);
  if (Name = '.') or (Name = '..') or (Name[Length(Name)] = '.') or
    (Name[Length(Name)] = ' ') then raise EInvalidDropFormat.Create('Invalid imported filename');
  for I := 1 to Length(Name) do
    if Pos(Name[I], UnicodeString('\/:*?<>|')) > 0 then
      raise EInvalidDropFormat.Create('Invalid imported filename');
  Stem := Name;
  I := Pos('.', Stem);
  if I > 0 then SetLength(Stem, I - 1);
  Stem := UpperCase(TrimRight(Stem));
  if (Stem = 'CON') or (Stem = 'PRN') or (Stem = 'AUX') or (Stem = 'NUL') or
    (Stem = 'CONIN$') or (Stem = 'CONOUT$') or
    ((Length(Stem) = 4) and ((Copy(Stem, 1, 3) = 'COM') or
    (Copy(Stem, 1, 3) = 'LPT')) and
    (((Stem[4] >= '0') and (Stem[4] <= '9')) or
    (Ord(Stem[4]) = $B9) or (Ord(Stem[4]) = $B2) or (Ord(Stem[4]) = $B3))) then
    raise EInvalidDropFormat.Create('Reserved imported filename');
end;

constructor TDropImportBatch.Create(const StorageRoot: UnicodeString);
begin
  inherited Create;
  FMarker := INVALID_HANDLE_VALUE;
  FOwned := TStringList.Create;
  FRoot := ExcludeTrailingPathDelimiter(StorageRoot);
end;

procedure TDropImportBatch.EnsureStage;
var Id: TGUID; Attempt: Integer;
begin
  if FStage <> '' then Exit;
  if FRoot = '' then raise EDropTransferError.Create('Import storage is unavailable');
  MakeDirectory(FRoot);
  for Attempt := 1 to 128 do
  begin
    CheckHR(CreateGUID(Id), 'Create import identifier');
    FStage := FRoot + '\' + STAGE_PREFIX + UnicodeString(GUIDToString(Id));
    if CreateDirectoryW(PWideChar(FStage), nil) then Break;
    FStage := '';
    if GetLastError <> ERROR_ALREADY_EXISTS then RaiseLastOSError;
  end;
  if FStage = '' then raise EDropTransferError.Create('Cannot reserve import directory');
  FMarker := CreateFileW(PWideChar(FStage + MARKER_NAME), GENERIC_READ or GENERIC_WRITE,
    0, nil, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, 0);
  if FMarker = INVALID_HANDLE_VALUE then RaiseLastOSError;
  WriteHandle(FMarker, PAnsiChar(MARKER_PENDING), Length(MARKER_PENDING));
  if not FlushFileBuffers(FMarker) then RaiseLastOSError;
end;

function TDropImportBatch.NewFile(const Name: UnicodeString; out Handle: THandle): UnicodeString;
var Candidate, Base, Extension: UnicodeString; Dot, Attempt: Integer; ErrorCode: DWORD;
begin
  Handle := INVALID_HANDLE_VALUE;
  ValidateName(Name);
  EnsureStage;
  Base := Name;
  Extension := '';
  Dot := Length(Name);
  while (Dot > 0) and (Name[Dot] <> '.') do Dec(Dot);
  if Dot > 1 then
  begin Base := Copy(Name, 1, Dot - 1); Extension := Copy(Name, Dot, MaxInt); end;
  for Attempt := 0 to 10000 do
  begin
    Candidate := Name;
    if Attempt > 0 then Candidate := Base + ' (' + UnicodeString(IntToStr(Attempt + 1)) + ')' + Extension;
    Result := FStage + '\' + Candidate;
    try ValidateDropTarget(Result);
    except on E: EInvalidDropFormat do
      raise EDropTransferError.Create('The imported destination cannot be represented: ' + E.Message); end;
    Handle := CreateFileW(PWideChar(Result), GENERIC_WRITE, 0, nil, CREATE_NEW,
      FILE_ATTRIBUTE_NORMAL, 0);
    if Handle <> INVALID_HANDLE_VALUE then
    begin
      try FOwned.Add(UTF8Encode(Result));
      except CloseHandle(Handle); DeleteFileW(PWideChar(Result)); raise; end;
      Exit;
    end;
    ErrorCode := GetLastError;
    if (ErrorCode <> ERROR_FILE_EXISTS) and (ErrorCode <> ERROR_ALREADY_EXISTS) then
      RaiseLastOSError(ErrorCode);
  end;
  raise EDropTransferError.Create('Cannot reserve imported filename');
end;

procedure TDropImportBatch.Expose;
begin
  if FExposed then Exit;
  SetLength(FDecisions, Count);
  if FMarker <> INVALID_HANDLE_VALUE then
  begin
    if SetFilePointer(FMarker, 0, nil, FILE_BEGIN) = INVALID_SET_FILE_POINTER then RaiseLastOSError;
    WriteHandle(FMarker, PAnsiChar(MARKER_EXPOSED), Length(MARKER_EXPOSED));
    if not FlushFileBuffers(FMarker) then RaiseLastOSError;
  end;
  FExposed := True;
end;

procedure TDropImportBatch.Decide(Index: Integer; Accepted: Boolean);
begin
  if not FExposed or (Index < 0) or (Index >= Length(FDecisions)) then
    raise EArgumentException.Create('Invalid import decision');
  if Accepted then FDecisions[Index] := idAccepted else FDecisions[Index] := idRejected;
end;

function TDropImportBatch.AcceptedCount: Integer;
var I: Integer;
begin
  Result := 0;
  for I := 0 to High(FDecisions) do
    if FDecisions[I] = idAccepted then Inc(Result);
end;

function TDropImportBatch.RejectedCount: Integer;
var I: Integer;
begin
  Result := 0;
  for I := 0 to High(FDecisions) do
    if FDecisions[I] = idRejected then Inc(Result);
end;

function TDropImportBatch.UndecidedCount: Integer;
begin
  Result := Count - AcceptedCount - RejectedCount;
end;

procedure TDropImportBatch.DiscardCandidate;
var I: Integer;
begin
  if FExposed then raise EInvalidOp.Create('Import paths are already exposed');
  for I := 0 to FOwned.Count - 1 do
    if not DeleteFileW(PWideChar(UTF8Decode(FOwned[I]))) then
      if GetLastError <> ERROR_FILE_NOT_FOUND then RaiseLastOSError;
  FOwned.Clear;
  Clear;
end;

destructor TDropImportBatch.Destroy;
var I, Index: Integer; Keep: Boolean; Path: UnicodeString;
begin
  Keep := False;
  if Assigned(FOwned) then
    for I := 0 to FOwned.Count - 1 do
    begin
      Index := IndexOf(FOwned[I]);
      if not FExposed or ((Index >= 0) and (Index < Length(FDecisions)) and
        (FDecisions[Index] = idRejected)) then
      begin
        Path := UTF8Decode(FOwned[I]);
        if not DeleteFileW(PWideChar(Path)) and (GetLastError <> ERROR_FILE_NOT_FOUND) then Keep := True;
      end else Keep := True;
    end;
  if FMarker <> INVALID_HANDLE_VALUE then CloseHandle(FMarker);
  if (FStage <> '') and not Keep then
  begin DeleteFileW(PWideChar(FStage + MARKER_NAME)); RemoveDirectoryW(PWideChar(FStage)); end;
  FOwned.Free;
  inherited Destroy;
end;

procedure CleanupIncompleteImports(const StorageRoot: UnicodeString);
var Search, ChildSearch: THandle; Find, Child: TWin32FindDataW;
  Stage, Name, Path: UnicodeString; Marker: THandle; Header: AnsiString;
  ReadCount: DWORD; Id: TGUID; Safe: Boolean;
begin
  if (StorageRoot = '') or IsReparse(StorageRoot) then Exit;
  Search := FindFirstFileW(PWideChar(StorageRoot + '\' + STAGE_PREFIX + '*'), Find);
  if Search = INVALID_HANDLE_VALUE then Exit;
  try
    repeat
      Name := Find.cFileName;
      if ((Find.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) = 0) or
        ((Find.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT) <> 0) or
        not TryStringToGUID(UTF8Encode(Copy(Name, Length(STAGE_PREFIX) + 1, MaxInt)), Id) then Continue;
      Stage := StorageRoot + '\' + Name;
      Marker := CreateFileW(PWideChar(Stage + MARKER_NAME), GENERIC_READ, 0, nil,
        OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
      if Marker = INVALID_HANDLE_VALUE then Continue;
      Safe := False;
      try
        SetLength(Header, Length(MARKER_PENDING));
        Safe := ReadFile(Marker, Header[1], Length(Header), ReadCount, nil) and
          (ReadCount = DWORD(Length(Header))) and (Header = MARKER_PENDING);
        if not Safe then Continue;
        ChildSearch := FindFirstFileW(PWideChar(Stage + '\*'), Child);
        if ChildSearch = INVALID_HANDLE_VALUE then Continue;
        try
          repeat
            Name := Child.cFileName;
            if (Name = '.') or (Name = '..') or (Name = Copy(MARKER_NAME, 2, MaxInt)) then Continue;
            if (Child.dwFileAttributes and (FILE_ATTRIBUTE_DIRECTORY or FILE_ATTRIBUTE_REPARSE_POINT)) <> 0 then
            begin Safe := False; Break; end;
          until not FindNextFileW(ChildSearch, Child);
        finally Windows.FindClose(ChildSearch); end;
        if not Safe then Continue;
        ChildSearch := FindFirstFileW(PWideChar(Stage + '\*'), Child);
        if ChildSearch <> INVALID_HANDLE_VALUE then
        try
          repeat
            Name := Child.cFileName;
            if (Name = '.') or (Name = '..') or (Name = Copy(MARKER_NAME, 2, MaxInt)) then Continue;
            Path := Stage + '\' + Name;
            if not DeleteFileW(PWideChar(Path)) then Safe := False;
          until not FindNextFileW(ChildSearch, Child);
        finally Windows.FindClose(ChildSearch); end;
      finally CloseHandle(Marker); end;
      if Safe then
      begin DeleteFileW(PWideChar(Stage + MARKER_NAME)); RemoveDirectoryW(PWideChar(Stage)); end;
    until not FindNextFileW(Search, Find);
  finally Windows.FindClose(Search); end;
end;

function SupportsDropData(const Data: IDataObject): Boolean;
const Names: array[0..8] of PChar = ('Shell IDList Array', 'FileNameW', 'FileName',
  'UniformResourceLocatorW', 'UniformResourceLocator', 'FileGroupDescriptorW',
  'FileGroupDescriptor', '', '');
var Request: TFormatEtc; I: Integer; Formats: IEnumFormatEtc; Fetched: LongInt;
  Status: HRESULT;
  function Offered(Format: Word; Media: DWORD): Boolean;
  begin
    Request.cfFormat := Format;
    Request.tymed := Media;
    try Result := Data.QueryGetData(Request) = S_OK;
    except Result := False; end;
  end;
  function SupportedOffer: Boolean;
  var Index: Integer; Media: DWORD;
  begin
    Result := False;
    if (Request.dwAspect <> DVASPECT_CONTENT) or (Request.lindex <> -1) then Exit;
    if (Request.cfFormat = CF_HDROP) or (Request.cfFormat = CF_UNICODETEXT) or
      (Request.cfFormat = CF_TEXT) then Exit((Request.tymed and TYMED_HGLOBAL) <> 0);
    for Index := 0 to 6 do
      if Request.cfFormat = RegisterClipboardFormat(Names[Index]) then
      begin
        Media := TYMED_HGLOBAL;
        if Index <= 2 then Media := Media or TYMED_ISTREAM;
        if (Index = 1) or (Index = 2) then Media := Media or TYMED_FILE;
        Exit((Request.tymed and Media) <> 0);
      end;
  end;
begin
  Result := False;
  if Data = nil then Exit;
  FillChar(Request, SizeOf(Request), 0);
  Request.dwAspect := DVASPECT_CONTENT;
  Request.lindex := -1;
  if Offered(CF_HDROP, TYMED_HGLOBAL) then Exit(True);
  for I := 0 to High(Names) do
    if I = 7 then
    begin
      if Offered(CF_UNICODETEXT, TYMED_HGLOBAL) then Exit(True);
    end
    else if I = 8 then
    begin
      if Offered(CF_TEXT, TYMED_HGLOBAL) then Exit(True);
    end
    else if I = 0 then
    begin
      if Offered(RegisterClipboardFormat(Names[I]), TYMED_HGLOBAL) or
        Offered(RegisterClipboardFormat(Names[I]), TYMED_ISTREAM) then Exit(True);
    end
    else if I <= 2 then
    begin
      if Offered(RegisterClipboardFormat(Names[I]), TYMED_HGLOBAL) or
        Offered(RegisterClipboardFormat(Names[I]), TYMED_ISTREAM) or
        Offered(RegisterClipboardFormat(Names[I]), TYMED_FILE) then Exit(True);
    end
    else if Offered(RegisterClipboardFormat(Names[I]), TYMED_HGLOBAL) then Exit(True);
  // Some providers enumerate usable formats while rejecting capability queries.
  // Missing metadata remains provisional for compatible GetData-only providers.
  // Drop always attempts the original readers, regardless of this preview.
  try
    if (Data.EnumFormatEtc(DATADIR_GET, Formats) <> S_OK) or (Formats = nil) then Exit(True);
    while True do
    begin
      FillChar(Request, SizeOf(Request), 0);
      Fetched := 0;
      try
        Status := Formats.Next(1, Request, @Fetched);
        if Status = S_FALSE then Exit(False);
        if (Status <> S_OK) or (Fetched <> 1) then Exit(True);
        if SupportedOffer then Exit(True);
      finally
        if Request.ptd <> nil then CoTaskMemFree(Request.ptd);
      end;
    end;
  except
    Result := True;
  end;
end;

function GetDropMedium(const Data: IDataObject; Format: Word; MediumType: DWORD;
  Index: Integer; out Medium: TStgMedium): Boolean;
var Request: TFormatEtc;
begin
  FillChar(Request, SizeOf(Request), 0);
  Request.cfFormat := Format;
  Request.dwAspect := DVASPECT_CONTENT;
  Request.lindex := Index;
  Request.tymed := MediumType;
  FillChar(Medium, SizeOf(Medium), 0);
  Result := Data.GetData(Request, Medium) = S_OK;
  if Result and (Medium.tymed <> MediumType) then
  begin
    ReleaseStgMedium(Medium);
    FillChar(Medium, SizeOf(Medium), 0);
    Result := False;
  end;
end;

function DecodeBytes(Data: Pointer; Size: NativeUInt; Wide: Boolean; CodePage: UINT): UnicodeString;
var N, Units: NativeUInt; Required: Integer;
begin
  Result := '';
  if (Data = nil) or (Size = 0) or (Size > DROP_TEXT_LIMIT) then
    raise EInvalidDropFormat.Create('Invalid drop text size');
  if Wide then
  begin
    if (Size mod 2) <> 0 then raise EInvalidDropFormat.Create('Odd Unicode text size');
    Units := Size div 2;
    N := 0;
    while (N < Units) and (PWideChar(Data)[N] <> #0) do Inc(N);
    if N = Units then raise EInvalidDropFormat.Create('Unterminated Unicode text');
    SetString(Result, PWideChar(Data), N);
    ValidateUTF16(Result);
  end
  else
  begin
    N := 0;
    while (N < Size) and (PAnsiChar(Data)[N] <> #0) do Inc(N);
    if N = Size then raise EInvalidDropFormat.Create('Unterminated ANSI text');
    if N = 0 then Exit;
    Required := MultiByteToWideChar(CodePage, MB_ERR_INVALID_CHARS, Data, N, nil, 0);
    if Required = 0 then raise EInvalidDropFormat.Create('Invalid ANSI text');
    SetLength(Result, Required);
    if MultiByteToWideChar(CodePage, MB_ERR_INVALID_CHARS, Data, N,
      PWideChar(Result), Required) <> Required then raise EInvalidDropFormat.Create('Invalid ANSI text');
  end;
end;

function MediumText(const Medium: TStgMedium; Wide: Boolean; CodePage: UINT): UnicodeString;
var Data: Pointer; Bytes: TBytes; Stream: IStream; ReadCount: ULONG; HR: HRESULT; N: Integer;
  Chunk: array[0..4095] of Byte;
begin
  if Medium.tymed = TYMED_HGLOBAL then
  begin
    Data := GlobalLock(Medium.hGlobal);
    if Data = nil then raise EInvalidDropFormat.Create('Cannot lock drop text');
    try Result := DecodeBytes(Data, GlobalSize(Medium.hGlobal), Wide, CodePage);
    finally GlobalUnlock(Medium.hGlobal); end;
  end
  else
  begin
    Stream := IStream(Medium.pstm);
    if Stream = nil then raise EInvalidDropFormat.Create('Missing pathname stream');
    Bytes := nil;
    repeat
      ReadCount := 0;
      HR := Stream.Read(@Chunk, SizeOf(Chunk), @ReadCount);
      if (HR <> S_OK) and (HR <> S_FALSE) then CheckHR(HR, 'Read pathname stream');
      if (ReadCount > SizeOf(Chunk)) or (Length(Bytes) + ReadCount > DROP_TEXT_LIMIT) then
        raise EInvalidDropFormat.Create('Pathname stream exceeds text limit');
      N := Length(Bytes);
      SetLength(Bytes, N + ReadCount);
      if ReadCount > 0 then Move(Chunk, Bytes[N], ReadCount);
    until (ReadCount = 0) or (HR = S_FALSE);
    if Length(Bytes) = 0 then raise EInvalidDropFormat.Create('Empty pathname stream');
    Result := DecodeBytes(@Bytes[0], Length(Bytes), Wide, CodePage);
  end;
end;

function IsAbsolutePath(const Value: UnicodeString): Boolean;
begin
  Result := ((Length(Value) >= 3) and (((Value[1] >= 'A') and (Value[1] <= 'Z')) or
    ((Value[1] >= 'a') and (Value[1] <= 'z'))) and (Value[2] = ':') and (Value[3] = '\')) or
    ((Length(Value) > 4) and (Copy(Value, 1, 2) = '\\') and (Value[3] <> '?') and (Value[3] <> '.'));
end;

function IsURI(const Value: UnicodeString): Boolean;
var I, Colon: Integer; Scheme, Rest: UnicodeString;
begin
  Result := False;
  Colon := Pos(':', Value);
  if (Colon < 2) or (Colon = Length(Value)) then Exit;
  if not (((Value[1] >= 'A') and (Value[1] <= 'Z')) or
    ((Value[1] >= 'a') and (Value[1] <= 'z'))) then Exit;
  // Drive-qualified and drive-relative paths are never URI schemes.
  if Colon = 2 then Exit;
  for I := 2 to Colon - 1 do
    if not (((Value[I] >= 'A') and (Value[I] <= 'Z')) or
      ((Value[I] >= 'a') and (Value[I] <= 'z')) or
      ((Value[I] >= '0') and (Value[I] <= '9')) or (Pos(Value[I], UnicodeString('+.-')) > 0)) then Exit;
  for I := Colon + 1 to Length(Value) do
    if (Value[I] = ' ') or (Value[I] = '\') then Exit;
  Scheme := LowerCase(Copy(Value, 1, Colon - 1));
  Rest := Copy(Value, Colon + 1, MaxInt);
  if (Scheme = 'http') or (Scheme = 'https') then
    if (Copy(Rest, 1, 2) <> '//') or (Length(Rest) <= 2) or (Rest[3] = '/') then Exit;
  if Scheme = 'file' then
    if (Copy(Rest, 1, 3) <> '///') and
      ((Copy(Rest, 1, 2) <> '//') or (Length(Rest) <= 2)) then Exit;
  Result := True;
end;

procedure AddPath(Batch: TDropImportBatch; const Value: UnicodeString);
var Attributes: DWORD;
begin
  ValidateDropTarget(Value);
  if not IsAbsolutePath(Value) then raise EInvalidDropFormat.Create('A filename drop requires an absolute path');
  Attributes := GetFileAttributesW(PWideChar(Value));
  if Attributes = INVALID_FILE_ATTRIBUTES then raise EInvalidDropFormat.Create('Dropped path does not exist');
  Batch.Add(UTF8Encode(Value));
end;

procedure AddText(Batch: TDropImportBatch; const Text: UnicodeString);
var Start, Finish: Integer; Value: UnicodeString;
begin
  Start := 1;
  while Start <= Length(Text) do
  begin
    Finish := Start;
    while (Finish <= Length(Text)) and (Text[Finish] <> #10) and (Text[Finish] <> #13) do Inc(Finish);
    Value := Trim(Copy(Text, Start, Finish - Start));
    if Value <> '' then
    begin
      if (Length(Value) >= 2) and (Value[1] = '"') and (Value[Length(Value)] = '"') then
        Value := Copy(Value, 2, Length(Value) - 2);
      ValidateDropTarget(Value);
      if IsAbsolutePath(Value) then AddPath(Batch, Value)
      else if IsURI(Value) then Batch.Add(UTF8Encode(Value))
      else raise EInvalidDropFormat.Create('Text requires an absolute path or URI without command arguments');
      if Batch.Count > DROP_TARGET_LIMIT then raise EInvalidDropFormat.Create('Too many drop targets');
    end;
    Start := Finish + 1;
    if (Finish <= Length(Text)) and (Text[Finish] = #13) and
      (Start <= Length(Text)) and (Text[Start] = #10) then Inc(Start);
  end;
end;

function TextCodePage(const Data: IDataObject): UINT;
var Medium: TStgMedium; Locale: Pointer; Buffer: array[0..15] of WideChar;
begin
  Result := GetACP;
  if not GetDropMedium(Data, CF_LOCALE, TYMED_HGLOBAL, -1, Medium) then Exit;
  try
    if GlobalSize(Medium.hGlobal) < SizeOf(LCID) then Exit;
    Locale := GlobalLock(Medium.hGlobal);
    if Locale = nil then Exit;
    try
      if GetLocaleInfoW(PDWORD(Locale)^, LOCALE_IDEFAULTANSICODEPAGE, @Buffer, Length(Buffer)) > 0 then
        Result := StrToIntDef(UTF8Encode(UnicodeString(PWideChar(@Buffer))), GetACP);
    finally GlobalUnlock(Medium.hGlobal); end;
  finally ReleaseStgMedium(Medium); end;
end;

procedure CopyStreamToFile(const Stream: IStream; Handle: THandle; HasSize: Boolean; Size: QWord);
var Buffer: array[0..65535] of Byte; ReadCount: ULONG; HR: HRESULT; Total: QWord;
begin
  if Stream = nil then raise EDropTransferError.Create('Missing file stream');
  Total := 0;
  repeat
    ReadCount := 0;
    HR := Stream.Read(@Buffer, SizeOf(Buffer), @ReadCount);
    if (HR <> S_OK) and (HR <> S_FALSE) then CheckHR(HR, 'Read virtual file');
    if ReadCount > SizeOf(Buffer) then raise EDropTransferError.Create('Invalid stream read count');
    if Total > High(QWord) - ReadCount then raise EDropTransferError.Create('File size overflow');
    Inc(Total, ReadCount);
    if HasSize and (Total > Size) then raise EDropTransferError.Create('Virtual file exceeds its declared size');
    WriteHandle(Handle, @Buffer, ReadCount);
  until (ReadCount = 0) or (HR = S_FALSE);
  if HasSize and (Total <> Size) then raise EDropTransferError.Create('Incomplete virtual file');
end;

procedure CopyMediumFile(Batch: TDropImportBatch; const Source: UnicodeString);
var Name, Destination: UnicodeString; I: Integer; Input, Output: THandle;
  Buffer: array[0..65535] of Byte; ReadCount: DWORD;
begin
  ValidateDropTarget(Source);
  Name := Source;
  for I := Length(Source) downto 1 do
    if (Source[I] = '\') or (Source[I] = '/') then
    begin Name := Copy(Source, I + 1, MaxInt); Break; end;
  Input := CreateFileW(PWideChar(Source), GENERIC_READ,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil,
    OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if Input = INVALID_HANDLE_VALUE then RaiseLastOSError;
  try
    Destination := Batch.NewFile(Name, Output);
    try
      repeat
        if not ReadFile(Input, Buffer, SizeOf(Buffer), ReadCount, nil) then RaiseLastOSError;
        WriteHandle(Output, @Buffer, ReadCount);
      until ReadCount = 0;
      if not FlushFileBuffers(Output) then RaiseLastOSError;
    finally CloseHandle(Output); end;
  finally CloseHandle(Input); end;
  Batch.Add(UTF8Encode(Destination));
end;

procedure MaterializeContent(const Data: IDataObject; Batch: TDropImportBatch;
  Index: Integer; const Name: UnicodeString; HasSize: Boolean; Size: QWord);
const Media: array[0..2] of DWORD = (TYMED_ISTREAM, TYMED_HGLOBAL, TYMED_ISTORAGE);
var Medium: TStgMedium; Kind: DWORD; Path: UnicodeString; Output: THandle;
  Memory: Pointer; Destination, Source: IStorage; ChunkSize: DWORD; Locked: Boolean;
begin
  for Kind in Media do
    if GetDropMedium(Data, RegisterClipboardFormat('FileContents'), Kind, Index, Medium) then
    try
      Path := Batch.NewFile(Name, Output);
      try
        case Kind of
          TYMED_ISTREAM: CopyStreamToFile(IStream(Medium.pstm), Output, HasSize, Size);
          TYMED_HGLOBAL:
            begin
              if not HasSize or (Size > GlobalSize(Medium.hGlobal)) then
                raise EDropTransferError.Create('Virtual memory data requires a valid declared file size');
              Memory := GlobalLock(Medium.hGlobal);
              Locked := Memory <> nil;
              if (Memory = nil) and (Size <> 0) then raise EDropTransferError.Create('Cannot lock virtual file');
              try
                while Size > 0 do
                begin
                  if Size > 65536 then ChunkSize := 65536 else ChunkSize := Size;
                  WriteHandle(Output, Memory, ChunkSize);
                  Memory := Pointer(PtrUInt(Memory) + ChunkSize);
                  Dec(Size, ChunkSize);
                end;
              finally if Locked then GlobalUnlock(Medium.hGlobal); end;
            end;
          TYMED_ISTORAGE:
            begin
              CloseHandle(Output);
              Output := INVALID_HANDLE_VALUE;
              Source := IStorage(Medium.pstg);
              if Source = nil then raise EDropTransferError.Create('Missing compound storage');
              CheckHR(StgCreateDocfile(PWideChar(Path), STGM_CREATE or STGM_READWRITE or
                STGM_SHARE_EXCLUSIVE, 0, Destination), 'Create compound file');
              try
                CheckHR(Source.CopyTo(0, nil, nil, Destination), 'Copy compound file');
                CheckHR(Destination.Commit(STGC_DEFAULT), 'Commit compound file');
              finally Destination := nil; Source := nil; end;
            end;
        end;
        if (Output <> INVALID_HANDLE_VALUE) and not FlushFileBuffers(Output) then RaiseLastOSError;
      finally if Output <> INVALID_HANDLE_VALUE then CloseHandle(Output); end;
      Batch.Add(UTF8Encode(Path));
      Exit;
    finally ReleaseStgMedium(Medium); end;
  raise EDropTransferError.Create('Virtual file contents are unavailable');
end;

procedure ReadDescriptors(const Data: IDataObject; Batch: TDropImportBatch;
  const Medium: TStgMedium; Wide: Boolean);
type TDescriptor = record Name: UnicodeString; HasSize: Boolean; Size: QWord; end;
var Memory: Pointer; Count, RecordSize, I: DWORD; Size: NativeUInt;
  W: PFILEDESCRIPTORW; A: PFILEDESCRIPTORA; Descriptors: array of TDescriptor;
begin
  Size := GlobalSize(Medium.hGlobal);
  if Size < SizeOf(DWORD) then raise EInvalidDropFormat.Create('Truncated file descriptor group');
  Memory := GlobalLock(Medium.hGlobal);
  if Memory = nil then raise EInvalidDropFormat.Create('Cannot lock file descriptors');
  try
    Count := PDWORD(Memory)^;
    if (Count = 0) or (Count > DROP_TARGET_LIMIT) then raise EInvalidDropFormat.Create('Invalid virtual file count');
    if Wide then RecordSize := SizeOf(FILEDESCRIPTORW) else RecordSize := SizeOf(FILEDESCRIPTORA);
    if Count > (Size - SizeOf(DWORD)) div RecordSize then raise EInvalidDropFormat.Create('Truncated file descriptors');
    SetLength(Descriptors, Count);
    for I := 0 to Count - 1 do
    begin
      if Wide then
      begin
        W := Pointer(PtrUInt(Memory) + SizeOf(DWORD) + NativeUInt(I) * RecordSize);
        if ((W^.dwFlags and FD_ATTRIBUTES_FLAG) <> 0) and
          ((W^.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) <> 0) then
          raise EInvalidDropFormat.Create('Virtual directories are unsupported');
        Descriptors[I].Name := DecodeBytes(@W^.cFileName, SizeOf(W^.cFileName), True, GetACP);
        Descriptors[I].HasSize := (W^.dwFlags and FD_FILESIZE_FLAG) <> 0;
        Descriptors[I].Size := (QWord(W^.nFileSizeHigh) shl 32) or W^.nFileSizeLow;
      end
      else
      begin
        A := Pointer(PtrUInt(Memory) + SizeOf(DWORD) + NativeUInt(I) * RecordSize);
        if ((A^.dwFlags and FD_ATTRIBUTES_FLAG) <> 0) and
          ((A^.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) <> 0) then
          raise EInvalidDropFormat.Create('Virtual directories are unsupported');
        Descriptors[I].Name := DecodeBytes(@A^.cFileName, SizeOf(A^.cFileName), False, GetACP);
        Descriptors[I].HasSize := (A^.dwFlags and FD_FILESIZE_FLAG) <> 0;
        Descriptors[I].Size := (QWord(A^.nFileSizeHigh) shl 32) or A^.nFileSizeLow;
      end;
      ValidateName(Descriptors[I].Name);
    end;
  finally GlobalUnlock(Medium.hGlobal); end;
  for I := 0 to Count - 1 do
    MaterializeContent(Data, Batch, I, Descriptors[I].Name, Descriptors[I].HasSize, Descriptors[I].Size);
end;

function ImportAdditionalFormats(const Data: IDataObject; Batch: TDropImportBatch): Boolean;
const Names: array[0..7] of PChar = ('FileNameW', 'FileName', 'UniformResourceLocatorW',
  'UniformResourceLocator', 'FileGroupDescriptorW', 'FileGroupDescriptor', '', '');
  FilenameMedia: array[0..2] of DWORD = (TYMED_HGLOBAL, TYMED_ISTREAM, TYMED_FILE);
var I, J: Integer; Format: Word; Kind: DWORD; Medium: TStgMedium;
  Value: UnicodeString; Wide: Boolean; CodePage: UINT;
begin
  Result := False;
  for I := 0 to High(Names) do
  begin
    if I = 6 then Format := CF_UNICODETEXT
    else if I = 7 then Format := CF_TEXT else Format := RegisterClipboardFormat(Names[I]);
    Wide := (I mod 2) = 0;
    CodePage := GetACP;
    if I = 7 then CodePage := TextCodePage(Data);
    for J := 0 to 2 do
    begin
      if (I >= 2) and (J > 0) then Break;
      Kind := FilenameMedia[J];
      if not GetDropMedium(Data, Format, Kind, -1, Medium) then Continue;
      try
        try
          if I < 2 then
          begin
            if Kind = TYMED_FILE then
            begin
              if Medium.lpszFileName = nil then raise EInvalidDropFormat.Create('Missing transfer filename');
              CopyMediumFile(Batch, UnicodeString(Medium.lpszFileName));
            end
            else AddPath(Batch, MediumText(Medium, Wide, CodePage));
          end
          else if I < 4 then
          begin
            Value := Trim(MediumText(Medium, Wide, CodePage));
            ValidateDropTarget(Value);
            if not IsURI(Value) then raise EInvalidDropFormat.Create('Invalid dropped URL');
            Batch.Add(UTF8Encode(Value));
          end
          else if I < 6 then ReadDescriptors(Data, Batch, Medium, Wide)
          else AddText(Batch, MediumText(Medium, Wide, CodePage));
          if Batch.Count > 0 then Exit(True);
        except
          on E: EInvalidDropFormat do
          begin Batch.FRejectionReason := E.Message; Batch.DiscardCandidate; end;
        end;
      finally ReleaseStgMedium(Medium); end;
    end;
  end;
end;

end.
