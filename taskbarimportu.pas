unit taskbarimportu;

{$mode delphi}

interface

uses Windows, Classes, SysUtils, ActiveX, ShlObj, itemserializationu;

type
  TTaskbarImportMode = (timCopyShortcuts, timReferenceShortcuts);
  TTaskbarPin = record
    Caption, Target: string;
  end;
  TTaskbarPins = array of TTaskbarPin;
  TTaskbarSnapshot = record
    Pins: TTaskbarPins;
    Failed: Integer;
    Details, Warning: string;
  end;
  TTaskbarImportResult = record
    Added, Updated, Skipped, Failed: Integer;
    Details, Warning: string;
  end;
  TInsertTaskbarLauncher = function(const Data: TShortcutDtoV1): Boolean of object;
  TUpdateTaskbarLauncher = function(const Data: TShortcutDtoV1): Boolean of object;

  TTaskbarSource = class
  protected
    function OpenPinnedList(out Items: IEnumIDList): HRESULT; virtual;
    function ShortcutFolder: UnicodeString; virtual;
    procedure ReadShortcutFolder(var Snapshot: TTaskbarSnapshot);
  public
    function ReadPins: TTaskbarSnapshot; virtual;
  end;

const
  DEFAULT_TASKBAR_IMPORT_MODE = timCopyShortcuts;

function TaskbarLauncherKey(const Data: TShortcutDtoV1): string;
function ImportTaskbarPins(const Snapshot: TTaskbarSnapshot;
  const StorageRoot: UnicodeString; ExistingKeys: TStrings;
  Insert: TInsertTaskbarLauncher; Mode: TTaskbarImportMode = DEFAULT_TASKBAR_IMPORT_MODE;
  UpdateExisting: TUpdateTaskbarLauncher = nil): TTaskbarImportResult;
function TaskbarImportMessage(const Value: TTaskbarImportResult): string;

implementation

uses ComObj, PIDL, shelltextu, toolu, dropimportu, sha1, declu, LazUTF8;

type
  // Only the common, read-only first method is used. Later slots vary by Windows version.
  // ABI references: vhanla/W1nDro1d TaskbarPinner.pas and ExplorerHelper Interop/PinnedList3.cs.
  ITaskbarPinnedList = interface(IUnknown)
    ['{0DD79AE2-D156-45D4-9EEB-3B549769E940}']
    function EnumObjects(out Items: IEnumIDList): HRESULT; stdcall;
  end;

const
  CLSID_TaskbandPin: TGUID = '{90AA3A4E-1CBA-4233-B8BB-535773D48449}';
  PinnedListIDs: array[0..3] of TGUID = (
    '{0DD79AE2-D156-45D4-9EEB-3B549769E940}',
    '{60274FA2-611F-4B8A-A293-F27BF103D148}',
    '{BBD20037-BC0E-42F1-913F-E2936BB0EA0C}',
    '{C3C6EB6D-C837-4EAE-B172-5FEC52A2A4FD}');
  MAX_TASKBAR_PINS = 4096;

function NativeFileSize(Handle: THandle; out Size: Int64): BOOL; stdcall;
  external 'kernel32.dll' name 'GetFileSizeEx';

