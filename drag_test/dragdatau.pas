unit dragdatau;
{$mode delphi}
{$codepage utf8}

interface

uses Windows, Classes, SysUtils, ActiveX, ShlObj, ShellAPI;

type
  TDragProfile = (dpNativeShell, dpShellID, dpShellIDStream, dpHDropW, dpHDropA,
    dpURLW, dpURLA, dpTextW, dpTextA, dpFilenameWGlobal, dpFilenameAGlobal,
    dpFilenameWStream, dpFilenameAStream, dpFilenameWFile, dpFilenameAFile,
    dpVirtualWStream, dpVirtualAStream, dpVirtualWGlobal, dpVirtualAGlobal,
    dpVirtualWStorage, dpVirtualAStorage, dpMixed, dpUnsupported, dpText1252);
  TDragOptions = record
    Profile: TDragProfile;
    Payload, Contents, Root: UnicodeString;
    ProviderOwned, FailData: Boolean;
    ShellData: IDataObject;
  end;
  IDragLog = interface
    ['{4DCB2B83-DF67-489C-9A58-FD4F3988981C}']
    procedure Add(const Value: string);
  end;
  TDragLog = class(TInterfacedObject, IDragLog)
  public
    Lines: TStringList;
    Filename: string;
    Revision: QWord;
    constructor Create(const Path: string);
    destructor Destroy; override;
    procedure Add(const Value: string);
  end;
  TDragSource = class(TInterfacedObject, IDropSource)
    function QueryContinueDrag(Escape: BOOL; Keys: DWORD): HRESULT; stdcall;
    function GiveFeedback(Effect: DWORD): HRESULT; stdcall;
  end;
  TInspectTarget = class(TInterfacedObject, IDropTarget)
  private
    FLog: IDragLog;
  public
    constructor Create(const Log: IDragLog);
    function DragEnter(const Data: IDataObject; Keys: DWORD; Point: TPoint; var Effect: DWORD): HRESULT; stdcall;
    function DragOver(Keys: DWORD; Point: TPoint; var Effect: DWORD): HRESULT; stdcall;
    function DragLeave: HRESULT; stdcall;
    function Drop(const Data: IDataObject; Keys: DWORD; Point: TPoint; var Effect: DWORD): HRESULT; stdcall;
  end;

const
  ProfileNames: array[TDragProfile] of string = (
    'Native Shell (all formats)', 'Shell IDList Array only (HGLOBAL)',
    'Shell IDList Array only (IStream)', 'CF_HDROP only (Unicode)', 'CF_HDROP only (ANSI)',
    'URL only (Unicode)', 'URL only (ANSI)', 'Plain text only (Unicode)', 'Plain text only (ANSI)',
    'FileNameW only (HGLOBAL)', 'FileName only (HGLOBAL)', 'FileNameW only (IStream)',
    'FileName only (IStream)', 'FileNameW only (TYMED_FILE)', 'FileName only (TYMED_FILE)',
    'Virtual files: Unicode + IStream', 'Virtual files: ANSI + IStream',
    'Virtual files: Unicode + HGLOBAL', 'Virtual files: ANSI + HGLOBAL',
    'Virtual files: Unicode + IStorage', 'Virtual files: ANSI + IStorage',
    'Mixed: file + URL + text', 'Unsupported format only', 'Plain text: CP1252 + CF_LOCALE');

function BuildDragObject(const Options: TDragOptions; const Log: IDragLog): IDataObject;
function NativeShellData(const Targets: TStrings): IDataObject;
function ShellDataFromIDList(ID: PItemIDList): IDataObject;
function FormatName(Format: Word): string;
function MediaName(Kind: DWORD): string;
function WideBytes(const Text: UnicodeString): RawByteString;
function EncodedANSIBytes(const Text: UnicodeString; CodePage: UINT): RawByteString;
function ANSIBytes(const Text: UnicodeString): RawByteString;
procedure CheckHR(Value: HRESULT; const Operation: string);
procedure WriteNewFile(const Path: UnicodeString; const Bytes: RawByteString);
procedure MakeDirectory(const Path: UnicodeString);
procedure ListOfferedFormats(const Data: IDataObject; const Log: IDragLog);

implementation

