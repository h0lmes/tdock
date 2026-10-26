unit setsu;

interface
uses Windows, Controls, Forms, Classes, SysUtils, Dialogs,
      Menus, StdCtrls, IniFiles, gfx, declu, toolu, dockh, loggeru, docksettingsu, settingsschemau;

type

  { TDSetsContainer }

  TDSetsContainer = TDockSettings;

  { TDSets }

  TDSets = class
  private
    FSetsPathFile: string;
    FPluginsPath: string;
    PluginsList: TStrings;
    PluginFilesList: TStrings;
    FBackupPath: string;
    BackupsList: TStrings;
    FThemesPath: string;
    FExtensions: TIniExtensions;
  public
    container: TDSetsContainer;
    cancel_container: TDSetsContainer;
    ParentHWnd: THandle;
    AutoRunList: TStrings;

    property SetsPathFile: string read FSetsPathFile;
    property BackupsPath: string read FBackupPath;
    property PluginsPath: string read FPluginsPath;
    property ThemesPath: string read FThemesPath;

    constructor Create(ASetsPathFile, AProgramPath: string; Handle: THandle);
    destructor Destroy; override;
    procedure Load; overload;
    procedure Load(ASetsFile: string); overload;
    procedure Save; overload;
    procedure SaveTo(const Filename: string);
    procedure Save(ASetsFile: string); overload;
    function Backup: boolean;
    function Restore(backupFilename: string): boolean;
    function StoreParam(id: TDParam; value: PtrInt): PtrInt;
    function GetParam(id: TDParam): PtrInt;
    procedure StoreSetsContainer;
    procedure RestoreSetsContainer;
    procedure CopySetsContainer(var dst: TDSetsContainer; var src: TDSetsContainer);
    function getBaseOrientation: TBaseOrientation;
    function GetMonitorCount: integer;
    function GetMonitorName(index: integer): string;
    function GetPluginCount: integer;
    function GetPluginName(index: integer): string;
    function GetPluginFileName(index: integer): string;
    procedure ScanPlugins;
    procedure GetPluginInfo(index: integer; mem: TMemo);
  end;

var sets: TDSets;

implementation
//------------------------------------------------------------------------------
constructor TDSets.Create(ASetsPathFile, AProgramPath: string; Handle: THandle);
begin
  inherited Create;
  ParentHWnd := Handle;
  container := DefaultDockSettings(toolu.GetFont);
  FSetsPathFile := ASetsPathFile;
  FBackupPath := IncludeTrailingPathDelimiter(AProgramPath) + 'Backup';
  FPluginsPath := IncludeTrailingPathDelimiter(AProgramPath) + 'Docklets';
  FThemesPath := IncludeTrailingPathDelimiter(AProgramPath) + 'Themes\';
end;
//------------------------------------------------------------------------------
destructor TDSets.Destroy;
begin
  if assigned(BackupsList) then BackupsList.free;
  if assigned(PluginsList) then PluginsList.free;
  if assigned(PluginFilesList) then PluginFilesList.free;
  if assigned(AutoRunList) then AutoRunList.free;
end;
//------------------------------------------------------------------------------
procedure TDSets.Load(ASetsFile: string);
begin
  FSetsPathFile := ASetsFile;
  Load;
end;
//------------------------------------------------------------------------------
procedure TDSets.Load;
var Ini: TIniFile; Data: TDockSettingsDtoV1; Value: string;
begin
  Ini := TIniFile.Create(SetsPathFile);
  try Data := ReadLegacySettings(Ini, toolu.GetFont, Screen.MonitorCount);
  finally Ini.Free; end;
  container := Data.Values;
  FExtensions := Data.Extensions;
  if not Assigned(AutoRunList) then AutoRunList := TStringList.Create;
  AutoRunList.Clear;
  for Value in Data.AutoRun do AutoRunList.Add(Value);
end;
//------------------------------------------------------------------------------
procedure TDSets.Save(ASetsFile: string);
begin
  FSetsPathFile := ASetsFile;
  Save;
