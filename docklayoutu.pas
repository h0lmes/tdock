unit docklayoutu;

{$mode delphi}

interface

uses Windows, GDIPAPI;

const
  DOCK_LEFT = 0;
  DOCK_TOP = 1;
  DOCK_RIGHT = 2;
  DOCK_BOTTOM = 3;
  NO_LAYOUT_ITEM = -MaxInt;

type
  TDockLayoutInput = record
    Site: integer;
    MonitorRect, ItemsArea, ItemsArea2: Windows.TRect;
    ItemSize, BigItemSize, ItemSpacing, ZoomWidth: integer;
    CenterOffsetPercent, Margin, Margin2, WndOffset, EdgeOffset: integer;
    ZoomSizeDiff: integer;
    ZoomPosition: extended;
    OccupyFullMonitor: boolean;
  end;

  TDockLayoutItem = record
    X, Y, Size: integer;
    ExactX, ExactY, ExactSize: extended;
    IsSeparator: boolean;
  end;
  TDockLayoutItems = array of TDockLayoutItem;

  TDockGeometry = record
    X, Y, Width, Height, WidthZoomed, HeightZoomed: integer;
    BaseImageRect, BaseWindowRect: GDIPAPI.TRect;
  end;

  TDockLayoutConfiguration = record
    MonitorRect, ItemsArea, ItemsArea2: Windows.TRect;
    Margin, Margin2: integer;
  end;

  TDockLayoutSnapshot = record
    MonitorRect: Windows.TRect;
    BaseWindowRect, BaseImageRect: GDIPAPI.TRect;
    X, Y, Width, Height, WidthZoomed, HeightZoomed: integer;
    DraggingFile: boolean;
  end;

function CalculateItemLayout(const Input: TDockLayoutInput;
  const Existing: TDockLayoutItems): TDockLayoutItems;
function CalculateDockGeometry(const Input: TDockLayoutInput;
  const Items: TDockLayoutItems): TDockGeometry;
function DockBounds(const Input: TDockLayoutInput;
  const Geometry: TDockGeometry): Windows.TRect;
function ItemPositionFromPoint(const Input: TDockLayoutInput;
  const Geometry: TDockGeometry; ItemCount, Ax, Ay, Distance: integer;
  const EmptyDockBounds: Windows.TRect): extended;
function ItemRectIndexFromPoint(const Rects: array of Windows.TRect;
  Ax, Ay: integer; const EmptyDockBounds: Windows.TRect): integer;

implementation

uses Math;

function CalculateItemLayout(const Input: TDockLayoutInput;
  const Existing: TDockLayoutItems): TDockLayoutItems;
var
  I, ItemPos, BasePoint, Center: integer;
  SizeInc, Offset, BubbleIndex: extended;
  Vertical: boolean;
