unit settingssaveu;

{$mode delphi}

interface

uses SysUtils;

type
  TSaveSnapshot = procedure(const Filename: string) of object;
  TSettingsSaveCoordinator = class
  private
    FSaveSettings, FSaveItems: TSaveSnapshot;
    FSaving: Boolean;
    FSequence: LongWord;
    function CreateStage(const Filename: string): string;
  public
    constructor Create(SaveSettings, SaveItems: TSaveSnapshot);
    function Save(const Filename: string): Boolean;
    property Saving: Boolean read FSaving;
  end;

implementation

uses Windows;

const MOVEFILE_WRITE_THROUGH_FLAG = $00000008;

constructor TSettingsSaveCoordinator.Create(SaveSettings, SaveItems: TSaveSnapshot);
begin
  inherited Create;
  if not Assigned(SaveSettings) or not Assigned(SaveItems) then
    raise EArgumentException.Create('Settings snapshot callbacks');
  FSaveSettings := SaveSettings;
  FSaveItems := SaveItems;
end;

function TSettingsSaveCoordinator.CreateStage(const Filename: string): string;
var Attempt: Integer; StageHandle: THandle; WideName: WideString; ErrorCode: DWORD;
begin
  for Attempt := 1 to 128 do
  begin
    if FSequence = High(FSequence) then FSequence := 0;
    Inc(FSequence);
    Result := Filename + '.' + IntToHex(GetCurrentProcessId, 8) + '.' +
      IntToHex(GetTickCount64, 16) + '.' + IntToHex(FSequence, 8) + '.tmpini';
    WideName := UTF8Decode(Result);
    StageHandle := CreateFileW(PWideChar(WideName), GENERIC_WRITE, 0, nil,
      CREATE_NEW, FILE_ATTRIBUTE_NORMAL, 0);
    if StageHandle <> INVALID_HANDLE_VALUE then
    begin CloseHandle(StageHandle); Exit; end;
    ErrorCode := GetLastError;
    if ErrorCode <> ERROR_FILE_EXISTS then RaiseLastOSError(ErrorCode);
  end;
  raise EInOutError.Create('Cannot create settings snapshot file');
end;

function TSettingsSaveCoordinator.Save(const Filename: string): Boolean;
var StageName, TargetName: string; WideStage, WideTarget: WideString;
  StageHandle: THandle;
begin
  if FSaving then Exit(False);
  FSaving := True;
  StageName := '';
  try
    TargetName := ExpandFileName(Filename);
    StageName := CreateStage(TargetName);
    WideStage := UTF8Decode(StageName);
    WideTarget := UTF8Decode(TargetName);
    FSaveSettings(StageName);
    FSaveItems(StageName);
    // The profile API returns zero when it flushes its cache.
    WritePrivateProfileStringW(nil, nil, nil, PWideChar(WideStage));
    StageHandle := CreateFileW(PWideChar(WideStage), GENERIC_WRITE,
      FILE_SHARE_READ, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
    if StageHandle = INVALID_HANDLE_VALUE then RaiseLastOSError;
    try
      if not FlushFileBuffers(StageHandle) then RaiseLastOSError;
    finally CloseHandle(StageHandle); end;
    if not MoveFileExW(PWideChar(WideStage), PWideChar(WideTarget),
      MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH_FLAG) then RaiseLastOSError;
    StageName := '';
    Result := True;
  finally
    if StageName <> '' then DeleteFileW(PWideChar(WideStage));
    FSaving := False;
  end;
end;

end.