end;
//------------------------------------------------------------------------------
procedure TDSets.Save;
begin SaveTo(FSetsPathFile); end;
//------------------------------------------------------------------------------
procedure TDSets.SaveTo(const Filename: string);
var Ini: TIniFile; Data: TDockSettingsDtoV1; Index: integer;
begin
  Data := Default(TDockSettingsDtoV1);
  Data.Version := DOCK_SETTINGS_DTO_VERSION;
  Data.Values := container;
  NormalizeDockSettings(Data.Values, Screen.MonitorCount);
  Data.Extensions := FExtensions;
  if Assigned(AutoRunList) then
  begin
    SetLength(Data.AutoRun, AutoRunList.Count);
    for Index := 0 to AutoRunList.Count - 1 do Data.AutoRun[Index] := AutoRunList[Index];
  end;
  ValidateSettingsDto(Data);
  if FileExists(Filename) and not Windows.DeleteFile(PChar(Filename)) then RaiseLastOSError;
  Ini := TIniFile.Create(Filename);
  try
    Ini.CacheUpdates := True;
    WriteLegacySettings(Ini, Data);
    Ini.UpdateFile;
  finally Ini.Free; end;
end;
//------------------------------------------------------------------------------
function TDSets.Backup: boolean;
var
  setsFilenameBase, backupFile, lastBackupFile: string;
  list: TStrings;
  lastBackupFS, setsFS: TFileStream;
  identical: boolean;