begin
  Result := Copy(Existing);
  Vertical := Input.Site in [DOCK_LEFT, DOCK_RIGHT];
  Center := Trunc(Input.ZoomPosition);
  if Vertical then
    BasePoint := Input.MonitorRect.Top + (Input.MonitorRect.Bottom - Input.MonitorRect.Top -
      Length(Result) * (Input.ItemSize + Input.ItemSpacing)) * Input.CenterOffsetPercent div 100
  else
    BasePoint := Input.MonitorRect.Left + (Input.MonitorRect.Right - Input.MonitorRect.Left -
      Length(Result) * (Input.ItemSize + Input.ItemSpacing)) * Input.CenterOffsetPercent div 100;
  Offset := Input.ZoomSizeDiff / 2;
  BubbleIndex := 0.5;
  while BubbleIndex < Input.ZoomWidth / 2 do
  begin
    Offset := Offset + (Input.ZoomSizeDiff - 1) *
      (Cos(PI * BubbleIndex * 2 / Input.ZoomWidth) + 1) / 2;
    BubbleIndex := BubbleIndex + 1;
  end;
  for I := 0 to High(Result) do
  begin
    SizeInc := 0;
    if Input.ZoomSizeDiff > 0 then
    begin
      if (I < Center - Input.ZoomWidth / 2) or (I > Center + Input.ZoomWidth / 2) then SizeInc := 0
      else if I = Center then SizeInc := Input.ZoomSizeDiff
      else if I < Center then SizeInc := (Input.ZoomSizeDiff - 1) *
        (Cos(PI * 2 * (I - Input.ZoomPosition + 1) / Input.ZoomWidth) + 1) / 2
      else SizeInc := (Input.ZoomSizeDiff - 1) *
        (Cos(PI * 2 * (I - Input.ZoomPosition) / Input.ZoomWidth) + 1) / 2;
    end;
    Result[I].ExactSize := Input.ItemSize + SizeInc;
    Result[I].Size := Round(Result[I].ExactSize);
    ItemPos := Input.ItemSpacing div 2 + I * (Input.ItemSize + Input.ItemSpacing);
    case Input.Site of
      DOCK_BOTTOM:
        begin
          Result[I].Y := Input.MonitorRect.Bottom - Result[I].Size - Input.Margin +
            Input.WndOffset - Input.EdgeOffset;
          if not Result[I].IsSeparator then Dec(Result[I].Y, Input.Margin2);
          Result[I].X := BasePoint + ItemPos;
        end;
      DOCK_TOP:
        begin
          Result[I].Y := Input.MonitorRect.Top + Input.Margin + Input.EdgeOffset - Input.WndOffset;
          if not Result[I].IsSeparator then Inc(Result[I].Y, Input.Margin2);
          Result[I].X := BasePoint + ItemPos;
        end;
      DOCK_LEFT:
        begin
          Result[I].X := Input.MonitorRect.Left + Input.Margin + Input.EdgeOffset - Input.WndOffset;
          if not Result[I].IsSeparator then Inc(Result[I].X, Input.Margin2);
          Result[I].Y := BasePoint + ItemPos;
        end;
      DOCK_RIGHT:
        begin
          Result[I].X := Input.MonitorRect.Right - Result[I].Size - Input.Margin +
            Input.WndOffset - Input.EdgeOffset;
          if not Result[I].IsSeparator then Dec(Result[I].X, Input.Margin2);
          Result[I].Y := BasePoint + ItemPos;
        end;
    end;
    if Input.ZoomSizeDiff > 0 then
      if Vertical then
      begin
        if I < Center then Result[I].ExactY := Result[I].Y - Offset
        else if I > Center then Result[I].ExactY := Result[I].Y + Offset
        else Result[I].ExactY := Result[I].Y - Input.ZoomSizeDiff * Frac(Input.ZoomPosition);
        Result[I].Y := Round(Result[I].ExactY);
      end
      else
      begin
        if I < Center then Result[I].ExactX := Result[I].X - Offset
        else if I > Center then Result[I].ExactX := Result[I].X + Offset
        else Result[I].ExactX := Result[I].X - Input.ZoomSizeDiff * Frac(Input.ZoomPosition);
        Result[I].X := Round(Result[I].ExactX);
      end;
  end;
  if Input.ZoomSizeDiff <= 0 then exit;
  I := Min(Center, Length(Result) - 1) - 1;
  while (I > Center - Input.ZoomWidth / 2) and (I >= 0) do
  begin
    if Vertical then
    begin
      Result[I].ExactY := Result[I + 1].ExactY - Result[I].ExactSize - Input.ItemSpacing;
      Result[I].Y := Round(Result[I].ExactY);
    end
    else
    begin
      Result[I].ExactX := Result[I + 1].ExactX - Result[I].ExactSize - Input.ItemSpacing;
      Result[I].X := Round(Result[I].ExactX);
    end;
    Dec(I);
  end;
  I := Max(Center, 0) + 1;
  while (I <= Center + Input.ZoomWidth / 2) and (I < Length(Result)) do
  begin
    if Vertical then
    begin
      Result[I].ExactY := Result[I - 1].ExactY + Result[I - 1].ExactSize + Input.ItemSpacing;
      if I = Center + Input.ZoomWidth / 2 then
        Inc(Result[I].Y, Input.ItemSize - Result[I].Size)
      else Result[I].Y := Round(Result[I].ExactY);
    end
    else
    begin
      Result[I].ExactX := Result[I - 1].ExactX + Result[I - 1].ExactSize + Input.ItemSpacing;
      if I = Center + Input.ZoomWidth / 2 then
        Inc(Result[I].X, Input.ItemSize - Result[I].Size)
      else Result[I].X := Round(Result[I].ExactX);
    end;
    Inc(I);
  end;