function FilenameW(const Path: UnicodeString): UnicodeString;
var Index: Integer;
begin
  Index := Length(Path);
  while (Index > 0) and (Path[Index] <> '\') and (Path[Index] <> '/') do Dec(Index);
  Result := Copy(Path, Index + 1, MaxInt);
end;

procedure AddDetail(var Details: string; const Text: string);
begin
  if Details <> '' then Details := Details + LineEnding;
  Details := Details + Text;
end;

procedure AddPin(var Snapshot: TTaskbarSnapshot; const Caption, Target: string);
var Index: Integer;
begin
  Index := Length(Snapshot.Pins);
  SetLength(Snapshot.Pins, Index + 1);
  Snapshot.Pins[Index].Caption := Caption;
  Snapshot.Pins[Index].Target := Target;
end;

function TTaskbarSource.OpenPinnedList(out Items: IEnumIDList): HRESULT;
var List: ITaskbarPinnedList; Index: Integer; Status: HRESULT;
begin
  Items := nil;
  Result := E_NOINTERFACE;
  for Index := Low(PinnedListIDs) to High(PinnedListIDs) do
  begin
    List := nil;
    Status := CoCreateInstance(CLSID_TaskbandPin, nil, CLSCTX_INPROC_SERVER,
      PinnedListIDs[Index], List);
    if Succeeded(Status) and (List <> nil) then
    begin
      Status := List.EnumObjects(Items);
      if (Status = S_OK) and (Items <> nil) then Exit(S_OK);
      Items := nil;
    end;
    Result := Status;
  end;
end;

function TTaskbarSource.ShortcutFolder: UnicodeString;
var Path: PWideChar;
begin
  Result := '';
  Path := nil;
  try
    if SHGetKnownFolderPath(FOLDERID_UserPinned, 0, 0, Path) = S_OK then
      if Path <> nil then Result := UnicodeString(Path) + '\TaskBar';
  finally CoTaskMemFree(Path); end;
end;

procedure TTaskbarSource.ReadShortcutFolder(var Snapshot: TTaskbarSnapshot);
var Folder, Name: UnicodeString; Search: THandle; Data: WIN32_FIND_DATAW;
  Names: TStringList; Index: Integer; ErrorCode: DWORD;
begin
  Folder := ShortcutFolder;
  if Folder = '' then Exit;
  Search := FindFirstFileW(PWideChar(Folder + '\*.lnk'), Data);
  if Search = INVALID_HANDLE_VALUE then
  begin
    ErrorCode := GetLastError;
    if not (ErrorCode in [ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND]) then
      AddDetail(Snapshot.Details, Format(XTaskbarReadShortcutsFailed, [SysErrorMessageUTF8(ErrorCode)]));
    Exit;
  end;
  Names := TStringList.Create;
  try
    repeat
      if (Data.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) = 0 then
      begin
        if Names.Count >= MAX_TASKBAR_PINS then
          raise ERangeError.Create(XTaskbarShortcutListTooLarge);
        Names.Add(ShellUTF8(UnicodeString(Data.cFileName)));
      end;
    until not FindNextFileW(Search, Data);
    ErrorCode := GetLastError;
    if ErrorCode <> ERROR_NO_MORE_FILES then
      AddDetail(Snapshot.Details, Format(XTaskbarReadShortcutsIncomplete, [SysErrorMessageUTF8(ErrorCode)]));
    Names.Sort;
    for Index := 0 to Names.Count - 1 do
    begin
      Name := ShellUTF16(Names[Index]);
      AddPin(Snapshot, ShellUTF8(Copy(Name, 1, Length(Name) - 4)), ShellUTF8(Folder + '\' + Name));
    end;
  finally
    Names.Free;
    Windows.FindClose(Search);
  end;
end;

function TTaskbarSource.ReadPins: TTaskbarSnapshot;
var Items: IEnumIDList; List: PItemIDList; Count: ULONG; Status, Init: HRESULT;
  Caption, Target, AppID: UnicodeString; Index: Integer;
begin
  Result := Default(TTaskbarSnapshot);
  Init := CoInitializeEx(nil, COINIT_APARTMENTTHREADED);
  if Failed(Init) and (Init <> RPC_E_CHANGED_MODE) then
    raise EOSError.Create(Format(XTaskbarReadPinsFailed, [IntToHex(LongWord(Init), 8)]));
  try
    Status := OpenPinnedList(Items);
    if (Status <> S_OK) or (Items = nil) then
    begin
      Result.Warning := Format(XTaskbarIncompleteSource, [IntToHex(LongWord(Status), 8)]);
      ReadShortcutFolder(Result);
      Exit;
    end;
    Index := 0;
    repeat
      List := nil;
      Count := 0;
      Status := Items.Next(1, List, Count);
      try
        if Status = S_FALSE then Break;
        if (Status <> S_OK) or (Count <> 1) or (List = nil) then
        begin
          Result.Warning := Format(XTaskbarEnumerationIncomplete, [IntToHex(LongWord(Status), 8)]);
          Break;
        end;
        Inc(Index);
        if Index > MAX_TASKBAR_PINS then
        begin
          Result.Warning := XTaskbarListTooLarge;
          Break;
        end;
        try
          Caption := '';
          PIDL_GetDisplayNameText(nil, List, SHGDN_NORMAL, Caption);
          Target := '';
          if not PIDL_GetDisplayNameText(nil, List, SHGDN_FORPARSING, Target) or (Target = '') then
            Target := ShellUTF16(PIDL_ToString(List));
          if TryNormalizeAppTarget(Target, AppID) then Target := APPS_FOLDER_PREFIX + AppID;
          if Caption = '' then Caption := Target;
          AddPin(Result, ShellUTF8(Caption), ShellUTF8(Target));
        except
          on E: Exception do
          begin
            Inc(Result.Failed);
            AddDetail(Result.Details, Format(XTaskbarItemFailure, [Index, E.Message]));
          end;
        end;
      finally CoTaskMemFree(List); end;
    until False;
  finally
    Items := nil;
    if Succeeded(Init) then CoUninitialize;
  end;
end;

function KeyField(const Value: string): string;
begin Result := IntToStr(Length(Value)) + ':' + Value; end;

function ShortcutBytesKey(const Path: UnicodeString): string;
var Handle: THandle; Size: Int64; Bytes: RawByteString; Count: DWORD;
begin
  Result := '';
  Handle := CreateFileW(PWideChar(Path), GENERIC_READ, FILE_SHARE_READ, nil,
    OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if Handle = INVALID_HANDLE_VALUE then Exit;
  try
    if not NativeFileSize(Handle, Size) or (Size <= 0) or (Size > SHELL_DATA_LIMIT) then Exit;
    SetLength(Bytes, Size);
    if not ReadFile(Handle, Bytes[1], Length(Bytes), Count, nil) or (Count <> Length(Bytes)) then Exit;
    Result := 'shortcut-bytes:' + SHA1Print(SHA1String(Bytes));
  finally CloseHandle(Handle); end;
end;

function TaskbarLauncherKey(const Data: TShortcutDtoV1): string;
var Target: WideString; AppID: UnicodeString; Params, Directory, Icon: string;
  Link: IShellLinkW; Persist: IPersistFile; ReadMetadata: Boolean; ContentKey: string;
begin
  Target := ShellUTF16(UnzipPath(Data.Command));
  Params := Data.Params;
  Directory := UnzipPath(Data.Directory);
  if SameText(ExtractFileExt(ShellUTF8(Target)), '.lnk') then
  begin
    ReadMetadata := False;
    // Read metadata without resolving, updating, or launching the source shortcut.
    try
      Link := CreateComObject(CLSID_ShellLink) as IShellLinkW;
      Persist := Link as IPersistFile;
      if (Persist.Load(PWideChar(Target), STGM_READ) = S_OK) and (Params = '') then
      begin
        ReadMetadata := ReadLNKMetadata(Link, Target, Params, Directory, Icon);
        if ReadMetadata then Directory := UnzipPath(Directory);
      end;
    except
      // The source path still provides an identity for unreadable shortcuts.
    end;
    if not ReadMetadata then
    begin
      ContentKey := ShortcutBytesKey(ShellUTF16(UnzipPath(Data.Command)));
      if ContentKey <> '' then Exit(ContentKey + KeyField(Data.Params) + KeyField(Data.Directory));
    end;
  end;
  if TryNormalizeAppTarget(Target, AppID) then Target := APPS_FOLDER_PREFIX + AppID;
  Result := KeyField(ShellUTF8(UnicodeLowerCase(Target))) + KeyField(Params) +
    KeyField(ShellUTF8(UnicodeLowerCase(ShellUTF16(Directory))));
end;

function CopyShortcut(const Source: UnicodeString; Batch: TDropImportBatch): string;
var Input, Output: THandle; Size: Int64; Path: UnicodeString;
  Buffer: array[0..16383] of Byte; Count, Written: DWORD;
begin
  Input := CreateFileW(PWideChar(Source), GENERIC_READ, FILE_SHARE_READ, nil,
    OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if Input = INVALID_HANDLE_VALUE then RaiseLastOSError;
  try
    if not NativeFileSize(Input, Size) then RaiseLastOSError;
    if (Size = 0) or (Size > SHELL_DATA_LIMIT) then
      raise ERangeError.Create(XTaskbarShortcutSizeUnsupported);
    Path := Batch.NewFile(FilenameW(Source), Output);
    try
      repeat
        if not ReadFile(Input, Buffer, SizeOf(Buffer), Count, nil) then RaiseLastOSError;
        if Count = 0 then Break;
        if not WriteFile(Output, Buffer, Count, Written, nil) then RaiseLastOSError;
        if Written <> Count then raise EOSError.Create(XTaskbarCopyFailed);
      until False;
      if not FlushFileBuffers(Output) then RaiseLastOSError;
    finally CloseHandle(Output); end;
    Result := ShellUTF8(Path);
  finally CloseHandle(Input); end;
end;

function ImportTaskbarPins(const Snapshot: TTaskbarSnapshot;
  const StorageRoot: UnicodeString; ExistingKeys: TStrings;
  Insert: TInsertTaskbarLauncher; Mode: TTaskbarImportMode;
  UpdateExisting: TUpdateTaskbarLauncher): TTaskbarImportResult;
var Pin: TTaskbarPin; Data: TShortcutDtoV1; Key: string;
  Keys: TStringList; Batch: TDropImportBatch; Accepted: Boolean;
begin
  Result := Default(TTaskbarImportResult);
  Result.Failed := Snapshot.Failed;
  Result.Details := Snapshot.Details;
  Result.Warning := Snapshot.Warning;
  if not Assigned(Insert) then raise EArgumentNilException.Create(XTaskbarInsertUnavailable);
  Keys := TStringList.Create;
  try
    Keys.CaseSensitive := True;
    if ExistingKeys <> nil then Keys.Assign(ExistingKeys);
    for Pin in Snapshot.Pins do
    begin
      Batch := nil;
      try
        try
          Data := DefaultShortcutDto;
          Data.Caption := ShellUTF16(Pin.Caption);
          Data.Command := Pin.Target;
          if Data.Command = '' then raise EConvertError.Create(XTaskbarEmptyTarget);
          if SameText(ExtractFileExt(Data.Command), '.lnk') then
            if not ShellFileExists(ShellUTF16(UnzipPath(Data.Command))) then
              raise EInOutError.Create(XTaskbarShortcutMissing);
          WriteShortcutText(Data);
          Key := TaskbarLauncherKey(Data);
          if Keys.IndexOf(Key) >= 0 then
          begin
            if (Mode = timReferenceShortcuts) and Assigned(UpdateExisting) and UpdateExisting(Data) then
              Inc(Result.Updated)
            else Inc(Result.Skipped);
            Continue;
          end;
          if (Mode = timCopyShortcuts) and SameText(ExtractFileExt(Data.Command), '.lnk') then
          begin
            Batch := TDropImportBatch.Create(StorageRoot);
            Data.Command := ZipPath(CopyShortcut(ShellUTF16(UnzipPath(Pin.Target)), Batch));
            Batch.Add(UnzipPath(Data.Command));
          end;
          WriteShortcutText(Data);
          if Batch <> nil then Batch.Expose;
          Accepted := Insert(Data);
          if Batch <> nil then Batch.Decide(0, Accepted);
          if not Accepted then raise EInvalidOp.Create(XTaskbarLauncherRejected);
          Inc(Result.Added);
          Keys.Add(Key);
        except
          on E: Exception do
          begin
            Inc(Result.Failed);
            AddDetail(Result.Details, Pin.Caption + ': ' + E.Message);
          end;
        end;
      finally Batch.Free; end;
    end;
  finally Keys.Free; end;
end;

function TaskbarImportMessage(const Value: TTaskbarImportResult): string;
begin
  Result := Format(XTaskbarImportSummary,
    [Value.Added, Value.Updated, Value.Skipped, Value.Failed]);
  if Value.Warning <> '' then AddDetail(Result, Value.Warning);
  if Value.Details <> '' then AddDetail(Result, Value.Details);
end;

end.
