unit dropimporttests;

{$mode delphi}
{$codepage utf8}

interface

uses Windows, Classes, SysUtils, ActiveX, ShlObj, fpcunit, testregistry,
  dropimportu, DropTgtU, itemserializationu, launchserviceu, setsu;

type
  TDropImportTests = class(TTestCase)
  private
    Root, Fixture: UnicodeString;
    Batch: TDropImportBatch;
    Manager: TDropManager;
    CallbackCount, ErrorCount: Integer;
    EnterCount, OverCount, ResetCount: Integer;
    CallbackAccept, CallbackRaise, CallbackPartial, CallbackUnknown, CallbackRaiseAfterFirst: Boolean;
    LastCallbackPath: string;
    LastErrorMessage: WideString;
    procedure Callback(Value: TDropImportBatch; Window: THandle);
    procedure ReportError(Message: WideString; Silent: Boolean);
    procedure EnterFeedback(List: TStrings; Window: THandle);
    procedure OverFeedback;
    procedure ResetFeedback;
    procedure RunText(const Text: UnicodeString; ExpectedCount: Integer);
    procedure CheckFilenameMedia(Wide: Boolean; Kind: DWORD);
    procedure CheckContent(Kind: DWORD; Wide: Boolean; Mode: Integer = 0);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure UnsupportedDragShowsNoEffectWithoutReading;
    procedure EffectsPreserveCopyAndLinkWithoutGatingExtraction;
    procedure AdvertisedFormatsSurviveBrokenQueries;
    procedure PartialDropReportsCountsAndRetainsAcceptedCopy;
    procedure UndecidedDropReportsFailureAndRetainsExposedCopies;
    procedure DisabledTargetClearsFeedback;
    procedure FeedbackStateResetsAfterLeaveAndDrop;
    procedure EmptyPayloadFailsAndClearsFeedback;
    procedure UnadvertisedDataStillReachesExtraction;
    procedure FeedbackRecognizesExistingFormatsAndMedia;
    procedure UnicodeURLWinsWithoutEnumeration;
    procedure ANSIURLSupportsRegisteredScheme;
    procedure InvalidUnicodeFallsBackToANSI;
    procedure URLWinsOverVirtualAndText;
    procedure HDropWinsOverURL;
    procedure TextPathsFoldersAndURIs;
    procedure TextRejectsCommandsAndRelativePaths;
    procedure TextRejectsWholeInvalidList;
    procedure TextRejectsSemicolonsAndOversize;
    procedure TextTargetCountBoundary;
    procedure TextLocaleUsesSourceCodePage;
    procedure FilenameUnicodeGlobal;
    procedure FilenameANSIGlobal;
    procedure FilenameUnicodeStream;
    procedure FilenameANSIStream;
    procedure FilenameUnicodeFileMedium;
    procedure FilenameANSIFileMedium;
    procedure FilenameRejectsUnterminatedData;
    procedure UnicodeFilenameSurvivesSaveReloadAndLaunch;
    procedure VirtualUnicodeStream;
    procedure VirtualANSIStream;
    procedure VirtualMemory;
    procedure VirtualStorage;
    procedure VirtualPartialReadsWithoutStat;
    procedure VirtualFailedReadRemovesUnexposedFiles;
    procedure VirtualMissingContentDoesNotFallBackToText;
    procedure VirtualRejectsTruncatedDescriptors;
    procedure VirtualRejectsUnsafeNamesAndDirectories;
    procedure VirtualMemoryRequiresExactLength;
    procedure VirtualMultipleIndicesAndCollisions;
    procedure VirtualZeroLengthFile;
    procedure AcceptedCopySurvivesRestart;
    procedure RejectedCopyIsDeleted;
    procedure UncertainConsumerRetainsCopy;
    procedure StartupRemovesOnlyAbandonedIncompleteStages;
    procedure ProviderOwnedMemoryReleasesOnce;
    procedure TransferFailureReportsNoEffectAndClearsDrag;
    procedure DropAcknowledgesAcceptedTargetsOnly;
    procedure FailedGetHasNoReleaseObligation;
    procedure StorageWriteFailureDoesNotFallBack;
    procedure FailedSecondContentRemovesFirstCopy;
    procedure RejectedDropCleansCopiedFile;
    procedure ConsumerExceptionKeepsExposedFile;
    procedure StreamWithoutDeclaredSize;
    procedure MemoryWithoutDeclaredSizeRejects;
    procedure InvalidSurrogateFallsBack;
    procedure ExposedFilesRemainAfterLauncherRemoval;
  end;

implementation

type
  TTestManager = class(TDropManager)
    constructor CreateForTests;
  end;
  TMediumOwner = class(TInterfacedObject)
    Handle: HGLOBAL;
    Releases: PInteger;
    destructor Destroy; override;
  end;
  TReadProbe = class(TStreamAdapter)
    Mode: Integer;
    Releases: PInteger;
    destructor Destroy; override;
    function Read(pv: Pointer; cb: DWORD; pcbRead: PDWORD): HRESULT; override; stdcall;
    function Stat(out StatStg: TStatStg; Flags: DWORD): HRESULT; override; stdcall;
  end;
  TEntry = record
    Format: Word;
    Kind: DWORD;
    Index, Mode: Integer;
    Bytes: RawByteString;
    FilePath: UnicodeString;
    Storage: IStorage;
    ProviderOwned: Boolean;
  end;
  TData = class(TInterfacedObject, IDataObject)
    Entries: array of TEntry;
    Releases, Calls: Integer;
    FailGet, DenyQuery, EnumerateFormats: Boolean;
    procedure Add(Format: Word; Kind: DWORD; const Bytes: RawByteString; Index: Integer = -1);
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
  TLaunchProbe = class(TLaunchService)
    Target: UnicodeString;
    procedure ExecuteShellTarget(const Value, Parameters, Directory: WideString; ShowCommand: Integer); override;
    function StartShellWorker(const Value, Parameters, Directory: WideString; ShowCommand: Integer): Boolean; override;
  end;

constructor TTestManager.CreateForTests;
begin end;

function CreateFormatEnumerator(Count: UINT; Formats: PFormatEtc;
  out Enumerator: IEnumFormatEtc): HRESULT; stdcall;
  external 'shell32.dll' name 'SHCreateStdEnumFmtEtc';

destructor TMediumOwner.Destroy;
begin
  Inc(Releases^);
  if GlobalFlags(Handle) = GMEM_INVALID_HANDLE then raise Exception.Create('Borrowed memory was already freed');
  GlobalFree(Handle);
  inherited Destroy;
end;

destructor TReadProbe.Destroy;
begin
  if Releases <> nil then Inc(Releases^);
  inherited Destroy;
end;

function TReadProbe.Read(pv: Pointer; cb: DWORD; pcbRead: PDWORD): HRESULT;
var Count: LongInt;
begin
  if (Mode = 2) and (Stream.Position >= 3) then Exit(E_FAIL);
  if Mode = 0 then Exit(inherited Read(pv, cb, pcbRead));
  if cb > 3 then cb := 3;
  Count := Stream.Read(pv^, cb);
  if pcbRead <> nil then pcbRead^ := Count;
  if Count = 0 then Result := S_FALSE else Result := S_OK;
end;

function TReadProbe.Stat(out StatStg: TStatStg; Flags: DWORD): HRESULT;
begin
  FillChar(StatStg, SizeOf(StatStg), 0);
  Result := E_NOTIMPL;
end;

procedure TData.Add(Format: Word; Kind: DWORD; const Bytes: RawByteString; Index: Integer);
var N: Integer;
begin
  N := Length(Entries);
  SetLength(Entries, N + 1);
  Entries[N].Format := Format;
  Entries[N].Kind := Kind;
  Entries[N].Index := Index;
  Entries[N].Bytes := Bytes;
end;

function TData.QueryGetData(const Format: TFormatEtc): HRESULT;
var Entry: TEntry;
begin
  if DenyQuery then Exit(DV_E_FORMATETC);
  for Entry in Entries do
    if (Entry.Format = Format.cfFormat) and (Entry.Index = Format.lindex) and
      (Format.dwAspect = DVASPECT_CONTENT) and ((Entry.Kind and Format.tymed) <> 0) then Exit(S_OK);
  Result := DV_E_FORMATETC;
