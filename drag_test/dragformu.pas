unit dragformu;
{$mode delphi}
{$codepage utf8}

interface

uses Windows, Classes, SysUtils, Forms, Controls, StdCtrls, ComCtrls, ExtCtrls,
  Dialogs, Contnrs, ActiveX, ShlObj, Graphics, dragdatau, dragsamplesu;

type
  TDragTestForm = class(TForm)
  private
    FRoot: UnicodeString;
    FSamples: TObjectList;
    FTree: TTreeView;
    FProfile: TComboBox;
    FPayload, FContents, FExpected, FLogMemo: TMemo;
    FProvider, FFailure: TCheckBox;
    FDragArea, FInspect: TPanel;
    FLoadApps, FBrowse, FShellBrowse: TButton;
    FTitle, FSubtitle, FTreeLabel, FFormatLabel, FPayloadLabel, FContentsLabel,
      FExpectedLabel, FLogLabel: TLabel;
    FStatus: TStatusBar;
    FTimer: TTimer;
    FLogObject: TDragLog;
    FLog: IDragLog;
    FInspector: IDropTarget;
    FChosenShell: IDataObject;
    FSettingPayload: Boolean;
    FMouseStart: TPoint;
    FArmed, FDragging: Boolean;
    FLogCount: QWord;
    procedure LayoutControls(Sender: TObject);
    procedure FillTree;
    procedure ChooseSample(Sender: TObject; Node: TTreeNode);
    procedure LoadAppsClick(Sender: TObject);
    procedure BrowseClick(Sender: TObject);
    procedure ShellBrowseClick(Sender: TObject);
    procedure PayloadChange(Sender: TObject);
    procedure StartMouse(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure MoveMouse(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure EndMouse(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure RefreshLog(Sender: TObject);
    function LabelControl(const Text: string): TLabel;
    function MemoControl(ReadOnlyValue: Boolean): TMemo;
  public
    property Log: IDragLog read FLog;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

implementation

function ShellParsingName(ID: PItemIDList; Kind: DWORD; out Name: PWideChar): HRESULT; stdcall;
  external 'shell32.dll' name 'SHGetNameFromIDList';

function TDragTestForm.LabelControl(const Text: string): TLabel;
begin
  Result := TLabel.Create(Self); Result.Parent := Self; Result.Caption := Text;
end;

function TDragTestForm.MemoControl(ReadOnlyValue: Boolean): TMemo;
begin
  Result := TMemo.Create(Self); Result.Parent := Self; Result.ReadOnly := ReadOnlyValue;
  Result.ScrollBars := ssAutoBoth; Result.WordWrap := False;
end;

constructor TDragTestForm.Create(AOwner: TComponent);
var Profile: TDragProfile;
begin
  inherited CreateNew(AOwner);
  Scaled := False;
  Caption := 'tdock Drag Test';
  Position := poScreenCenter; Width := 1120; Height := 820;
  Constraints.MinWidth := 960; Constraints.MinHeight := 710;
  Font.Name := 'Segoe UI'; Font.Size := 10;
  FRoot := UTF8Decode(ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))));
  FLogObject := TDragLog.Create(UTF8Encode(FRoot + '\source.log'));
  FLog := FLogObject;
  FLog.Add('SESSION START; Windows ACP=' + IntToStr(GetACP));
  FSamples := TObjectList.Create(True);
  CreateSamples(FRoot, FSamples);
  FLog.Add('Sample fixtures and presets ready');
  FTitle := LabelControl('Windows drag-source test'); FTitle.Font.Size := 18; FTitle.Font.Style := [fsBold];
  FSubtitle := LabelControl('Choose a sample and format. Drag the blue area onto tdock or the local inspector.');
  FTreeLabel := LabelControl('Object samples');
  FFormatLabel := LabelControl('Format');
  FPayloadLabel := LabelControl('Targets or text (one path, target, or virtual filename per line)');
  FContentsLabel := LabelControl('Virtual file contents (each file also contains its item number)');
  FExpectedLabel := LabelControl('Expected result / sample notes');
  FLogLabel := LabelControl('Transfer log (also saved in source.log)');
  FTree := TTreeView.Create(Self); FTree.Parent := Self; FTree.ReadOnly := True;
  FTree.HideSelection := False; FTree.OnChange := ChooseSample;
  FProfile := TComboBox.Create(Self); FProfile.Parent := Self; FProfile.Style := csDropDownList;
  for Profile := Low(TDragProfile) to High(TDragProfile) do FProfile.Items.Add(ProfileNames[Profile]);
  FProfile.ItemIndex := 0;
  FPayload := MemoControl(False); FContents := MemoControl(False); FExpected := MemoControl(True);
  FPayload.OnChange := PayloadChange;
  FExpected.WordWrap := True; FExpected.ScrollBars := ssAutoVertical;
  FContents.Text := 'tdock virtual-file sample. Close this source, restart tdock, then verify this content.';
  FLogMemo := MemoControl(True); FLogMemo.Font.Name := 'Consolas'; FLogMemo.Font.Size := 9;
  FLoadApps := TButton.Create(Self); FLoadApps.Parent := Self; FLoadApps.Caption := 'Load installed applications';
  FLoadApps.OnClick := LoadAppsClick;
  FShellBrowse := TButton.Create(Self); FShellBrowse.Parent := Self;
  FShellBrowse.Caption := 'Browse Shell objects...'; FShellBrowse.OnClick := ShellBrowseClick;
  FBrowse := TButton.Create(Self); FBrowse.Parent := Self; FBrowse.Caption := 'Browse files...'; FBrowse.OnClick := BrowseClick;
  FProvider := TCheckBox.Create(Self); FProvider.Parent := Self; FProvider.Caption := 'Provider-owned synthetic HGLOBAL';
  FFailure := TCheckBox.Create(Self); FFailure.Parent := Self; FFailure.Caption := 'Force GetData failure';
  FDragArea := TPanel.Create(Self); FDragArea.Parent := Self;
  FDragArea.Caption := 'Hold here, then drag to tdock'; FDragArea.Color := $00B45B20;
  FDragArea.Font.Color := clWhite; FDragArea.Font.Size := 13; FDragArea.Font.Style := [fsBold];
  FDragArea.ParentBackground := False; FDragArea.Cursor := crHandPoint;
  FDragArea.OnMouseDown := StartMouse; FDragArea.OnMouseMove := MoveMouse; FDragArea.OnMouseUp := EndMouse;
  FInspect := TPanel.Create(Self); FInspect.Parent := Self; FInspect.Caption := 'Drop here to inspect formats';
  FInspect.Color := $00E8F2E8; FInspect.ParentBackground := False;
  FStatus := TStatusBar.Create(Self); FStatus.Parent := Self; FStatus.SimplePanel := True;
  FStatus.SimpleText := 'Ready. Use normal elevation for both applications.';
  FTimer := TTimer.Create(Self); FTimer.Interval := 150; FTimer.OnTimer := RefreshLog;
  OnResize := LayoutControls;
  FLog.Add('Controls ready');
  FillTree; LayoutControls(nil);
  FLog.Add('Sample tree ready');
  FInspector := TInspectTarget.Create(FLog);
  CheckHR(RegisterDragDrop(FInspect.Handle, FInspector), 'Register local drop inspector');
  FLog.Add('Inspector registered; window ready');
