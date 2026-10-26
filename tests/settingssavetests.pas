unit settingssavetests;

{$mode delphi}

interface

uses Windows, SysUtils, Classes, fpcunit, testregistry, settingssaveu;

type
  EItemSaveFailure = class(Exception);
  TSettingsSaveTests = class(TTestCase)
  private
    Coordinator: TSettingsSaveCoordinator;
    Folder, PrimaryFile, OldContents, ContentsDuringCallback, CallbackFilename: string;
    FailItems, Reenter, NestedResult, UseProfileAPI: Boolean;
    SettingsCalls, ItemCalls: Integer;
    procedure SaveSettings(const Filename: string);
    procedure SaveItems(const Filename: string);
    procedure WriteText(const Filename, Contents: string);
    function ReadText(const Filename: string): string;
    function FileCount: Integer;
    function AttemptSave: Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure FailedItemSaveRetainsCompleteFile;
    procedure ReentrantSaveRetainsCompleteFileDuringCallback;
    procedure SuccessfulSaveCommitsBothSections;
    procedure FailedAndSuccessfulSavesRemoveStages;
    procedure FailureReleasesSavingGuard;
    procedure ProfileWritesSurviveReplacement;
    procedure FailedReplacementPreservesCheckpoint;
  end;

implementation

procedure TSettingsSaveTests.WriteText(const Filename, Contents: string);
var Stream: TFileStream; Bytes: UTF8String;
begin
  Bytes := UTF8String(Contents);
  Stream := TFileStream.Create(Filename, fmCreate);
  try
    if Length(Bytes) > 0 then Stream.WriteBuffer(Bytes[1], Length(Bytes));
  finally Stream.Free; end;
end;

function TSettingsSaveTests.ReadText(const Filename: string): string;
var Stream: TFileStream; Bytes: UTF8String;
begin
  Stream := TFileStream.Create(Filename, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Bytes, Stream.Size);
    if Length(Bytes) > 0 then Stream.ReadBuffer(Bytes[1], Length(Bytes));
    Result := string(Bytes);
  finally Stream.Free; end;
end;

procedure TSettingsSaveTests.SetUp;
var Id: TGUID;
begin
  repeat
    CreateGUID(Id);
    Folder := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
      'settings-save-' + GUIDToString(Id);
    if CreateDir(Folder) then Break;
    if not DirectoryExists(Folder) then RaiseLastOSError;
  until False;
  PrimaryFile := IncludeTrailingPathDelimiter(Folder) + 'dock.ini';
  OldContents := '[base]' + LineEnding + 'version=old' + LineEnding +
    '[item1]' + LineEnding + 'class=old' + LineEnding;
  WriteText(PrimaryFile, OldContents);
  FailItems := False;
  Reenter := False;
  UseProfileAPI := False;
  NestedResult := True;
  SettingsCalls := 0;
  ItemCalls := 0;
  ContentsDuringCallback := '';
  CallbackFilename := '';
  Coordinator := TSettingsSaveCoordinator.Create(SaveSettings, SaveItems);
end;

procedure TSettingsSaveTests.TearDown;
var Search: TSearchRec;
begin
  Coordinator.Free;
  if FindFirst(IncludeTrailingPathDelimiter(Folder) + '*', faAnyFile, Search) = 0 then
  try
    repeat
      if (Search.Attr and faDirectory) = 0 then
        DeleteFile(IncludeTrailingPathDelimiter(Folder) + Search.Name);
    until FindNext(Search) <> 0;
  finally FindClose(Search); end;
  RemoveDir(Folder);
end;

function TSettingsSaveTests.FileCount: Integer;
var Search: TSearchRec;
begin
  Result := 0;
  if FindFirst(IncludeTrailingPathDelimiter(Folder) + '*', faAnyFile, Search) = 0 then
  try
    repeat
      if (Search.Attr and faDirectory) = 0 then Inc(Result);
    until FindNext(Search) <> 0;
  finally FindClose(Search); end;
end;

procedure TSettingsSaveTests.SaveSettings(const Filename: string);
begin
  Inc(SettingsCalls);
  CallbackFilename := Filename;
  WriteText(Filename, '[base]' + LineEnding + 'version=new' + LineEnding);
end;