end;

function TData.GetData(const Format: TFormatEtc; out Medium: TStgMedium): HRESULT;
var Entry: TEntry; Memory: Pointer; Stream: TMemoryStream; Probe: TReadProbe;
  Owner: IUnknown; StreamInterface: IStream;
begin
  FillChar(Medium, SizeOf(Medium), 0);
  Result := DV_E_FORMATETC;
  if Format.dwAspect <> DVASPECT_CONTENT then Exit;
  for Entry in Entries do
    if (Entry.Format = Format.cfFormat) and (Entry.Index = Format.lindex) and
      ((Entry.Kind and Format.tymed) <> 0) then
    begin
      Inc(Calls);
      if FailGet then Exit(E_FAIL);
      Medium.tymed := Entry.Kind;
      case Entry.Kind of
        TYMED_HGLOBAL:
          begin
            Medium.hGlobal := GlobalAlloc(GMEM_MOVEABLE or GMEM_ZEROINIT, Length(Entry.Bytes));
            Memory := GlobalLock(Medium.hGlobal);
            if Length(Entry.Bytes) > 0 then Move(Entry.Bytes[1], Memory^, Length(Entry.Bytes));
            GlobalUnlock(Medium.hGlobal);
            if Entry.ProviderOwned then
            begin
              Owner := TMediumOwner.Create;
              TMediumOwner(Owner as TMediumOwner).Handle := Medium.hGlobal;
              TMediumOwner(Owner as TMediumOwner).Releases := @Releases;
              Medium.pUnkForRelease := Pointer(Owner);
              Owner._AddRef;
            end;
          end;
        TYMED_ISTREAM:
          begin
            Stream := TMemoryStream.Create;
            if Length(Entry.Bytes) > 0 then Stream.WriteBuffer(Entry.Bytes[1], Length(Entry.Bytes));
            Stream.Position := 0;
            Probe := TReadProbe.Create(Stream, soOwned);
            Probe.Mode := Entry.Mode;
            Probe.Releases := @Releases;
            StreamInterface := Probe;
            Medium.pstm := Pointer(StreamInterface);
            StreamInterface._AddRef;
          end;
        TYMED_FILE:
          begin
            Medium.lpszFileName := CoTaskMemAlloc((Length(Entry.FilePath) + 1) * 2);
            Move(PWideChar(Entry.FilePath)^, Medium.lpszFileName^, (Length(Entry.FilePath) + 1) * 2);
          end;
        TYMED_ISTORAGE:
          begin Medium.pstg := Pointer(Entry.Storage); Entry.Storage._AddRef; end;
      end;
      Exit(S_OK);
    end;
end;

function TData.GetDataHere(const Format: TFormatEtc; out Medium: TStgMedium): HRESULT;
begin FillChar(Medium, SizeOf(Medium), 0); Result := E_NOTIMPL; end;
function TData.GetCanonicalFormatEtc(const Format: TFormatEtc; out Canonical: TFormatEtc): HRESULT;
begin FillChar(Canonical, SizeOf(Canonical), 0); Result := E_NOTIMPL; end;
function TData.SetData(const Format: TFormatEtc; var Medium: TStgMedium; Release: BOOL): HRESULT;
begin Result := E_NOTIMPL; end;
function TData.EnumFormatEtc(Direction: DWORD; out Formats: IEnumFormatEtc): HRESULT;
var Values: array of TFormatEtc; I: Integer;
begin
  Formats := nil;
  if not EnumerateFormats or (Direction <> DATADIR_GET) then Exit(E_NOTIMPL);
  SetLength(Values, Length(Entries));
  for I := 0 to High(Values) do
  begin
    Values[I].cfFormat := Entries[I].Format;
    Values[I].tymed := Entries[I].Kind;
    Values[I].dwAspect := DVASPECT_CONTENT;
    Values[I].lindex := Entries[I].Index;
  end;
  if Length(Values) = 0 then Result := CreateFormatEnumerator(0, nil, Formats)
  else Result := CreateFormatEnumerator(Length(Values), @Values[0], Formats);
end;
function TData.DAdvise(const Format: TFormatEtc; Flags: DWORD; const Sink: IAdviseSink; out Connection: DWORD): HRESULT;
begin Connection := 0; Result := E_NOTIMPL; end;
function TData.DUnadvise(Connection: DWORD): HRESULT;
begin Result := E_NOTIMPL; end;
function TData.EnumDAdvise(out Advises: IEnumStatData): HRESULT;
begin Advises := nil; Result := E_NOTIMPL; end;

function WideBytes(const Text: UnicodeString): RawByteString;
begin
  SetLength(Result, (Length(Text) + 1) * 2);
  Move(PWideChar(Text)^, Result[1], Length(Result));
end;

function DescriptorBytes(const Names: array of UnicodeString; Wide: Boolean;
  ContentSize: Integer = 11): RawByteString;
var I, RecordSize: Integer; W: PFILEDESCRIPTORW; A: PFILEDESCRIPTORA; Encoded: RawByteString;
begin
  if Wide then RecordSize := SizeOf(FILEDESCRIPTORW) else RecordSize := SizeOf(FILEDESCRIPTORA);
  SetLength(Result, 4 + Length(Names) * RecordSize);
  FillChar(Result[1], Length(Result), 0);
  PDWORD(@Result[1])^ := Length(Names);
  for I := 0 to High(Names) do
    if Wide then
    begin
      W := Pointer(PtrUInt(@Result[1]) + 4 + NativeUInt(I) * RecordSize);
      W^.dwFlags := FD_FILESIZE_FLAG;
      W^.nFileSizeLow := ContentSize;
      Move(PWideChar(Names[I])^, W^.cFileName, (Length(Names[I]) + 1) * 2);
    end
    else
    begin
      A := Pointer(PtrUInt(@Result[1]) + 4 + NativeUInt(I) * RecordSize);
      A^.dwFlags := FD_FILESIZE_FLAG;
      A^.nFileSizeLow := ContentSize;
      Encoded := AnsiString(Names[I]) + #0;
      Move(Encoded[1], A^.cFileName, Length(Encoded));
    end;
end;

function NewData(out Value: TData): IDataObject;
begin Value := TData.Create; Result := Value; end;

function ReadFileBytes(const Path: UnicodeString): RawByteString;
var Handle: THandle; Size, ReadCount: DWORD;
begin
  Handle := CreateFileW(PWideChar(Path), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0);
  if Handle = INVALID_HANDLE_VALUE then RaiseLastOSError;
  try
    Size := GetFileSize(Handle, nil);
    SetLength(Result, Size);
    if Size > 0 then
      if not ReadFile(Handle, Result[1], Size, ReadCount, nil) or (ReadCount <> Size) then RaiseLastOSError;
  finally CloseHandle(Handle); end;
end;

procedure CreateFixtureFile(const Path: UnicodeString; const Bytes: RawByteString);
var Handle: THandle; Written: DWORD;
begin
  Handle := CreateFileW(PWideChar(Path), GENERIC_WRITE, 0, nil, CREATE_ALWAYS, 0, 0);
  if Handle = INVALID_HANDLE_VALUE then RaiseLastOSError;
  try
    if Length(Bytes) > 0 then
      if not WriteFile(Handle, Bytes[1], Length(Bytes), Written, nil) then RaiseLastOSError;
  finally CloseHandle(Handle); end;
end;

procedure TLaunchProbe.ExecuteShellTarget(const Value, Parameters, Directory: WideString; ShowCommand: Integer);
begin Target := Value; end;
function TLaunchProbe.StartShellWorker(const Value, Parameters, Directory: WideString; ShowCommand: Integer): Boolean;
begin Target := Value; Result := True; end;