end;

function CalculateDockGeometry(const Input: TDockLayoutInput;
  const Items: TDockLayoutItems): TDockGeometry;
var
  Vertical: boolean;
  Count, AreaSize: integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  Vertical := Input.Site in [DOCK_LEFT, DOCK_RIGHT];
  Count := Length(Items);
  AreaSize := Count * (Input.ItemSize + Input.ItemSpacing);
  if Vertical then
  begin
    Result.Width := Input.ItemsArea.Left + Input.ItemsArea2.Left + Input.ItemSize +
      Input.ItemsArea.Right + Input.ItemsArea2.Right;
    if Input.Site = DOCK_LEFT then
      Result.WidthZoomed := Max(Result.Width, Input.ItemsArea.Left +
        Input.ItemsArea2.Left + Input.ItemSize + Input.ZoomSizeDiff)
    else
      Result.WidthZoomed := Max(Result.Width, Input.ItemsArea.Right +
        Input.ItemsArea2.Right + Input.ItemSize + Input.ZoomSizeDiff);
    if Input.Site = DOCK_LEFT then
      Result.X := Input.Margin - Input.ItemsArea.Left - Input.ItemsArea2.Left;
    if Input.OccupyFullMonitor then
      Result.Height := Input.MonitorRect.Bottom - Input.MonitorRect.Top
    else if Count > 0 then
    begin
      Result.Y := Items[0].Y - Input.ItemSpacing div 2 - Input.ItemsArea.Top -
        Input.ItemsArea2.Top - Input.MonitorRect.Top;
      Result.Height := Input.ItemsArea.Top + Input.ItemsArea2.Top +
        Items[Count - 1].Y + Items[Count - 1].Size - Items[0].Y +
        Input.ItemSpacing + Input.ItemsArea.Bottom + Input.ItemsArea2.Bottom;
    end
    else
    begin
      Result.Height := Input.ItemSize + Input.ItemsArea.Top + Input.ItemsArea.Bottom +
        Input.ItemsArea2.Top + Input.ItemsArea2.Bottom;
      Result.Y := (Input.MonitorRect.Bottom - Input.MonitorRect.Top - AreaSize) *
        Input.CenterOffsetPercent div 100 - Input.ItemsArea.Top - Input.ItemsArea2.Top +
        (AreaSize - Result.Height + Input.ItemsArea.Top + Input.ItemsArea.Bottom +
        Input.ItemsArea2.Top + Input.ItemsArea2.Bottom - Input.ItemSpacing) div 2;
    end;
    Result.BaseWindowRect.Width := Result.Width;
    if Input.Site = DOCK_RIGHT then
      Inc(Result.BaseWindowRect.Width, Input.Margin - Input.ItemsArea.Right - Input.ItemsArea2.Right);
    Result.BaseWindowRect.Height := Input.MonitorRect.Bottom - Input.MonitorRect.Top;
  end
  else
  begin
    Result.Height := Input.ItemsArea.Top + Input.ItemsArea2.Top + Input.ItemSize +
      Input.ItemsArea.Bottom + Input.ItemsArea2.Bottom;
    if Input.Site = DOCK_TOP then
      Result.HeightZoomed := Max(Result.Height, Input.ItemsArea.Top +
        Input.ItemsArea2.Top + Input.ItemSize + Input.ZoomSizeDiff)
    else
      Result.HeightZoomed := Max(Result.Height, Input.ItemsArea.Bottom +
        Input.ItemsArea2.Bottom + Input.ItemSize + Input.ZoomSizeDiff);
    if Input.Site = DOCK_TOP then
      Result.Y := Input.Margin - Input.ItemsArea.Top - Input.ItemsArea2.Top;
    if Input.OccupyFullMonitor then
      Result.Width := Input.MonitorRect.Right - Input.MonitorRect.Left
    else if Count > 0 then
    begin
      Result.X := Items[0].X - Input.ItemSpacing div 2 - Input.ItemsArea.Left -
        Input.ItemsArea2.Left - Input.MonitorRect.Left;
      Result.Width := Input.ItemsArea.Left + Input.ItemsArea2.Left +
        Items[Count - 1].X + Items[Count - 1].Size - Items[0].X +
        Input.ItemSpacing + Input.ItemsArea.Right + Input.ItemsArea2.Right;
    end
    else
    begin
      Result.Width := Input.ItemSize + Input.ItemsArea.Left + Input.ItemsArea.Right +
        Input.ItemsArea2.Left + Input.ItemsArea2.Right;
      Result.X := (Input.MonitorRect.Right - Input.MonitorRect.Left - AreaSize) *
        Input.CenterOffsetPercent div 100 - Input.ItemsArea.Left - Input.ItemsArea2.Left +
        (AreaSize - Result.Width + Input.ItemsArea.Left + Input.ItemsArea.Right +
        Input.ItemsArea2.Left + Input.ItemsArea2.Right - Input.ItemSpacing) div 2;
    end;
    Result.BaseWindowRect.Width := Input.MonitorRect.Right - Input.MonitorRect.Left;
    Result.BaseWindowRect.Height := Result.Height;
    if Input.Site = DOCK_BOTTOM then
      Inc(Result.BaseWindowRect.Height, Input.Margin - Input.ItemsArea.Bottom - Input.ItemsArea2.Bottom);
  end;
  Result.BaseImageRect.X := Result.X;
  Result.BaseImageRect.Y := Result.Y;
  Result.BaseImageRect.Width := Result.Width;
  Result.BaseImageRect.Height := Result.Height;
  Result.BaseWindowRect.X := Input.MonitorRect.Left;
  Result.BaseWindowRect.Y := Input.MonitorRect.Top;
  case Input.Site of
    DOCK_LEFT: Result.BaseWindowRect.X := Input.MonitorRect.Left - Input.WndOffset + Input.EdgeOffset;
    DOCK_TOP: Result.BaseWindowRect.Y := Input.MonitorRect.Top - Input.WndOffset + Input.EdgeOffset;
    DOCK_RIGHT: Result.BaseWindowRect.X := Input.MonitorRect.Right - Result.BaseWindowRect.Width + Input.WndOffset - Input.EdgeOffset;
    DOCK_BOTTOM: Result.BaseWindowRect.Y := Input.MonitorRect.Bottom - Result.BaseWindowRect.Height + Input.WndOffset - Input.EdgeOffset;
  end;
