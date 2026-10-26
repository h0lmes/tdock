unit launchserviceu;

{$mode delphi}

interface

uses Windows, ShellAPI, setsu, launchresultu, shellactivationu;

type
  TLaunchReport = procedure(Message: WideString; Silent: Boolean) of object;
  TLaunchService = class
  private
    FSettings: TDSets;
    FClosing: Boolean;
    FOnReport: TLaunchReport;
    FReports: ILaunchResultQueue;
    FShell: TShellActivation;
    FOwnerWindow: HWND;
    procedure Report(Message: WideString);
  protected
    function InvokeShell(var Info: TShellExecuteInfoW): Boolean; virtual;
    procedure ActivatePackagedApp(const AppID: UnicodeString); virtual;
    procedure ActivatePackagedAppWithArguments(const AppID, Arguments: UnicodeString); virtual;
    procedure ExecuteShellIDList(var Info: TShellExecuteInfoW); virtual;
    procedure ExecuteShellTarget(const Target, Parameters, Directory: WideString;
      ShowCommand: Integer); virtual;
    function StartShellWorker(const Target, Parameters, Directory: WideString;
      ShowCommand: Integer): Boolean; virtual;
  public
    constructor Create(Settings: TDSets; OnReport: TLaunchReport;
      Shell: TShellActivation = nil; OwnerWindow: HWND = 0);
    destructor Destroy; override;
    procedure Close;
    procedure DispatchPending;
    procedure Run(exename: string; params: string = ''; dir: string = '';
      showcmd: integer = SW_SHOWNORMAL);
    function OpenDocument(Target, Parameters, Directory, Document: string;
      ShowCommand: Integer; Caller: HWND): Boolean;
  end;

implementation

uses SysUtils, ShlObj, PIDL, toolu, processhlp, runthreadu, shelltextu;

constructor TLaunchService.Create(Settings: TDSets; OnReport: TLaunchReport;
  Shell: TShellActivation; OwnerWindow: HWND);
begin
  inherited Create;
  FSettings := Settings;
  FOnReport := OnReport;
  FReports := NewLaunchResultQueue;
  FShell := Shell;
  if FShell = nil then FShell := TShellActivation.Create;
  FOwnerWindow := OwnerWindow;
end;
destructor TLaunchService.Destroy;
begin Close; FReports := nil; FShell.Free; inherited Destroy; end;
procedure TLaunchService.Close;
begin
  FClosing := True;
  FOnReport := nil;
  if FReports <> nil then FReports.Close;
end;
procedure TLaunchService.DispatchPending;
var Value: TLaunchResult; Reports: ILaunchResultQueue;
begin
  Reports := FReports;
  while not FClosing and (Reports <> nil) and Reports.TryTake(Value) do
    Report(WideString(LaunchResultMessage(Value)));
end;
procedure TLaunchService.Report(Message: WideString);
begin if Assigned(FOnReport) then FOnReport(Message, False); end;

procedure TLaunchService.ActivatePackagedApp(const AppID: UnicodeString);
var Status: HRESULT;
begin
  if ProcessHelper = nil then Status := E_NOINTERFACE
  else Status := ProcessHelper.RunImmersiveApp(PWideChar(AppID));
  if Status < 0 then raise ELaunchFailure.Create(LaunchFailure(lsActivation, AppID, 0, Status));
end;

procedure TLaunchService.ExecuteShellIDList(var Info: TShellExecuteInfoW);
var Executed: Boolean; Error: DWORD;
begin
  SetLastError(0);
  Executed := InvokeShell(Info);
  Error := GetLastError;
  if not Executed then
    raise ELaunchFailure.Create(LaunchFailure(lsShell, '', Error, 0, PtrInt(Info.hInstApp)));
end;

procedure TLaunchService.ActivatePackagedAppWithArguments(const AppID, Arguments: UnicodeString);
var Status: HRESULT;
begin
  if Arguments = '' then begin ActivatePackagedApp(AppID); Exit; end;
  if ProcessHelper = nil then Status := E_NOINTERFACE
  else Status := ProcessHelper.RunImmersiveApp(PWideChar(AppID), PWideChar(Arguments));
  if Failed(Status) then raise ELaunchFailure.Create(LaunchFailure(lsActivation, AppID, 0, Status));
end;

function TLaunchService.InvokeShell(var Info: TShellExecuteInfoW): Boolean;
begin Result := ShellExecuteExW(@Info); end;

