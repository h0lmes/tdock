program check_source;
{$mode delphi}
{$codepage utf8}

uses Interfaces, Windows, SysUtils, Classes, Contnrs, ActiveX, ShlObj, ShellAPI,
  dragdatau, dragsamplesu, dropimportu;

type
  TChecks = class
  private
    FRoot: UnicodeString;
    FLogObject: TDragLog;
    FLog: IDragLog;
    FOptions: TDragOptions;
    FCount: Integer;
    procedure Require(Value: Boolean; const Message: string);
    function Data: IDataObject;
    procedure CheckFormatIsolation;
    procedure CheckFiles;
    procedure CheckImports;
    procedure CheckNativeObjects;
    procedure CheckFailureAndOwnership;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Run;
  end;

procedure TChecks.Require(Value: Boolean; const Message: string);
begin
  if not Value then raise Exception.Create(Message);
  Inc(FCount);
end;

constructor TChecks.Create;
var Id: TGUID; Samples: TObjectList;
begin
  inherited Create;
  CheckHR(CreateGUID(Id), 'Create check identifier');
  FRoot := UTF8Decode(ExtractFilePath(ParamStr(0))) + 'check-' + UnicodeString(GUIDToString(Id));
  MakeDirectory(FRoot);
  FLogObject := TDragLog.Create(''); FLog := FLogObject;
  FOptions.Root := FRoot;
  FOptions.Contents := 'Content from the isolated source check.';
  Samples := TObjectList.Create(True);
  try
    CreateSamples(FRoot, Samples);
    Require(Samples.Count >= 50, 'The object catalog is incomplete');
  finally Samples.Free; end;
end;

destructor TChecks.Destroy;
begin
  FLogObject.Lines.SaveToFile(UTF8Encode(FRoot + '\source-check.log'));
  FLog := nil;
  inherited Destroy;
end;

function TChecks.Data: IDataObject;
begin Result := BuildDragObject(FOptions, FLog); end;

procedure TChecks.CheckFormatIsolation;
var Profile: TDragProfile; Value: IDataObject; Enumerator: IEnumFormatEtc;
  Format: TFormatEtc; Fetched: LongInt; Count: Integer;
begin
  for Profile := Low(TDragProfile) to High(TDragProfile) do
  begin
    FOptions.Profile := Profile;
    if Profile in [dpURLW, dpURLA] then FOptions.Payload := 'https://example.com/'
    else if Profile in [dpVirtualWStream..dpVirtualAStorage] then FOptions.Payload := 'sample.txt'
    else FOptions.Payload := FRoot + '\samples\sample.txt';
    Value := Data;
    CheckHR(Value.EnumFormatEtc(DATADIR_GET, Enumerator), 'Enumerate ' + ProfileNames[Profile]);
    Count := 0;
    while Enumerator.Next(1, Format, @Fetched) = S_OK do
    begin
      Inc(Count);
      try
        Require(Format.dwAspect = DVASPECT_CONTENT, 'The source advertised the wrong aspect');
        if Profile in [dpURLW, dpURLA] then
          Require(Pos('UniformResourceLocator', FormatName(Format.cfFormat)) = 1, 'A URL-only source offered another format');
        if Profile in [dpFilenameWGlobal..dpFilenameAFile] then
          Require(Pos('FileName', FormatName(Format.cfFormat)) = 1, 'A filename-only source offered another format');
        if Profile = dpShellID then
          Require(Format.cfFormat = RegisterClipboardFormat('Shell IDList Array'), 'The Shell filter leaked another format');
        if Profile in [dpVirtualWStream..dpVirtualAStorage] then
          Require((Format.cfFormat = RegisterClipboardFormat('FileContents')) or
            (Pos('FileGroupDescriptor', FormatName(Format.cfFormat)) = 1), 'A virtual source offered a competing format');
      finally if Format.ptd <> nil then CoTaskMemFree(Format.ptd); end;
    end;
    Require(Count > 0, 'The source advertised no formats');
    if not (Profile in [dpNativeShell, dpVirtualWStream..dpVirtualAStorage, dpMixed, dpText1252]) then
      Require(Count = 1, 'An isolated source advertised more than one format');
  end;
  Writeln('PASS exact format enumeration across all ', Ord(High(TDragProfile)) + 1, ' profiles');
