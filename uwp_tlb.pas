unit UWP_TLB;
{$mode delphi}

interface
uses Windows, Classes, SysUtils, ComObj, ActiveX;

const
  IID_IApplicationActivationManager : TGUID = '{2E941141-7F97-4756-BA1D-9DECDE894A3D}';
  CLASS_ApplicationActivationManager : TGUID = '{45BA127D-10A8-46EA-8AB7-56EA9078943C}';
  IID_IShellItem : TGUID = '{43826D1E-E718-42EE-BC55-A1E261C37BFE}';
  IID_IShellItemArray : TGUID = '{B63EA76D-1F85-456F-A19C-48159EFA858B}';
  ActivateOptionNone = $00000000;  // No flags set
  ActivateOptionDesignMode = $00000001;  // The application is being activated for design mode, and thus will not be able to
  // to create an immersive window. Window creation must be done by design tools which
  // load the necessary components by communicating with a designer-specified service on
  // the site chain established on the activation manager.  The splash screen normally
  // shown when an application is activated will also not appear.  Most activations
  // will not use this flag.
  ActivateOptionNoErrorUI = $00000002;  // Do not show an error dialog if the app fails to activate.
  ActivateOptionNoSplashScreen = $00000004;  // Do not show the splash screen when activating the app.

type

  IShellItem = interface(IUnknown)
    ['{43826D1E-E718-42EE-BC55-A1E261C37BFE}']
  end;

  IShellItemArray = interface(IUnknown)
    ['{B63EA76D-1F85-456F-A19C-48159EFA858B}']
  end;

  IApplicationActivationManager = interface(IUnknown)
    ['{2E941141-7F97-4756-BA1D-9DECDE894A3D}']
    // Activates the specified immersive application for the "Launch" contract, passing the provided arguments
    // string into the application.  Callers can obtain the process Id of the application instance fulfilling this contract.
    function ActivateApplication(appUserModelId: LPCWSTR; arguments: LPCWSTR; options: UInt32; out processId: UInt32): HRESULT; stdcall;
    function ActivateForFile(appUserModelId: LPCWSTR; itemArray: IShellItemArray; verb: LPCWSTR; out processId: UInt32): HRESULT; stdcall;
    function ActivateForProtocol(appUserModelId: LPCWSTR; itemArray: IShellItemArray; out processId: UInt32): HRESULT; stdcall;
  end;

  ApplicationActivationManager = class
  private
    intf: IApplicationActivationManager;
    FCreationStatus: HRESULT;
  public
    constructor Create; overload;
    constructor Create(const Manager: IApplicationActivationManager; CreationStatus: HRESULT); overload;
    function ActivateApplication(appUserModelId: LPCWSTR; out processId: UInt32;
      arguments: LPCWSTR = nil): HRESULT;
    function ActivateForFile(appUserModelId: LPCWSTR; Items: IShellItemArray;
      out processId: UInt32): HRESULT;
    function ActivateForProtocol(appUserModelId: LPCWSTR; Items: IShellItemArray;
      out processId: UInt32): HRESULT;
  end;

implementation

constructor ApplicationActivationManager.Create;
begin
  inherited Create;
  FCreationStatus := CoCreateInstance(CLASS_ApplicationActivationManager, nil, CLSCTX_LOCAL_SERVER, IApplicationActivationManager, intf);
end;

constructor ApplicationActivationManager.Create(const Manager: IApplicationActivationManager; CreationStatus: HRESULT);
begin
  inherited Create;
  intf := Manager;
  FCreationStatus := CreationStatus;
end;

function ApplicationActivationManager.ActivateApplication(appUserModelId: LPCWSTR; out processId: UInt32;
  arguments: LPCWSTR): HRESULT;
begin
  processId := 0;
  if FCreationStatus < 0 then Exit(FCreationStatus);
  if not Assigned(intf) then Exit(E_NOINTERFACE);
  Result := intf.ActivateApplication(appUserModelId, arguments, ActivateOptionNoErrorUI, processId);
end;

function ApplicationActivationManager.ActivateForFile(appUserModelId: LPCWSTR;
  Items: IShellItemArray; out processId: UInt32): HRESULT;
begin
  processId := 0;
  if FCreationStatus < 0 then Exit(FCreationStatus);
  if not Assigned(intf) then Exit(E_NOINTERFACE);
  if Items = nil then Exit(E_INVALIDARG);
  Result := intf.ActivateForFile(appUserModelId, Items, 'open', processId);
end;

function ApplicationActivationManager.ActivateForProtocol(appUserModelId: LPCWSTR;
  Items: IShellItemArray; out processId: UInt32): HRESULT;
begin
  processId := 0;
  if FCreationStatus < 0 then Exit(FCreationStatus);
  if not Assigned(intf) then Exit(E_NOINTERFACE);
  if Items = nil then Exit(E_INVALIDARG);
  Result := intf.ActivateForProtocol(appUserModelId, Items, processId);
end;

end.