procedure TLaunchService.ExecuteShellTarget(const Target, Parameters, Directory: WideString;
  ShowCommand: Integer);
var Info: TShellExecuteInfoW;
begin
  Info := Default(TShellExecuteInfoW);
  Info.cbSize := SizeOf(Info);
  Info.fMask := SEE_MASK_FLAG_NO_UI;
  Info.lpFile := PWideChar(Target);
  Info.lpParameters := PWideChar(Parameters);
  Info.lpDirectory := PWideChar(Directory);
  Info.nShow := ShowCommand;
  ExecuteShellIDList(Info);
end;

function TLaunchService.StartShellWorker(const Target, Parameters, Directory: WideString;
  ShowCommand: Integer): Boolean;
begin Result := StartDetachedRun(Target, Parameters, Directory, ShowCommand, FReports); end;

procedure TLaunchService.Run(exename: string; params: string = ''; dir: string = ''; showcmd: integer = sw_shownormal);
var
  wexename, wparams, wdir: WideString;
  shell: string;
  sei: TShellExecuteInfoW;
  aPIDL: PItemIDList;
  AppID: UnicodeString;
  Route: UnicodeString;
  Failure: TLaunchResult;
  Stage: TLaunchStage;
  TargetInfo: TShellTarget;
  Status: HRESULT;
begin
  if FClosing then Exit;
  Route := 'Direct';
  Stage := lsPreparation;
  try
    wexename := ShellUTF16(exename);
    exename := toolu.UnzipPath(exename);
    wexename := ShellUTF16(exename);
    CheckShellText(wexename);
    if params <> '' then params := toolu.UnzipPath(params);
    if dir <> '' then dir := toolu.UnzipPath(dir);
    wparams := ShellUTF16(params); wdir := ShellUTF16(dir);
    CheckShellText(wparams); CheckShellText(wdir);
    if Pos(':', exename) > 2 then Route := 'URI';
    if TryNormalizeAppTarget(wexename, AppID) then
    begin
      Route := 'Packaged application';
      Stage := lsActivation;
      if wdir <> '' then raise EConvertError.Create('Packaged activation does not support a working directory');
      ActivatePackagedAppWithArguments(AppID, wparams);
      exit;
    end;

    if ShellDirectoryExists(ShellUTF16(exename)) then
    begin
      shell := toolu.UnzipPath(FSettings.container.Shell);
      if FSettings.container.useShell and fileexists(shell) then
      begin
        params := '"' + exename + '"';
        exename := shell;
        dir := '';
      end;
    end;

    aPIDL := nil;
    aPIDL := PIDL_ParseTarget(ShellUTF16(exename));
    if assigned(aPIDL) then
    begin
      Route := 'PIDL';
      Stage := lsShell;
      try
        TargetInfo := FShell.Describe(aPIDL);
        if (TargetInfo.Kind = skPackaged) and (wparams <> '') then
        begin
          if wdir <> '' then raise EConvertError.Create('Packaged activation does not support a working directory');
          Stage := lsActivation;
          ActivatePackagedAppWithArguments(TargetInfo.AppID, wparams);
          Exit;
        end;
        if (TargetInfo.Kind <> skExecutable) and ((wparams <> '') or (wdir <> '')) then
          raise EConvertError.Create('This Shell target does not support arguments or a working directory');
        if TargetInfo.Kind = skNamespace then
        begin
          Status := FShell.InvokeNamespace(aPIDL, FOwnerWindow, showcmd);
          if Failed(Status) then
          begin
            Failure := LaunchFailure(lsShell, wexename, 0, Status);
            if DWORD(Status) = $80070483 then Failure.Detail := 'No supported open action';
            raise ELaunchFailure.Create(Failure);
          end;
        end else begin
          sei := Default(TShellExecuteInfoW);
          sei.cbSize := sizeof(sei);
          sei.lpIDList := aPIDL;
          sei.fMask := SEE_MASK_IDLIST or SEE_MASK_FLAG_NO_UI;
          sei.Wnd := FOwnerWindow;
          sei.nShow := showcmd;
          if (TargetInfo.Kind = skFolder) and (TargetInfo.Path = '') then sei.lpVerb := 'open';
          if TargetInfo.Kind = skExecutable then
          begin
            if wparams <> '' then sei.lpParameters := PWideChar(wparams);
            if wdir <> '' then sei.lpDirectory := PWideChar(wdir);
          end;
          ExecuteShellIDList(sei);
        end;
      finally PIDL_Free(aPIDL); end;
      exit;
    end;

    wexename := ShellUTF16(exename);
    wparams := ShellUTF16(params);
    wdir := ShellUTF16(dir);
    CheckShellText(wexename); CheckShellText(wparams); CheckShellText(wdir);

    if FSettings.container.RunInThread then
    begin
      if Route = 'URI' then Route := 'Threaded URI' else Route := 'Threaded';
      Stage := lsThreadCreation;
      if not StartShellWorker(wexename, wparams, wdir, showcmd) then
        raise ELaunchFailure.Create(LaunchFailure(lsThreadCreation, wexename, GetLastError));
    end else begin
      Stage := lsShell;
      ExecuteShellTarget(wexename, wparams, wdir, showcmd);
    end;
  except
    on E: Exception do
    begin
      Failure := LaunchException(Stage, wexename, E);
      Failure.Route := Route;
      Report(WideString(LaunchResultMessage(Failure)));
    end;
  end;
