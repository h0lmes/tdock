unit docksettingsu;

{$mode delphi}

interface

uses Windows, declu;

type
  TDockSettings = record
    Monitor: integer;
    Site: TBaseSite;
    CenterOffsetPercent: integer;
    EdgeOffset: integer;
    OccupyFullMonitor: boolean; // draw the background over the entire width (or height) of the monitor
    StartOffset: integer; // for example: when Site=bsBottom this is at the left side of the dock
    EndOffset: integer; // and this is at the right side of the dock
    AutoHide: boolean;
    AutoHideTime: integer;
    AutoShowTime: integer;
    AutoHidePixels: integer;
    ItemSize: integer;
    BigItemSize: integer;
    ZoomWidth: integer;
    ItemSpacing: integer;
    ZoomEnabled: boolean;
    ZoomTime: integer;
    GlobalHotkeyFlag_Hide: boolean;
    GlobalHotkeyValue_Hide: integer;
    GlobalHotkeyFlag_Console: boolean;
    GlobalHotkeyValue_Console: integer;
    DropDistance: integer;
    LaunchInterval: integer;
    ActivateRunningApps: boolean;
    ShowRunningIndicator: boolean;
    ItemAnimationType: integer;
    LaunchInThread: boolean;
    ActivateOnMouse: boolean;
    ActivateOnMouseInterval: integer;
    CloseCmdWindow: boolean;
    HideSystemTaskbar: boolean;
    ReserveScreenEdge: boolean;
    ReserveScreenEdgePercent: integer;
    AeroPeekEnabled: boolean;
    Taskbar: boolean;
    TaskLivePreviews: boolean;
    TaskThumbSize: integer;
    TaskGrouping: boolean;
    TaskSameMonitor: boolean;
    TaskSystemMenus: boolean;
    TaskSpot: integer;
    StayOnTop: boolean;
    ShowHint: boolean;
    HintEffects: boolean;
    LockDragging: boolean;
    UseShellContextMenus: boolean;
    StackAnimationEnabled: boolean;
    AutoHideOnFullScreenApp: boolean;
    RunInThread: boolean;
    UseShell: boolean;
    Hello: boolean;
    ReflectionEnabled: boolean;
    ReflectionSize: integer;
    BaseAlpha: integer;
    SeparatorAlpha: integer;
    BlurEnabled: boolean;
    Font: TDFontData;
    Shell: array [0..MAX_PATH] of char;
    ThemeName: array [0..MAX_PATH] of char;
  end;

  PDockSettings = ^TDockSettings;

implementation

end.