end;

destructor TDragTestForm.Destroy;
begin
  if Assigned(FTimer) then FTimer.Enabled := False;
  if FInspector <> nil then RevokeDragDrop(FInspect.Handle);
  FInspector := nil;
  FChosenShell := nil;
  FSamples.Free;
  FLog := nil;
  inherited Destroy;
end;

procedure TDragTestForm.LayoutControls(Sender: TObject);
var X, W, H: Integer;
begin
  if FStatus = nil then Exit;
  X := 300; W := ClientWidth - X - 18; H := ClientHeight - FStatus.Height;
  FTitle.SetBounds(18, 12, ClientWidth - 36, 30);
  FSubtitle.SetBounds(18, 46, ClientWidth - 36, 22);
  FTreeLabel.SetBounds(18, 80, 260, 22);
  FLoadApps.SetBounds(18, 106, 264, 30);
  FShellBrowse.SetBounds(18, 142, 264, 30);
  FTree.SetBounds(18, 181, 264, H - 250);
  FInspect.SetBounds(18, H - 58, 264, 42);
  FFormatLabel.SetBounds(X, 83, 58, 24);
  FProfile.SetBounds(X + 62, 78, W - 180, 28); FBrowse.SetBounds(X + W - 110, 78, 110, 30);
  FPayloadLabel.SetBounds(X, 118, W, 22); FPayload.SetBounds(X, 142, W, 96);
  FContentsLabel.SetBounds(X, 248, W, 22); FContents.SetBounds(X, 272, W, 54);
  FExpectedLabel.SetBounds(X, 336, W, 22); FExpected.SetBounds(X, 360, W, 58);
  FProvider.SetBounds(X, 428, 300, 25); FFailure.SetBounds(X + 308, 428, W - 308, 25);
  FDragArea.SetBounds(X, 465, W, 52);
  FLogLabel.SetBounds(X, 529, W, 22); FLogMemo.SetBounds(X, 553, W, H - 569);
