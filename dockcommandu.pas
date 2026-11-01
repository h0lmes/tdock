unit dockcommandu;

{$mode delphi}

interface

uses Windows, SysUtils, declu, itemhostu;

type
  TDockCommandKind = (dcActivate, dcRepaint, dcMenu, dcSaveSettings,
    dcThemeChanged, dcSetVisible, dcGetVisible, dcToggleVisible,
    dcToggleTaskbar, dcDebug);
  TDockCommandRequest = record
    Kind: TDockCommandKind;
    Visible: Boolean;
    PaintFlags: Integer;
  end;
  TApplicationAction = (aaUnknown, aaLaunch,
    aaItemManager,
    aaQuit,
    aaHide,
    aaSay,
    aaAlert,
    aaToggleVisible,
    aaToggleTaskbar,
    aaSettings,
    aaCommandWindow,
    aaCommandWindowNoActivate,
    aaCollection,
    aaTaskManager,
    aaUndo,
    aaAddProgram,
    aaNewDock,
    aaRemoveDock,
    aaAddCommand,
    aaHello,
    aaHelp,
    aaBackup,
    aaRestore,
    aaPaste,
    aaSetVolume,
    aaAutoTray,
    aaTray,
    aaVolume,
    aaNetworks,
    aaBattery,
    aaActionCenter,
    aaStartMenu,
    aaThemes,
    aaTaskSpot,
    aaThemeEditor,
    aaLockDragging,
    aaSite,
    aaLogoff,
    aaShutdown,
    aaReboot,
    aaSuspend,
    aaHibernate,
    aaKill,
    aaDisplayOff,
    aaEmptyBin,
    aaPlay,
    aaSetClipboard,
    aaGuid,
    aaDebug,
    aaTasks,
    aaLogWindow,
    aaSetDisplayMode,
    aaBroadcastMessage,
    aaWindowFromPoint,
    aaFindWindow,
    aaFindWindowEx,
    aaShowWindow,
    aaSendMessage,
    aaSaveWindows,
    aaRestoreWindows,
    aaImportTaskbar,
    aaImportTaskbarLinks);
  TCommandRequest = record
    Command, Parameters, Directory: string;
    ShowCommand: Integer;
    Caller: HWND;
  end;
  TApplicationCommandHandler = procedure(Action: TApplicationAction;
    const Request: TCommandRequest) of object;
  TDockCommandHandler = function(const Request: TDockCommandRequest): Boolean of object;

  TDockCommandController = class
  private
    FApplicationHandler: TApplicationCommandHandler;
    FDockHandler: TDockCommandHandler;
    FDocumentHandler: TDocumentCommand;
  public
    constructor Create(ApplicationHandler: TApplicationCommandHandler;
      DockHandler: TDockCommandHandler);
    procedure Execute(Command, Parameters, Directory: string;
      ShowCommand: Integer = SW_SHOWNORMAL; Caller: HWND = 0);
    procedure ExecuteMulti(Command, Parameters, Directory: string;
      ShowCommand: Integer = SW_SHOWNORMAL; Caller: HWND = 0);
    procedure ExecuteCommandLine(Command: string; ShowCommand: Integer = SW_SHOWNORMAL);
    function Send(const Request: TDockCommandRequest): Boolean;
    function LegacyCommand(Id: TDParam; Value: PtrInt): PtrInt;
    function OpenDocument(Command, Parameters, Directory, Document: string;
      ShowCommand: Integer; Caller: HWND): Boolean;
    property OnDocument: TDocumentCommand read FDocumentHandler write FDocumentHandler;
  end;

function DecodeApplicationAction(const Name: string): TApplicationAction;

implementation

uses toolu;

