program objectactivation_native;
{$mode delphi}
uses Interfaces, Windows, SysUtils, Classes, ActiveX, ComObj, ShlObj, GDIPAPI,
  PIDL, shelltextu, shellactivationu, launchserviceu, setsu, scitemu, scsubitemu,
  stackitemu, customsubitemu, declu, themeu, itemhostu;
const PhotosID = 'Microsoft.Windows.Photos_8wekyb3d8bbwe!App';
  CalculatorID = 'Microsoft.WindowsCalculator_8wekyb3d8bbwe!App';
  PaintID = 'Microsoft.MSPaint_8wekyb3d8bbwe!Microsoft.MSPaint';
  Names: array[0..6] of string = ('shell:AppsFolder', 'shell:Downloads', 'shell:ControlPanelFolder',
    'shell:NetworkPlacesFolder', '::{20D04FE0-3AEA-1069-A2D8-08002B30309D}',
    '::{645FF040-5081-101B-9F08-00AA002F954E}', 'shell:AppsFolder\' + PhotosID);
type
  TNativeChecks = class
    Reports: Integer;
    procedure Report(Message: WideString; Silent: Boolean);
    procedure EnterHost;
    procedure LeaveHost;
  end;
  TObservedStack = class(TStackItem)
    Child: TCustomSubitem;
    function CreateSubitem: TCustomSubitem; override;
  end;
procedure TNativeChecks.Report(Message: WideString; Silent: Boolean);
begin Inc(Reports); WriteLn(UTF8Encode(Message)); end;
procedure TNativeChecks.EnterHost; begin end;
procedure TNativeChecks.LeaveHost; begin end;
function TObservedStack.CreateSubitem: TCustomSubitem;
begin Result := inherited CreateSubitem; Child := Result; end;
procedure Require(Value: Boolean; const Message: string);
begin if not Value then raise Exception.Create(Message); end;
procedure SaveCapture;
var Buffer: array of WideChar; Text: UTF8String; Stream: TFileStream;
begin
  SetLength(Buffer, SHELL_TEXT_LIMIT + 1);
  Require(GetCurrentDirectoryW(Length(Buffer), @Buffer[0]) <> 0, 'Read working directory');
  Text := ShellUTF8(UnicodeString(PWideChar(@Buffer[0]))) + #13#10 + ShellUTF8(UnicodeString(GetCommandLineW));
  Stream := TFileStream.Create(ParamStr(2), fmCreate);
  try if Text <> '' then Stream.WriteBuffer(Text[1], Length(Text)); finally Stream.Free; end;
end;
procedure PumpMessages;
var Message: TMsg; Deadline: QWord;
begin
  Deadline := GetTickCount64 + 1500;
  repeat
    while PeekMessageW(Message, 0, 0, 0, PM_REMOVE) do
    begin TranslateMessage(Message); DispatchMessageW(Message); end;
    Sleep(10);
  until GetTickCount64 >= Deadline;
end;
function FindStatusWindow(Window: HWND; Data: LPARAM): BOOL; stdcall;
var Buffer: array[0..511] of WideChar; Title: UnicodeString;
begin
  Result := True;
  if not IsWindowVisible(Window) then Exit;
  GetWindowTextW(Window, @Buffer[0], Length(Buffer)); Title := PWideChar(@Buffer[0]);
  if Pos('Wi-Fi', Title) > 0 then WriteLn('Visible provider window: ', ShellUTF8(Title));
end;
var Settings: TDSets; Service: TLaunchService; Shell: TShellActivation; Checks: TNativeChecks;
  Owner: HWND; List, Root, Child, Absolute: PItemIDList; Info: TShellTarget;
  Mode, Name, Output, FileApp, SerializedApp: string; Source: UnicodeString; Params: TDItemCreateParams;
  Item: TShortcutItem; Stack: TObservedStack; FixtureTheme: TDTheme;
  Host: TItemHostServices; Desktop, Folder: IShellFolder; Items: IEnumIDList; Fetched: ULONG;
  Bitmap: Pointer; Encoder: TGUID; Found: Boolean; ID: TGUID;
begin
  if ParamStr(1) = '--capture' then begin SaveCapture; Halt(0); end;
  OleCheck(OleInitialize(nil));
  Settings := TDSets.Create('', '', 0); Checks := TNativeChecks.Create;
  Owner := CreateWindowExW(0, 'STATIC', 'WO-13 through WO-17', WS_POPUP, 0, 0, 0, 0, 0, 0, HInstance, nil);
  Service := TLaunchService.Create(Settings, Checks.Report, nil, Owner); Shell := TShellActivation.Create;
  try
    Mode := ParamStr(1);
    if Mode = 'inspect' then
    begin
      for Name in Names do
      begin
        WriteLn('Parsing: ', Name);
        List := PIDL_ParseTarget(ShellUTF16(Name));
        try Info := Shell.Describe(List); WriteLn(Name, ' kind=', Ord(Info.Kind), ' app=', UTF8Encode(Info.AppID));
          if Name = 'shell:AppsFolder\' + PhotosID then Require(Info.AppID = PhotosID, 'Resolve packaged PIDL');
        finally PIDL_Free(List); end;
      end;
      Require(Shell.HasContract(PhotosID, 'test.jpg', False), 'Photos JPG registration');
      Require(not Shell.HasContract(CalculatorID, 'test.jpg', False), 'Calculator rejects JPG');
      Require(Shell.HasContract(CalculatorID, 'calculator:', True), 'Calculator protocol registration');
      WriteLn('Native target and contract checks passed.');
    end
    else if Mode = 'roots' then
    begin
      for Name in Names do
      begin
        if Name = 'shell:AppsFolder\' + PhotosID then Continue;
        Service.Run(Name); WriteLn('Shell request: ', Name);
      end;
      PumpMessages;
      Require(Checks.Reports = 0, 'Standard Shell activation failed');
      WriteLn('Standard Shell requests accepted.');
    end
    else if Mode = 'pidl' then
    begin
      CreateGUID(ID); Output := ExtractFilePath(ParamStr(0)) + GUIDToString(ID) + '.txt';
      List := PIDL_GetFromPath(PChar(ParamStr(0)));
      try
        Source := '--capture ' + QuoteDocumentArgument(ShellUTF16(Output)) + ' ' + WideChar($0416) + WideChar($6587);
        Service.Run(PIDL_ToString(List), ShellUTF8(Source), ExtractFilePath(ParamStr(0)), SW_HIDE);
        WriteLn('Capture: ', Output);
      finally PIDL_Free(List); end;
      Require(Checks.Reports = 0, 'Executable PIDL launch rejected');
    end
    else if Mode = 'document' then
    begin
      FileApp := ParamStr(2);
      if FileApp = '' then FileApp := PaintID;
      Source := ShellUTF16(ExtractFilePath(ParamStr(0))) + 'WO13-17-' + WideChar($0416) + WideChar($6587) + '.jpg';
      Encoder := StringToGUID('{557CF401-1A04-11D3-9A73-0000F81EF32E}'); Bitmap := nil;
      Require(GdipCreateBitmapFromScan0(160, 100, 0, PixelFormat32bppPARGB, nil, Bitmap) = Ok, 'Create JPG');
      try Require(GdipSaveImageToFile(Bitmap, PWideChar(Source), @Encoder, nil) = Ok, 'Save JPG'); finally GdipDisposeImage(Bitmap); end;
      Host := Default(TItemHostServices); Host.OnEnter := Checks.EnterHost; Host.OnLeave := Checks.LeaveHost;
      Host.OnOpenDocument := Service.OpenDocument; BindItemHost(Owner, Host);
      Params := Default(TDItemCreateParams); Params.ItemSize := 32; Params.BigItemSize := 32;
      Params.Parameter := TShortcutItem.Make('File contract', FileApp);
      Item := TShortcutItem.Create(Owner, Params);
      try Require(Item.DropFile(Item.Handle, Point(0, 0), ShellUTF8(Source)), 'Dock document drop'); finally Item.Free; end;
      FixtureTheme := TDTheme(TDTheme.NewInstance); theme := FixtureTheme;
      Params.Parameter := TStackItem.Make('Native stack');
      Stack := TObservedStack.Create(Owner, Params);
      try
        List := PIDL_ParseTarget(ShellUTF16('shell:AppsFolder\' + FileApp));
        try SerializedApp := PIDL_ToString(List); finally PIDL_Free(List); end;
        Require(Stack.AddSubitem(TShortcutSubitem.Make('File contract PIDL', SerializedApp)), 'Create stack target');
        Require(Stack.DropFile(Stack.Child.Handle, Point(0, 0), ShellUTF8(Source)), 'Stack document drop');
      finally Stack.Free; theme := nil; FixtureTheme.Free; end;
      Require(Service.OpenDocument(CalculatorID, '', '', 'calculator:', 1, Owner), 'Calculator protocol');
      Require(Checks.Reports = 0, 'Unexpected activation failure');
      Require(not Service.OpenDocument(CalculatorID, '', '', ShellUTF8(Source), 1, Owner), 'Calculator must reject JPG');
      Require(Checks.Reports = 1, 'Unsupported contract must report once');
      WriteLn('Native dock, stack, protocol, and rejection checks passed.');
      WriteLn('Document: ', ShellUTF8(Source));
    end
    else if Mode = 'provider' then
    begin
      Found := False; Root := PIDL_ParseTarget('shell:ConnectionsFolder');
      try
        OleCheck(SHGetDesktopFolder(Desktop));
        OleCheck(Desktop.BindToObject(Root, nil, IID_IShellFolder, Folder));
        OleCheck(Folder.EnumObjects(Owner, SHCONTF_FOLDERS or SHCONTF_NONFOLDERS, Items));
        repeat
          Fetched := 0; Child := nil;
          if (Items.Next(1, Child, Fetched) <> S_OK) or (Fetched = 0) then Break;
          try
            Absolute := PIDL_GetAbsolute(Root, Child);
            try
              Name := PIDL_GetDisplayName3(Absolute);
              if Name = 'Wi-Fi' then begin Service.Run(PIDL_ToString(Absolute)); Found := True; Break; end;
            finally PIDL_Free(Absolute); end;
          finally PIDL_Free(Child); end;
        until False;
      finally PIDL_Free(Root); end;
      Require(Found, 'Wi-Fi provider fixture unavailable');
      Require(Checks.Reports = 0, 'Provider status invocation failed');
      PumpMessages;
      EnumWindows(@FindStatusWindow, 0);
      WriteLn('Native Wi-Fi status request accepted.');
    end else raise Exception.Create('Use inspect, roots, pidl, document, or provider.');
  except on E: Exception do begin WriteLn(E.Message); ExitCode := 1; end; end;
  UnbindItemHost(Owner); Shell.Free; Service.Free; Checks.Free; Settings.Free; DestroyWindow(Owner); OleUninitialize;
end.
