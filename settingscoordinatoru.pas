unit settingscoordinatoru;

{$mode delphi}

interface

uses SysUtils, declu, setsu, itemsettingsu;

type
  TDockSetting = gpMonitor..gpTaskSpot;
  TDockSettingChange = record
    Key: TDockSetting;
    OldValue, NewValue: Integer;
  end;
  TSettingChangeEvent = procedure(const Change: TDockSettingChange) of object;
  TSettingsCoordinator = class
  private
    FStore: TDSets;
    FMouseEffectLocked: boolean;
  public
    OnBeforeChange, OnApplying, OnNotifyItems, OnApplied: TSettingChangeEvent;
    constructor Create(Store: TDSets);
    procedure Apply(Key: TDParam; Value: Integer);
    procedure Reapply;
    procedure SetShell(const Value: string);
    procedure SetTheme(const Value: string);
    procedure SetFont(const Value: TDFontData);
    property Store: TDSets read FStore;
  end;

function ItemSettingsFromContainer(const Settings: TDSetsContainer): TItemManagerSettings;

implementation

uses settingsschemau, iniproc;

constructor TSettingsCoordinator.Create(Store: TDSets);
begin
  inherited Create;
  if Store = nil then raise EArgumentNilException.Create('Settings store');
  FStore := Store;
end;

procedure TSettingsCoordinator.Apply(Key: TDParam; Value: Integer);
var Change: TDockSettingChange; OldBigSize: Integer;
begin
  if (Key <= gpMin) or (Key >= gpMax) then Exit;
  if (Key <> gpLockMouseEffect) and not IsStoredDockParam(Key) then Exit;
  Change.Key := TDockSetting(Key);
  if Key = gpLockMouseEffect then Change.OldValue := Ord(FMouseEffectLocked)
  else Change.OldValue := FStore.GetParam(Key);
  Change.NewValue := Value;
  OldBigSize := FStore.container.BigItemSize;
  if Assigned(OnBeforeChange) then OnBeforeChange(Change);
  if Key = gpLockMouseEffect then
  begin
    FMouseEffectLocked := Value <> 0;
    Change.NewValue := Ord(FMouseEffectLocked);
  end else Change.NewValue := FStore.StoreParam(Key, Value);
  if Assigned(OnApplying) then OnApplying(Change);
  if Assigned(OnNotifyItems) then OnNotifyItems(Change);
  if Assigned(OnApplied) then OnApplied(Change);
  if (Key = gpItemSize) and (OldBigSize <> FStore.container.BigItemSize) then
  begin
    Change.Key := gpBigItemSize;
    Change.OldValue := OldBigSize;
    Change.NewValue := FStore.container.BigItemSize;
    if Assigned(OnBeforeChange) then OnBeforeChange(Change);
    if Assigned(OnApplying) then OnApplying(Change);
    if Assigned(OnNotifyItems) then OnNotifyItems(Change);
    if Assigned(OnApplied) then OnApplied(Change);
  end;
end;

procedure TSettingsCoordinator.Reapply;
var Key: TDockSetting;
begin
  for Key := Low(TDockSetting) to High(TDockSetting) do
    if not (Key in [gpActivateRunningApps, gpLockMouseEffect]) then
      Apply(Key, FStore.GetParam(Key));
end;

procedure TSettingsCoordinator.SetShell(const Value: string);
begin
  CheckIniValue(Value);
  StrPLCopy(@FStore.container.Shell[0], Value, High(FStore.container.Shell));
end;

procedure TSettingsCoordinator.SetTheme(const Value: string);
begin
  CheckIniValue(Value);
  StrPLCopy(@FStore.container.ThemeName[0], Value, High(FStore.container.ThemeName));
end;

procedure TSettingsCoordinator.SetFont(const Value: TDFontData);
begin
  FStore.container.Font := Value;
  NormalizeDockFont(FStore.container.Font);
end;

function ItemSettingsFromContainer(const Settings: TDSetsContainer): TItemManagerSettings;
begin
  Result := Default(TItemManagerSettings);
  Result.ItemSize := Settings.ItemSize;
  Result.BigItemSize := Settings.BigItemSize;
  Result.ZoomWidth := Settings.ZoomWidth;
  Result.ZoomTime := Settings.ZoomTime;
  Result.ItemSpacing := Settings.ItemSpacing;
  Result.ZoomEnabled := Settings.ZoomEnabled;
  Result.ReflectionEnabled := Settings.ReflectionEnabled;
  Result.ReflectionSize := Settings.ReflectionSize;
  Result.LaunchInterval := Settings.LaunchInterval;
  Result.ItemAnimationType := Settings.ItemAnimationType;
  Result.SeparatorAlpha := Settings.SeparatorAlpha;
  Result.ActivateRunning := Settings.ActivateRunningApps;
  Result.UseShellContextMenus := Settings.UseShellContextMenus;
  Result.LockDragging := Settings.LockDragging;
  Result.StackAnimationEnabled := Settings.StackAnimationEnabled;
  Result.AeroPeekEnabled := Settings.AeroPeekEnabled;
  Result.TaskLivePreviews := Settings.TaskLivePreviews;
  Result.TaskGrouping := Settings.TaskGrouping;
  Result.TaskSystemMenus := Settings.TaskSystemMenus;
  Result.TaskThumbSize := Settings.TaskThumbSize;
  Result.TaskSpot := Settings.TaskSpot;
  Result.ShowHint := Settings.ShowHint;
  Result.Font := Settings.Font;
  Result.Monitor := Settings.Monitor;
  Result.Site := Settings.Site;
  Result.CenterOffsetPercent := Settings.CenterOffsetPercent;
  Result.EdgeOffset := Settings.EdgeOffset;
  Result.DropDistance := Settings.DropDistance;
  Result.OccupyFullMonitor := Settings.OccupyFullMonitor;
  Result.ShowRunningIndicator := Settings.ShowRunningIndicator;
  Result.TaskSameMonitor := Settings.TaskSameMonitor;
end;

end.
