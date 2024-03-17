unit frmstackpropu;

interface

uses
  Windows, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  DefaultTranslator, Dialogs, StdCtrls, ExtCtrls, ComCtrls, Menus, Buttons,
  GDIPAPI, gfx, PIDL, stackitemu, themeu, DividerBevel;

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
    btnOK: TButton;
    btnApply: TButton;
    btnCancel: TButton;
    cboMode: TComboBox;
    chbBackground: TCheckBox;
    chbPreview: TCheckBox;
    chbSorted: TCheckBox;
    edCaption: TEdit;
    edImage: TEdit;
    edSpecialFolder: TEdit;
    iPic: TPaintBox;
    lblAnimationSpeed: TLabel;
    lblCaption: TLabel;
    lblDir: TLabel;
    lblDistort: TLabel;
    lblImage: TLabel;
    lblOffset: TLabel;
    lblSpecialFolder: TLabel;
    lblStyle: TLabel;
    list: TListBox;
    tbAnimationSpeed: TTrackBar;
    tbDistort: TTrackBar;
    tbOffset: TTrackBar;
    procedure bbAddIconClick(Sender: TObject);
    procedure bbDelIconClick(Sender: TObject);
    procedure bbEditIconClick(Sender: TObject);
    procedure bbIconDownClick(Sender: TObject);
    procedure bbIconUpClick(Sender: TObject);
    procedure btnBrowseImage1Click(Sender: TObject);
    procedure cboModeChange(Sender: TObject);
    procedure chbBackgroundChange(Sender: TObject);
    procedure chbPreviewChange(Sender: TObject);
    procedure chbSortedChange(Sender: TObject);
    procedure edCaptionChange(Sender: TObject);
    procedure edImageChange(Sender: TObject);
    procedure edSpecialFolderChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure btnClearImageClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
    procedure btnOKClick(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure btnApplyClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
		procedure FormShow(Sender: TObject);
    procedure listDblClick(Sender: TObject);
    procedure tbAnimationSpeedChange(Sender: TObject);
    procedure tbDistortChange(Sender: TObject);
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
    savedPreview: boolean;
    savedShowBackground: boolean;
    savedSorted: boolean;
    //
    color_data: uint;
    background_color: uint;
    SpecialFolder: string;
    ItemHWnd: HWND;
    Item: TStackItem;
    FChanged: boolean;
    FImage: Pointer;
    FIW: cardinal;
    FIH: cardinal;
    function SetData(wnd: HWND): boolean;
    procedure ReadSubitems;
    procedure iPicPaint(Sender: TObject);
    procedure Draw;
    procedure DrawFit;
  public
    class procedure Open(wnd: HWND);
  end;

var
  frmStackProp: TfrmStackProp;

{$t+}
implementation
uses declu, toolu, frmmainu, stackmodeu;
{$R *.lfm}
//------------------------------------------------------------------------------
class procedure TfrmStackProp.Open(wnd: HWND);
begin
  try
    if not assigned(frmStackProp) then Application.CreateForm(self, frmStackProp);
    if frmStackProp.SetData(wnd) then frmStackProp.Show;
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
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.FormShow(Sender: TObject);
begin
end;
//------------------------------------------------------------------------------
function TfrmStackProp.SetData(wnd: HWND): boolean;
begin
  Item := nil;
  result := false;

  if FChanged then
  begin
    if not confirm(Handle, UTF8Decode(XMsgUnsavedIconParams)) then exit;
  end;

  Item := TStackItem(GetWindowLongPtr(wnd, GWL_USERDATA));
  if not (Item is TStackItem) then exit;

  result := true;

  ItemHWnd                   := wnd;
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
  edImage.Text               := AnsiToUTF8(savedImageFile);
  edSpecialFolder.Text       := AnsiToUTF8(savedSpecialFolder);
  color_data                 := savedColorData;

  tbOffset.Position          := -1;
  tbOffset.Position          := 0;
  tbAnimationSpeed.Position  := tbAnimationSpeed.Min;
  tbDistort.Position         := -1;
  tbDistort.Position         := 0;

  cboMode.ItemIndex          := savedMode;
  tbOffset.Position          := savedOffset;
  tbAnimationSpeed.Position  := savedAnimationSpeed;
  tbDistort.Position         := savedDistort;
  chbPreview.Checked         := savedPreview;
  chbBackground.checked      := savedShowBackground;
  chbSorted.checked          := savedSorted;

  Draw;
  iPic.OnPaint := iPicPaint;

  ReadSubitems;

  // reset 'changed' state //
  FChanged := false;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.ReadSubitems;
var
  idx: integer;
begin
  list.Items.BeginUpdate;
  list.Clear;
  if item.ItemCount > 0 then
  begin
    for idx := 0 to item.ItemCount - 1 do
    begin
      list.Items.Add(UTF8Encode(Item.GetSubitemCaption(idx)));
    end;
  end;
  list.Items.EndUpdate;
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
  frmmain.BaseCmd(tcSaveSets, 0);
  Close;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.btnApplyClick(Sender: TObject);
begin
  try
    Item.Caption        := UTF8Decode(edCaption.Text);
    Item.ImageFile      := UTF8ToAnsi(edImage.Text);
    Item.SpecialFolder  := UTF8ToAnsi(edSpecialFolder.Text);
    Item.ColorData      := color_data;
    Item.Mode           := cboMode.ItemIndex;
    Item.Offset         := tbOffset.Position;
    Item.AnimationSpeed := tbAnimationSpeed.Position;
    Item.Distort        := tbDistort.Position;
    Item.Preview        := chbPreview.Checked;
    Item.ShowBackground := chbBackground.Checked;
    Item.Sorted         := chbSorted.Checked;
    Item.Update;
    FChanged := false;
  except
    on e: Exception do frmmain.err('frmStackProp.btnApplyClick', e);
  end;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.btnCancelClick(Sender: TObject);
begin
  if FChanged then
  begin
    Item.Caption        := savedCaption;
    Item.ImageFile      := savedImageFile;
    Item.SpecialFolder  := savedSpecialFolder;
    Item.ColorData      := savedColorData;
    Item.Mode           := savedMode;
    Item.Offset         := savedOffset;
    Item.AnimationSpeed := savedAnimationSpeed;
    Item.Distort        := savedDistort;
    Item.Preview        := savedPreview;
    Item.ShowBackground := savedShowBackground;
    Item.Sorted         := savedSorted;
    Item.Update;
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
  action := caFree;
  frmStackProp := nil;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.btnClearImageClick(Sender: TObject);
begin
  edImage.Clear;
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
procedure TfrmStackProp.chbBackgroundChange(Sender: TObject);
begin
  FChanged := true;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.chbPreviewChange(Sender: TObject);
begin
  FChanged := true;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.chbSortedChange(Sender: TObject);
begin
  FChanged := true;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.bbIconUpClick(Sender: TObject);
var
  idx: integer;
begin
  idx := list.ItemIndex;
  Item.SubitemMoveUp(idx);
  ReadSubitems;
  if idx > 0 then dec(idx);
  list.ItemIndex := idx;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.bbIconDownClick(Sender: TObject);
var
  idx: integer;
begin
  idx := list.ItemIndex;
  Item.SubitemMoveDown(idx);
  ReadSubitems;
  if idx < list.Items.Count - 1 then inc(idx);
  list.ItemIndex := idx;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.bbAddIconClick(Sender: TObject);
begin
  Item.AddSubitemDefault;
  ReadSubitems;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.bbDelIconClick(Sender: TObject);
begin
  Item.DeleteSubitem(list.ItemIndex);
  ReadSubitems;
end;
//------------------------------------------------------------------------------
procedure TfrmStackProp.bbEditIconClick(Sender: TObject);
begin
  Item.SubitemConfigure(list.ItemIndex);
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

    str := WideString(UnzipPath(UTF8ToAnsi(edImage.Text)));
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
  hgdip, hbrush: Pointer;
  w_coeff, h_coeff: extended;
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

    GdipDrawImageRectRectI(hgdip, FImage,
      (iPic.Width - trunc(iPic.Width * w_coeff)) div 2, (iPic.Height - trunc(iPic.Height * h_coeff)) div 2,
      trunc(iPic.Width * w_coeff), trunc(iPic.Height * h_coeff),
      0, 0, FIW, FIH, UnitPixel, nil, nil, nil);

    GdipDeleteGraphics(hgdip);
  except
    on e: Exception do frmmain.err('frmStackProp.DrawFit', e);
  end;
end;
//------------------------------------------------------------------------------
end.

