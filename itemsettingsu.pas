unit itemsettingsu;

{$mode delphi}

interface

uses Windows, declu, itemmodelu;

type
  TItemRepaintEvent = procedure(ForceDraw: boolean) of object;

  TDockInteractionSnapshot = record
    HoverItem, SelectedItem, DraggedItem: TItemId;
    DraggingItem, DraggingFile, Zooming: boolean;
    DropDistance, DropPlace, DropTarget: integer;
  end;

  TItemManagerSettings = record
    ItemSize, BigItemSize, ZoomWidth, ZoomTime, ItemSpacing: integer;
    ZoomEnabled, ReflectionEnabled: boolean;
    ReflectionSize, LaunchInterval, ItemAnimationType, SeparatorAlpha: integer;
    ActivateRunning, UseShellContextMenus, LockDragging: boolean;
    StackAnimationEnabled, AeroPeekEnabled, TaskLivePreviews: boolean;
    TaskGrouping, TaskSystemMenus: boolean;
    TaskThumbSize, TaskSpot: integer;
    ShowHint: boolean;
    Font: TDFontData;
    Monitor: integer;
    Site: TBaseSite;
    CenterOffsetPercent, EdgeOffset, DropDistance: integer;
    OccupyFullMonitor, LockMouseEffect, ShowRunningIndicator, TaskSameMonitor: boolean;
  end;

implementation

end.