end;

procedure TDragTestForm.FillTree;
var I: Integer; Group, Node: TTreeNode; Sample: TDragSample;
begin
  FTree.Items.BeginUpdate;
  try
    FTree.Items.Clear; Group := nil;
    for I := 0 to FSamples.Count - 1 do
    begin
      Sample := TDragSample(FSamples[I]);
      if (Group = nil) or (Group.Text <> Sample.Group) then Group := FTree.Items.Add(nil, Sample.Group);
      Node := FTree.Items.AddChild(Group, Sample.Name); Node.Data := Sample;
    end;
    if FTree.Items.Count > 1 then
    begin FTree.Items[0].Expand(False); FTree.Selected := FTree.Items[1]; end;
  finally FTree.Items.EndUpdate; end;
end;

procedure TDragTestForm.ChooseSample(Sender: TObject; Node: TTreeNode);
var Sample: TDragSample;
begin
  if (Node = nil) or (Node.Data = nil) then Exit;
  FChosenShell := nil;
  Sample := TDragSample(Node.Data);
  FProfile.ItemIndex := Ord(Sample.Profile); FPayload.Text := Sample.Payload;
  FExpected.Text := Sample.Expected;
end;

procedure TDragTestForm.LoadAppsClick(Sender: TObject);
var Before: Integer;
begin
  Before := FSamples.Count;
  try
    LoadInstalledApps(FSamples); FillTree;
    if FSamples.Count = Before then
    begin
      FLog.Add('Installed application catalog unavailable in this account');
      FStatus.SimpleText := 'No AppsFolder entries are available in this account. Use Browse Shell objects or enter a parsing name.';
      Exit;
    end;
    FLoadApps.Enabled := False; FLoadApps.Caption := 'Applications loaded';
    FLog.Add('Loaded ' + IntToStr(FSamples.Count - Before) + ' real AppsFolder entries');
    FStatus.SimpleText := 'Installed applications are at the end of the sample tree.';
  except on E: Exception do begin FLog.Add(E.Message); ShowMessage(E.Message); end; end;
end;

procedure TDragTestForm.BrowseClick(Sender: TObject);
var Dialog: TOpenDialog;
begin
  Dialog := TOpenDialog.Create(Self);
  try
    Dialog.Options := [ofFileMustExist, ofAllowMultiSelect, ofEnableSizing];
    if Dialog.Execute then FPayload.Lines.Assign(Dialog.Files);
  finally Dialog.Free; end;
end;

procedure TDragTestForm.PayloadChange(Sender: TObject);
begin
  if not FSettingPayload then FChosenShell := nil;
end;