procedure TDropImportTests.SetUp;
var Id: TGUID;
begin
  OleInitialize(nil);
  CreateGUID(Id);
  Root := UTF8Decode(ExtractFilePath(ParamStr(0))) + 'fixture-' + GUIDToString(Id);
  if not CreateDirectoryW(PWideChar(Root), nil) then RaiseLastOSError;
  Fixture := Root + '\文档 with space-Ж.txt';
  CreateFixtureFile(Fixture, 'fixture');
  Batch := TDropImportBatch.Create(Root + '\ImportedFiles');
  Manager := TTestManager.CreateForTests;
  Manager.ImportStorage := Root + '\ImportedFiles';
  CallbackAccept := True;
  CallbackRaise := False;
  CallbackPartial := False;
  CallbackUnknown := False;
  CallbackRaiseAfterFirst := False;
  CallbackCount := 0;
  ErrorCount := 0;
  EnterCount := 0;
  OverCount := 0;
  ResetCount := 0;
  Manager.OnDragEnter := EnterFeedback;
  Manager.OnDragOver := OverFeedback;
  Manager.OnDragReset := ResetFeedback;
end;

procedure RemoveFixture(const Path: UnicodeString);
var Search: THandle; Data: TWin32FindDataW; Child: UnicodeString;
begin
  Search := FindFirstFileW(PWideChar(Path + '\*'), Data);
  if Search <> INVALID_HANDLE_VALUE then
  try
    repeat
      Child := Data.cFileName;
      if (Child = '.') or (Child = '..') then Continue;
      Child := Path + '\' + Child;
      if (Data.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT) <> 0 then
        raise Exception.Create('Unexpected fixture reparse point');
      if (Data.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then RemoveFixture(Child)
      else DeleteFileW(PWideChar(Child));
    until not FindNextFileW(Search, Data);
  finally Windows.FindClose(Search); end;
  RemoveDirectoryW(PWideChar(Path));
end;

procedure TDropImportTests.TearDown;
begin
  Batch.Free;
  Manager.Free;
  // Root is a directly created GUID directory beneath the test executable.
  if Pos(UTF8Decode(ExtractFilePath(ParamStr(0))) + 'fixture-{', Root) <> 1 then
    raise Exception.Create('Unsafe fixture cleanup path');
  RemoveFixture(Root);
  OleUninitialize;
end;

procedure TDropImportTests.Callback(Value: TDropImportBatch; Window: THandle);
var I: Integer;
begin
  Inc(CallbackCount);
  if Value.Count > 0 then LastCallbackPath := Value[0];
  if CallbackRaise then raise Exception.Create('Consumer failed after exposure');
  for I := 0 to Value.Count - 1 do
    if not CallbackUnknown or (I < Value.Count - 1) then
    begin
      Value.Decide(I, CallbackAccept and (not CallbackPartial or (I = 0)));
      if CallbackRaiseAfterFirst and (I = 0) then raise Exception.Create('Consumer stopped after the first target');
    end;
end;

procedure TDropImportTests.ReportError(Message: WideString; Silent: Boolean);
begin Inc(ErrorCount); LastErrorMessage := Message; end;

procedure TDropImportTests.EnterFeedback(List: TStrings; Window: THandle);
begin Inc(EnterCount); end;
procedure TDropImportTests.OverFeedback;
begin Inc(OverCount); end;
procedure TDropImportTests.ResetFeedback;
begin Inc(ResetCount); end;

procedure TDropImportTests.UnsupportedDragShowsNoEffectWithoutReading;
var Data: IDataObject; Value: TData; Effect: DWORD;
begin
  Data := NewData(Value);
  Value.Add(RegisterClipboardFormat('tdock.Unsupported'), TYMED_HGLOBAL, 'unsupported');
  Value.EnumerateFormats := True;
  Manager.OnDrop := Callback;
  Effect := DROPEFFECT_COPY or DROPEFFECT_LINK;
  AssertEquals(S_OK, Manager.DragEnter(Data, 0, Point(0, 0), Effect));
  AssertEquals('Unsupported hover must not advertise acceptance', 0, Integer(Effect));
  AssertEquals('Hover must not retrieve payloads', 0, Value.Calls);
end;

procedure TDropImportTests.EffectsPreserveCopyAndLinkWithoutGatingExtraction;
const Allowed: array[0..7] of DWORD = (DROPEFFECT_COPY, DROPEFFECT_LINK,
  DROPEFFECT_COPY or DROPEFFECT_LINK, DROPEFFECT_COPY or DROPEFFECT_LINK,
  DROPEFFECT_COPY, DROPEFFECT_COPY or DROPEFFECT_LINK, DROPEFFECT_MOVE, 0);
  Keys: array[0..7] of DWORD = (0, 0, 0, MK_CONTROL or MK_SHIFT,
    MK_CONTROL or MK_SHIFT, MK_SHIFT, 0, 0);
  Expected: array[0..7] of DWORD = (DROPEFFECT_COPY, DROPEFFECT_LINK,
    DROPEFFECT_COPY, DROPEFFECT_LINK, DROPEFFECT_COPY, DROPEFFECT_COPY, 0, 0);
var Data: IDataObject; Value: TData; Effect: DWORD; I, CallsBefore: Integer;
begin
  Data := NewData(Value);
  Value.Add(RegisterClipboardFormat('UniformResourceLocatorW'), TYMED_HGLOBAL,
    WideBytes('unknown-tdock-scheme:extractable'));
  Manager.OnDrop := Callback;
  for I := 0 to High(Allowed) do
  begin
    CallsBefore := Value.Calls;
    Effect := Allowed[I];
    AssertEquals(S_OK, Manager.DragEnter(Data, Keys[I], Point(0, 0), Effect));
    AssertEquals('Entry effect ' + IntToStr(I), Integer(Expected[I]), Integer(Effect));
    Effect := Allowed[I];
    AssertEquals(S_OK, Manager.DragOver(Keys[I], Point(0, 0), Effect));
    AssertEquals('Hover effect ' + IntToStr(I), Integer(Expected[I]), Integer(Effect));
    AssertEquals('Feedback must not extract', CallsBefore, Value.Calls);
    Effect := Allowed[I];
    AssertEquals(S_OK, Manager.Drop(Data, Keys[I], Point(0, 0), Effect));
    AssertEquals('Completion effect ' + IntToStr(I), Integer(Expected[I]), Integer(Effect));
    AssertEquals('Every extractable target must reach the consumer', I + 1, CallbackCount);
    AssertEquals('unknown-tdock-scheme:extractable', LastCallbackPath);
  end;
end;

procedure TDropImportTests.AdvertisedFormatsSurviveBrokenQueries;
var Data: IDataObject; Value: TData; Effect: DWORD;
begin
  Data := NewData(Value);
  Value.Add(RegisterClipboardFormat('UniformResourceLocatorW'), TYMED_HGLOBAL,
    WideBytes('unknown-tdock-scheme:extractable'));
  Value.DenyQuery := True;
  Value.EnumerateFormats := True;
  Manager.OnDrop := Callback;
  Effect := DROPEFFECT_COPY;
  AssertEquals(S_OK, Manager.DragEnter(Data, 0, Point(0, 0), Effect));
  AssertEquals('Advertised formats must preserve hover acceptance', Integer(DROPEFFECT_COPY), Integer(Effect));
  AssertEquals(0, Value.Calls);
  Effect := DROPEFFECT_COPY;
  AssertEquals(S_OK, Manager.Drop(Data, 0, Point(0, 0), Effect));
  AssertEquals(1, CallbackCount);
  AssertEquals('unknown-tdock-scheme:extractable', LastCallbackPath);
end;

procedure TDropImportTests.PartialDropReportsCountsAndRetainsAcceptedCopy;
var Data: IDataObject; Value: TData; Effect: DWORD; RejectedPath: UnicodeString;
begin
  Data := NewData(Value);
  Value.Add(RegisterClipboardFormat('FileGroupDescriptorW'), TYMED_HGLOBAL,
    DescriptorBytes(['accepted.txt', 'rejected.txt'], True));
  Value.Add(RegisterClipboardFormat('FileContents'), TYMED_HGLOBAL, 'hello world', 0);
  Value.Add(RegisterClipboardFormat('FileContents'), TYMED_HGLOBAL, 'hello world', 1);
  Manager.OnDrop := Callback;
  Manager.OnError := ReportError;
  CallbackPartial := True;
  Effect := DROPEFFECT_COPY;
  AssertEquals(S_OK, Manager.Drop(Data, 0, Point(0, 0), Effect));
  AssertEquals(Integer(DROPEFFECT_COPY), Integer(Effect));
  AssertEquals('Partial acceptance must be reported once', 1, ErrorCount);
  AssertTrue(Pos('1 of 2', LastErrorMessage) > 0);
  AssertEquals('hello world', ReadFileBytes(UTF8Decode(LastCallbackPath)));
  RejectedPath := ExtractFilePath(UTF8Decode(LastCallbackPath)) + 'rejected.txt';
  AssertEquals(INVALID_FILE_ATTRIBUTES, GetFileAttributesW(PWideChar(RejectedPath)));
end;

procedure TDropImportTests.UndecidedDropReportsFailureAndRetainsExposedCopies;
var Data: IDataObject; Value: TData; Effect: DWORD; UnknownPath: UnicodeString;
begin
  Data := NewData(Value);
  Value.Add(RegisterClipboardFormat('FileGroupDescriptorW'), TYMED_HGLOBAL,
    DescriptorBytes(['accepted.txt', 'unknown.txt'], True));
  Value.Add(RegisterClipboardFormat('FileContents'), TYMED_HGLOBAL, 'hello world', 0);
  Value.Add(RegisterClipboardFormat('FileContents'), TYMED_HGLOBAL, 'hello world', 1);
  Manager.OnDrop := Callback;
  Manager.OnError := ReportError;
  CallbackUnknown := True;
  Effect := DROPEFFECT_COPY;
  AssertTrue(Manager.Drop(Data, 0, Point(0, 0), Effect) <> S_OK);
  AssertEquals('An incomplete result must not report success', 0, Integer(Effect));
  AssertEquals(1, ErrorCount);
  AssertTrue(Pos('1 of 2', LastErrorMessage) > 0);
  AssertTrue(Pos('unknown', LastErrorMessage) > 0);
  AssertEquals('hello world', ReadFileBytes(UTF8Decode(LastCallbackPath)));
  UnknownPath := ExtractFilePath(UTF8Decode(LastCallbackPath)) + 'unknown.txt';
  AssertEquals('hello world', ReadFileBytes(UnknownPath));
  CallbackUnknown := False;
  CallbackRaiseAfterFirst := True;
  Effect := DROPEFFECT_COPY;
  AssertTrue(Manager.Drop(Data, 0, Point(0, 0), Effect) <> S_OK);
  AssertEquals(0, Integer(Effect));
  AssertEquals(2, ErrorCount);
  AssertTrue('Exceptions must report confirmed progress', Pos('1 of 2', LastErrorMessage) > 0);
  AssertEquals('hello world', ReadFileBytes(UTF8Decode(LastCallbackPath)));
  UnknownPath := ExtractFilePath(UTF8Decode(LastCallbackPath)) + 'unknown.txt';
  AssertEquals('hello world', ReadFileBytes(UnknownPath));
end;

procedure TDropImportTests.DisabledTargetClearsFeedback;
var Data: IDataObject; Value: TData; Effect: DWORD; Target: TDropTarget; I, Before: Integer;
begin
  Data := NewData(Value);
  Value.Add(CF_UNICODETEXT, TYMED_HGLOBAL, WideBytes('https://example.invalid/'));
  Manager.OnDrop := Callback;
  Target := TDropTarget.Create(0, Manager);
  try
    Target.Enable := False;
    for I := 0 to 2 do
    begin
      Effect := DROPEFFECT_COPY;
      Manager.DragEnter(Data, 0, Point(0, 0), Effect);
      Before := ResetCount;
      Effect := DROPEFFECT_COPY;
      case I of
        0: Target.DragEnter(Data, 0, Point(0, 0), Effect);
        1: Target.DragOver(0, Point(0, 0), Effect);
        2: Target.Drop(Data, 0, Point(0, 0), Effect);
      end;
      AssertEquals(0, Integer(Effect));
      AssertEquals('Disabled target must clear feedback ' + IntToStr(I), Before + 1, ResetCount);
    end;
    AssertEquals(0, CallbackCount);
    AssertEquals(0, Value.Calls);
  finally Target.Free; end;
end;

procedure TDropImportTests.FeedbackStateResetsAfterLeaveAndDrop;
var Data: IDataObject; Value: TData; Effect: DWORD;
begin
  Data := NewData(Value);
  Value.Add(CF_UNICODETEXT, TYMED_HGLOBAL, WideBytes('https://example.invalid/'));
  Manager.OnDrop := Callback;
  Effect := DROPEFFECT_COPY; Manager.DragEnter(Data, 0, Point(0, 0), Effect);
  AssertEquals(1, EnterCount);
  Manager.DragLeave;
  Effect := DROPEFFECT_COPY; Manager.DragOver(0, Point(0, 0), Effect);
  AssertEquals(0, Integer(Effect));
  AssertEquals(0, OverCount);
  Effect := DROPEFFECT_COPY; Manager.DragEnter(Data, 0, Point(0, 0), Effect);
  AssertEquals(2, EnterCount);
  Effect := DROPEFFECT_COPY; Manager.Drop(Data, 0, Point(0, 0), Effect);
  AssertEquals(1, ResetCount);
  Effect := DROPEFFECT_COPY; Manager.DragOver(0, Point(0, 0), Effect);
  AssertEquals(0, Integer(Effect));
  Effect := DROPEFFECT_COPY; Manager.DragEnter(nil, 0, Point(0, 0), Effect);
  AssertEquals(2, ResetCount);
  AssertEquals(2, EnterCount);
  Manager.OnDrop := nil;
  Effect := DROPEFFECT_COPY; Manager.DragEnter(Data, 0, Point(0, 0), Effect);
  AssertEquals(0, Integer(Effect));
  Effect := DROPEFFECT_COPY; Manager.Drop(Data, 0, Point(0, 0), Effect);
  AssertEquals(4, ResetCount);
end;

procedure TDropImportTests.EmptyPayloadFailsAndClearsFeedback;
var Data: IDataObject; Value: TData; Effect: DWORD;
begin
  Data := NewData(Value);
  Value.Add(CF_UNICODETEXT, TYMED_HGLOBAL, WideBytes(''));
  Manager.OnDrop := Callback; Manager.OnError := ReportError;
  Effect := DROPEFFECT_COPY; Manager.DragEnter(Data, 0, Point(0, 0), Effect);
  AssertEquals(Integer(DROPEFFECT_COPY), Integer(Effect));
  AssertEquals(0, Value.Calls);
  Effect := DROPEFFECT_COPY;
  AssertTrue(Manager.Drop(Data, 0, Point(0, 0), Effect) <> S_OK);
  AssertEquals(0, Integer(Effect));
  AssertEquals(1, ErrorCount);
  AssertEquals(1, ResetCount);
  AssertEquals('', LastCallbackPath);
end;

procedure TDropImportTests.UnadvertisedDataStillReachesExtraction;
var Data: IDataObject; Value: TData; Effect: DWORD;
begin
  Data := NewData(Value);
  Value.Add(CF_UNICODETEXT, TYMED_HGLOBAL, WideBytes('unknown-tdock-scheme:kept'));
  Value.DenyQuery := True;
  Manager.OnDrop := Callback;
  Effect := DROPEFFECT_COPY;
  AssertEquals(S_OK, Manager.DragEnter(Data, 0, Point(0, 0), Effect));
  AssertEquals('Unavailable advertisements must not block extraction', Integer(DROPEFFECT_COPY), Integer(Effect));
  AssertEquals(0, Value.Calls);
  Effect := DROPEFFECT_COPY;
  AssertEquals(S_OK, Manager.Drop(Data, 0, Point(0, 0), Effect));
  AssertEquals(Integer(DROPEFFECT_COPY), Integer(Effect));
  AssertEquals(1, CallbackCount);
  AssertEquals('unknown-tdock-scheme:kept', LastCallbackPath);
end;

procedure TDropImportTests.FeedbackRecognizesExistingFormatsAndMedia;
const Names: array[0..6] of PChar = ('Shell IDList Array', 'FileNameW', 'FileName',
  'UniformResourceLocatorW', 'UniformResourceLocator', 'FileGroupDescriptorW', 'FileGroupDescriptor');
var Data: IDataObject; Value: TData; I: Integer; Kind: DWORD; Format: Word;
begin
  for I := 0 to High(Names) do
    for Kind in [DWORD(TYMED_HGLOBAL), DWORD(TYMED_ISTREAM), DWORD(TYMED_FILE)] do
    begin
      Data := NewData(Value);
      Value.Add(RegisterClipboardFormat(Names[I]), Kind, '');
      Value.EnumerateFormats := True;
      AssertEquals('Offered medium ' + IntToStr(I) + ':' + IntToStr(Kind),
        (Kind = TYMED_HGLOBAL) or ((I <= 2) and (Kind = TYMED_ISTREAM)) or
        (((I = 1) or (I = 2)) and (Kind = TYMED_FILE)), SupportsDropData(Data));
      AssertEquals(0, Value.Calls);
    end;
  for Format in [Word(CF_HDROP), Word(CF_UNICODETEXT), Word(CF_TEXT)] do
  begin
    Data := NewData(Value); Value.Add(Format, TYMED_HGLOBAL, '');
    AssertTrue(SupportsDropData(Data)); AssertEquals(0, Value.Calls);
  end;
end;

procedure TDropImportTests.UnicodeURLWinsWithoutEnumeration;
var Data: IDataObject; Value: TData;
begin
  Data := NewData(Value);
  Value.Add(RegisterClipboardFormat('UniformResourceLocator'), TYMED_HGLOBAL, 'https://ansi.invalid/'#0);
  Value.Add(RegisterClipboardFormat('UniformResourceLocatorW'), TYMED_HGLOBAL, WideBytes('https://example.invalid/文档'));
  AssertTrue(ImportAdditionalFormats(Data, Batch));
  AssertEquals('https://example.invalid/文档', Batch[0]);
  AssertEquals(1, Value.Calls);
end;

procedure TDropImportTests.ANSIURLSupportsRegisteredScheme;
var Data: IDataObject; Value: TData;
begin
  Data := NewData(Value);
  Value.Add(RegisterClipboardFormat('UniformResourceLocator'), TYMED_HGLOBAL, 'ms-settings:display'#0);
  AssertTrue(ImportAdditionalFormats(Data, Batch));
  AssertEquals('ms-settings:display', Batch[0]);
end;

procedure TDropImportTests.InvalidUnicodeFallsBackToANSI;
var Data: IDataObject; Value: TData;
begin
  Data := NewData(Value);
  Value.Add(RegisterClipboardFormat('UniformResourceLocatorW'), TYMED_HGLOBAL, 'bad');
  Value.Add(RegisterClipboardFormat('UniformResourceLocator'), TYMED_HGLOBAL, 'https://example.invalid/'#0);
  AssertTrue(ImportAdditionalFormats(Data, Batch));
  AssertEquals('https://example.invalid/', Batch[0]);
end;

procedure TDropImportTests.URLWinsOverVirtualAndText;
var Data: IDataObject; Value: TData;
begin
  Data := NewData(Value);
  Value.Add(CF_UNICODETEXT, TYMED_HGLOBAL, WideBytes('https://text.invalid/'));
  Value.Add(RegisterClipboardFormat('FileGroupDescriptorW'), TYMED_HGLOBAL, DescriptorBytes(['link.url'], True));
  Value.Add(RegisterClipboardFormat('UniformResourceLocatorW'), TYMED_HGLOBAL, WideBytes('https://url.invalid/'));
  AssertTrue(ImportAdditionalFormats(Data, Batch));
  AssertEquals(1, Batch.Count);
  AssertEquals('https://url.invalid/', Batch[0]);
  AssertEquals(1, Value.Calls);
end;

procedure TDropImportTests.HDropWinsOverURL;
var Data: IDataObject; Value: TData; Bytes, Names: RawByteString; List: TStrings;
begin
  Data := NewData(Value);
  Names := WideBytes(Fixture + #0);
  SetLength(Bytes, SizeOf(TDROPFILES) + Length(Names));
  FillChar(Bytes[1], Length(Bytes), 0);
  PDROPFILES(@Bytes[1])^.pFiles := SizeOf(TDROPFILES);
  PDROPFILES(@Bytes[1])^.fWide := True;
  Move(Names[1], Bytes[SizeOf(TDROPFILES) + 1], Length(Names));
  Value.Add(CF_HDROP, TYMED_HGLOBAL, Bytes);
  Value.Add(RegisterClipboardFormat('UniformResourceLocatorW'), TYMED_HGLOBAL, WideBytes('https://url.invalid/'));
  List := Batch;
  Manager.MakeList(Data, List);
  AssertEquals(1, Batch.Count);
  AssertEquals(UTF8Encode(Fixture), Batch[0]);
  AssertEquals(1, Value.Calls);
end;

procedure TDropImportTests.RunText(const Text: UnicodeString; ExpectedCount: Integer);
var Data: IDataObject; Value: TData;
begin
  Batch.DiscardCandidate;
  Data := NewData(Value);
  Value.Add(CF_UNICODETEXT, TYMED_HGLOBAL, WideBytes(Text));
  AssertEquals(ExpectedCount > 0, ImportAdditionalFormats(Data, Batch));
  AssertEquals(ExpectedCount, Batch.Count);
end;

procedure TDropImportTests.TextPathsFoldersAndURIs;
begin
  RunText(Fixture, 1);
  RunText('"' + Fixture + '"'#13#10 + Root + #10 + 'https://example.invalid/a%20b'#13#10 +
    'ms-settings:display'#10 + 'file:///C:/Windows/', 5);
  AssertEquals(UTF8Encode(Fixture), Batch[0]);
end;

procedure TDropImportTests.TextRejectsCommandsAndRelativePaths;
begin
  RunText('"' + Fixture + '" --flag', 0);
  RunText('notepad.exe', 0);
  RunText('.\file.txt', 0);
  RunText('This is prose', 0);
  RunText('C:relative.txt', 0);
  RunText('https://example.invalid/ --flag', 0);
end;

procedure TDropImportTests.TextRejectsWholeInvalidList;
begin RunText('https://example.invalid/'#10'not a target', 0); end;
procedure TDropImportTests.TextRejectsSemicolonsAndOversize;
begin
  RunText('https://example.invalid/a;b', 0);
  RunText('https://example.invalid/' + UnicodeString(StringOfChar('a', 1024)), 0);
  RunText(UnicodeString(StringOfChar('a', DROP_TEXT_LIMIT)), 0);
end;
procedure TDropImportTests.TextTargetCountBoundary;
var Text: UnicodeString; I: Integer;
begin
  Text := '';
  for I := 1 to 64 do Text := Text + 'https://example.invalid/' + IntToStr(I) + #10;
  RunText(Text, 64);
  RunText(Text + 'https://extra.invalid/', 0);
end;

procedure TDropImportTests.TextLocaleUsesSourceCodePage;
var Data: IDataObject; Value: TData; Bytes: RawByteString; Locale: DWORD;
begin
  Data := NewData(Value);
  Locale := $0409;
  SetLength(Bytes, 4);
  Move(Locale, Bytes[1], 4);
  Value.Add(CF_LOCALE, TYMED_HGLOBAL, Bytes);
  Value.Add(CF_TEXT, TYMED_HGLOBAL, RawByteString('https://example.invalid/caf') + AnsiChar($E9) + #0);
  AssertTrue(ImportAdditionalFormats(Data, Batch));
  AssertEquals('https://example.invalid/café', Batch[0]);
end;

procedure TDropImportTests.CheckFilenameMedia(Wide: Boolean; Kind: DWORD);
var Data: IDataObject; Value: TData; Name: PChar; Bytes: RawByteString; Source: UnicodeString;
begin
  Data := NewData(Value);
  if Wide then begin Name := 'FileNameW'; Source := Fixture; Bytes := WideBytes(Source); end
  else
  begin
    Name := 'FileName'; Source := Root + '\ascii.txt';
    CreateFixtureFile(Source, 'fixture'); Bytes := UTF8Encode(Source) + #0;
  end;
  Value.Add(RegisterClipboardFormat(Name), Kind, Bytes);
  Value.Entries[0].FilePath := Source;
  AssertTrue(ImportAdditionalFormats(Data, Batch));
  AssertEquals(1, Batch.Count);
  if Kind = TYMED_FILE then
  begin
    AssertTrue('Receiver-owned medium deletes its source', GetFileAttributesW(PWideChar(Source)) = INVALID_FILE_ATTRIBUTES);
    AssertEquals('fixture', ReadFileBytes(UTF8Decode(Batch[0])));
    AssertTrue('Copy has a different path', UTF8Decode(Batch[0]) <> Source);
  end else AssertEquals(UTF8Encode(Source), Batch[0]);
end;

procedure TDropImportTests.FilenameUnicodeGlobal; begin CheckFilenameMedia(True, TYMED_HGLOBAL); end;
procedure TDropImportTests.FilenameANSIGlobal; begin CheckFilenameMedia(False, TYMED_HGLOBAL); end;
procedure TDropImportTests.FilenameUnicodeStream; begin CheckFilenameMedia(True, TYMED_ISTREAM); end;
procedure TDropImportTests.FilenameANSIStream; begin CheckFilenameMedia(False, TYMED_ISTREAM); end;
procedure TDropImportTests.FilenameUnicodeFileMedium; begin CheckFilenameMedia(True, TYMED_FILE); end;
procedure TDropImportTests.FilenameANSIFileMedium; begin CheckFilenameMedia(False, TYMED_FILE); end;

procedure TDropImportTests.FilenameRejectsUnterminatedData;
var Data: IDataObject; Value: TData;
begin
  Data := NewData(Value);
  Value.Add(RegisterClipboardFormat('FileName'), TYMED_ISTREAM, 'non-terminated');
  AssertFalse(ImportAdditionalFormats(Data, Batch));
  AssertEquals(0, Batch.Count);
end;

procedure TDropImportTests.UnicodeFilenameSurvivesSaveReloadAndLaunch;
var Settings: TDSets; Probe: TLaunchProbe; Item: TShortcutDtoV1; Mode: Boolean;
begin
  CheckFilenameMedia(True, TYMED_HGLOBAL);
  Item := DefaultShortcutDto;
  Item.Command := Batch[0];
  WriteShortcutIni(UTF8Encode(Root + '\items.ini'), 'item1', Item);
  Item := ReadShortcutIni(UTF8Encode(Root + '\items.ini'), 'item1');
  AssertEquals(Batch[0], Item.Command);
  Settings := TDSets.Create('', '', 0);
  Probe := TLaunchProbe.Create(Settings, nil);
  try
    for Mode in [False, True] do
    begin
      Settings.container.RunInThread := Mode;
      Probe.Run(Item.Command);
      AssertEquals(UTF8Encode(Fixture), UTF8Encode(Probe.Target));
    end;
  finally Probe.Free; Settings.Free; end;
end;

procedure TDropImportTests.CheckContent(Kind: DWORD; Wide: Boolean; Mode: Integer);
var Data: IDataObject; Value: TData; Name: PChar; Source: IStorage; Content: IStream;
  Bytes: RawByteString; Written: ULONG; Destination: IStorage; ReadCount: ULONG;
  Buffer: array[0..10] of AnsiChar;
begin
  Data := NewData(Value);
  if Wide then Name := 'FileGroupDescriptorW' else Name := 'FileGroupDescriptor';
  if Wide then Value.Add(RegisterClipboardFormat(Name), TYMED_HGLOBAL, DescriptorBytes(['文档-Ж.bin'], True))
  else Value.Add(RegisterClipboardFormat(Name), TYMED_HGLOBAL, DescriptorBytes(['sample.bin'], False));
  Value.Add(RegisterClipboardFormat('FileContents'), Kind, 'hello world', 0);
  Value.Entries[1].Mode := Mode;
  if Kind = TYMED_ISTORAGE then
  begin
    AssertEquals(0, StgCreateDocfile(PWideChar(Root + '\source.bin'), STGM_CREATE or STGM_READWRITE or STGM_SHARE_EXCLUSIVE, 0, Source));
    AssertEquals(0, Source.CreateStream('contents', STGM_CREATE or STGM_READWRITE or STGM_SHARE_EXCLUSIVE, 0, 0, Content));
    Bytes := 'hello world';
    AssertEquals(0, Content.Write(@Bytes[1], Length(Bytes), @Written));
    Content := nil;
    Value.Entries[1].Storage := Source;
  end;
  AssertTrue(ImportAdditionalFormats(Data, Batch));
  AssertEquals(1, Batch.Count);
  if Kind = TYMED_ISTORAGE then
  begin
    AssertEquals(0, StgOpenStorage(PWideChar(UTF8Decode(Batch[0])), nil, STGM_READ or STGM_SHARE_EXCLUSIVE, nil, 0, Destination));
    AssertEquals(0, Destination.OpenStream('contents', nil, STGM_READ or STGM_SHARE_EXCLUSIVE, 0, Content));
    AssertEquals(0, Content.Read(@Buffer, Length(Buffer), @ReadCount));
    SetString(Bytes, PAnsiChar(@Buffer), ReadCount);
    AssertEquals('hello world', Bytes);
  end
  else AssertEquals('hello world', ReadFileBytes(UTF8Decode(Batch[0])));
  if Wide then AssertEquals('文档-Ж.bin', ExtractFileName(Batch[0]));
  if Kind = TYMED_ISTREAM then AssertEquals('Stream released exactly once', 1, Value.Releases);
end;

procedure TDropImportTests.VirtualUnicodeStream; begin CheckContent(TYMED_ISTREAM, True); end;
procedure TDropImportTests.VirtualANSIStream; begin CheckContent(TYMED_ISTREAM, False); end;
procedure TDropImportTests.VirtualMemory; begin CheckContent(TYMED_HGLOBAL, True); end;
procedure TDropImportTests.VirtualStorage; begin CheckContent(TYMED_ISTORAGE, True); end;
procedure TDropImportTests.VirtualPartialReadsWithoutStat; begin CheckContent(TYMED_ISTREAM, True, 1); end;

procedure TDropImportTests.VirtualFailedReadRemovesUnexposedFiles;
var Data: IDataObject; Value: TData; Search: THandle; Find: TWin32FindDataW; Raised: Boolean;
begin
  Data := NewData(Value);
  Value.Add(RegisterClipboardFormat('FileGroupDescriptorW'), TYMED_HGLOBAL, DescriptorBytes(['sample.bin'], True));
  Value.Add(RegisterClipboardFormat('FileContents'), TYMED_ISTREAM, 'hello world', 0);
  Value.Entries[1].Mode := 2;
  Raised := False;
  try ImportAdditionalFormats(Data, Batch); except on E: EDropTransferError do Raised := True; end;
  AssertTrue(Raised);
  FreeAndNil(Batch);
  Search := FindFirstFileW(PWideChar(Root + '\ImportedFiles\import-*'), Find);
  if Search <> INVALID_HANDLE_VALUE then Windows.FindClose(Search);
  AssertTrue('Failed transfer leaves no stage', Search = INVALID_HANDLE_VALUE);
end;

procedure TDropImportTests.VirtualMissingContentDoesNotFallBackToText;
var Data: IDataObject; Value: TData; Raised: Boolean;
begin
  Data := NewData(Value);
  Value.Add(RegisterClipboardFormat('FileGroupDescriptorW'), TYMED_HGLOBAL, DescriptorBytes(['sample.bin'], True));
  Value.Add(CF_UNICODETEXT, TYMED_HGLOBAL, WideBytes('https://fallback.invalid/'));
  Raised := False;
  try ImportAdditionalFormats(Data, Batch); except on E: EDropTransferError do Raised := True; end;
  AssertTrue(Raised);
  AssertEquals(0, Batch.Count);
end;

procedure TDropImportTests.VirtualRejectsTruncatedDescriptors;
var Data: IDataObject; Value: TData; Bytes: RawByteString;
begin
  Data := NewData(Value);
  Bytes := DescriptorBytes(['one.bin'], True);
  PDWORD(@Bytes[1])^ := 64;
  Value.Add(RegisterClipboardFormat('FileGroupDescriptorW'), TYMED_HGLOBAL, Bytes);
  AssertFalse(ImportAdditionalFormats(Data, Batch));
end;

procedure TDropImportTests.VirtualRejectsUnsafeNamesAndDirectories;
var Data: IDataObject; Value: TData; Name: UnicodeString; Bytes: RawByteString;
begin
  for Name in ['..\evil.exe', 'C:\evil.exe', 'name:stream', 'NUL.txt', 'COM1', 'trailing.', 'bad;name.txt'] do
  begin
    Data := NewData(Value);
    Value.Add(RegisterClipboardFormat('FileGroupDescriptorW'), TYMED_HGLOBAL, DescriptorBytes([Name], True));
    AssertFalse(UTF8Encode(Name), ImportAdditionalFormats(Data, Batch));
  end;
  Bytes := DescriptorBytes(['directory'], True);
  PFILEDESCRIPTORW(PtrUInt(@Bytes[1]) + 4)^.dwFlags := FD_ATTRIBUTES_FLAG;
  PFILEDESCRIPTORW(PtrUInt(@Bytes[1]) + 4)^.dwFileAttributes := FILE_ATTRIBUTE_DIRECTORY;
  Data := NewData(Value);
  Value.Add(RegisterClipboardFormat('FileGroupDescriptorW'), TYMED_HGLOBAL, Bytes);
  AssertFalse(ImportAdditionalFormats(Data, Batch));
end;

procedure TDropImportTests.VirtualMemoryRequiresExactLength;
var Data: IDataObject; Value: TData; Bytes: RawByteString; Raised: Boolean;
begin
  Data := NewData(Value);
  Bytes := DescriptorBytes(['sample.bin'], True, 999);
  Value.Add(RegisterClipboardFormat('FileGroupDescriptorW'), TYMED_HGLOBAL, Bytes);
  Value.Add(RegisterClipboardFormat('FileContents'), TYMED_HGLOBAL, 'small', 0);
  Raised := False;
  try ImportAdditionalFormats(Data, Batch); except on E: EDropTransferError do Raised := True; end;
  AssertTrue(Raised);
end;

procedure TDropImportTests.VirtualMultipleIndicesAndCollisions;
var Data: IDataObject; Value: TData;
begin
  Data := NewData(Value);
  Value.Add(RegisterClipboardFormat('FileGroupDescriptorW'), TYMED_HGLOBAL,
    DescriptorBytes(['same.txt', 'same.txt', 'SAME.TXT'], True, 3));
  Value.Add(RegisterClipboardFormat('FileContents'), TYMED_ISTREAM, 'one', 0);
  Value.Add(RegisterClipboardFormat('FileContents'), TYMED_HGLOBAL, 'two', 1);
  Value.Add(RegisterClipboardFormat('FileContents'), TYMED_ISTREAM, 'tri', 2);
  AssertTrue(ImportAdditionalFormats(Data, Batch));
  AssertEquals(3, Batch.Count);
  AssertTrue(Batch[0] <> Batch[1]); AssertTrue(Batch[1] <> Batch[2]);
  AssertEquals('one', ReadFileBytes(UTF8Decode(Batch[0])));
  AssertEquals('two', ReadFileBytes(UTF8Decode(Batch[1])));
  AssertEquals('tri', ReadFileBytes(UTF8Decode(Batch[2])));
end;

procedure TDropImportTests.VirtualZeroLengthFile;
var Data: IDataObject; Value: TData;
begin
  Data := NewData(Value);
  Value.Add(RegisterClipboardFormat('FileGroupDescriptorW'), TYMED_HGLOBAL, DescriptorBytes(['empty.txt'], True, 0));
  Value.Add(RegisterClipboardFormat('FileContents'), TYMED_ISTREAM, '', 0);
  AssertTrue(ImportAdditionalFormats(Data, Batch));
  AssertEquals('', ReadFileBytes(UTF8Decode(Batch[0])));
end;

procedure TDropImportTests.AcceptedCopySurvivesRestart;
var Path: UnicodeString; Item: TShortcutDtoV1; Settings: TDSets; Probe: TLaunchProbe;
  Threaded: Boolean;
begin
  CheckContent(TYMED_ISTREAM, True);
  Path := UTF8Decode(Batch[0]);
  Item := DefaultShortcutDto; Item.Command := Batch[0];
  WriteShortcutIni(UTF8Encode(Root + '\items.ini'), 'item1', Item);
  Batch.Expose; Batch.Decide(0, True);
  FreeAndNil(Batch);
  CleanupIncompleteImports(Root + '\ImportedFiles');
  AssertEquals('hello world', ReadFileBytes(Path));
  Batch := TDropImportBatch.Create(Root + '\ImportedFiles');
  Item := ReadShortcutIni(UTF8Encode(Root + '\items.ini'), 'item1');
  AssertEquals(UTF8Encode(Path), Item.Command);
  Settings := TDSets.Create('', '', 0);
  Probe := TLaunchProbe.Create(Settings, nil);
  try
    for Threaded in [False, True] do
    begin
      Settings.container.RunInThread := Threaded;
      Probe.Run(Item.Command);
      AssertEquals(UTF8Encode(Path), UTF8Encode(Probe.Target));
    end;
  finally Probe.Free; Settings.Free; end;
end;

procedure TDropImportTests.RejectedCopyIsDeleted;
var Path: UnicodeString;
begin
  CheckContent(TYMED_ISTREAM, True);
  Path := UTF8Decode(Batch[0]);
  Batch.Expose; Batch.Decide(0, False);
  FreeAndNil(Batch);
  AssertTrue(GetFileAttributesW(PWideChar(Path)) = INVALID_FILE_ATTRIBUTES);
end;

procedure TDropImportTests.UncertainConsumerRetainsCopy;
var Path: UnicodeString;
begin
  CheckContent(TYMED_ISTREAM, True);
  Path := UTF8Decode(Batch[0]); Batch.Expose;
  FreeAndNil(Batch);
  CleanupIncompleteImports(Root + '\ImportedFiles');
  AssertEquals('hello world', ReadFileBytes(Path));
end;

procedure TDropImportTests.StartupRemovesOnlyAbandonedIncompleteStages;
var Id: TGUID; Stage, LivePath: UnicodeString;
begin
  CheckContent(TYMED_ISTREAM, True);
  LivePath := UTF8Decode(Batch[0]);
  CleanupIncompleteImports(Root + '\ImportedFiles');
  AssertEquals('hello world', ReadFileBytes(LivePath));
  CreateGUID(Id);
  Stage := Root + '\ImportedFiles\import-' + GUIDToString(Id);
  AssertTrue(CreateDirectoryW(PWideChar(Stage), nil));
  CreateFixtureFile(Stage + '\.tdock-import', 'TDOCK-IMPORT-1:P');
  CreateFixtureFile(Stage + '\unfinished.bin', 'partial');
  CleanupIncompleteImports(Root + '\ImportedFiles');
  AssertTrue(GetFileAttributesW(PWideChar(Stage)) = INVALID_FILE_ATTRIBUTES);
  AssertEquals('hello world', ReadFileBytes(LivePath));
end;

procedure TDropImportTests.ProviderOwnedMemoryReleasesOnce;
var Data: IDataObject; Value: TData;
begin
  Data := NewData(Value);
  Value.Add(RegisterClipboardFormat('UniformResourceLocatorW'), TYMED_HGLOBAL, WideBytes('https://example.invalid/'));
  Value.Entries[0].ProviderOwned := True;
  AssertTrue(ImportAdditionalFormats(Data, Batch));
  AssertEquals(1, Value.Releases);
end;

procedure TDropImportTests.TransferFailureReportsNoEffectAndClearsDrag;
var Data: IDataObject; Value: TData; Effect: DWORD;
begin
  Data := NewData(Value);
  Value.Add(RegisterClipboardFormat('FileGroupDescriptorW'), TYMED_HGLOBAL, DescriptorBytes(['sample.bin'], True));
  Value.Add(RegisterClipboardFormat('FileContents'), TYMED_ISTREAM, 'hello world', 0);
  Value.Entries[1].Mode := 2;
  Manager.OnDrop := Callback;
  Manager.OnError := ReportError;
  Effect := DROPEFFECT_COPY;
  AssertTrue(Manager.Drop(Data, 0, Point(0, 0), Effect) <> S_OK);
  AssertEquals(0, Integer(Effect));
  AssertEquals(1, CallbackCount);
  AssertEquals(1, ErrorCount);
end;

procedure TDropImportTests.DropAcknowledgesAcceptedTargetsOnly;
var Data: IDataObject; Value: TData; Effect: DWORD;
begin
  Data := NewData(Value);
  Value.Add(RegisterClipboardFormat('UniformResourceLocatorW'), TYMED_HGLOBAL, WideBytes('https://example.invalid/'));
  Manager.OnDrop := Callback;
  CallbackAccept := False;
  Effect := DROPEFFECT_COPY;
  AssertEquals(0, Manager.Drop(Data, 0, Point(0, 0), Effect));
  AssertEquals(0, Integer(Effect));
  CallbackAccept := True;
  Effect := DROPEFFECT_COPY;
  AssertEquals(0, Manager.Drop(Data, 0, Point(0, 0), Effect));
  AssertEquals(Integer(DROPEFFECT_COPY), Integer(Effect));
end;

procedure TDropImportTests.FailedGetHasNoReleaseObligation;
var Data: IDataObject; Value: TData;
begin
  Data := NewData(Value);
  Value.Add(RegisterClipboardFormat('UniformResourceLocatorW'), TYMED_HGLOBAL, WideBytes('https://example.invalid/'));
  Value.FailGet := True;
  AssertFalse(ImportAdditionalFormats(Data, Batch));
  AssertEquals(0, Value.Releases);
end;

procedure TDropImportTests.StorageWriteFailureDoesNotFallBack;
var Data: IDataObject; Value: TData; Raised: Boolean;
begin
  FreeAndNil(Batch);
  Batch := TDropImportBatch.Create(Fixture);
  Data := NewData(Value);
  Value.Add(RegisterClipboardFormat('FileGroupDescriptorW'), TYMED_HGLOBAL, DescriptorBytes(['sample.bin'], True));
  Value.Add(RegisterClipboardFormat('FileContents'), TYMED_ISTREAM, 'hello world', 0);
  Value.Add(CF_UNICODETEXT, TYMED_HGLOBAL, WideBytes('https://fallback.invalid/'));
  Raised := False;
  try ImportAdditionalFormats(Data, Batch); except on E: Exception do Raised := True; end;
  AssertTrue(Raised);
  AssertEquals(0, Batch.Count);
end;

procedure TDropImportTests.FailedSecondContentRemovesFirstCopy;
var Data: IDataObject; Value: TData; First: UnicodeString; Raised: Boolean;
begin
  Data := NewData(Value);
  Value.Add(RegisterClipboardFormat('FileGroupDescriptorW'), TYMED_HGLOBAL,
    DescriptorBytes(['first.bin', 'missing.bin'], True, 3));
  Value.Add(RegisterClipboardFormat('FileContents'), TYMED_ISTREAM, 'one', 0);
  Raised := False;
  try ImportAdditionalFormats(Data, Batch); except on E: EDropTransferError do Raised := True; end;
  AssertTrue(Raised);
  AssertEquals(1, Batch.Count);
  First := UTF8Decode(Batch[0]); FreeAndNil(Batch);
  AssertTrue(GetFileAttributesW(PWideChar(First)) = INVALID_FILE_ATTRIBUTES);
  AssertEquals(1, Value.Releases);
end;

procedure TDropImportTests.RejectedDropCleansCopiedFile;
var Data: IDataObject; Value: TData; Effect: DWORD;
begin
  Data := NewData(Value);
  Value.Add(RegisterClipboardFormat('FileGroupDescriptorW'), TYMED_HGLOBAL, DescriptorBytes(['reject.bin'], True));
  Value.Add(RegisterClipboardFormat('FileContents'), TYMED_ISTREAM, 'hello world', 0);
  Manager.OnDrop := Callback; CallbackAccept := False;
  AssertEquals(0, Manager.Drop(Data, 0, Point(0, 0), Effect));
  AssertEquals(0, Integer(Effect));
  AssertTrue(GetFileAttributesW(PWideChar(UTF8Decode(LastCallbackPath))) = INVALID_FILE_ATTRIBUTES);
end;

procedure TDropImportTests.ConsumerExceptionKeepsExposedFile;
var Data: IDataObject; Value: TData; Effect: DWORD;
begin
  Data := NewData(Value);
  Value.Add(RegisterClipboardFormat('FileGroupDescriptorW'), TYMED_HGLOBAL, DescriptorBytes(['keep.bin'], True));
  Value.Add(RegisterClipboardFormat('FileContents'), TYMED_ISTREAM, 'hello world', 0);
  Manager.OnDrop := Callback; CallbackRaise := True;
  AssertTrue(Manager.Drop(Data, 0, Point(0, 0), Effect) <> S_OK);
  AssertEquals(0, Integer(Effect));
  AssertEquals('hello world', ReadFileBytes(UTF8Decode(LastCallbackPath)));
end;

procedure TDropImportTests.StreamWithoutDeclaredSize;
var Data: IDataObject; Value: TData; Bytes: RawByteString;
begin
  Data := NewData(Value); Bytes := DescriptorBytes(['unknown.bin'], True);
  PFILEDESCRIPTORW(PtrUInt(@Bytes[1]) + 4)^.dwFlags := 0;
  Value.Add(RegisterClipboardFormat('FileGroupDescriptorW'), TYMED_HGLOBAL, Bytes);
  Value.Add(RegisterClipboardFormat('FileContents'), TYMED_ISTREAM, 'unknown length', 0);
  Value.Entries[1].Mode := 1;
  AssertTrue(ImportAdditionalFormats(Data, Batch));
  AssertEquals('unknown length', ReadFileBytes(UTF8Decode(Batch[0])));
end;

procedure TDropImportTests.MemoryWithoutDeclaredSizeRejects;
var Data: IDataObject; Value: TData; Bytes: RawByteString; Raised: Boolean;
begin
  Data := NewData(Value); Bytes := DescriptorBytes(['unknown.bin'], True);
  PFILEDESCRIPTORW(PtrUInt(@Bytes[1]) + 4)^.dwFlags := 0;
  Value.Add(RegisterClipboardFormat('FileGroupDescriptorW'), TYMED_HGLOBAL, Bytes);
  Value.Add(RegisterClipboardFormat('FileContents'), TYMED_HGLOBAL, 'unknown length', 0);
  Raised := False;
  try ImportAdditionalFormats(Data, Batch); except on E: EDropTransferError do Raised := True; end;
  AssertTrue(Raised);
end;

procedure TDropImportTests.InvalidSurrogateFallsBack;
var Data: IDataObject; Value: TData; Bad: UnicodeString;
begin
  Data := NewData(Value); Bad := 'https://example.invalid/' + WideChar($D800);
  Value.Add(RegisterClipboardFormat('UniformResourceLocatorW'), TYMED_HGLOBAL, WideBytes(Bad));
  Value.Add(RegisterClipboardFormat('UniformResourceLocator'), TYMED_HGLOBAL, 'https://fallback.invalid/'#0);
  AssertTrue(ImportAdditionalFormats(Data, Batch)); AssertEquals('https://fallback.invalid/', Batch[0]);
end;

procedure TDropImportTests.ExposedFilesRemainAfterLauncherRemoval;
var Path: UnicodeString; Item: TShortcutDtoV1;
begin
  CheckContent(TYMED_ISTREAM, True);
  Path := UTF8Decode(Batch[0]);
  Item := DefaultShortcutDto; Item.Command := Batch[0];
  WriteShortcutIni(UTF8Encode(Root + '\items.ini'), 'item1', Item);
  Batch.Expose; Batch.Decide(0, True); FreeAndNil(Batch);
  DeleteFileW(PWideChar(Root + '\items.ini'));
  CleanupIncompleteImports(Root + '\ImportedFiles');
  AssertEquals('hello world', ReadFileBytes(Path));
end;

initialization
  RegisterTest(TDropImportTests);
end.