end;

procedure TChecks.CheckFiles;
var Profile: TDragProfile; Value: IDataObject; Medium: TStgMedium; Name: array[0..1023] of WideChar;
begin
  for Profile in [dpHDropW, dpHDropA] do
  begin
    FOptions.Profile := Profile;
    FOptions.Payload := FRoot + '\samples\sample.txt'#13#10 + FRoot + '\samples\one;two.txt';
    Value := Data;
    Require(GetDropMedium(Value, CF_HDROP, TYMED_HGLOBAL, -1, Medium), 'Cannot retrieve HDROP');
    try
      Require(DragQueryFileW(Medium.hGlobal, $FFFFFFFF, nil, 0) = 2, 'The HDROP count is wrong');
      DragQueryFileW(Medium.hGlobal, 1, @Name, Length(Name));
      Require(UnicodeString(PWideChar(@Name)) = FRoot + '\samples\one;two.txt', 'HDROP changed a filename');
    finally ReleaseStgMedium(Medium); end;
  end;
  Writeln('PASS Unicode and ANSI HDROP with multiple files');
end;

procedure TChecks.CheckImports;
var Profile: TDragProfile; Value: IDataObject; Batch: TDropImportBatch; I: Integer;
  Storage: IStorage; Stream: IStream; Bytes: array[0..127] of AnsiChar; ReadCount: ULONG;
  Actual: RawByteString; Original: UnicodeString;
begin
  for Profile in [dpURLW..dpVirtualAStorage] do
  begin
    FOptions.Profile := Profile;
    if Profile in [dpURLW, dpURLA] then FOptions.Payload := 'https://example.com/source-test'
    else if Profile in [dpVirtualWStream..dpVirtualAStorage] then FOptions.Payload := 'same.txt'#13#10'same.txt'
    else FOptions.Payload := FRoot + '\samples\sample.txt';
    Value := Data;
    Batch := TDropImportBatch.Create(FRoot + '\ImportedFiles');
    try
      Require(ImportAdditionalFormats(Value, Batch), 'Production importer rejected ' + ProfileNames[Profile]);
      if Profile in [dpVirtualWStream..dpVirtualAStorage] then
      begin
        Require(Batch.Count = 2, 'The virtual group lost a file');
        Require(Batch[0] <> Batch[1], 'Duplicate virtual names collided');
        for I := 0 to Batch.Count - 1 do
        begin
          Require(GetFileAttributesW(PWideChar(UTF8Decode(Batch[I]))) <> INVALID_FILE_ATTRIBUTES, 'A virtual output is missing');
          if Profile in [dpVirtualWStorage, dpVirtualAStorage] then
          begin
            CheckHR(StgOpenStorage(PWideChar(UTF8Decode(Batch[I])), nil, STGM_READ or STGM_SHARE_EXCLUSIVE,
              nil, 0, Storage), 'Open materialized compound file');
            CheckHR(Storage.OpenStream('Contents', nil, STGM_READ or STGM_SHARE_EXCLUSIVE, 0, Stream), 'Read compound contents');
            ReadCount := 0;
            CheckHR(Stream.Read(@Bytes, 16, @ReadCount), 'Read compound item marker');
            SetString(Actual, PAnsiChar(@Bytes), ReadCount);
            Require(Pos('Virtual item ' + IntToStr(I + 1), Actual) = 1, 'The compound file lost its contents');
            Stream := nil; Storage := nil;
          end;
        end;
      end
      else Require(Batch.Count = 1, 'An isolated source imported the wrong number of targets');
      if Profile in [dpFilenameWFile, dpFilenameAFile] then
      begin
        Original := FRoot + '\samples\sample.txt';
        Require(GetFileAttributesW(PWideChar(Original)) <> INVALID_FILE_ATTRIBUTES, 'TYMED_FILE destroyed the original fixture');
        Require(UTF8Decode(Batch[0]) <> Original, 'TYMED_FILE did not produce a persistent target copy');
      end;
    finally Batch.Free; end;
  end;
  Writeln('PASS all URL, text, filename, and virtual profiles through the production importer');