procedure TDragTestForm.ShellBrowseClick(Sender: TObject);
var Info: TBrowseInfoW; ID: PItemIDList; Name: PWideChar;
begin
  FillChar(Info, SizeOf(Info), 0);
  Info.hwndOwner := Handle;
  Info.lpszTitle := 'Choose a file, folder, printer, or other Shell object';
  Info.ulFlags := BIF_NEWDIALOGSTYLE or BIF_BROWSEINCLUDEFILES;
  ID := SHBrowseForFolderW(Info);
  if ID = nil then Exit;
  Name := nil;
  try
    try
    FChosenShell := ShellDataFromIDList(ID);
    FSettingPayload := True;
    try
      if ShellParsingName(ID, $80028000, Name) = S_OK then FPayload.Text := UTF8Encode(UnicodeString(Name))
      else FPayload.Text := '<selected Shell object>';
    finally FSettingPayload := False; end;
    FProfile.ItemIndex := Ord(dpNativeShell);
    FExpected.Text := 'Native data from the selected Shell object. Its provider controls the offered formats and activation.';
    except on E: Exception do begin FLog.Add(E.Message); ShowMessage(E.Message); end; end;
  finally CoTaskMemFree(Name); CoTaskMemFree(ID); end;
end;

procedure TDragTestForm.StartMouse(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then begin FMouseStart := Point(X, Y); FArmed := True; end;
end;
procedure TDragTestForm.EndMouse(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin FArmed := False; end;
procedure TDragTestForm.MoveMouse(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var Options: TDragOptions; Data: IDataObject; Source: IDropSource; Effect: DWORD; HR: HRESULT;
begin
  if not FArmed or FDragging or not (ssLeft in Shift) or
    ((Abs(X - FMouseStart.X) < 5) and (Abs(Y - FMouseStart.Y) < 5)) then Exit;
  FArmed := False; FDragging := True;
  Windows.ReleaseCapture;
  FProfile.Enabled := False; FBrowse.Enabled := False; FLoadApps.Enabled := False; FShellBrowse.Enabled := False;
  try
    try
      Options := Default(TDragOptions);
      Options.Profile := TDragProfile(FProfile.ItemIndex); Options.Payload := UTF8Decode(TrimRight(FPayload.Text));
      Options.Contents := UTF8Decode(FContents.Text); Options.Root := FRoot;
      Options.ProviderOwned := FProvider.Checked; Options.FailData := FFailure.Checked;
      Options.ShellData := FChosenShell;
      Data := BuildDragObject(Options, FLog);
      FLog.Add('DRAG ' + ProfileNames[Options.Profile]); ListOfferedFormats(Data, FLog);
      Source := TDragSource.Create; Effect := DROPEFFECT_NONE;
      HR := ActiveX.DoDragDrop(Data, Source, DROPEFFECT_COPY or DROPEFFECT_LINK, @Effect);
      FLog.Add('DRAG END result=0x' + IntToHex(LongWord(HR), 8) + ' effect=' + IntToStr(Effect));
      if HR = DRAGDROP_S_CANCEL then FStatus.SimpleText := 'Drag canceled.'
      else if Effect = DROPEFFECT_NONE then FStatus.SimpleText := 'The target reported no accepted effect.'
      else FStatus.SimpleText := 'Target effect=' + IntToStr(Effect) + '. Verify the created item and its contents.';
    except on E: Exception do begin FLog.Add('ERROR ' + E.Message); FStatus.SimpleText := E.Message; end; end;
  finally
    Data := nil; Source := nil; FDragging := False;
    FProfile.Enabled := True; FBrowse.Enabled := True; FShellBrowse.Enabled := True;
    if FLoadApps.Caption <> 'Applications loaded' then FLoadApps.Enabled := True;
    RefreshLog(nil);
  end;
end;

procedure TDragTestForm.RefreshLog(Sender: TObject);
begin
  if FLogCount = FLogObject.Revision then Exit;
  FLogMemo.Lines.Assign(FLogObject.Lines); FLogCount := FLogObject.Revision;
  FLogMemo.SelStart := Length(FLogMemo.Text);
end;

end.
