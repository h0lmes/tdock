unit itemhostu;

{$mode delphi}

interface

uses Windows;

type
  TItemHostOperation = procedure of object;
  TItemHostWindowAction = procedure(wnd: HWND) of object;
  TItemHostNotification = procedure(message: WideString; silent: boolean) of object;
  TItemHostMouseLock = procedure(wnd: HWND; lock: boolean) of object;
  TDocumentCommand = function(Command, Parameters, Directory, Document: string;
    ShowCommand: Integer; Caller: HWND): Boolean of object;

  TItemHostServices = record
    OnEnter, OnLeave: TItemHostOperation;
    OnDelete, OnDock, OnUndock: TItemHostWindowAction;
    OnNotify: TItemHostNotification;
    OnLockMouseEffect: TItemHostMouseLock;
    OnOpenDocument: TDocumentCommand;
  end;

  TItemHostScope = record
    Services: TItemHostServices;
    Active: boolean;
  end;

procedure BindItemHost(parent: HWND; const Services: TItemHostServices);
procedure UnbindItemHost(parent: HWND);
function TryGetItemHost(parent: HWND; out Services: TItemHostServices): boolean;
function BeginItemHostOperation(parent: HWND): TItemHostScope;
procedure EndItemHostOperation(var Scope: TItemHostScope);
function ItemHostOpenDocument(Parent, Caller: HWND; Command, Parameters, Directory,
  Document: string; ShowCommand: Integer): Boolean;

implementation

type
  TItemHostBinding = record
    Parent: HWND;
    Services: TItemHostServices;
  end;

var Bindings: array of TItemHostBinding;

function HostIndex(parent: HWND): integer;
var index: integer;
begin
  result := -1;
  for index := 0 to High(Bindings) do
    if Bindings[index].Parent = parent then exit(index);
end;

procedure BindItemHost(parent: HWND; const Services: TItemHostServices);
var index: integer;
begin
  index := HostIndex(parent);
  if index < 0 then
  begin
    index := Length(Bindings);
    SetLength(Bindings, index + 1);
    Bindings[index].Parent := parent;
  end;
  Bindings[index].Services := Services;
end;

procedure UnbindItemHost(parent: HWND);
var index, i: integer;
begin
  index := HostIndex(parent);
  if index < 0 then exit;
  for i := index to High(Bindings) - 1 do Bindings[i] := Bindings[i + 1];
  SetLength(Bindings, Length(Bindings) - 1);
end;

function TryGetItemHost(parent: HWND; out Services: TItemHostServices): boolean;
var index: integer;
begin
  Services := Default(TItemHostServices);
  index := HostIndex(parent);
  result := index >= 0;
  if result then Services := Bindings[index].Services;
end;

function BeginItemHostOperation(parent: HWND): TItemHostScope;
begin
  result := Default(TItemHostScope);
  if TryGetItemHost(parent, result.Services) and assigned(result.Services.OnEnter) and
    assigned(result.Services.OnLeave) then
  begin
    result.Services.OnEnter;
    result.Active := true;
  end;
end;

procedure EndItemHostOperation(var Scope: TItemHostScope);
begin
  if not Scope.Active then exit;
  Scope.Active := false;
  Scope.Services.OnLeave;
end;

function ItemHostOpenDocument(Parent, Caller: HWND; Command, Parameters, Directory,
  Document: string; ShowCommand: Integer): Boolean;
var Scope: TItemHostScope; Services: TItemHostServices; Next: HWND;
begin
  Result := False;
  while not TryGetItemHost(Parent, Services) do
  begin
    if (Parent = 0) or not IsWindow(Parent) then Exit;
    Next := GetParent(Parent);
    if Next = Parent then Exit;
    Parent := Next;
  end;
  Scope := BeginItemHostOperation(Parent);
  try
    if Scope.Active and Assigned(Scope.Services.OnOpenDocument) then
      Result := Scope.Services.OnOpenDocument(Command, Parameters, Directory, Document, ShowCommand, Caller);
  finally EndItemHostOperation(Scope); end;
end;

end.