type
  TEntry = record
    Format: Word;
    Kind: DWORD;
    Index: Integer;
    Bytes: RawByteString;
    SourcePath: UnicodeString;
  end;
  TMediumOwner = class(TInterfacedObject)
    Memory: HGLOBAL;
    Log: IDragLog;
    destructor Destroy; override;
  end;
  TPayloadObject = class(TInterfacedObject, IDataObject)
  private
    FEntries: array of TEntry;
    FInner: IDataObject;
    FShellOnly, FProviderOwned, FFailData: Boolean;
    FRoot: UnicodeString;
    FLog: IDragLog;
    function Render(const Entry: TEntry; out Medium: TStgMedium): HRESULT;
  public
    constructor Create(const Options: TDragOptions; const Log: IDragLog);
    procedure Add(Format: Word; Kind: DWORD; const Bytes: RawByteString;
      Index: Integer = -1; const SourcePath: UnicodeString = '');
    function GetData(const Format: TFormatEtc; out Medium: TStgMedium): HRESULT; stdcall;
    function GetDataHere(const Format: TFormatEtc; out Medium: TStgMedium): HRESULT; stdcall;
    function QueryGetData(const Format: TFormatEtc): HRESULT; stdcall;
    function GetCanonicalFormatEtc(const Format: TFormatEtc; out Canonical: TFormatEtc): HRESULT; stdcall;
    function SetData(const Format: TFormatEtc; var Medium: TStgMedium; Release: BOOL): HRESULT; stdcall;
    function EnumFormatEtc(Direction: DWORD; out Formats: IEnumFormatEtc): HRESULT; stdcall;
    function DAdvise(const Format: TFormatEtc; Flags: DWORD; const Sink: IAdviseSink; out Connection: DWORD): HRESULT; stdcall;
    function DUnadvise(Connection: DWORD): HRESULT; stdcall;
    function EnumDAdvise(out Advises: IEnumStatData): HRESULT; stdcall;
  end;

function CreateFormatEnumerator(Count: UINT; Formats: PFormatEtc;
  out Enumerator: IEnumFormatEtc): HRESULT; stdcall;
  external 'shell32.dll' name 'SHCreateStdEnumFmtEtc';

function CreateShellObject(Parent: PItemIDList; Count: UINT; Children: Pointer;
  Inner: Pointer; const IID: TGUID; out Obj): HRESULT; stdcall;
  external 'shell32.dll' name 'SHCreateDataObject';

procedure CheckHR(Value: HRESULT; const Operation: string);
begin
  if Value < 0 then raise Exception.Create(Operation + ': ' + IntToHex(LongWord(Value), 8));
end;

procedure MakeDirectory(const Path: UnicodeString);
var Attributes: DWORD;
begin
  if CreateDirectoryW(PWideChar(Path), nil) then Exit;
  if GetLastError <> ERROR_ALREADY_EXISTS then RaiseLastOSError;
  Attributes := GetFileAttributesW(PWideChar(Path));
  if (Attributes = INVALID_FILE_ATTRIBUTES) or
    ((Attributes and FILE_ATTRIBUTE_DIRECTORY) = 0) or
    ((Attributes and FILE_ATTRIBUTE_REPARSE_POINT) <> 0) then
    raise Exception.Create('The output path is not a regular directory');
end;

procedure WriteNewFile(const Path: UnicodeString; const Bytes: RawByteString);
var Handle: THandle; Written: DWORD;
begin
  Handle := CreateFileW(PWideChar(Path), GENERIC_WRITE, 0, nil, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, 0);
  if Handle = INVALID_HANDLE_VALUE then
  begin
    if GetLastError = ERROR_FILE_EXISTS then Exit;
    RaiseLastOSError;
  end;
  try
    if Length(Bytes) > 0 then
      if not WriteFile(Handle, Bytes[1], Length(Bytes), Written, nil) or
        (Written <> DWORD(Length(Bytes))) then RaiseLastOSError;
  finally CloseHandle(Handle); end;
end;

constructor TDragLog.Create(const Path: string);
begin
  inherited Create;
  Lines := TStringList.Create;
  Filename := Path;
end;

destructor TDragLog.Destroy;
begin Lines.Free; inherited Destroy; end;

procedure TDragLog.Add(const Value: string);
var Line: string; Stream: TFileStream;
begin
  Line := FormatDateTime('hh:nn:ss.zzz', Now) + '  ' + Value;
  Lines.Add(Line);
  Inc(Revision);
  if Lines.Count > 2000 then Lines.Delete(0);
  if Filename = '' then Exit;
  try
    if FileExists(Filename) then Stream := TFileStream.Create(Filename, fmOpenWrite or fmShareDenyWrite)
    else Stream := TFileStream.Create(Filename, fmCreate);
    try
      Stream.Position := Stream.Size;
      Line := Line + #13#10;
      Stream.WriteBuffer(Pointer(Line)^, Length(Line));
    finally Stream.Free; end;
  except
    // A locked log must not change ownership or interrupt an OLE callback.
  end;