function DecodeApplicationAction(const Name: string): TApplicationAction;
begin
  if Name = 'itemmgr' then Exit(aaItemManager);
  if Name = 'quit' then Exit(aaQuit);
  if Name = 'hide' then Exit(aaHide);
  if Name = 'say' then Exit(aaSay);
  if Name = 'alert' then Exit(aaAlert);
  if Name = 'visible' then Exit(aaToggleVisible);
  if Name = 'systaskbar' then Exit(aaToggleTaskbar);
  if Name = 'sets' then Exit(aaSettings);
  if Name = 'cmd' then Exit(aaCommandWindow);
  if Name = 'cmdna' then Exit(aaCommandWindowNoActivate);
  if Name = 'collection' then Exit(aaCollection);
  if Name = 'taskmgr' then Exit(aaTaskManager);
  if Name = 'undelete' then Exit(aaUndo);
  if Name = 'program' then Exit(aaAddProgram);
  if Name = 'newdock' then Exit(aaNewDock);
  if Name = 'removedock' then Exit(aaRemoveDock);
  if Name = 'command' then Exit(aaAddCommand);
  if Name = 'hello' then Exit(aaHello);
  if Name = 'help' then Exit(aaHelp);
  if Name = 'backup' then Exit(aaBackup);
  if Name = 'restore' then Exit(aaRestore);
  if Name = 'savewindows' then Exit(aaSaveWindows);
  if Name = 'restorewindows' then Exit(aaRestoreWindows);
  if Name = 'importtaskbar' then Exit(aaImportTaskbar);
  if Name = 'importtaskbarlinks' then Exit(aaImportTaskbarLinks);
  if Name = 'paste' then Exit(aaPaste);
  if Name = 'setvolume' then Exit(aaSetVolume);
  if Name = 'autotray' then Exit(aaAutoTray);
  if Name = 'tray' then Exit(aaTray);
  if Name = 'volume' then Exit(aaVolume);
  if Name = 'networks' then Exit(aaNetworks);
  if Name = 'battery' then Exit(aaBattery);
  if Name = 'actioncenter' then Exit(aaActionCenter);
  if Name = 'startmenu' then Exit(aaStartMenu);
  if Name = 'theme' then Exit(aaThemes);
  if Name = 'taskspot' then Exit(aaTaskSpot);
  if Name = 'themeeditor' then Exit(aaThemeEditor);
  if Name = 'lockdragging' then Exit(aaLockDragging);
  if Name = 'site' then Exit(aaSite);
  if Name = 'logoff' then Exit(aaLogoff);
  if Name = 'shutdown' then Exit(aaShutdown);
  if Name = 'reboot' then Exit(aaReboot);
  if Name = 'suspend' then Exit(aaSuspend);
  if Name = 'hibernate' then Exit(aaHibernate);
  if Name = 'kill' then Exit(aaKill);
  if Name = 'displayoff' then Exit(aaDisplayOff);
  if Name = 'emptybin' then Exit(aaEmptyBin);
  if Name = 'play' then Exit(aaPlay);
  if Name = 'setclipboard' then Exit(aaSetClipboard);
  if Name = 'guid' then Exit(aaGuid);
  if Name = 'debug' then Exit(aaDebug);
  if Name = 'tasks' then Exit(aaTasks);
  if Name = 'logwindow' then Exit(aaLogWindow);
  if Name = 'setdisplaymode' then Exit(aaSetDisplayMode);
  if Name = 'bsm' then Exit(aaBroadcastMessage);
  if Name = 'wfp' then Exit(aaWindowFromPoint);
  if Name = 'findwindow' then Exit(aaFindWindow);
  if Name = 'findwindowex' then Exit(aaFindWindowEx);
  if Name = 'showwindow' then Exit(aaShowWindow);
  if Name = 'sendmessage' then Exit(aaSendMessage);
  Result := aaUnknown;
end;

constructor TDockCommandController.Create(ApplicationHandler: TApplicationCommandHandler;
  DockHandler: TDockCommandHandler);
begin
  inherited Create;
  FApplicationHandler := ApplicationHandler;
  FDockHandler := DockHandler;
end;

procedure TDockCommandController.Execute(Command, Parameters, Directory: string;
  ShowCommand: Integer; Caller: HWND);
