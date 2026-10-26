unit frmstackpropu;

interface

uses
  Windows, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  DefaultTranslator, Dialogs, StdCtrls, ExtCtrls, ComCtrls, Menus, Buttons,
  GDIPAPI, gfx, iconserviceu, PIDL, stackitemu, themeu, DividerBevel, itemmodelu, itemserializationu;

type
  _uproc = procedure(AData: string) of object;

  { TfrmStackProp }

  TfrmStackProp = class(TForm)
    bbAddIcon: TBitBtn;
    bbDelIcon: TBitBtn;
    bbEditIcon: TBitBtn;
    bbIconDown: TBitBtn;
    bbIconUp: TBitBtn;
    btnBrowseImage1: TButton;
    btnClearImage: TButton;
    btnDefaultColor: TButton;
    btnOK: TButton;
    btnApply: TButton;
    btnCancel: TButton;
    btnProperties: TButton;
    btnSelectColor: TButton;
    cboMode: TComboBox;
    cboPreview: TComboBox;
    chbBackground: TCheckBox;
    chbSorted: TCheckBox;
    edImage: TEdit;
    edCaption: TEdit;
    edSpecialFolder: TEdit;
    iPic: TPaintBox;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    lblImage: TLabel;
    lblDistort: TLabel;
    lblCaption: TLabel;
    lblAnimationSpeed: TLabel;
    lblSpecialFolder: TLabel;
    lblStyle: TLabel;
    lblDir: TLabel;
    lblOffset: TLabel;
    list: TListBox;
    pages: TPageControl;
    tbAnimationSpeed: TTrackBar;
    tbDistort: TTrackBar;
    tbOffset: TTrackBar;
    tsProperties: TTabSheet;
    tsColor: TTabSheet;
    tbBr: TTrackBar;
    tbCont: TTrackBar;
    tbHue: TTrackBar;
    tbSat: TTrackBar;
    procedure bbAddIconClick(Sender: TObject);
    procedure bbDelIconClick(Sender: TObject);
    procedure bbEditIconClick(Sender: TObject);
    procedure bbIconDownClick(Sender: TObject);
    procedure bbIconUpClick(Sender: TObject);
    procedure btnBrowseImage1Click(Sender: TObject);
    procedure btnDefaultColorClick(Sender: TObject);
    procedure btnPropertiesClick(Sender: TObject);
    procedure cboModeChange(Sender: TObject);
    procedure cboPreviewChange(Sender: TObject);
    procedure chbBackgroundChange(Sender: TObject);
    procedure chbSortedChange(Sender: TObject);
    procedure edCaptionChange(Sender: TObject);
    procedure edImageChange(Sender: TObject);
    procedure edSpecialFolderChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure btnClearImageClick(Sender: TObject);
    procedure btnSelectColorClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
    procedure btnOKClick(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure btnApplyClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
		procedure FormShow(Sender: TObject);
    procedure listDblClick(Sender: TObject);
    procedure tbAnimationSpeedChange(Sender: TObject);
    procedure tbDistortChange(Sender: TObject);
    procedure tbHueChange(Sender: TObject);
    procedure tbOffsetChange(Sender: TObject);
  private
    savedCaption: WideString;
    savedImageFile: string;
    savedSpecialFolder: string;
    savedColorData: integer;
    savedMode: integer;
    savedOffset: integer;
    savedAnimationSpeed: integer;
    savedDistort: integer;
    savedPreview: integer;
    savedShowBackground: boolean;
    savedSorted: boolean;
    //
    color_data: uint;
    background_color: uint;
    SpecialFolder: string;
    FItemId: TItemId;
    FChanged: boolean;
    FImage: Pointer;
    FIW: cardinal;
    FIH: cardinal;
    function AcquireItem(out Item: TStackItem; out Id: TItemId): boolean;
    procedure ItemUnavailable;
    procedure ReadSubitems(Item: TStackItem);
    procedure iPicPaint(Sender: TObject);
    procedure Draw;
    procedure DrawFit;
  protected
    function SetData(wnd: HWND): boolean;
  public
    class procedure Open(wnd: HWND);
  end;

var
  frmStackProp: TfrmStackProp;

{$t+}
implementation
uses declu, toolu, frmmainu, stackmodeu, itemviewu, shelltextu;
{$R *.lfm}
//------------------------------------------------------------------------------
class procedure TfrmStackProp.Open(wnd: HWND);
begin
  try
    if not assigned(frmStackProp) then Application.CreateForm(self, frmStackProp);
    if frmStackProp.SetData(wnd) then
    begin
      frmStackProp.Show;
      frmStackProp.edCaption.SetFocus;
    end;
  except
    on e: Exception do frmmain.err('frmStackProp.Open', e);
  end;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.FormCreate(Sender: TObject);
var
  idx: integer;
begin
  FChanged := false;

  for idx := 0 to mc.GetModeCount - 1 do cboMode.Items.Add(mc.GetModeName(idx));
  cboPreview.Clear;
  cboPreview.Items.Add(XStackPreviewNone);
  cboPreview.Items.Add(XStackPreviewFour);
  cboPreview.Items.Add(XStackPreviewNine);
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.FormShow(Sender: TObject);
begin
end;
//------------------------------------------------------------------------------
function TfrmStackProp.SetData(wnd: HWND): boolean;
var
  Model: TItemModel;
  Item: TStackItem;
  Id: TItemId;
begin
  result := false;

  if FChanged then
  begin
    if not confirm(Handle, UTF8Decode(XMsgUnsavedIconParams)) then exit;
  end;

  Id := ItemViews.ItemIdOf(wnd);
  if not AcquireItemModel(Id, Model) then
  begin
    ItemUnavailable;
    exit;
  end;
  try
    if not (Model is TStackItem) or (Model.State in [imsDeleted, imsRetiring]) then
    begin
      ItemUnavailable;
      exit;
    end;
    Item := TStackItem(Model);

    result := true;
    pages.ActivePageIndex := 0;

    FItemId                    := Id;
    pages.Enabled              := true;
    btnApply.Enabled           := true;
    btnOK.Enabled              := true;
    savedCaption               := Item.Caption;
    savedImageFile             := Item.ImageFile;
    savedSpecialFolder         := Item.SpecialFolder;
    savedColorData             := Item.ColorData;
    savedMode                  := Item.Mode;
    savedOffset                := Item.Offset;
    savedAnimationSpeed        := Item.AnimationSpeed;
    savedDistort               := Item.Distort;
    savedPreview               := Item.Preview;
    savedShowBackground        := Item.ShowBackground;
    savedSorted                := Item.Sorted;

    // show parameters //

    edCaption.Text             := UTF8Encode(savedCaption);
    edImage.Text               := savedImageFile;
    edSpecialFolder.Text       := savedSpecialFolder;

    color_data                 := savedColorData;
    tbHue.OnChange             := nil;
    tbSat.OnChange             := nil;
    tbBr.OnChange              := nil;
    tbCont.OnChange            := nil;
    tbHue.position             := byte(color_data);
    tbSat.position             := byte(color_data shr 8);
    tbBr.position              := byte(color_data shr 16);
    tbCont.position            := byte(color_data shr 24);
    tbHue.OnChange             := tbHueChange;
    tbSat.OnChange             := tbHueChange;
    tbBr.OnChange              := tbHueChange;
    tbCont.OnChange            := tbHueChange;

    tbOffset.Position          := -1;
    tbOffset.Position          := 0;
    tbAnimationSpeed.Position  := tbAnimationSpeed.Min;
    tbDistort.Position         := -1;
    tbDistort.Position         := 0;

    cboMode.ItemIndex          := savedMode;
    tbOffset.Position          := savedOffset;
    tbAnimationSpeed.Position  := savedAnimationSpeed;
    tbDistort.Position         := savedDistort;
    cboPreview.ItemIndex       := savedPreview;
    chbBackground.checked      := savedShowBackground;
    chbSorted.checked          := savedSorted;

    Draw;
    iPic.OnPaint := iPicPaint;

    ReadSubitems(Item);

    // reset 'changed' state //
    FChanged := false;
  finally
    ReleaseItemModel(Id);
  end;
end;
//------------------------------------------------------------------------------
function TfrmStackProp.AcquireItem(out Item: TStackItem; out Id: TItemId): boolean;
var
  Model: TItemModel;
begin
  Item := nil;
  Id := FItemId;
  result := AcquireItemModel(Id, Model);
  if result then
  begin
    result := (Model is TStackItem)
      and not (Model.State in [imsDeleted, imsRetiring]);
    if result then Item := TStackItem(Model)
    else ReleaseItemModel(Id);
  end;
  if not result then ItemUnavailable;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.ItemUnavailable;
begin
  FItemId := NO_ITEM_ID;
  FChanged := false;
  pages.Enabled := false;
  btnApply.Enabled := false;
  btnOK.Enabled := false;
  Close;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.ReadSubitems(Item: TStackItem);
var
  idx: integer;
begin
  list.Items.BeginUpdate;
  try
    list.Clear;
    if item.ItemCount > 0 then
    begin
      for idx := 0 to item.ItemCount - 1 do
      begin
        list.Items.Add(UTF8Encode(Item.GetSubitemCaption(idx)));
      end;
    end;
  finally
    list.Items.EndUpdate;
  end;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  if (key = 27) and (shift = []) then btnCancel.Click;
  if (key = 13) and (shift = []) then btnOK.Click;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.btnOKClick(Sender: TObject);
begin
  if FChanged then btnApply.Click;
  // save settings !!!
  frmmain.BaseCmd(tcSaveSets, 0);
  Close;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.btnApplyClick(Sender: TObject);
var
  Item: TStackItem;
  Id: TItemId;
  Draft: TStackDtoV1;
begin
  try
    if not AcquireItem(Item, Id) then exit;
    try
      Draft := DefaultStackDto;
      Draft.Caption := UTF8Decode(edCaption.Text);
      Draft.Image := edImage.Text;
      Draft.SpecialFolder := edSpecialFolder.Text;
      Draft.ColorData := color_data;
      Draft.Mode := cboMode.ItemIndex;
      Draft.Offset := tbOffset.Position;
      Draft.AnimationSpeed := tbAnimationSpeed.Position;
      Draft.Distort := tbDistort.Position;
      Draft.Preview := cboPreview.ItemIndex;
      Draft.Background := chbBackground.Checked;
      Draft.Sorted := chbSorted.Checked;
      WriteStackText(Draft);
      Item.Caption               := UTF8Decode(edCaption.Text);
      Item.ImageFile             := edImage.Text;
      Item.SpecialFolder         := edSpecialFolder.Text;
      Item.ColorData             := color_data;
      Item.Mode                  := cboMode.ItemIndex;
      Item.Offset                := tbOffset.Position;
      Item.AnimationSpeed        := tbAnimationSpeed.Position;
      Item.Distort               := tbDistort.Position;
      Item.Preview               := cboPreview.ItemIndex;
      Item.ShowBackground        := chbBackground.Checked;
      Item.Sorted                := chbSorted.Checked;
      Item.Update;
      FChanged := false;
    finally
      ReleaseItemModel(Id);
    end;
  except
    on e: Exception do frmmain.err('frmStackProp.btnApplyClick', e);
  end;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.btnCancelClick(Sender: TObject);
var
  Item: TStackItem;
  Id: TItemId;
begin
  if FChanged then
  begin
    if not AcquireItem(Item, Id) then exit;
    try
      Item.Caption               := savedCaption;
      Item.ImageFile             := savedImageFile;
      Item.SpecialFolder         := savedSpecialFolder;
      Item.ColorData             := savedColorData;
      Item.Mode                  := savedMode;
      Item.Offset                := savedOffset;
      Item.AnimationSpeed        := savedAnimationSpeed;
      Item.Distort               := savedDistort;
      Item.Preview               := savedPreview;
      Item.ShowBackground        := savedShowBackground;
      Item.Sorted                := savedSorted;
      Item.Update;
    finally
      ReleaseItemModel(Id);
    end;
  end;
  FChanged := false;
  Close;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  try if assigned(FImage) then GdipDisposeImage(FImage);
  except end;
  FImage := nil;
  FItemId := NO_ITEM_ID;
  action := caFree;
  frmStackProp := nil;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.btnClearImageClick(Sender: TObject);
begin
  edImage.Clear;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.btnSelectColorClick(Sender: TObject);
begin
  pages.ActivePageIndex := 1;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.btnPropertiesClick(Sender: TObject);
begin
  pages.ActivePageIndex := 0;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.btnBrowseImage1Click(Sender: TObject);
begin
  with TOpenDialog.Create(self) do
  try
    if edImage.Text = '' then InitialDir:= toolu.UnzipPath('%pp%\images')
    else InitialDir:= ExtractFilePath(toolu.UnzipPath(edImage.Text));
    if execute then edImage.Text := toolu.ZipPath(FileName);
  finally
    free;
  end;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.edCaptionChange(Sender: TObject);
begin
  FChanged := true;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.edImageChange(Sender: TObject);
begin
  FChanged := true;
  Draw;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.edSpecialFolderChange(Sender: TObject);
begin
  FChanged := true;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.tbOffsetChange(Sender: TObject);
begin
  FChanged := true;
  lblOffset.Caption := Format(XOffsetOfIcons, [TTrackBar(Sender).Position]);
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.tbDistortChange(Sender: TObject);
begin
  FChanged := true;
  lblDistort.Caption := Format(XDistort, [TTrackBar(Sender).Position]);
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.tbAnimationSpeedChange(Sender: TObject);
begin
  FChanged := true;
  lblAnimationSpeed.Caption := Format(XAnimationSpeed, [TTrackBar(Sender).Position]);
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.cboModeChange(Sender: TObject);
begin
  FChanged := true;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.cboPreviewChange(Sender: TObject);
begin
  FChanged := true;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.chbBackgroundChange(Sender: TObject);
begin
  FChanged := true;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.chbSortedChange(Sender: TObject);
begin
  FChanged := true;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.tbHueChange(Sender: TObject);
begin
  FChanged := true;
  color_data := byte(tbHue.Position) +
    byte(tbSat.Position) shl 8 +
    byte(tbBr.Position) shl 16 +
    byte(tbCont.Position) shl 24;
  DrawFit;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.btnDefaultColorClick(Sender: TObject);
begin
  FChanged := true;
  color_data      := DEF_COLOR_DATA;
  tbHue.OnChange  := nil;
  tbSat.OnChange  := nil;
  tbBr.OnChange   := nil;
  tbCont.OnChange := nil;
  tbHue.position  := byte(color_data);
  tbSat.position  := byte(color_data shr 8);
  tbBr.position   := byte(color_data shr 16);
  tbCont.position := byte(color_data shr 24);
  tbHue.OnChange  := tbHueChange;
  tbSat.OnChange  := tbHueChange;
  tbBr.OnChange   := tbHueChange;
  tbCont.OnChange := tbHueChange;
  tbHueChange(nil);
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.bbIconUpClick(Sender: TObject);
var
  idx: integer;
  Item: TStackItem;
  Id: TItemId;
begin
  if not AcquireItem(Item, Id) then exit;
  try
    idx := list.ItemIndex;
    Item.SubitemMoveUp(idx);
    ReadSubitems(Item);
    if idx > 0 then dec(idx);
    list.ItemIndex := idx;
  finally
    ReleaseItemModel(Id);
  end;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.bbIconDownClick(Sender: TObject);
var
  idx: integer;
  Item: TStackItem;
  Id: TItemId;
begin
  if not AcquireItem(Item, Id) then exit;
  try
    idx := list.ItemIndex;
    Item.SubitemMoveDown(idx);
    ReadSubitems(Item);
    if idx < list.Items.Count - 1 then inc(idx);
    list.ItemIndex := idx;
  finally
    ReleaseItemModel(Id);
  end;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.bbAddIconClick(Sender: TObject);
var
  Item: TStackItem;
  Id: TItemId;
begin
  if not AcquireItem(Item, Id) then exit;
  try
    Item.AddSubitemDefault;
    ReadSubitems(Item);
  finally
    ReleaseItemModel(Id);
  end;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.bbDelIconClick(Sender: TObject);
var
  Item: TStackItem;
  Id: TItemId;
begin
  if not AcquireItem(Item, Id) then exit;
  try
    Item.DeleteSubitem(list.ItemIndex);
    ReadSubitems(Item);
  finally
    ReleaseItemModel(Id);
  end;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.bbEditIconClick(Sender: TObject);
var
  Item: TStackItem;
  Id: TItemId;
begin
  if not AcquireItem(Item, Id) then exit;
  try
    Item.SubitemConfigure(list.ItemIndex);
  finally
    ReleaseItemModel(Id);
  end;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.listDblClick(Sender: TObject);
begin
  bbEditIcon.Click;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.Draw;
var
  str: WideString;
begin
  try
    try if assigned(FImage) then GdipDisposeImage(FImage);
    except end;
    FImage := nil;

    str := ShellUTF16(UnzipPath(edImage.Text));
    LoadImage(str, 128, true, false, FImage, FIW, FIH);

    // default stack image //
    if not assigned(FImage) then
    begin
      FImage := theme.Stack.Image;
      DownscaleImage(Fimage, 128, true, FIW, FIH, false);
    end;

    DrawFit;
  except
    on e: Exception do frmmain.err('frmStackProp.Draw', e);
  end;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.iPicPaint(Sender: TObject);
begin
  DrawFit;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.DrawFit;
var
  hgdip, hbrush, hattr: Pointer;
  w_coeff, h_coeff: extended;
  matrix: ColorMatrix;
  background: cardinal;
begin
  if assigned(FImage) then
  try
    w_coeff := 1;
    h_coeff := 1;
    try
      if FIW / FIH > (iPic.Width - 2) / (iPic.Height - 2) then h_coeff := (iPic.Width - 2) * FIH / FIW / (iPic.Height - 2);
      if FIW / FIH < (iPic.Width - 2) / (iPic.Height - 2) then w_coeff := (iPic.Height - 2) * FIW / FIH / (iPic.Width - 2);
    except
    end;

    GdipCreateFromHDC(iPic.canvas.handle, hgdip);
    GdipSetInterpolationMode(hgdip, InterpolationModeHighQualityBicubic);

    background := GetRGBColorResolvingParent;
    background := SwapColor(background) or $ff000000;
    GdipCreateSolidFill(background, hbrush);
    GdipFillRectangleI(hgdip, hbrush, 0, 0, iPic.Width, iPic.Height);
    GdipDeleteBrush(hbrush);

    CreateColorMatrix(color_data, matrix);
    GdipCreateImageAttributes(hattr);
    GdipSetImageAttributesColorMatrix(hattr, ColorAdjustTypeBitmap, true, @matrix, nil, ColorMatrixFlagsDefault);

    GdipDrawImageRectRectI(hgdip, FImage,
      (iPic.Width - trunc(iPic.Width * w_coeff)) div 2, (iPic.Height - trunc(iPic.Height * h_coeff)) div 2,
      trunc(iPic.Width * w_coeff), trunc(iPic.Height * h_coeff),
      0, 0, FIW, FIH, UnitPixel, hattr, nil, nil);

    GdipDisposeImageAttributes(hattr);
    GdipDeleteGraphics(hgdip);
  except
    on e: Exception do frmmain.err('frmStackProp.DrawFit', e);
  end;
end;
//------------------------------------------------------------------------------
end.