procedure TSettingsSaveTests.SaveItems(const Filename: string);
begin
  Inc(ItemCalls);
  if Reenter then
  begin
    NestedResult := Coordinator.Save(PrimaryFile);
    ContentsDuringCallback := ReadText(PrimaryFile);
  end;
  if FailItems then raise EItemSaveFailure.Create('Expected item save failure');
  if UseProfileAPI then
  begin
    if not WritePrivateProfileStringW('item1', 'class', 'new', PWideChar(UTF8Decode(Filename))) then
      RaiseLastOSError;
  end
  else WriteText(Filename, ReadText(Filename) + '[item1]' + LineEnding + 'class=new' + LineEnding);
end;

function TSettingsSaveTests.AttemptSave: Boolean;
begin
  try
    Result := Coordinator.Save(PrimaryFile);
  except
    on E: EItemSaveFailure do Result := False;
  end;
end;

procedure TSettingsSaveTests.FailedItemSaveRetainsCompleteFile;
begin
  FailItems := True;
  AssertFalse(AttemptSave);
  AssertEquals('Failed saving must preserve every original section', OldContents, ReadText(PrimaryFile));
end;

procedure TSettingsSaveTests.ReentrantSaveRetainsCompleteFileDuringCallback;
begin
  Reenter := True;
  AssertTrue(Coordinator.Save(PrimaryFile));
  AssertFalse('Nested saves must not call snapshot writers', NestedResult);
  AssertEquals('Nested shutdown must see a complete checkpoint', OldContents, ContentsDuringCallback);
  AssertEquals(1, SettingsCalls);
  AssertEquals(1, ItemCalls);
end;

procedure TSettingsSaveTests.SuccessfulSaveCommitsBothSections;
var Expected: string;
begin
  AssertTrue(Coordinator.Save(PrimaryFile));
  Expected := '[base]' + LineEnding + 'version=new' + LineEnding +
    '[item1]' + LineEnding + 'class=new' + LineEnding;
  AssertEquals(Expected, ReadText(PrimaryFile));
  AssertEquals(ExtractFilePath(PrimaryFile), ExtractFilePath(CallbackFilename));
end;

procedure TSettingsSaveTests.FailedAndSuccessfulSavesRemoveStages;
begin
  FailItems := True;
  AssertFalse(AttemptSave);
  AssertEquals('Failed save leaves one complete file', 1, FileCount);
  FailItems := False;
  AssertTrue(Coordinator.Save(PrimaryFile));
  AssertEquals('Successful save leaves no staging files', 1, FileCount);
end;

procedure TSettingsSaveTests.FailureReleasesSavingGuard;
begin
  FailItems := True;
  AssertFalse(AttemptSave);
  AssertFalse(Coordinator.Saving);
  FailItems := False;
  AssertTrue(Coordinator.Save(PrimaryFile));
  AssertEquals(2, SettingsCalls);
  AssertEquals(2, ItemCalls);
end;

procedure TSettingsSaveTests.ProfileWritesSurviveReplacement;
var Buffer: array[0..31] of WideChar;
begin
  UseProfileAPI := True;
  AssertTrue(Coordinator.Save(PrimaryFile));
  FillChar(Buffer, SizeOf(Buffer), 0);
  GetPrivateProfileStringW('item1', 'class', '', @Buffer[0], Length(Buffer),
    PWideChar(UTF8Decode(PrimaryFile)));
  AssertEquals('new', UTF8Encode(WideString(PWideChar(@Buffer[0]))));
  AssertTrue('Combined settings must retain their base section',
    Pos('version=new', ReadText(PrimaryFile)) > 0);
  AssertEquals(1, FileCount);
end;

procedure TSettingsSaveTests.FailedReplacementPreservesCheckpoint;
var LockHandle: THandle; Failed: Boolean;
begin
  LockHandle := CreateFileW(PWideChar(UTF8Decode(PrimaryFile)), GENERIC_READ,
    FILE_SHARE_READ, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if LockHandle = INVALID_HANDLE_VALUE then RaiseLastOSError;
  Failed := False;
  try
    try Coordinator.Save(PrimaryFile);
    except on E: EOSError do Failed := True; end;
  finally CloseHandle(LockHandle); end;
  AssertTrue('A denied replacement must report failure', Failed);
  AssertEquals(OldContents, ReadText(PrimaryFile));
  AssertEquals('Denied replacement must remove its stage', 1, FileCount);
  AssertFalse(Coordinator.Saving);
end;

initialization
  RegisterTest(TSettingsSaveTests);
end.