var Request: TCommandRequest; Action: TApplicationAction;
begin
  if Command = '' then Exit;
  Request := Default(TCommandRequest);
  Request.Command := Command;
  Request.Parameters := Parameters;
  Request.Directory := Directory;
  Request.ShowCommand := ShowCommand;
  Request.Caller := Caller;
  Action := aaLaunch;
  if Command[1] = '/' then
  begin
    System.Delete(Command, 1, 1);
    if Cut(Command, '.') = 'itemmgr' then
    begin
      Action := aaItemManager;
      Request.Command := CutAfter(Command, '.');
    end
    else
    begin
      Action := DecodeApplicationAction(Command);
      Request.Command := Command;
    end;
  end;
  if (Action <> aaUnknown) and Assigned(FApplicationHandler) then
    FApplicationHandler(Action, Request);
end;

procedure TDockCommandController.ExecuteMulti(Command, Parameters, Directory: string;
  ShowCommand: Integer; Caller: HWND);
var OneCommand, OneParameters, OneDirectory: string;
begin
  try
    while Command <> '' do
    begin
      OneCommand := Trim(Fetch(Command, ';', True));
      OneParameters := Trim(Fetch(Parameters, ';', True));
      OneDirectory := Trim(Fetch(Directory, ';', True));
      Execute(OneCommand, OneParameters, OneDirectory, ShowCommand, Caller);
    end;
  except
    on E: Exception do raise Exception.Create('Command parse/execute error.' + LineEnding +
      'Command=' + OneCommand + LineEnding + 'Params=' + OneParameters +
      LineEnding + 'SYSMSG=' + E.Message);
  end;
end;

procedure TDockCommandController.ExecuteCommandLine(Command: string; ShowCommand: Integer);
var Parameters: string;
begin
  if Command = '' then Exit;
  if Command[1] = '/' then Split(Command, ' ', Command, Parameters)
  else Split_Cmd(Command, Command, Parameters);
  Execute(Command, Parameters, '', ShowCommand);
end;

function TDockCommandController.OpenDocument(Command, Parameters, Directory, Document: string;
  ShowCommand: Integer; Caller: HWND): Boolean;
var OneCommand, OneParameters, OneDirectory: string; Accepted: Boolean;
begin
  Result := False;
  if not Assigned(FDocumentHandler) then Exit;
  // Keep the existing separator rules. Do not parse document text as command syntax.
  while Command <> '' do
  begin
    OneCommand := Trim(Fetch(Command, ';', True));
    OneParameters := Trim(Fetch(Parameters, ';', True));
    OneDirectory := Trim(Fetch(Directory, ';', True));
    if (OneCommand = '') or (OneCommand[1] = '/') then Continue;
    Accepted := FDocumentHandler(OneCommand, OneParameters, OneDirectory, Document, ShowCommand, Caller);
    Result := Result or Accepted;
  end;
end;

function TDockCommandController.Send(const Request: TDockCommandRequest): Boolean;
begin
  Result := False;
  if Assigned(FDockHandler) then Result := FDockHandler(Request);
end;

function TDockCommandController.LegacyCommand(Id: TDParam; Value: PtrInt): PtrInt;
var Request: TDockCommandRequest;
begin
  Result := 0;
  Request := Default(TDockCommandRequest);
  case Id of
    tcActivate: Request.Kind := dcActivate;
    tcRepaintBase: begin Request.Kind := dcRepaint; Request.PaintFlags := Integer(Value); end;
    tcMenu: Request.Kind := dcMenu;
    tcSaveSets: Request.Kind := dcSaveSettings;
    tcThemeChanged: Request.Kind := dcThemeChanged;
    tcSetVisible: begin Request.Kind := dcSetVisible; Request.Visible := Value <> 0; end;
    tcGetVisible: Request.Kind := dcGetVisible;
    tcToggleVisible: Request.Kind := dcToggleVisible;
    tcToggleTaskbar: Request.Kind := dcToggleTaskbar;
    tcDebugInfo: Request.Kind := dcDebug;
    else Exit;
  end;
  if Send(Request) and (Request.Kind = dcGetVisible) then Result := 1;
end;

end.