end;

function TLaunchService.OpenDocument(Target, Parameters, Directory, Document: string;
  ShowCommand: Integer; Caller: HWND): Boolean;
var Name, Args, WorkDir, Source, AppID: UnicodeString; List: PItemIDList;
  Info: TShellTarget; Protocol: Boolean; Status: HRESULT; Failure: TLaunchResult;
  ExecuteInfo: TShellExecuteInfoW;
begin
  Result := False;
  if FClosing then Exit;
  Name := ''; List := nil;
  try
    try
      Name := ShellUTF16(UnzipPath(Target));
      Args := ShellUTF16(UnzipPath(Parameters));
      WorkDir := ShellUTF16(UnzipPath(Directory));
      Source := ShellUTF16(Document);
      CheckShellText(Name); CheckShellText(Args); CheckShellText(WorkDir); CheckShellText(Source);
      if Source = '' then raise EConvertError.Create('Document request is empty');
      Protocol := not ShellFileExists(Source) and DocumentIsURI(Source);
      if not Protocol and not ShellFileExists(Source) then
        raise EConvertError.Create('Document file does not exist');
      AppID := '';
      if not TryNormalizeAppTarget(Name, AppID) then
      begin
        List := PIDL_ParseTarget(Name);
        if List <> nil then
        begin
          Info := FShell.Describe(List);
          if Info.Kind = skPackaged then AppID := Info.AppID
          else if Info.Kind <> skExecutable then
            raise EConvertError.Create('This Shell target cannot accept documents');
        end
        else if not FShell.Executable(Name) then
          raise EConvertError.Create('This target cannot accept documents');
      end;
      if AppID <> '' then
      begin
        if (Args <> '') or (WorkDir <> '') then
          raise EConvertError.Create('File and protocol activation cannot include launch arguments or a working directory');
        if not FShell.HasContract(AppID, Source, Protocol) then
          raise EConvertError.Create('The selected application has no registered contract for this document');
        Status := FShell.ActivateDocument(AppID, Source, Protocol);
        if Failed(Status) then raise ELaunchFailure.Create(LaunchFailure(lsActivation, Name, 0, Status));
      end else begin
        if Args <> '' then Args := Args + ' ';
        Args := Args + QuoteDocumentArgument(Source);
        CheckShellText(Args);
        if List <> nil then
        begin
          ExecuteInfo := Default(TShellExecuteInfoW);
          ExecuteInfo.cbSize := SizeOf(ExecuteInfo);
          ExecuteInfo.fMask := SEE_MASK_IDLIST or SEE_MASK_FLAG_NO_UI;
          ExecuteInfo.lpIDList := List;
          ExecuteInfo.lpParameters := PWideChar(Args);
          if WorkDir <> '' then ExecuteInfo.lpDirectory := PWideChar(WorkDir);
          if Caller = 0 then Caller := FOwnerWindow;
          ExecuteInfo.Wnd := Caller;
          ExecuteInfo.nShow := ShowCommand;
          ExecuteShellIDList(ExecuteInfo);
        end else ExecuteShellTarget(Name, Args, WorkDir, ShowCommand);
      end;
      Result := True;
    finally PIDL_Free(List); end;
  except
    on E: Exception do
    begin
      Failure := LaunchException(lsActivation, Name, E);
      Failure.Route := 'Document request';
      Report(WideString(LaunchResultMessage(Failure)));
    end;
  end;
end;

end.