end;

function DockBounds(const Input: TDockLayoutInput;
  const Geometry: TDockGeometry): Windows.TRect;
begin
  Result.Left := Geometry.BaseWindowRect.X + Geometry.X;
  Result.Top := Geometry.BaseWindowRect.Y + Geometry.Y;
  Result.Right := Result.Left + Geometry.Width;
  Result.Bottom := Result.Top + Geometry.Height;
  case Input.Site of
    DOCK_LEFT: Result.Right := Max(Result.Right, Result.Left + Geometry.WidthZoomed);
    DOCK_TOP: Result.Bottom := Max(Result.Bottom, Result.Top + Geometry.HeightZoomed);
    DOCK_RIGHT: Result.Left := Min(Result.Left, Result.Right - Geometry.WidthZoomed);
    DOCK_BOTTOM: Result.Top := Min(Result.Top, Result.Bottom - Geometry.HeightZoomed);
  end;
end;

function ContainsPoint(const Bounds: Windows.TRect; Ax, Ay: integer): boolean;
begin
  Result := (Ax >= Bounds.Left) and (Ay >= Bounds.Top) and
    (Ax < Bounds.Right) and (Ay < Bounds.Bottom);
end;

function ItemPositionFromPoint(const Input: TDockLayoutInput;
  const Geometry: TDockGeometry; ItemCount, Ax, Ay, Distance: integer;
  const EmptyDockBounds: Windows.TRect): extended;