end;

function WideBytes(const Text: UnicodeString): RawByteString;
begin
  SetLength(Result, (Length(Text) + 1) * 2);
  Move(PWideChar(Text)^, Result[1], Length(Result));
end;

function EncodedANSIBytes(const Text: UnicodeString; CodePage: UINT): RawByteString;
var Required: Integer; UsedDefault: BOOL;
begin
  if CodePage = CP_UTF8 then Exit(RawByteString(UTF8Encode(Text)) + #0);
  UsedDefault := False;
  Required := WideCharToMultiByte(CodePage, WC_NO_BEST_FIT_CHARS, PWideChar(Text),
    Length(Text), nil, 0, nil, @UsedDefault);
  if (Required = 0) and (Text <> '') then RaiseLastOSError;
  SetLength(Result, Required + 1);
  if Required > 0 then
    if WideCharToMultiByte(CodePage, WC_NO_BEST_FIT_CHARS, PWideChar(Text), Length(Text),
      PAnsiChar(Result), Required, nil, @UsedDefault) = 0 then RaiseLastOSError;
  if UsedDefault then raise Exception.Create('The selected ANSI code page cannot represent this text. Choose Unicode.');
  Result[Required + 1] := #0;
end;

function ANSIBytes(const Text: UnicodeString): RawByteString;
begin Result := EncodedANSIBytes(Text, GetACP); end;

function FormatName(Format: Word): string;
var Buffer: array[0..255] of WideChar;
begin
  case Format of
    CF_HDROP: Exit('CF_HDROP');
    CF_TEXT: Exit('CF_TEXT');
    CF_UNICODETEXT: Exit('CF_UNICODETEXT');
    CF_LOCALE: Exit('CF_LOCALE');
  end;
  if GetClipboardFormatNameW(Format, @Buffer, Length(Buffer)) > 0 then
    Result := UTF8Encode(UnicodeString(PWideChar(@Buffer)))
  else Result := 'format #' + IntToStr(Format);
end;

function MediaName(Kind: DWORD): string;
begin
  Result := '';
  if (Kind and TYMED_HGLOBAL) <> 0 then Result := Result + 'HGLOBAL ';
  if (Kind and TYMED_ISTREAM) <> 0 then Result := Result + 'IStream ';
  if (Kind and TYMED_ISTORAGE) <> 0 then Result := Result + 'IStorage ';
  if (Kind and TYMED_FILE) <> 0 then Result := Result + 'TYMED_FILE ';
  if Result = '' then Result := IntToHex(Kind, 8);
  Result := Trim(Result);
end;

function ShellDataFromIDList(ID: PItemIDList): IDataObject;
var Parent: IShellFolder; Child: PItemIDList;
begin
  if SHBindToParent(ID, IID_IShellFolder, @Parent, Child) = S_OK then
    if Parent.GetUIObjectOf(0, 1, Child, IID_IDataObject, nil, Result) = S_OK then Exit;
  CheckHR(CreateShellObject(nil, 1, @ID, nil, IID_IDataObject, Result), 'Create Shell data object');
end;

function NativeShellData(const Targets: TStrings): IDataObject;
var Absolute, Child: array of PItemIDList; Parent: IShellFolder; I: Integer;
begin
  if Targets.Count = 0 then raise Exception.Create('Enter a filesystem path or Shell parsing name.');
  SetLength(Absolute, Targets.Count);
  SetLength(Child, Targets.Count);
  try
    for I := 0 to Targets.Count - 1 do
    begin
      CheckHR(SHParseDisplayName(PWideChar(UTF8Decode(Targets[I])), nil, Absolute[I], 0, nil), 'Parse Shell object');
      if Targets.Count = 1 then
      begin
        if SHBindToParent(Absolute[I], IID_IShellFolder, @Parent, Child[I]) = S_OK then
          if Parent.GetUIObjectOf(0, 1, Child[I], IID_IDataObject, nil, Result) = S_OK then Exit;
      end;
    end;
    // The Shell supplies the standard object when no provider exposes its own object.
    CheckHR(CreateShellObject(nil, Length(Absolute), @Absolute[0], nil, IID_IDataObject, Result), 'Create Shell data object');
  finally
    for I := 0 to High(Absolute) do CoTaskMemFree(Absolute[I]);
  end;
end;

destructor TMediumOwner.Destroy;
begin
  if Memory <> 0 then
  begin
    if GlobalFlags(Memory) = GMEM_INVALID_HANDLE then
      Log.Add('ERROR: target freed provider-owned HGLOBAL before release')
    else GlobalFree(Memory);
    Log.Add('Provider-owned HGLOBAL released');
  end;
  inherited Destroy;
end;

constructor TPayloadObject.Create(const Options: TDragOptions; const Log: IDragLog);
begin
  inherited Create;
  FRoot := Options.Root;
  FLog := Log;
  FProviderOwned := Options.ProviderOwned;
  FFailData := Options.FailData;
end;

procedure TPayloadObject.Add(Format: Word; Kind: DWORD; const Bytes: RawByteString;
  Index: Integer; const SourcePath: UnicodeString);
var N: Integer;
begin
  N := Length(FEntries);
  SetLength(FEntries, N + 1);
  FEntries[N].Format := Format;
  FEntries[N].Kind := Kind;
  FEntries[N].Bytes := Bytes;
  FEntries[N].Index := Index;
  FEntries[N].SourcePath := SourcePath;
end;

function TPayloadObject.QueryGetData(const Format: TFormatEtc): HRESULT;
var Entry: TEntry;
begin
  if Format.dwAspect <> DVASPECT_CONTENT then Exit(DV_E_DVASPECT);
  if Format.ptd <> nil then Exit(DV_E_DVTARGETDEVICE);
  if FInner <> nil then
  begin
    if FShellOnly and (Format.cfFormat <> RegisterClipboardFormat('Shell IDList Array')) then Exit(DV_E_FORMATETC);
    if FShellOnly and ((Format.tymed and TYMED_HGLOBAL) = 0) then Exit(DV_E_TYMED);
    Exit(FInner.QueryGetData(Format));
  end;
  for Entry in FEntries do
    if (Entry.Format = Format.cfFormat) and (Entry.Index = Format.lindex) and
      ((Entry.Kind and Format.tymed) <> 0) then Exit(S_OK);
  Result := DV_E_FORMATETC;
end;

function TPayloadObject.Render(const Entry: TEntry; out Medium: TStgMedium): HRESULT;
var Memory: Pointer; Stream: TMemoryStream; StreamIntf: IStream; Storage: IStorage;
  Owner: TMediumOwner; OwnerIntf: IUnknown; Id: TGUID; Directory, Path: UnicodeString;
  Written: ULONG;
begin
  FillChar(Medium, SizeOf(Medium), 0);
  Result := E_FAIL;
  case Entry.Kind of
    TYMED_HGLOBAL:
      begin
        Medium.hGlobal := GlobalAlloc(GMEM_MOVEABLE or GMEM_ZEROINIT, Length(Entry.Bytes));
        if Medium.hGlobal = 0 then Exit(E_OUTOFMEMORY);
        Medium.tymed := TYMED_HGLOBAL;
        Memory := GlobalLock(Medium.hGlobal);
        if (Memory = nil) and (Length(Entry.Bytes) > 0) then
        begin GlobalFree(Medium.hGlobal); FillChar(Medium, SizeOf(Medium), 0); Exit(E_OUTOFMEMORY); end;
        if Length(Entry.Bytes) > 0 then Move(Entry.Bytes[1], Memory^, Length(Entry.Bytes));
        if Memory <> nil then GlobalUnlock(Medium.hGlobal);
        if FProviderOwned then
        begin
          Owner := TMediumOwner.Create;
          Owner.Memory := Medium.hGlobal; Owner.Log := FLog;
          OwnerIntf := Owner;
          Medium.pUnkForRelease := Pointer(OwnerIntf); OwnerIntf._AddRef;
        end;
      end;
    TYMED_ISTREAM:
      begin
        Stream := TMemoryStream.Create;
        try
          if Length(Entry.Bytes) > 0 then Stream.WriteBuffer(Entry.Bytes[1], Length(Entry.Bytes));
          Stream.Position := 0;
          StreamIntf := TStreamAdapter.Create(Stream, soOwned);
        except Stream.Free; raise; end;
        Medium.pstm := Pointer(StreamIntf); StreamIntf._AddRef;
      end;
    TYMED_ISTORAGE:
      begin
        CheckHR(StgCreateDocfile(nil, STGM_CREATE or STGM_READWRITE or STGM_SHARE_EXCLUSIVE or
          STGM_DELETEONRELEASE, 0, Storage), 'Create virtual compound storage');
        CheckHR(Storage.CreateStream('Contents', STGM_CREATE or STGM_READWRITE or
          STGM_SHARE_EXCLUSIVE, 0, 0, StreamIntf), 'Create compound stream');
        if Length(Entry.Bytes) > 0 then
        begin
          CheckHR(StreamIntf.Write(@Entry.Bytes[1], Length(Entry.Bytes), @Written), 'Write compound contents');
          if Written <> DWORD(Length(Entry.Bytes)) then raise Exception.Create('Incomplete compound storage write');
        end;
        StreamIntf := nil;
        CheckHR(Storage.Commit(STGC_DEFAULT), 'Commit compound storage');
        Medium.pstg := Pointer(Storage); Storage._AddRef;
      end;
    TYMED_FILE:
      begin
        MakeDirectory(FRoot + '\transfers');
        CheckHR(CreateGUID(Id), 'Create transfer identifier');
        Directory := FRoot + '\transfers\' + UnicodeString(GUIDToString(Id));
        if not CreateDirectoryW(PWideChar(Directory), nil) then RaiseLastOSError;
        Path := Directory + '\' + ExtractFileName(Entry.SourcePath);
        if not CopyFileW(PWideChar(Entry.SourcePath), PWideChar(Path), True) then RaiseLastOSError;
        Medium.lpszFileName := CoTaskMemAlloc((Length(Path) + 1) * 2);
        if Medium.lpszFileName = nil then
        begin DeleteFileW(PWideChar(Path)); Exit(E_OUTOFMEMORY); end;
        Move(PWideChar(Path)^, Medium.lpszFileName^, (Length(Path) + 1) * 2);
        FLog.Add('TYMED_FILE exposes a disposable copy: ' + UTF8Encode(Path));
      end;
  else Exit(DV_E_TYMED);
  end;
  Medium.tymed := Entry.Kind;
  Result := S_OK;
end;

function TPayloadObject.GetData(const Format: TFormatEtc; out Medium: TStgMedium): HRESULT;
var Entry: TEntry;
begin
  FillChar(Medium, SizeOf(Medium), 0);
  Result := QueryGetData(Format);
  if Result = S_OK then
  try
    if FFailData then Result := E_FAIL
    else if FInner <> nil then Result := FInner.GetData(Format, Medium)
    else
      for Entry in FEntries do
        if (Entry.Format = Format.cfFormat) and (Entry.Index = Format.lindex) and
          ((Entry.Kind and Format.tymed) <> 0) then
        begin Result := Render(Entry, Medium); Break; end;
  except
    on E: Exception do
    begin
      if Medium.tymed <> TYMED_NULL then ReleaseStgMedium(Medium);
      FillChar(Medium, SizeOf(Medium), 0);
      FLog.Add('Render error: ' + E.Message); Result := E_FAIL;
    end;
  end;
  FLog.Add('GetData ' + FormatName(Format.cfFormat) + ' requested=' + MediaName(Format.tymed) +
    ' index=' + IntToStr(Format.lindex) + ' result=0x' + IntToHex(LongWord(Result), 8) +
    ' returned=' + MediaName(Medium.tymed));
end;

function TPayloadObject.GetDataHere(const Format: TFormatEtc; out Medium: TStgMedium): HRESULT;
begin FillChar(Medium, SizeOf(Medium), 0); Result := E_NOTIMPL; end;
function TPayloadObject.GetCanonicalFormatEtc(const Format: TFormatEtc; out Canonical: TFormatEtc): HRESULT;
begin FillChar(Canonical, SizeOf(Canonical), 0); Result := E_NOTIMPL; end;
function TPayloadObject.SetData(const Format: TFormatEtc; var Medium: TStgMedium; Release: BOOL): HRESULT;
begin
  FLog.Add('Target SetData ' + FormatName(Format.cfFormat));
  if FInner <> nil then Result := FInner.SetData(Format, Medium, Release)
  else Result := E_NOTIMPL;
end;
function TPayloadObject.EnumFormatEtc(Direction: DWORD; out Formats: IEnumFormatEtc): HRESULT;
var Values: array of TFormatEtc; I: Integer;
begin
  Formats := nil;
  if Direction <> DATADIR_GET then Exit(E_NOTIMPL);
  if (FInner <> nil) and not FShellOnly then Exit(FInner.EnumFormatEtc(Direction, Formats));
  if FShellOnly then
  begin
    SetLength(Values, 1);
    Values[0].cfFormat := RegisterClipboardFormat('Shell IDList Array');
    Values[0].tymed := TYMED_HGLOBAL;
    Values[0].dwAspect := DVASPECT_CONTENT;
    Values[0].lindex := -1;
  end
  else
  begin
    SetLength(Values, Length(FEntries));
    for I := 0 to High(Values) do
    begin
      Values[I].cfFormat := FEntries[I].Format; Values[I].tymed := FEntries[I].Kind;
      Values[I].dwAspect := DVASPECT_CONTENT; Values[I].lindex := FEntries[I].Index;
    end;
  end;
  if Length(Values) = 0 then Exit(E_NOTIMPL);
  Result := CreateFormatEnumerator(Length(Values), @Values[0], Formats);
end;
function TPayloadObject.DAdvise(const Format: TFormatEtc; Flags: DWORD; const Sink: IAdviseSink; out Connection: DWORD): HRESULT;
begin Connection := 0; Result := OLE_E_ADVISENOTSUPPORTED; end;
function TPayloadObject.DUnadvise(Connection: DWORD): HRESULT;
begin Result := OLE_E_ADVISENOTSUPPORTED; end;
function TPayloadObject.EnumDAdvise(out Advises: IEnumStatData): HRESULT;
begin Advises := nil; Result := OLE_E_ADVISENOTSUPPORTED; end;

function FileDropBytes(const Lines: TStrings; Wide: Boolean): RawByteString;
var Text: UnicodeString; Names: RawByteString; I: Integer;
begin
  Text := '';
  for I := 0 to Lines.Count - 1 do Text := Text + UTF8Decode(Lines[I]) + #0;
  if Wide then Names := WideBytes(Text) else Names := ANSIBytes(Text);
  SetLength(Result, SizeOf(TDROPFILES) + Length(Names));
  FillChar(Result[1], Length(Result), 0);
  PDROPFILES(@Result[1])^.pFiles := SizeOf(TDROPFILES);
  PDROPFILES(@Result[1])^.fWide := Wide;
  Move(Names[1], Result[SizeOf(TDROPFILES) + 1], Length(Names));
end;

function BuildDragObject(const Options: TDragOptions; const Log: IDragLog): IDataObject;
var ObjectValue: TPayloadObject; Lines: TStringList; I, RecordSize: Integer; Locale: DWORD;
  Wide: Boolean; Bytes, Content: RawByteString; DescriptorW: PFILEDESCRIPTORW;
  DescriptorA: PFILEDESCRIPTORA; Format: Word; Kind: DWORD;
  Native: IDataObject; Request: TFormatEtc; Medium: TStgMedium; Memory: Pointer;
begin
  ObjectValue := TPayloadObject.Create(Options, Log);
  Result := ObjectValue;
  Lines := TStringList.Create;
  try
    Lines.Text := UTF8Encode(Options.Payload);
    for I := Lines.Count - 1 downto 0 do
      if Trim(Lines[I]) = '' then Lines.Delete(I);
    if Lines.Count = 0 then raise Exception.Create('Enter at least one target or text value.');
    case Options.Profile of
      dpNativeShell, dpShellID:
        begin
          if Options.ShellData <> nil then ObjectValue.FInner := Options.ShellData
          else ObjectValue.FInner := NativeShellData(Lines);
          ObjectValue.FShellOnly := Options.Profile = dpShellID;
        end;
      dpShellIDStream:
        begin
          if Options.ShellData <> nil then Native := Options.ShellData else Native := NativeShellData(Lines);
          FillChar(Request, SizeOf(Request), 0);
          Request.cfFormat := RegisterClipboardFormat('Shell IDList Array');
          Request.tymed := TYMED_HGLOBAL; Request.dwAspect := DVASPECT_CONTENT; Request.lindex := -1;
          CheckHR(Native.GetData(Request, Medium), 'Read native Shell ID list');
          try
            if (Medium.tymed <> TYMED_HGLOBAL) or (GlobalSize(Medium.hGlobal) > 4096) then
              raise Exception.Create('This Shell object cannot use the bounded IStream compatibility sample.');
            Memory := GlobalLock(Medium.hGlobal);
            if Memory = nil then RaiseLastOSError;
            try
              SetLength(Bytes, GlobalSize(Medium.hGlobal));
              if Length(Bytes) > 0 then Move(Memory^, Bytes[1], Length(Bytes));
            finally GlobalUnlock(Medium.hGlobal); end;
          finally ReleaseStgMedium(Medium); end;
          ObjectValue.Add(Request.cfFormat, TYMED_ISTREAM, Bytes);
        end;
      dpHDropW, dpHDropA: ObjectValue.Add(CF_HDROP, TYMED_HGLOBAL, FileDropBytes(Lines, Options.Profile = dpHDropW));
      dpURLW: ObjectValue.Add(RegisterClipboardFormat('UniformResourceLocatorW'), TYMED_HGLOBAL, WideBytes(Options.Payload));
      dpURLA: ObjectValue.Add(RegisterClipboardFormat('UniformResourceLocator'), TYMED_HGLOBAL, ANSIBytes(Options.Payload));
      dpTextW: ObjectValue.Add(CF_UNICODETEXT, TYMED_HGLOBAL, WideBytes(Options.Payload));
      dpTextA: ObjectValue.Add(CF_TEXT, TYMED_HGLOBAL, ANSIBytes(Options.Payload));
      dpText1252:
        begin
          ObjectValue.Add(CF_TEXT, TYMED_HGLOBAL, EncodedANSIBytes(Options.Payload, 1252));
          Locale := $0409;
          SetLength(Bytes, SizeOf(Locale)); Move(Locale, Bytes[1], SizeOf(Locale));
          ObjectValue.Add(CF_LOCALE, TYMED_HGLOBAL, Bytes);
        end;
      dpFilenameWGlobal..dpFilenameAFile:
        begin
          if Lines.Count <> 1 then raise Exception.Create('Filename formats carry exactly one file or folder.');
          Wide := Options.Profile in [dpFilenameWGlobal, dpFilenameWStream, dpFilenameWFile];
          if Wide then begin Format := RegisterClipboardFormat('FileNameW'); Bytes := WideBytes(UTF8Decode(Lines[0])); end
          else begin Format := RegisterClipboardFormat('FileName'); Bytes := ANSIBytes(UTF8Decode(Lines[0])); end;
          if Options.Profile in [dpFilenameWGlobal, dpFilenameAGlobal] then Kind := TYMED_HGLOBAL
          else if Options.Profile in [dpFilenameWStream, dpFilenameAStream] then Kind := TYMED_ISTREAM
          else Kind := TYMED_FILE;
          ObjectValue.Add(Format, Kind, Bytes, -1, UTF8Decode(Lines[0]));
        end;
      dpVirtualWStream..dpVirtualAStorage:
        begin
          if Lines.Count > 64 then raise Exception.Create('This test source supports up to 64 virtual files.');
          Wide := Options.Profile in [dpVirtualWStream, dpVirtualWGlobal, dpVirtualWStorage];
          if Wide then begin RecordSize := SizeOf(FILEDESCRIPTORW); Format := RegisterClipboardFormat('FileGroupDescriptorW'); end
          else begin RecordSize := SizeOf(FILEDESCRIPTORA); Format := RegisterClipboardFormat('FileGroupDescriptor'); end;
          if Options.Profile in [dpVirtualWStream, dpVirtualAStream] then Kind := TYMED_ISTREAM
          else if Options.Profile in [dpVirtualWGlobal, dpVirtualAGlobal] then Kind := TYMED_HGLOBAL
          else Kind := TYMED_ISTORAGE;
          SetLength(Bytes, 4 + Lines.Count * RecordSize); FillChar(Bytes[1], Length(Bytes), 0);
          PDWORD(@Bytes[1])^ := Lines.Count;
          ObjectValue.Add(Format, TYMED_HGLOBAL, '');
          for I := 0 to Lines.Count - 1 do
          begin
            Content := RawByteString(UTF8Encode('Virtual item ' + UnicodeString(IntToStr(I + 1)) + #13#10 + Options.Contents));
            if Wide then
            begin
              if Length(UTF8Decode(Lines[I])) >= MAX_PATH then raise Exception.Create('A virtual filename exceeds its descriptor capacity.');
              DescriptorW := Pointer(PtrUInt(@Bytes[1]) + 4 + NativeUInt(I) * RecordSize);
              DescriptorW^.dwFlags := $40; DescriptorW^.nFileSizeLow := Length(Content);
              Move(PWideChar(UTF8Decode(Lines[I]))^, DescriptorW^.cFileName, (Length(UTF8Decode(Lines[I])) + 1) * 2);
            end
            else
            begin
              DescriptorA := Pointer(PtrUInt(@Bytes[1]) + 4 + NativeUInt(I) * RecordSize);
              DescriptorA^.dwFlags := $40; DescriptorA^.nFileSizeLow := Length(Content);
              if Length(ANSIBytes(UTF8Decode(Lines[I]))) > MAX_PATH then raise Exception.Create('An ANSI filename exceeds its descriptor capacity.');
              Move(PAnsiChar(ANSIBytes(UTF8Decode(Lines[I])))^, DescriptorA^.cFileName, Length(ANSIBytes(UTF8Decode(Lines[I]))));
            end;
            ObjectValue.Add(RegisterClipboardFormat('FileContents'), Kind, Content, I);
          end;
          ObjectValue.FEntries[0].Bytes := Bytes;
        end;
      dpMixed:
        begin
          ObjectValue.Add(CF_UNICODETEXT, TYMED_HGLOBAL, WideBytes('https://example.com/text-fallback'));
          ObjectValue.Add(RegisterClipboardFormat('UniformResourceLocatorW'), TYMED_HGLOBAL, WideBytes('https://example.com/url-fallback'));
          ObjectValue.Add(CF_HDROP, TYMED_HGLOBAL, FileDropBytes(Lines, True));
        end;
      dpUnsupported: ObjectValue.Add(RegisterClipboardFormat('tdock.DragTest.Unsupported'), TYMED_HGLOBAL, 'unsupported'#0);
    end;
  finally Lines.Free; end;
end;

procedure ListOfferedFormats(const Data: IDataObject; const Log: IDragLog);
var Enumerator: IEnumFormatEtc; Format: TFormatEtc; Fetched: LongInt;
begin
  CheckHR(Data.EnumFormatEtc(DATADIR_GET, Enumerator), 'Enumerate offered formats');
  while Enumerator.Next(1, Format, @Fetched) = S_OK do
  begin
    try Log.Add('OFFER ' + FormatName(Format.cfFormat) + ' / ' + MediaName(Format.tymed) + ' / index ' + IntToStr(Format.lindex));
    finally if Format.ptd <> nil then CoTaskMemFree(Format.ptd); end;
  end;
end;

function TDragSource.QueryContinueDrag(Escape: BOOL; Keys: DWORD): HRESULT;
begin
  if Escape then Result := DRAGDROP_S_CANCEL
  else if (Keys and MK_LBUTTON) = 0 then Result := DRAGDROP_S_DROP else Result := S_OK;
end;
function TDragSource.GiveFeedback(Effect: DWORD): HRESULT;
begin Result := DRAGDROP_S_USEDEFAULTCURSORS; end;

constructor TInspectTarget.Create(const Log: IDragLog);
begin inherited Create; FLog := Log; end;
function TInspectTarget.DragEnter(const Data: IDataObject; Keys: DWORD; Point: TPoint; var Effect: DWORD): HRESULT;
begin Effect := Effect and DROPEFFECT_COPY; Result := S_OK; end;
function TInspectTarget.DragOver(Keys: DWORD; Point: TPoint; var Effect: DWORD): HRESULT;
begin Effect := Effect and DROPEFFECT_COPY; Result := S_OK; end;
function TInspectTarget.DragLeave: HRESULT;
begin Result := S_OK; end;
function TInspectTarget.Drop(const Data: IDataObject; Keys: DWORD; Point: TPoint; var Effect: DWORD): HRESULT;
var Enumerator: IEnumFormatEtc; Format: TFormatEtc; Medium: TStgMedium; Fetched: LongInt; ReadAny: Boolean; HR: HRESULT;
begin
  Effect := DROPEFFECT_NONE; Result := S_OK; ReadAny := False;
  FLog.Add('INSPECT: drop received; contents are read and released without creating launchers');
  try
    CheckHR(Data.EnumFormatEtc(DATADIR_GET, Enumerator), 'Enumerate inspector formats');
    while Enumerator.Next(1, Format, @Fetched) = S_OK do
    try
      FillChar(Medium, SizeOf(Medium), 0);
      HR := Data.GetData(Format, Medium);
      if HR = S_OK then
      try
        ReadAny := True;
        FLog.Add('INSPECT read ' + FormatName(Format.cfFormat) + ' / ' + MediaName(Medium.tymed));
      finally ReleaseStgMedium(Medium); end;
    finally if Format.ptd <> nil then CoTaskMemFree(Format.ptd); end;
    if ReadAny then Effect := DROPEFFECT_COPY;
  except on E: Exception do begin FLog.Add('INSPECT error: ' + E.Message); Result := E_FAIL; end; end;
end;

end.