begin
  result := true;
  try
    if not FileExists(SetsPathFile) then exit;
    setsFilenameBase := ChangeFileExt(ExtractFileName(SetsPathFile), '');

    // list all backup files
    list := TStringList.Create;
    toolu.SearchFilesRecursive(BackupsPath, setsFilenameBase + '*.ini', list);
    toolu.qSortStrings(list);

    // compare the last one (if exists) with the settings file
    identical := false;
    if list.Count > 0 then
    begin
      lastBackupFile := list.Strings[list.Count - 1];
      lastBackupFS := TFileStream.Create(lastBackupFile, fmOpenRead);
      setsFS := TFileStream.Create(SetsPathFile, fmOpenRead);
      identical := IsIdenticalStreams(lastBackupFS, setsFS);
      lastBackupFS.free;
      setsFS.free;
		end;
    list.free;

    // if exists and they are identical - exit
    if identical then exit;

    if not DirectoryExists(BackupsPath) then windows.CreateDirectory(pchar(BackupsPath), nil);
    backupFile := BackupsPath + '\' + setsFilenameBase + '__' + FormatDateTime('yyyy-MM-dd__hh-nn-ss', Now) + '.ini';
    if not windows.CopyFile(pchar(SetsPathFile), pchar(backupFile), false) then result := false;
  except
    on e: Exception do raise Exception.Create('Sets.Backup ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
function TDSets.Restore(backupFilename: string): boolean;
begin
  result := false;
  try
    AddLog('Sets.Restore');

    if not FileExists(backupFilename) then
      raise Exception.Create('Backup file not found!');

    if FileExists(SetsPathFile) then
      if not windows.DeleteFile(PChar(SetsPathFile)) then
        raise Exception.Create('Can not delete settings file!');

    if windows.CopyFile(pchar(backupFilename), pchar(SetsPathFile), false) then result := true;
  except
    on e: Exception do raise Exception.Create('Sets.Restore ' + LineEnding + e.message);
  end;
end;
//------------------------------------------------------------------------------
function TDSets.StoreParam(id: TDParam; value: PtrInt): PtrInt;
begin
  Result := StoreDockParam(container, id, value, Screen.MonitorCount);
end;
//------------------------------------------------------------------------------
function TDSets.GetParam(id: TDParam): PtrInt;
begin
  Result := ReadDockParam(container, id);
  if id = gpMonitor then Result := SetRange(Result, -1, Screen.MonitorCount - 1);
end;
//------------------------------------------------------------------------------
procedure TDSets.StoreSetsContainer;
begin
  CopySetsContainer(cancel_container, container);
end;
//------------------------------------------------------------------------------
procedure TDSets.RestoreSetsContainer;
begin
  CopySetsContainer(container, cancel_container);
end;
//------------------------------------------------------------------------------
procedure TDSets.CopySetsContainer(var dst: TDSetsContainer; var src: TDSetsContainer);
begin
  dst := src;
end;
//------------------------------------------------------------------------------
function TDSets.getBaseOrientation: TBaseOrientation;
begin
  result := boHorizontal;
  if (container.site = bsLeft) or (container.site = bsRight) then result := boVertical;
end;
//------------------------------------------------------------------------------
//
//
//
//------------------------------------------------------------------------------
function TDSets.GetMonitorCount: integer;
begin
  result := screen.MonitorCount;
end;
//------------------------------------------------------------------------------
function TDSets.GetMonitorName(index: integer): string;
begin
  if index < 0 then result := XAll
  else result := XMonitor + ' ' + inttostr(screen.Monitors[index].MonitorNum + 1);
end;
//------------------------------------------------------------------------------
//
//
//
//------------------------------------------------------------------------------
function TDSets.GetPluginCount: integer;
begin
  result := -1;
  if assigned(PluginsList) then result := PluginsList.Count;
end;
//------------------------------------------------------------------------------
function TDSets.GetPluginName(index: integer): string;
begin
  result := '';
  if assigned(PluginsList) then result := PluginsList.Strings[index];
end;
//------------------------------------------------------------------------------
function TDSets.GetPluginFileName(index: integer): string;
begin
  result := '';
  if assigned(PluginFilesList) then result := PluginFilesList.Strings[index];
end;
//------------------------------------------------------------------------------
procedure TDSets.ScanPlugins;
var
  idx: integer;
  hLib: THandle;
  OnGetInformation: _OnGetInformation;
  szName, szAuthor, szNotes: array [0..255] of char;
  lpiVersion: integer;
  cdir: string;
begin
  try
    cdir := GetCurrentDir;
    if not assigned(PluginsList) then PluginsList:= TStringList.Create;
    if not assigned(PluginFilesList) then PluginFilesList:= TStringList.Create;
    PluginsList.clear;
    PluginFilesList.clear;
    toolu.SearchFilesRecursive(PluginsPath, '*.dll', PluginFilesList);

    idx := 0;
    while idx < PluginFilesList.Count do
    begin
      SetCurrentDir(ExtractFilePath(PluginFilesList.strings[idx]));
      hLib := LoadLibrary(pchar(PluginFilesList.strings[idx]));
      if hLib < 33 then PluginFilesList.Delete(idx)
      else begin
        @OnGetInformation := GetProcAddress(hLib, 'OnGetInformation');
        if not assigned(OnGetInformation) then PluginFilesList.Delete(idx)
        else
        begin
          try OnGetInformation(@szName, @szAuthor, @lpiVersion, @szNotes);
          except end;
          PluginsList.add(strpas(@szName));
          inc(idx);
        end;
        FreeLibrary(hLib);
      end;
    end;
  finally
    if cdir <> '' then SetCurrentDir(cdir);
  end;
end;
//------------------------------------------------------------------------------
procedure TDSets.GetPluginInfo(index: integer; mem: TMemo);
var
  hLib: THandle;
  OnGetInformation: _OnGetInformation;
  szName, szAuthor, szNotes: array [0..255] of char;
  lpiVersion: integer;
  ver: string;
  cdir: string;
begin
  try
    mem.clear;

    cdir := GetCurrentDir;
    SetCurrentDir(ExtractFilePath(PluginFilesList.strings[Index]));
    hLib := LoadLibrary(pansichar(PluginFilesList.strings[Index]));
    if hLib < 33 then
    begin
      mem.text:= 'Error loading plugin';
      exit;
    end;

    @OnGetInformation:= GetProcAddress(hLib, 'OnGetInformation');
    if assigned(OnGetInformation) then
    begin
      try OnGetInformation(@szName[0], @szAuthor[0], @lpiVersion, @szNotes[0]);
      except
        begin
          FreeLibrary(hLib);
          messagebox(application.mainform.handle, 'Error trying to get information', 'Terry', mb_iconerror);
          exit;
        end;
      end;
      mem.lines.add(strpas(@szNotes[0]));
      mem.lines.add('');
      mem.lines.add('Author: ' + strpas(@szAuthor[0]));
      mem.lines.add('');
      ver := 'v' + inttostr(lpiVersion div 100) + '.';
      if lpiVersion mod 100 < 10 then ver:= ver + '0';
      ver := ver + inttostr(lpiVersion mod 100);
      mem.lines.add(ver);
    end else
      mem.text := 'Unknown plugin format';
    FreeLibrary(hLib);
  finally
    if cdir <> '' then SetCurrentDir(cdir);
  end;
end;
//------------------------------------------------------------------------------
end.
