unit settingsschemau;

{$mode delphi}

interface

uses Windows, Classes, SysUtils, IniFiles, declu, docksettingsu;

const DOCK_SETTINGS_DTO_VERSION = 1;

type
  TIniExtension = record
    Section, Name, Value: string;
  end;
  TIniExtensions = array of TIniExtension;
  TSettingsStrings = array of string;
  TDockSettingsDtoV1 = record
    Version: integer;
    Values: TDockSettings;
    AutoRun: TSettingsStrings;
    Extensions: TIniExtensions;
  end;

function DefaultDockSettings(const FontName: string): TDockSettings;
procedure NormalizeDockSettings(var Value: TDockSettings; MonitorCount: integer);
procedure NormalizeDockFont(var Value: TDFontData);
function ReadDockParam(const Value: TDockSettings; Key: TDParam): PtrInt;
function StoreDockParam(var Settings: TDockSettings; Key: TDParam;
  Value: PtrInt; MonitorCount: integer): PtrInt;
function IsStoredDockParam(Key: TDParam): boolean;
function ReadLegacySettings(Ini: TCustomIniFile; const FontName: string;
  MonitorCount: integer): TDockSettingsDtoV1;
procedure WriteLegacySettings(Ini: TCustomIniFile; const Data: TDockSettingsDtoV1);
procedure ValidateSettingsDto(const Data: TDockSettingsDtoV1);

implementation

uses iniproc;

type
  TSettingKind = (skInteger, skBoolean, skSite, skText, skColor);
  PBaseSite = ^TBaseSite;
  TSettingField = record
    Param: TDParam;
    Section, Name: string;
    Offset: PtrUInt;
    Kind: TSettingKind;
    Initial, Minimum, Maximum: integer;
    TextLimit: integer;
    InitialText: string;
  end;

var Fields: array of TSettingField;
  Sample: TDockSettings;

function Clamp(Value: PtrInt; Minimum, Maximum: integer): integer;
begin
  if Value < Minimum then Exit(Minimum);
  if Value > Maximum then Exit(Maximum);
  Result := Value;
end;

function FieldAddress(const Settings: TDockSettings; const Field: TSettingField): Pointer;
begin
  Result := Pointer(PtrUInt(@Settings) + Field.Offset);
end;

function ReadNumber(const Settings: TDockSettings; const Field: TSettingField): PtrInt;
var Address: Pointer;
begin
  Address := FieldAddress(Settings, Field);
  case Field.Kind of
    skBoolean: Result := Ord(PBoolean(Address)^);
    skSite: Result := Ord(PBaseSite(Address)^);
    skColor: Result := PCardinal(Address)^;
    else Result := PInteger(Address)^;
  end;
end;

