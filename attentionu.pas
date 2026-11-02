unit attentionu;

{$mode delphi}

interface

uses Windows, GDIPAPI;

const ATTENTION_BADGE_COLOR = $ffffbf00;

type
  TAttentionWindow = record
    Handle: HWND;
    ThreadId, ProcessId: DWORD;
  end;

  TAttentionWindows = record
  private
    FWindows: array of TAttentionWindow;
    function GetActive: boolean;
    function GetLastWindow: HWND;
    procedure Remove(Index: integer);
  public
    // True means a new pending request, not another flash from the same window.
    function Request(Window, Foreground: HWND): boolean;
    procedure Observe(Foreground: HWND);
    procedure Clear;
    property Active: boolean read GetActive;
    property LastWindow: HWND read GetLastWindow;
  end;

procedure DrawAttentionBadge(Graphics: Pointer; X, Y, ItemSize: integer);

implementation

uses Math, gfx;

function TAttentionWindows.GetActive: boolean;
begin Result := Length(FWindows) > 0; end;

function TAttentionWindows.GetLastWindow: HWND;
begin
  Result := 0;
  if Active then Result := FWindows[High(FWindows)].Handle;
end;

procedure TAttentionWindows.Remove(Index: integer);
var Next: integer;
begin
  for Next := Index to High(FWindows) - 1 do
    FWindows[Next] := FWindows[Next + 1];
  SetLength(FWindows, Length(FWindows) - 1);
end;

procedure TAttentionWindows.Observe(Foreground: HWND);
var Index: integer; ProcessId, ThreadId: DWORD;
begin
  for Index := High(FWindows) downto 0 do
  begin
    ProcessId := 0;
    ThreadId := GetWindowThreadProcessId(FWindows[Index].Handle, @ProcessId);
    if (ThreadId = 0) or (ThreadId <> FWindows[Index].ThreadId) or
      (ProcessId <> FWindows[Index].ProcessId) or
      (FWindows[Index].Handle = Foreground) then Remove(Index);
  end;
end;

function TAttentionWindows.Request(Window, Foreground: HWND): boolean;
var Entry: TAttentionWindow; Index: integer;
begin
  Observe(Foreground);
  Result := false;
  if (Window = 0) or (Window = Foreground) then Exit;
  Entry := Default(TAttentionWindow);
  Entry.Handle := Window;
  Entry.ThreadId := GetWindowThreadProcessId(Window, @Entry.ProcessId);
  if Entry.ThreadId = 0 then Exit;
  for Index := 0 to High(FWindows) do
    if FWindows[Index].Handle = Window then Exit(false);
  Index := Length(FWindows);
  SetLength(FWindows, Index + 1);
  FWindows[Index] := Entry;
  Result := true;
end;

procedure TAttentionWindows.Clear;
begin SetLength(FWindows, 0); end;

procedure DrawAttentionBadge(Graphics: Pointer; X, Y, ItemSize: integer);
var Brush, Family, Font, Format, Path: Pointer; Rect: GDIPAPI.TRectF;
  BadgeSize: integer;
begin
  Brush := nil; Family := nil; Font := nil; Format := nil; Path := nil;
  BadgeSize := Max(ItemSize, 40);
  Rect.Width := Round(BadgeSize * 5 / 12);
  Rect.Height := Rect.Width;
  Rect.X := X - 5;
  Rect.Y := Y - 5;
  GdipSetSmoothingMode(Graphics, SmoothingModeAntiAlias);
  GdipSetTextRenderingHint(Graphics, TextRenderingHintAntiAlias);
  try
    if GdipCreatePath(FillModeWinding, Path) <> Ok then Exit;
    AddPathRoundRect(Path, Rect, Rect.Height / 2);
    if GdipCreateSolidFill(ATTENTION_BADGE_COLOR, Brush) <> Ok then Exit;
    GdipFillPath(Graphics, Brush, Path);
    GdipDeleteBrush(Brush); Brush := nil;
    if GdipCreateFontFamilyFromName('Segoe UI', nil, Family) <> Ok then
      if GdipGetGenericFontFamilySansSerif(Family) <> Ok then Exit;
    if GdipCreateFont(Family, BadgeSize * 5 div 16, FontStyleBold, Ord(UnitPixel), Font) <> Ok then Exit;
    if GdipCreateSolidFill($ff000000, Brush) <> Ok then Exit;
    if GdipCreateStringFormat(0, 0, Format) <> Ok then Exit;
    GdipSetStringFormatAlign(Format, StringAlignmentCenter);
    GdipSetStringFormatLineAlign(Format, StringAlignmentCenter);
    GdipDrawString(Graphics, '!', 1, Font, @Rect, Format, Brush);
  finally
    if Assigned(Format) then GdipDeleteStringFormat(Format);
    if Assigned(Brush) then GdipDeleteBrush(Brush);
    if Assigned(Font) then GdipDeleteFont(Font);
    if Assigned(Family) then GdipDeleteFontFamily(Family);
    if Assigned(Path) then GdipDeletePath(Path);
  end;
end;

end.