var BasePoint, AreaSize: integer; ItemArea: Windows.TRect;
begin
  Result := NO_LAYOUT_ITEM;
  if ItemCount = 0 then
  begin
    if ContainsPoint(EmptyDockBounds, Ax, Ay) then Result := 0;
    exit;
  end;
  AreaSize := ItemCount * (Input.ItemSize + Input.ItemSpacing);
  if Input.Site in [DOCK_LEFT, DOCK_RIGHT] then
  begin
    BasePoint := Input.MonitorRect.Top + (Input.MonitorRect.Bottom - Input.MonitorRect.Top -
      AreaSize) * Input.CenterOffsetPercent div 100;
    Result := (Ay - BasePoint) / (Input.ItemSize + Input.ItemSpacing);
  end
  else
  begin
    BasePoint := Input.MonitorRect.Left + (Input.MonitorRect.Right - Input.MonitorRect.Left -
      AreaSize) * Input.CenterOffsetPercent div 100;
    Result := (Ax - BasePoint) / (Input.ItemSize + Input.ItemSpacing);
  end;
  if (Result < -1) or (Result >= ItemCount + 1) then Result := NO_LAYOUT_ITEM;
  ItemArea := Input.ItemsArea;
  case Input.Site of
    DOCK_LEFT: ItemArea.Right := 0;
    DOCK_TOP: ItemArea.Bottom := 0;
    DOCK_RIGHT: ItemArea.Left := 0;
    DOCK_BOTTOM: ItemArea.Top := 0;
  end;
  case Input.Site of
    DOCK_BOTTOM:
      if (Ay < Geometry.BaseWindowRect.Y + Geometry.BaseWindowRect.Height - Input.Margin -
        Input.ItemSize - ItemArea.Top - Input.ZoomSizeDiff - Distance) or
        (Ay > Geometry.BaseWindowRect.Y + Geometry.BaseWindowRect.Height + Distance) or
        (Ax < BasePoint - Input.BigItemSize) or (Ax > BasePoint + Geometry.Width) then Result := NO_LAYOUT_ITEM;
    DOCK_LEFT:
      if (Ax < Geometry.BaseWindowRect.X - Distance) or
        (Ax > Geometry.BaseWindowRect.X + Geometry.X + Input.Margin + Input.ItemSize +
        ItemArea.Right + Input.ZoomSizeDiff + Distance) or
        (Ay < BasePoint - Input.BigItemSize) or (Ay > BasePoint + Geometry.Height) then Result := NO_LAYOUT_ITEM;
    DOCK_RIGHT:
      if (Ax < Geometry.BaseWindowRect.X + Geometry.BaseWindowRect.Width - Input.Margin -
        Input.ItemSize - ItemArea.Left - Input.ZoomSizeDiff - Distance) or
        (Ax > Geometry.BaseWindowRect.X + Geometry.BaseWindowRect.Width + Distance) or
        (Ay < BasePoint - Input.BigItemSize) or (Ay > BasePoint + Geometry.Height) then Result := NO_LAYOUT_ITEM;
    DOCK_TOP:
      if (Ay < Geometry.BaseWindowRect.Y - Distance) or
        (Ay > Geometry.BaseWindowRect.Y + Geometry.Y + Input.Margin + Input.ItemSize +
        ItemArea.Bottom + Input.ZoomSizeDiff + Distance) or
        (Ax < BasePoint - Input.BigItemSize) or (Ax > BasePoint + Geometry.Width) then Result := NO_LAYOUT_ITEM;
  end;
end;

function ItemRectIndexFromPoint(const Rects: array of Windows.TRect;
  Ax, Ay: integer; const EmptyDockBounds: Windows.TRect): integer;
var I: integer;
begin
  Result := NO_LAYOUT_ITEM;
  if Length(Rects) = 0 then
  begin
    if ContainsPoint(EmptyDockBounds, Ax, Ay) then Result := 0;
    exit;
  end;
  for I := 0 to High(Rects) do
    if ContainsPoint(Rects[I], Ax, Ay) then exit(I);
end;

end.
