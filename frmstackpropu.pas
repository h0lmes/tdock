unit frmstackpropu;

{$mode delphi}

interface

uses Windows, SysUtils, Classes, Math, Graphics, Controls, Forms,
  DefaultTranslator, Dialogs, StdCtrls, ExtCtrls, ComCtrls, Spin, LCLType,
  GDIPAPI, gfx, iconserviceu, stackitemu, themeu, itemmodelu, itemserializationu;

type
  TStackDraftIcon = record
    Image: Pointer;
    Width, Height: UINT;
    ColorData: integer;
  end;

  TfrmStackProp = class(TForm)
    btnOK, btnApply, btnCancel: TButton;
    btnBrowseImage1, btnClearImage, btnDefaultColor: TButton;
    bbAddIcon, bbDelIcon, bbEditIcon, bbIconUp, bbIconDown: TButton;
    pages: TPageControl;
    tsGeneral, tsItems, tsAppearance, tsAnimation: TTabSheet;
    pnlBody, pnlButtons, pnlPreview: TPanel;
    appearanceScroll: TScrollBox;
    edCaption, edImage: TEdit;
    cboLocation, cboOrder, cboMode, cboPreview: TComboBox;
    chbBackground: TCheckBox;
    list: TListBox;
    iPic: TPaintBox;
    lblCaption, lblLocation, lblLocationHelp, lblError: TLabel;
    lblOrder, lblItemsHelp, lblImage, lblPreview, lblPreviewTitle: TLabel;
    lblHue, lblSat, lblBr, lblCont: TLabel;
    lblStyle, lblOffset, lblDistanceUnit, lblDistort, lblAnimationSpeed: TLabel;
    lblSlow, lblFast: TLabel;
    tbOffset, tbDistort, tbAnimationSpeed, tbHue, tbSat, tbBr, tbCont: TTrackBar;
    numDistance: TFloatSpinEdit;
    numDistort, numSpeed, numHue, numSat, numBr, numCont: TSpinEdit;
    procedure FormCreate(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure Changed(Sender: TObject);
    procedure ImageChanged(Sender: TObject);
    procedure LocationChanged(Sender: TObject);
    procedure OrderChanged(Sender: TObject);
    procedure ModeChanged(Sender: TObject);
    procedure SliderChanged(Sender: TObject);
    procedure NumberChanged(Sender: TObject);
    procedure btnOKClick(Sender: TObject);
    procedure btnApplyClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
    procedure btnBrowseImage1Click(Sender: TObject);
    procedure btnClearImageClick(Sender: TObject);
    procedure btnDefaultColorClick(Sender: TObject);
    procedure bbAddIconClick(Sender: TObject);
    procedure bbDelIconClick(Sender: TObject);
    procedure bbEditIconClick(Sender: TObject);
    procedure bbIconUpClick(Sender: TObject);
    procedure bbIconDownClick(Sender: TObject);
    procedure listDblClick(Sender: TObject);
    procedure SelectionChanged(Sender: TObject; User: boolean);
    procedure ListDrawItem(Control: TWinControl; Index: integer;
      Rect: Windows.TRect; State: TOwnerDrawState);
    procedure PreviewPaint(Sender: TObject);
  private
    FItemId: TItemId;
    FLoading: boolean;
    FChildren, FCustomChildren: TStringList;
    FSource, FBaseline: string;
    FImage: Pointer;
    FIW, FIH: UINT;
    FIcons: array of TStackDraftIcon;
    function AcquireItem(out Item: TStackItem; out Id: TItemId): boolean;
    function CanEditItems: boolean;
    procedure ItemUnavailable;
    procedure LoadItem(Item: TStackItem);
    function CaptureControls: TStackDtoV1;
    function DraftText: string;
    function ApplyDraft: boolean;
    procedure UpdateActions;
    procedure UpdateLayoutLabel;
    procedure RebuildItems(Selected: integer);
    procedure SortDraft;
    procedure ClearIcons;
    procedure LoadImagePreview;
    procedure PaintImage(Graphics, Image: Pointer; ImageWidth, ImageHeight: UINT;
      const Bounds: Windows.TRect; ColorData: integer);
  protected
    function SetData(wnd: HWND): boolean;
    function EditChild(var Text: string): boolean; virtual;
    procedure RenderPreview(Graphics: Pointer; Size: integer);
  public
    destructor Destroy; override;
    class procedure Open(wnd: HWND);
  end;

var frmStackProp: TfrmStackProp;

implementation

uses declu, toolu, frmmainu, frmitemoptu, stackmodeu, itemviewu, shelltextu;

{$R *.lfm}

resourcestring
  XNoLocation = 'None (custom stack)';
  XControlPanel = 'Control Panel';
  XThisPC = 'This PC';
  XRecycleBin = 'Recycle Bin';
  XNetwork = 'Network';
  XDesktop = 'Desktop';
  XPrinters = 'Printers';
  XMusic = 'Music';
  XVideos = 'Videos';
  XManualOrder = 'Manual';
  XNameOrder = 'Name';
  XNewStackItem = 'New item';
  XSelectLocation = 'Select a supported Windows location.';
  XLocationReadError = 'Cannot read this Windows location: %s';
  XLocationItems = 'Windows manages these items. Select None (custom stack) to edit items manually.';
  XCustomItems = 'Add shortcuts or commands to this stack.';
  XColorNeutral = '%s (neutral: %d)';
  XHueName = '&Hue';
  XSaturationName = '&Saturation';
  XBrightnessName = 'Bri&ghtness';
  XContrastName = '&Contrast';
  XFanCurve = '&Fan curve';
  XItemSpacing = '&Item spacing';
  XArcSize = '&Arc size';

const
  LOCATION_CODES: array[0..8] of string = ('', 'CSIDL_CONTROLS', 'CSIDL_DRIVES',
    'CSIDL_BITBUCKET', 'CSIDL_NETWORK', 'CSIDL_DESKTOPDIRECTORY',
    'CSIDL_PRINTERS', 'CSIDL_MYMUSIC', 'CSIDL_MYVIDEO');

class procedure TfrmStackProp.Open(wnd: HWND);
begin
  try
    if not Assigned(frmStackProp) then Application.CreateForm(Self, frmStackProp);
    if frmStackProp.SetData(wnd) then
    begin
      frmStackProp.Show;
      frmStackProp.edCaption.SetFocus;
    end;
  except on E: Exception do
    if Assigned(frmmain) then frmmain.err('frmStackProp.Open', E) else raise;
  end;
end;

procedure TfrmStackProp.FormCreate(Sender: TObject);
var Index: integer;
begin
  FLoading := true;
  FChildren := TStringList.Create;
  FCustomChildren := TStringList.Create;
  cboLocation.Items.Add(XNoLocation);
  cboLocation.Items.Add(XControlPanel);
  cboLocation.Items.Add(XThisPC);
  cboLocation.Items.Add(XRecycleBin);
  cboLocation.Items.Add(XNetwork);
  cboLocation.Items.Add(XDesktop);
  cboLocation.Items.Add(XPrinters);
  cboLocation.Items.Add(XMusic);
  cboLocation.Items.Add(XVideos);
  cboOrder.Items.Add(XManualOrder);
  cboOrder.Items.Add(XNameOrder);
  for Index := 0 to mc.GetModeCount - 1 do cboMode.Items.Add(mc.GetModeName(Index));
  cboPreview.Items.Add(XStackPreviewNone);
  cboPreview.Items.Add(XStackPreviewFour);
  cboPreview.Items.Add(XStackPreviewNine);
  lblHue.Caption := Format(XColorNeutral, [XHueName, byte(DEF_COLOR_DATA and $ff)]);
  lblSat.Caption := Format(XColorNeutral, [XSaturationName, byte((DEF_COLOR_DATA shr 8) and $ff)]);
  lblBr.Caption := Format(XColorNeutral, [XBrightnessName, byte((DEF_COLOR_DATA shr 16) and $ff)]);
  lblCont.Caption := Format(XColorNeutral, [XContrastName, byte(DEF_COLOR_DATA shr 24)]);
  FLoading := false;
end;

destructor TfrmStackProp.Destroy;
begin
  ClearIcons;
  if FImage <> nil then GdipDisposeImage(FImage);
  FChildren.Free;
  FCustomChildren.Free;
  inherited;
end;

function TfrmStackProp.SetData(wnd: HWND): boolean;
var Item: TStackItem; Id: TItemId;
begin
  Result := false;
  if (FItemId <> NO_ITEM_ID) and btnApply.Enabled then
    if not confirm(Handle, UTF8Decode(XMsgUnsavedIconParams)) then Exit;
  FItemId := ItemViews.ItemIdOf(wnd);
  if not AcquireItem(Item, Id) then Exit;
  try
    pages.Enabled := true;
    btnOK.Enabled := true;
    pages.ActivePage := tsGeneral;
    LoadItem(Item);
    Result := true;
  finally ReleaseItemModel(Id); end;
end;

function TfrmStackProp.AcquireItem(out Item: TStackItem; out Id: TItemId): boolean;
var Model: TItemModel;
begin
  Item := nil;
  Id := FItemId;
  Result := AcquireItemModel(Id, Model);
  if Result then
  begin
    Result := (Model is TStackItem) and not (Model.State in [imsDeleted, imsRetiring]);
    if Result then Item := TStackItem(Model) else ReleaseItemModel(Id);
  end;
  if not Result then ItemUnavailable;
end;

procedure TfrmStackProp.ItemUnavailable;
begin
  FItemId := NO_ITEM_ID;
  pages.Enabled := false;
  btnOK.Enabled := false;
  btnApply.Enabled := false;
  Close;
end;

procedure TfrmStackProp.LoadItem(Item: TStackItem);
var Data: TStackDtoV1; Index, Selected: integer;
begin
  Selected := list.ItemIndex;
  Data := ReadStackText(Item.ToString);
  FLoading := true;
  try
    edCaption.Text := UTF8Encode(Data.Caption);
    edImage.Text := Data.Image;
    FSource := Data.SpecialFolder;
    cboLocation.ItemIndex := -1;
    for Index := Low(LOCATION_CODES) to High(LOCATION_CODES) do
      if LOCATION_CODES[Index] = FSource then cboLocation.ItemIndex := Index;
    cboOrder.ItemIndex := Ord(Data.Sorted);
    cboMode.ItemIndex := Data.Mode;
    cboPreview.ItemIndex := Data.Preview;
    chbBackground.Checked := Data.Background;
    tbOffset.Position := Data.DistanceSteps;
    numDistance.Value := tbOffset.Position / 4;
    tbAnimationSpeed.Position := Data.AnimationSpeed;
    numSpeed.Value := Data.AnimationSpeed;
    tbDistort.Position := Data.Distort;
    numDistort.Value := Data.Distort;
    tbHue.Position := byte(Data.ColorData);
    tbSat.Position := byte(Data.ColorData shr 8);
    tbBr.Position := byte(Data.ColorData shr 16);
    tbCont.Position := byte(Data.ColorData shr 24);
    numHue.Value := tbHue.Position;
    numSat.Value := tbSat.Position;
    numBr.Value := tbBr.Position;
    numCont.Value := tbCont.Position;
    FChildren.Clear;
    for Index := 0 to Item.ItemCount - 1 do FChildren.Add(Item.SubitemToString(Index));
    FCustomChildren.Clear;
    if FSource = '' then FCustomChildren.Assign(FChildren);
    lblError.Caption := '';
    RebuildItems(Selected);
    UpdateLayoutLabel;
    LoadImagePreview;
    FBaseline := DraftText;
  finally FLoading := false; end;
  UpdateActions;
end;

function TfrmStackProp.CaptureControls: TStackDtoV1;
begin
  if (cboLocation.ItemIndex < 0) or (cboLocation.ItemIndex > High(LOCATION_CODES)) then
    raise EConvertError.Create(XSelectLocation);
  Result := DefaultStackDto;
  Result.Caption := UTF8Decode(edCaption.Text);
  Result.Image := edImage.Text;
  Result.SpecialFolder := LOCATION_CODES[cboLocation.ItemIndex];
  Result.Mode := cboMode.ItemIndex;
  Result.DistanceSteps := tbOffset.Position;
  Result.AnimationSpeed := tbAnimationSpeed.Position;
  Result.Distort := tbDistort.Position;
  Result.Preview := cboPreview.ItemIndex;
  Result.Background := chbBackground.Checked;
  Result.Sorted := cboOrder.ItemIndex = 1;
  Result.ColorData := integer(cardinal(byte(tbHue.Position)) or
    (cardinal(byte(tbSat.Position)) shl 8) or
    (cardinal(byte(tbBr.Position)) shl 16) or
    (cardinal(byte(tbCont.Position)) shl 24));
end;

function TfrmStackProp.DraftText: string;
begin
  Result := WriteStackText(CaptureControls) + LineEnding + FChildren.Text;
end;

procedure TfrmStackProp.UpdateActions;
var Custom, Selected, Dirty: boolean;
begin
  if FLoading then Exit;
  Custom := cboLocation.ItemIndex = 0;
  Selected := (list.ItemIndex >= 0) and (list.ItemIndex < FChildren.Count);
  bbAddIcon.Enabled := Custom and (FChildren.Count < STACK_CHILD_LIMIT) and pages.Enabled;
  bbEditIcon.Enabled := Custom and Selected and pages.Enabled;
  bbDelIcon.Enabled := bbEditIcon.Enabled;
  bbIconUp.Enabled := bbEditIcon.Enabled and (cboOrder.ItemIndex = 0) and (list.ItemIndex > 0);
  bbIconDown.Enabled := bbEditIcon.Enabled and (cboOrder.ItemIndex = 0) and
    (list.ItemIndex < FChildren.Count - 1);
  if Custom then lblItemsHelp.Caption := XCustomItems else lblItemsHelp.Caption := XLocationItems;
  try Dirty := DraftText <> FBaseline;
  except Dirty := true; end;
  btnApply.Enabled := pages.Enabled and (FItemId <> NO_ITEM_ID) and Dirty;
end;

procedure TfrmStackProp.Changed(Sender: TObject);
begin
  if FLoading then Exit;
  UpdateActions;
  iPic.Invalidate;
end;

procedure TfrmStackProp.ImageChanged(Sender: TObject);
begin
  if FLoading then Exit;
  LoadImagePreview;
  Changed(Sender);
end;

procedure TfrmStackProp.LocationChanged(Sender: TObject);
var Candidate: TStringList; Source: string; Index: integer;
begin
  if FLoading then Exit;
  Index := cboLocation.ItemIndex;
  if (Index < 0) or (Index > High(LOCATION_CODES)) then Exit;
  Source := LOCATION_CODES[Index];
  if Source = FSource then Exit;
  try
    if Source = '' then Candidate := TStringList.Create
    else Candidate := TStackItem.ReadLocationItems(Source);
    try
      if FSource = '' then FCustomChildren.Assign(FChildren);
      if Source = '' then FChildren.Assign(FCustomChildren) else FChildren.Assign(Candidate);
      FSource := Source;
    finally Candidate.Free; end;
    lblError.Caption := '';
    SortDraft;
    RebuildItems(0);
    UpdateLayoutLabel;
    Changed(Sender);
  except on E: Exception do
    begin
      FLoading := true;
      try
        for Index := Low(LOCATION_CODES) to High(LOCATION_CODES) do
          if LOCATION_CODES[Index] = FSource then cboLocation.ItemIndex := Index;
      finally FLoading := false; end;
      lblError.Caption := Format(XLocationReadError, [E.Message]);
      UpdateActions;
    end;
  end;
end;

function CompareDraftChildren(List: TStringList; Index1, Index2: integer): integer;
begin
  Result := CompareText(UTF8Encode(ReadShortcutText(List[Index1]).Caption),
    UTF8Encode(ReadShortcutText(List[Index2]).Caption));
end;

procedure TfrmStackProp.SortDraft;
begin
  if cboOrder.ItemIndex = 1 then FChildren.CustomSort(CompareDraftChildren);
end;

procedure TfrmStackProp.OrderChanged(Sender: TObject);
var SelectedText: string; Selected: integer;
begin
  if FLoading then Exit;
  SelectedText := '';
  if list.ItemIndex >= 0 then SelectedText := FChildren[list.ItemIndex];
  SortDraft;
  Selected := FChildren.IndexOf(SelectedText);
  RebuildItems(Selected);
  Changed(Sender);
end;

procedure TfrmStackProp.UpdateLayoutLabel;
var Mode: integer;
begin
  Mode := cboMode.ItemIndex;
  if Mode = 0 then
    if FChildren.Count > 15 then Mode := 4 else Mode := 1;
  case Mode of
    1, 2: lblDistort.Caption := XFanCurve;
    7: lblDistort.Caption := XArcSize;
    else lblDistort.Caption := XItemSpacing;
  end;
end;

procedure TfrmStackProp.ModeChanged(Sender: TObject);
begin
  UpdateLayoutLabel;
  Changed(Sender);
end;

procedure TfrmStackProp.SliderChanged(Sender: TObject);
begin
  if FLoading then Exit;
  FLoading := true;
  try
    numDistance.Value := tbOffset.Position / 4;
    numDistort.Value := tbDistort.Position;
    numSpeed.Value := tbAnimationSpeed.Position;
    numHue.Value := tbHue.Position;
    numSat.Value := tbSat.Position;
    numBr.Value := tbBr.Position;
    numCont.Value := tbCont.Position;
  finally FLoading := false; end;
  Changed(Sender);
end;

procedure TfrmStackProp.NumberChanged(Sender: TObject);
begin
  if FLoading then Exit;
  FLoading := true;
  try
    tbOffset.Position := Round(numDistance.Value * 4);
    numDistance.Value := tbOffset.Position / 4;
    tbDistort.Position := numDistort.Value;
    tbAnimationSpeed.Position := numSpeed.Value;
    tbHue.Position := numHue.Value;
    tbSat.Position := numSat.Value;
    tbBr.Position := numBr.Value;
    tbCont.Position := numCont.Value;
  finally FLoading := false; end;
  Changed(Sender);
end;

function TfrmStackProp.ApplyDraft: boolean;
var Item: TStackItem; Id: TItemId; Data: TStackDtoV1; Index: integer;
begin
  Result := false;
  if not AcquireItem(Item, Id) then Exit;
  try
    try
      Data := CaptureControls;
      WriteStackText(Data);
      for Index := 0 to FChildren.Count - 1 do ReadShortcutText(FChildren[Index]);
      Item.ApplyProperties(Data, FChildren);
      LoadItem(Item);
      if Assigned(frmmain) then frmmain.BaseCmd(tcSaveSets, 0);
      Result := true;
    except on E: Exception do
      begin
        lblError.Caption := E.Message;
        pages.ActivePage := tsGeneral;
        UpdateActions;
      end;
    end;
  finally ReleaseItemModel(Id); end;
end;

procedure TfrmStackProp.btnApplyClick(Sender: TObject);
begin
  ApplyDraft;
end;

procedure TfrmStackProp.btnOKClick(Sender: TObject);
begin
  if ApplyDraft then Close;
end;

procedure TfrmStackProp.btnCancelClick(Sender: TObject);
begin
  Close;
end;

procedure TfrmStackProp.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  FItemId := NO_ITEM_ID;
  Action := caFree;
  if frmStackProp = Self then frmStackProp := nil;
end;

procedure TfrmStackProp.FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  if Shift <> [] then Exit;
  if (ActiveControl is TComboBox) and TComboBox(ActiveControl).DroppedDown then Exit;
  if Key = VK_ESCAPE then
  begin
    Key := 0;
    btnCancelClick(nil);
  end
  else if Key = VK_RETURN then
  begin
    if ActiveControl = list then
    begin
      Key := 0;
      if bbEditIcon.Enabled then bbEditIconClick(nil);
    end
    else if not (ActiveControl is TComboBox) and not (ActiveControl is TButton) then
    begin
      Key := 0;
      btnOKClick(nil);
    end;
  end;
end;

procedure TfrmStackProp.btnBrowseImage1Click(Sender: TObject);
var Picker: TOpenDialog;
begin
  Picker := TOpenDialog.Create(Self);
  try
    if edImage.Text = '' then Picker.InitialDir := UnzipPath('%pp%\Images')
    else Picker.InitialDir := ExtractFilePath(UnzipPath(edImage.Text));
    if Picker.Execute then edImage.Text := ZipPath(Picker.FileName);
  finally Picker.Free; end;
end;

procedure TfrmStackProp.btnClearImageClick(Sender: TObject);
begin
  edImage.Clear;
end;

procedure TfrmStackProp.btnDefaultColorClick(Sender: TObject);
begin
  FLoading := true;
  try
    tbHue.Position := byte(DEF_COLOR_DATA and $ff);
    tbSat.Position := byte((DEF_COLOR_DATA shr 8) and $ff);
    tbBr.Position := byte((DEF_COLOR_DATA shr 16) and $ff);
    tbCont.Position := byte(DEF_COLOR_DATA shr 24);
  finally FLoading := false; end;
  SliderChanged(nil);
end;

function TfrmStackProp.CanEditItems: boolean;
var Item: TStackItem; Id: TItemId;
begin
  Result := AcquireItem(Item, Id);
  if not Result then Exit;
  ReleaseItemModel(Id);
  Result := cboLocation.ItemIndex = 0;
end;

procedure TfrmStackProp.bbAddIconClick(Sender: TObject);
var Data: TShortcutDtoV1;
begin
  if not CanEditItems or (FChildren.Count >= STACK_CHILD_LIMIT) then Exit;
  Data := DefaultShortcutDto;
  Data.Caption := UTF8Decode(XNewStackItem);
  FChildren.Add(WriteShortcutText(Data));
  SortDraft;
  if cboOrder.ItemIndex = 0 then RebuildItems(FChildren.Count - 1)
  else RebuildItems(FChildren.IndexOf(WriteShortcutText(Data)));
  UpdateLayoutLabel;
  Changed(nil);
end;

procedure TfrmStackProp.bbDelIconClick(Sender: TObject);
var Index: integer;
begin
  if not CanEditItems then Exit;
  Index := list.ItemIndex;
  if (Index < 0) or (Index >= FChildren.Count) then Exit;
  FChildren.Delete(Index);
  RebuildItems(Min(Index, FChildren.Count - 1));
  UpdateLayoutLabel;
  Changed(nil);
end;

function TfrmStackProp.EditChild(var Text: string): boolean;
begin
  Result := TfrmItemProp.EditDraft(Text);
end;

procedure TfrmStackProp.bbEditIconClick(Sender: TObject);
var Text: string; Index: integer;
begin
  if not CanEditItems then Exit;
  Index := list.ItemIndex;
  if (Index < 0) or (Index >= FChildren.Count) then Exit;
  Text := FChildren[Index];
  if not EditChild(Text) then Exit;
  if not CanEditItems then Exit;
  ReadShortcutText(Text);
  FChildren[Index] := Text;
  SortDraft;
  RebuildItems(FChildren.IndexOf(Text));
  Changed(nil);
end;

procedure TfrmStackProp.bbIconUpClick(Sender: TObject);
var Index: integer;
begin
  if not CanEditItems or (cboOrder.ItemIndex <> 0) then Exit;
  Index := list.ItemIndex;
  if (Index <= 0) or (Index >= FChildren.Count) then Exit;
  FChildren.Exchange(Index, Index - 1);
  RebuildItems(Index - 1);
  Changed(nil);
end;

procedure TfrmStackProp.bbIconDownClick(Sender: TObject);
var Index: integer;
begin
  if not CanEditItems or (cboOrder.ItemIndex <> 0) then Exit;
  Index := list.ItemIndex;
  if (Index < 0) or (Index >= FChildren.Count - 1) then Exit;
  FChildren.Exchange(Index, Index + 1);
  RebuildItems(Index + 1);
  Changed(nil);
end;

procedure TfrmStackProp.listDblClick(Sender: TObject);
begin
  if bbEditIcon.Enabled then bbEditIconClick(nil);
end;

procedure TfrmStackProp.SelectionChanged(Sender: TObject; User: boolean);
begin
  UpdateActions;
end;

procedure TfrmStackProp.ClearIcons;
var Index: integer;
begin
  for Index := 0 to High(FIcons) do
    if FIcons[Index].Image <> nil then GdipDisposeImage(FIcons[Index].Image);
  FIcons := nil;
end;

procedure TfrmStackProp.RebuildItems(Selected: integer);
var Index: integer; Data: TShortcutDtoV1;
begin
  ClearIcons;
  SetLength(FIcons, FChildren.Count);
  list.Items.BeginUpdate;
  try
    list.Clear;
    for Index := 0 to FChildren.Count - 1 do
    begin
      Data := ReadShortcutText(FChildren[Index]);
      list.Items.Add(UTF8Encode(Data.Caption));
      FIcons[Index].ColorData := Data.ColorData;
      LoadShortcutImage(ShellUTF16(UnzipPath(Data.Command)),
        ShellUTF16(UnzipPath(cut(Data.Image, ';'))), Max(64, iPic.Width div 2), true, true,
        FIcons[Index].Image, FIcons[Index].Width, FIcons[Index].Height);
    end;
    if FChildren.Count > 0 then list.ItemIndex := EnsureRange(Selected, 0, FChildren.Count - 1);
  finally list.Items.EndUpdate; end;
  iPic.Invalidate;
  UpdateActions;
end;

procedure TfrmStackProp.PaintImage(Graphics, Image: Pointer; ImageWidth, ImageHeight: UINT;
  const Bounds: Windows.TRect; ColorData: integer);
var Scale: Double; W, H: integer; Attributes: Pointer; Matrix: ColorMatrix;
begin
  if (Image = nil) or (ImageWidth = 0) or (ImageHeight = 0) then Exit;
  Scale := Min((Bounds.Right - Bounds.Left) / ImageWidth,
    (Bounds.Bottom - Bounds.Top) / ImageHeight);
  W := Round(ImageWidth * Scale);
  H := Round(ImageHeight * Scale);
  CreateColorMatrix(ColorData, Matrix);
  GdipCreateImageAttributes(Attributes);
  try
    GdipSetImageAttributesColorMatrix(Attributes, ColorAdjustTypeBitmap, true,
      @Matrix, nil, ColorMatrixFlagsDefault);
    GdipDrawImageRectRectI(Graphics, Image,
      Bounds.Left + (Bounds.Right - Bounds.Left - W) div 2,
      Bounds.Top + (Bounds.Bottom - Bounds.Top - H) div 2, W, H,
      0, 0, ImageWidth, ImageHeight, UnitPixel, Attributes, nil, nil);
  finally GdipDisposeImageAttributes(Attributes); end;
end;

procedure TfrmStackProp.ListDrawItem(Control: TWinControl; Index: integer;
  Rect: Windows.TRect; State: TOwnerDrawState);
var Graphics: Pointer; IconBounds, TextBounds: Windows.TRect; Text: UnicodeString; IconSize: integer;
begin
  if (Index < 0) or (Index >= Length(FIcons)) then Exit;
  if LCLType.odSelected in State then
  begin
    list.Canvas.Brush.Color := clHighlight;
    list.Canvas.Font.Color := clHighlightText;
  end
  else
  begin
    list.Canvas.Brush.Color := clWindow;
    list.Canvas.Font.Color := clWindowText;
  end;
  list.Canvas.FillRect(Rect);
  IconSize := list.ItemHeight - 8;
  IconBounds := Bounds(Rect.Left + 4, Rect.Top + 4, IconSize, IconSize);
  GdipCreateFromHDC(list.Canvas.Handle, Graphics);
  try
    GdipSetInterpolationMode(Graphics, InterpolationModeHighQualityBicubic);
    PaintImage(Graphics, FIcons[Index].Image, FIcons[Index].Width, FIcons[Index].Height,
      IconBounds, FIcons[Index].ColorData);
  finally GdipDeleteGraphics(Graphics); end;
  TextBounds := Rect;
  TextBounds.Left := IconBounds.Right + 8;
  TextBounds.Right -= 4;
  Text := UTF8Decode(list.Items[Index]);
  DrawTextW(list.Canvas.Handle, PWideChar(Text), Length(Text), TextBounds,
    DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);
  if LCLType.odFocused in State then list.Canvas.DrawFocusRect(Rect);
end;

procedure TfrmStackProp.LoadImagePreview;
begin
  LoadImage(ShellUTF16(UnzipPath(edImage.Text)), Max(128, iPic.Width), true, false, FImage, FIW, FIH);
  if (FImage = nil) and Assigned(theme) and (theme.Stack.Image <> nil) then
  begin
    GdipCloneImage(theme.Stack.Image, FImage);
    GdipGetImageWidth(FImage, FIW);
    GdipGetImageHeight(FImage, FIH);
  end;
  iPic.Invalidate;
end;

procedure TfrmStackProp.PreviewPaint(Sender: TObject);
var Graphics: Pointer;
begin
  iPic.Canvas.Brush.Color := pnlPreview.Color;
  iPic.Canvas.FillRect(iPic.ClientRect);
  if (FChildren = nil) or (cboLocation.ItemIndex < 0) then Exit;
  GdipCreateFromHDC(iPic.Canvas.Handle, Graphics);
  try
    GdipSetInterpolationMode(Graphics, InterpolationModeHighQualityBicubic);
    RenderPreview(Graphics, Min(iPic.Width, iPic.Height));
  finally GdipDeleteGraphics(Graphics); end;
end;

procedure TfrmStackProp.RenderPreview(Graphics: Pointer; Size: integer);
var Data: TStackDtoV1; Count, Columns, Tile, Border, Index: integer;
  TileBounds: Windows.TRect;
begin
  Data := CaptureControls;
  PaintImage(Graphics, FImage, FIW, FIH, Bounds(0, 0, Size, Size), Data.ColorData);
  Count := 0;
  if cboPreview.ItemIndex = 1 then Count := Min(4, Length(FIcons));
  if cboPreview.ItemIndex = 2 then Count := Min(9, Length(FIcons));
  if Count <= 0 then Exit;
  Columns := 1;
  if Count > 1 then Columns := 2;
  if Count > 4 then Columns := 3;
  Border := Round(Size / 8);
  Tile := (Size - Border * 2) div Columns;
  for Index := 0 to Count - 1 do
  begin
    TileBounds := Bounds(Border + (Tile + 1) * (Index mod Columns),
      Border + (Tile + 1) * (Index div Columns), Tile - 2, Tile - 2);
    PaintImage(Graphics, FIcons[Index].Image, FIcons[Index].Width,
      FIcons[Index].Height, TileBounds, FIcons[Index].ColorData);
  end;
end;

end.