end;

procedure TChecks.CheckNativeObjects;
var Target: UnicodeString; Value: IDataObject; Medium: TStgMedium; Memory: Pointer;
begin
  for Target in ['::{20D04FE0-3AEA-1069-A2D8-08002B30309D}',
    '::{645FF040-5081-101B-9F08-00AA002F954E}', 'shell:AppsFolder', 'shell:Desktop'] do
  begin
    FOptions.Profile := dpShellID; FOptions.Payload := Target; Value := Data;
    Require(GetDropMedium(Value, RegisterClipboardFormat('Shell IDList Array'), TYMED_HGLOBAL, -1, Medium), 'Native Shell ID list unavailable');
    try
      Memory := GlobalLock(Medium.hGlobal);
      Require(Memory <> nil, 'Native Shell data is not readable');
      try Require(PDWORD(Memory)^ = 1, 'Native Shell selection lost its object');
      finally GlobalUnlock(Medium.hGlobal); end;
    finally ReleaseStgMedium(Medium); end;
  end;
  Writeln('PASS real This PC, Recycle Bin, AppsFolder, and Desktop Shell data');
end;

procedure TChecks.CheckFailureAndOwnership;
var Value: IDataObject; Medium: TStgMedium; Before: Integer; Batch: TDropImportBatch;
begin
  FOptions.Profile := dpURLW; FOptions.Payload := 'https://example.com/';
  FOptions.ProviderOwned := True; Value := Data;
  Before := FLogObject.Lines.Count;
  Require(GetDropMedium(Value, RegisterClipboardFormat('UniformResourceLocatorW'), TYMED_HGLOBAL, -1, Medium), 'Provider-owned transfer unavailable');
  ReleaseStgMedium(Medium);
  Require(Pos('Provider-owned HGLOBAL released', FLogObject.Lines[FLogObject.Lines.Count - 1]) > 0, 'Provider cleanup was not observed');
  Require(FLogObject.Lines.Count > Before, 'Provider cleanup produced no evidence');
  FOptions.FailData := True; Value := Data;
  Require(not GetDropMedium(Value, RegisterClipboardFormat('UniformResourceLocatorW'), TYMED_HGLOBAL, -1, Medium), 'Injected GetData failure was ignored');
  FOptions.FailData := False; FOptions.ProviderOwned := False;
  FOptions.Profile := dpUnsupported; FOptions.Payload := 'unsupported'; Value := Data;
  Batch := TDropImportBatch.Create(FRoot + '\ImportedFiles');
  try Require(not ImportAdditionalFormats(Value, Batch), 'Unsupported data imported unexpectedly');
  finally Batch.Free; end;
  Writeln('PASS provider ownership, injected failure, and unsupported formats');
  FOptions.Profile := dpText1252; FOptions.Payload := 'https://example.com/café'; Value := Data;
  Batch := TDropImportBatch.Create(FRoot + '\ImportedFiles');
  try
    Require(ImportAdditionalFormats(Value, Batch), 'The CP1252 text source failed');
    Require(Batch[0] = 'https://example.com/café', 'The locale-aware text changed its Unicode contents');
  finally Batch.Free; end;
  Writeln('PASS CP1252 text with an explicit source locale');
end;

procedure TChecks.Run;
var Samples: TObjectList;
begin
  CheckFormatIsolation; CheckFiles; CheckImports; CheckNativeObjects; CheckFailureAndOwnership;
  Samples := TObjectList.Create(True);
  try
    LoadInstalledApps(Samples);
    if Samples.Count > 0 then Writeln('PASS installed application enumeration: ', Samples.Count, ' entries')
    else Writeln('SKIP installed application catalog: unavailable in this account');
  finally Samples.Free; end;
  Writeln('PASS ', FCount, ' assertions');
  Writeln('Evidence: ', UTF8Encode(FRoot));
end;

var Checks: TChecks;
begin
  OleInitialize(nil);
  try
    try
      Checks := TChecks.Create;
      try Checks.Run; finally Checks.Free; end;
    except on E: Exception do begin Writeln('FAIL ', E.Message); ExitCode := 1; end; end;
  finally OleUninitialize; end;
end.