function ReadText(const Settings: TDockSettings; const Field: TSettingField): string;
var Text: PChar; Count: integer;
begin
  Text := PChar(FieldAddress(Settings, Field));
  Count := 0;
  while (Count < Field.TextLimit) and (Text[Count] <> #0) do Inc(Count);
  SetString(Result, Text, Count);
end;

procedure WriteNumber(var Settings: TDockSettings; const Field: TSettingField; Value: PtrInt);
var Address: Pointer; Bits: cardinal; SignedValue: integer;
begin
  Address := FieldAddress(Settings, Field);
  case Field.Kind of
    skBoolean: PBoolean(Address)^ := Value <> 0;
    skSite: PBaseSite(Address)^ := TBaseSite(Clamp(Value, 0, 3));
    skColor:
      begin
        SignedValue := integer(Value);
        Move(SignedValue, Bits, SizeOf(Bits));
        PCardinal(Address)^ := Bits;
      end;
    else PInteger(Address)^ := Clamp(Value, Field.Minimum, Field.Maximum);
  end;
end;

procedure AddField(Param: TDParam; const Section, Name: string; Address: Pointer;
  Kind: TSettingKind; Initial, Minimum, Maximum: integer);
var Index: integer;
begin
  Index := Length(Fields);
  SetLength(Fields, Index + 1);
  Fields[Index].Param := Param;
  Fields[Index].Section := Section;
  Fields[Index].Name := Name;
  Fields[Index].Offset := PtrUInt(Address) - PtrUInt(@Sample);
  Fields[Index].Kind := Kind;
  Fields[Index].Initial := Initial;
  Fields[Index].Minimum := Minimum;
  Fields[Index].Maximum := Maximum;
end;

procedure AddText(Param: TDParam; const Section, Name: string; Address: Pointer;
  Limit: integer; const Initial: string);
begin
  AddField(Param, Section, Name, Address, skText, 0, 0, 0);
  Fields[High(Fields)].TextLimit := Limit;
  Fields[High(Fields)].InitialText := Initial;
end;

procedure NormalizeDockFont(var Value: TDFontData);
begin
  Value.Name[High(Value.Name)] := #0;
  Value.Size := Clamp(Value.Size, 6, 72);
  Value.Size2 := Clamp(Value.Size2, 6, 72);
end;

procedure NormalizeDockSettings(var Value: TDockSettings; MonitorCount: integer);
var Field: TSettingField;
begin
  for Field in Fields do
    if Field.Kind in [skInteger, skBoolean, skSite] then
      WriteNumber(Value, Field, ReadNumber(Value, Field));
  Value.Monitor := Clamp(Value.Monitor, -1, MonitorCount - 1);
  if Value.BigItemSize < Value.ItemSize then Value.BigItemSize := Value.ItemSize;
  Value.ZoomWidth := (Value.ZoomWidth div 2) * 2;
  NormalizeDockFont(Value.Font);
  Value.Shell[High(Value.Shell)] := #0;
  Value.ThemeName[High(Value.ThemeName)] := #0;
end;

function DefaultDockSettings(const FontName: string): TDockSettings;
var Field: TSettingField;
begin
  Result := Default(TDockSettings);
  for Field in Fields do
    if Field.Kind = skText then
      StrPLCopy(PChar(FieldAddress(Result, Field)), Field.InitialText, Field.TextLimit)
    else WriteNumber(Result, Field, Field.Initial);
  StrPLCopy(@Result.Font.Name[0], FontName, High(Result.Font.Name));
  Result.DropDistance := Result.ItemSize;
end;

function IsStoredDockParam(Key: TDParam): boolean;
var Field: TSettingField;
begin
  Result := False;
  if Key = gpMin then Exit;
  for Field in Fields do if Field.Param = Key then Exit(True);
end;

function ReadDockParam(const Value: TDockSettings; Key: TDParam): PtrInt;
var Field: TSettingField;
begin
  Result := 0;
  if Key = gpMin then Exit;
  for Field in Fields do
    if Field.Param = Key then Exit(ReadNumber(Value, Field));
end;

function StoreDockParam(var Settings: TDockSettings; Key: TDParam;
  Value: PtrInt; MonitorCount: integer): PtrInt;
var Field: TSettingField;
begin
  Result := 0;
  if Key = gpMin then Exit;
  for Field in Fields do
    if Field.Param = Key then
    begin
      WriteNumber(Settings, Field, Value);
      NormalizeDockSettings(Settings, MonitorCount);
      Exit(ReadDockParam(Settings, Key));
    end;
end;

function KnownField(const Section, Name: string): boolean;
var Field: TSettingField;
begin
  for Field in Fields do
    if SameText(Field.Section, Section) and SameText(Field.Name, Name) then Exit(True);
  Result := False;
end;

function ReadLegacySettings(Ini: TCustomIniFile; const FontName: string;
  MonitorCount: integer): TDockSettingsDtoV1;
var Field: TSettingField; Sections, Names: TStringList; Section, Name: string;
  Index, Count: integer;
begin
  Result := Default(TDockSettingsDtoV1);
  Result.Version := DOCK_SETTINGS_DTO_VERSION;
  Result.Values := DefaultDockSettings(FontName);
  for Field in Fields do
    if Field.Section <> '' then
      case Field.Kind of
        skText: StrPLCopy(PChar(FieldAddress(Result.Values, Field)),
          Ini.ReadString(Field.Section, Field.Name,
            ReadText(Result.Values, Field)), Field.TextLimit);
        skSite: WriteNumber(Result.Values, Field,
          Ord(StringToSite(LowerCase(Trim(Ini.ReadString(Field.Section, Field.Name, 'top'))))));
        skBoolean: WriteNumber(Result.Values, Field,
          Ord(ParseLegacyBoolean(Ini.ReadString(Field.Section, Field.Name, ''), Field.Initial <> 0)));
        else WriteNumber(Result.Values, Field,
          Ini.ReadInteger(Field.Section, Field.Name, Field.Initial));
      end;
  Result.Values.DropDistance := Result.Values.ItemSize;
  NormalizeDockSettings(Result.Values, MonitorCount);
  Sections := TStringList.Create;
  Names := TStringList.Create;
  try
    Ini.ReadSection('autorun', Names);
    SetLength(Result.AutoRun, Names.Count);
    for Index := 0 to Names.Count - 1 do
      Result.AutoRun[Index] := Ini.ReadString('autorun', Names[Index], '');
    Ini.ReadSections(Sections);
    for Section in Sections do
      if not SameText(Section, 'autorun') and (Pos('item', LowerCase(Section)) <> 1) then
      begin
        Names.Clear;
        Ini.ReadSection(Section, Names);
        for Name in Names do if not KnownField(Section, Name) then
        begin
          Count := Length(Result.Extensions);
          SetLength(Result.Extensions, Count + 1);
          Result.Extensions[Count].Section := Section;
          Result.Extensions[Count].Name := Name;
          Result.Extensions[Count].Value := Ini.ReadString(Section, Name, '');
        end;
      end;
  finally Names.Free; Sections.Free; end;
end;

procedure ValidateSettingsDto(const Data: TDockSettingsDtoV1);
var Field: TSettingField; Extension: TIniExtension; Value: string;
begin
  if Data.Version <> DOCK_SETTINGS_DTO_VERSION then
    raise EConvertError.Create('Unsupported settings DTO version');
  for Field in Fields do
    if Field.Kind = skText then CheckIniValue(ReadText(Data.Values, Field));
  for Extension in Data.Extensions do CheckIniValue(Extension.Value);
  for Value in Data.AutoRun do CheckIniValue(Value);
end;

procedure WriteLegacySettings(Ini: TCustomIniFile; const Data: TDockSettingsDtoV1);
var Field: TSettingField; Extension: TIniExtension; Index, SignedColor: integer;
  Color: cardinal;
begin
  ValidateSettingsDto(Data);
  for Extension in Data.Extensions do
    Ini.WriteString(Extension.Section, Extension.Name, Extension.Value);
  for Field in Fields do
    if Field.Section <> '' then
      case Field.Kind of
        skText:
          begin
            Ini.WriteString(Field.Section, Field.Name,
              ReadText(Data.Values, Field));
          end;
        skSite: Ini.WriteString(Field.Section, Field.Name, SiteToString(Data.Values.Site));
        skBoolean: if SameText(Field.Name, 'Hello') then
          Ini.WriteBool(Field.Section, Field.Name, False)
        else if Field.Param in [gpActivateRunning, gpShowRunningIndicator] then
          Ini.WriteInteger(Field.Section, Field.Name, ReadNumber(Data.Values, Field))
        else Ini.WriteBool(Field.Section, Field.Name, ReadNumber(Data.Values, Field) <> 0);
        skColor:
          begin
            Color := PCardinal(FieldAddress(Data.Values, Field))^;
            Move(Color, SignedColor, SizeOf(Color));
            Ini.WriteInteger(Field.Section, Field.Name, SignedColor);
          end;
        else Ini.WriteInteger(Field.Section, Field.Name, ReadNumber(Data.Values, Field));
      end;
  for Index := 0 to High(Data.AutoRun) do
    if Data.AutoRun[Index] <> '' then
      Ini.WriteString('autorun', 'command' + IntToStr(Index), '"' + Data.AutoRun[Index] + '"');
end;

procedure InitializeSchema;
begin
  AddText(gpMin, 'base', 'Theme', @Sample.ThemeName, SizeOf(Sample.ThemeName) - 1, 'Aero');
  AddField(gpMonitor, 'base', 'Monitor', @Sample.Monitor, skInteger, 0, -2147483648, 2147483647);
  AddField(gpSite, 'base', 'Site', @Sample.Site, skSite, 1, 0, 3);
  AddField(gpCenterOffsetPercent, 'base', 'CenterOffsetPercent', @Sample.CenterOffsetPercent, skInteger, 50, 0, 100);
  AddField(gpEdgeOffset, 'base', 'EdgeOffset', @Sample.EdgeOffset, skInteger, 0, -100, 100);
  AddField(gpOccupyFullMonitor, 'base', 'OccupyFullMonitor', @Sample.OccupyFullMonitor, skBoolean, Ord(false), 0, 1);
  AddField(gpStartOffset, 'base', 'StartOffset', @Sample.StartOffset, skInteger, 0, -10000, 10000);
  AddField(gpEndOffset, 'base', 'EndOffset', @Sample.EndOffset, skInteger, 0, -10000, 10000);
  AddText(gpMin, 'base', 'Shell', @Sample.Shell, SizeOf(Sample.Shell) - 1, '');
  AddField(gpAutoHide, 'base', 'AutoHide', @Sample.autohide, skBoolean, Ord(false), 0, 1);
  AddField(gpAutoHideTime, 'base', 'AutoHideTime', @Sample.autohidetime, skInteger, 800, 0, 9999);
  AddField(gpAutoShowTime, 'base', 'AutoShowTime', @Sample.autoshowtime, skInteger, 400, 0, 9999);
  AddField(gpAutoHidePixels, 'base', 'AutoHidePixels', @Sample.AutoHidePixels, skInteger, 15, 0, 9999);
  AddField(gpLaunchInterval, 'base', 'LaunchInterval', @Sample.LaunchInterval, skInteger, 500, 0, 9999);
  AddField(gpActivateRunning, 'base', 'ActivateRunning', @Sample.ActivateRunningApps, skBoolean, Ord(true), 0, 1);
  AddField(gpShowRunningIndicator, 'base', 'ShowRunningIndicator', @Sample.ShowRunningIndicator, skBoolean, Ord(true), 0, 1);
  AddField(gpItemAnimationType, 'base', 'ItemAnimation', @Sample.ItemAnimationType, skInteger, 4, 0, 8);
  AddField(gpItemSize, 'base', 'ItemSize', @Sample.ItemSize, skInteger, 48, 16, 128);
  AddField(gpBigItemSize, 'base', 'BigItemSize', @Sample.BigItemSize, skInteger, 96, 16, 256);
  AddField(gpItemSpacing, 'base', 'ItemSpacing', @Sample.ItemSpacing, skInteger, 4, 0, 30);
  AddField(gpZoomWidth, 'base', 'ZoomWidth', @Sample.ZoomWidth, skInteger, 6, 4, 10);
  AddField(gpZoomTime, 'base', 'ZoomTime', @Sample.ZoomTime, skInteger, 120, 0, 600);
  AddField(gpGlobalHotkeyFlag_Hide, 'base', 'GlobalHotkeyFlag_Hide', @Sample.GlobalHotkeyFlag_Hide, skBoolean, Ord(false), 0, 1);
  AddField(gpGlobalHotkeyValue_Hide, 'base', 'GlobalHotkeyValue_Hide', @Sample.GlobalHotkeyValue_Hide, skInteger, 16506, -2147483648, 2147483647);
  AddField(gpGlobalHotkeyFlag_Console, 'base', 'GlobalHotkeyFlag_Console', @Sample.GlobalHotkeyFlag_Console, skBoolean, Ord(false), 0, 1);
  AddField(gpGlobalHotkeyValue_Console, 'base', 'GlobalHotkeyValue_Console', @Sample.GlobalHotkeyValue_Console, skInteger, 0, -2147483648, 2147483647);
  AddField(gpAutoHideOnFullScreenApp, 'base', 'AutoHideOnFullScreenApp', @Sample.AutoHideOnFullScreenApp, skBoolean, Ord(true), 0, 1);
  AddField(gpUseShell, 'base', 'UseShell', @Sample.useShell, skBoolean, Ord(false), 0, 1);
  AddField(gpRunInThread, 'base', 'RunInThread', @Sample.RunInThread, skBoolean, Ord(false), 0, 1);
  AddField(gpZoomEnabled, 'base', 'ZoomItems', @Sample.ZoomEnabled, skBoolean, Ord(true), 0, 1);
  AddField(gpLaunchInThread, 'base', 'LaunchInThread', @Sample.LaunchInThread, skBoolean, Ord(true), 0, 1);
  AddField(gpActivateOnMouse, 'base', 'ActivateOnMouse', @Sample.ActivateOnMouse, skBoolean, Ord(true), 0, 1);
  AddField(gpActivateOnMouseInterval, 'base', 'ActivateOnMouseInterval', @Sample.ActivateOnMouseInterval, skInteger, 400, 0, 2000);
  AddField(gpCloseCmdWindow, 'base', 'CloseCmdWindow', @Sample.CloseCmdWindow, skBoolean, Ord(true), 0, 1);
  AddField(gpHideSystemTaskbar, 'base', 'HideTaskBar', @Sample.HideSystemTaskbar, skBoolean, Ord(false), 0, 1);
  AddField(gpReserveScreenEdge, 'base', 'ReserveScreenEdge', @Sample.ReserveScreenEdge, skBoolean, Ord(false), 0, 1);
  AddField(gpReserveScreenEdgePercent, 'base', 'ReserveScreenEdgePercent', @Sample.ReserveScreenEdgePercent, skInteger, 100, 0, 200);
  AddField(gpAeroPeekEnabled, 'base', 'AeroPeekEnabled', @Sample.AeroPeekEnabled, skBoolean, Ord(true), 0, 1);
  AddField(gpTaskbar, 'base', 'Taskbar', @Sample.Taskbar, skBoolean, Ord(false), 0, 1);
  AddField(gpTaskLivePreviews, 'base', 'TaskbarLivePreviews', @Sample.TaskLivePreviews, skBoolean, Ord(true), 0, 1);
  AddField(gpTaskThumbSize, 'base', 'TaskThumbSize', @Sample.TaskThumbSize, skInteger, 200, 1, 4096);
  AddField(gpTaskGrouping, 'base', 'TaskbarGrouping', @Sample.TaskGrouping, skBoolean, Ord(true), 0, 1);
  AddField(gpTaskSameMonitor, 'base', 'TaskbarSameMonitor', @Sample.TaskSameMonitor, skBoolean, Ord(false), 0, 1);
  AddField(gpTaskSystemMenus, 'base', 'TaskSystemMenus', @Sample.TaskSystemMenus, skBoolean, Ord(false), 0, 1);
  AddField(gpTaskSpot, 'base', 'TaskSpot', @Sample.TaskSpot, skInteger, -1, -1, 2147483647);
  AddField(gpStayOnTop, 'base', 'StayOnTop', @Sample.StayOnTop, skBoolean, Ord(false), 0, 1);
  AddField(gpLockDragging, 'base', 'LockDragging', @Sample.LockDragging, skBoolean, Ord(true), 0, 1);
  AddField(gpShowHint, 'base', 'ShowHint', @Sample.ShowHint, skBoolean, Ord(true), 0, 1);
  AddField(gpHintEffects, 'base', 'HintEffects', @Sample.HintEffects, skBoolean, Ord(false), 0, 1);
  AddField(gpUseShellContextMenus, 'base', 'UseShellContextMenus', @Sample.UseShellContextMenus, skBoolean, Ord(true), 0, 1);
  AddField(gpStackAnimationEnabled, 'base', 'StackOpenAnimation', @Sample.StackAnimationEnabled, skBoolean, Ord(true), 0, 1);
  AddField(gpMin, 'base', 'Hello', @Sample.Hello, skBoolean, Ord(true), 0, 1);
  AddField(gpBaseAlpha, 'gfx', 'BaseAlpha', @Sample.BaseAlpha, skInteger, 255, 13, 255);
  AddField(gpSeparatorAlpha, 'gfx', 'SeparatorAlpha', @Sample.SeparatorAlpha, skInteger, 255, 0, 255);
  AddField(gpReflectionEnabled, 'gfx', 'Reflection', @Sample.ReflectionEnabled, skBoolean, Ord(true), 0, 1);
  AddField(gpReflectionSize, 'gfx', 'ReflectionSize', @Sample.ReflectionSize, skInteger, 10, 0, 256);
  AddField(gpBlurEnabled, 'gfx', 'Blur', @Sample.BlurEnabled, skBoolean, Ord(true), 0, 1);
  AddText(gpMin, 'Font', 'name', @Sample.Font.name, SizeOf(Sample.Font.name) - 1, '');
  AddField(gpMin, 'Font', 'size', @Sample.Font.size, skInteger, 15, 6, 72);
  AddField(gpMin, 'Font', 'size2', @Sample.Font.size2, skInteger, 14, 6, 72);
  AddField(gpMin, 'Font', 'color', @Sample.Font.color, skColor, -1, -2147483648, 2147483647);
  AddField(gpMin, 'Font', 'backcolor', @Sample.Font.backcolor, skColor, -14671840, -2147483648, 2147483647);
  AddField(gpMin, 'Font', 'bold', @Sample.Font.bold, skBoolean, Ord(true), 0, 1);
  AddField(gpMin, 'Font', 'italic', @Sample.Font.italic, skBoolean, Ord(false), 0, 1);
  AddField(gpDropDistance, '', '', @Sample.DropDistance, skInteger, 48, 16, 500);
end;

initialization
  InitializeSchema;
end.
