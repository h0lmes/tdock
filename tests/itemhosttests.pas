unit itemhosttests;

{$mode delphi}

interface

uses Windows, SysUtils, fpcunit, testregistry, itemhostu;

type
  TItemHostTests = class(TTestCase)
  private
    Entered, Left: integer;
    procedure Enter;
    procedure Leave;
  protected
    procedure TearDown; override;
  published
    procedure BindingIsParentScoped;
    procedure ScopeBalancesAfterCallbackException;
    procedure ScopeRetainsLeaveAfterUnbinding;
  end;

implementation

procedure TItemHostTests.Enter;
begin
  inc(Entered);
end;

procedure TItemHostTests.Leave;
begin
  inc(Left);
end;

procedure TItemHostTests.TearDown;
begin
  UnbindItemHost(101);
end;

procedure TItemHostTests.BindingIsParentScoped;
var services, found: TItemHostServices;
begin
  services := Default(TItemHostServices);
  services.OnEnter := Enter;
  services.OnLeave := Leave;
  BindItemHost(101, services);
  AssertTrue('Bound parent must expose its services', TryGetItemHost(101, found));
  AssertFalse(TryGetItemHost(102, found));
  AssertFalse(assigned(found.OnEnter));
  UnbindItemHost(101);
  AssertFalse(TryGetItemHost(101, found));
end;

procedure TItemHostTests.ScopeBalancesAfterCallbackException;
var services: TItemHostServices; scope: TItemHostScope; raised: boolean;
begin
  services := Default(TItemHostServices);
  services.OnEnter := Enter;
  services.OnLeave := Leave;
  BindItemHost(101, services);
  raised := false;
  try
    scope := BeginItemHostOperation(101);
    try
      raise Exception.Create('Callback failed');
    finally
      EndItemHostOperation(scope);
    end;
  except
    on Exception do raised := true;
  end;
  AssertTrue(raised);
  AssertEquals('Scope must enter before the callback', 1, Entered);
  AssertEquals('Scope must leave after callback failure', 1, Left);
  EndItemHostOperation(scope);
  AssertEquals('Ending a scope twice must not leave twice', 1, Left);
end;

procedure TItemHostTests.ScopeRetainsLeaveAfterUnbinding;
var services: TItemHostServices; scope: TItemHostScope;
begin
  services := Default(TItemHostServices);
  services.OnEnter := Enter;
  services.OnLeave := Leave;
  BindItemHost(101, services);
  scope := BeginItemHostOperation(101);
  UnbindItemHost(101);
  EndItemHostOperation(scope);
  AssertEquals(1, Entered);
  AssertEquals('Unbinding must not lose the pending leave callback', 1, Left);
end;

initialization
  RegisterTest(TItemHostTests);
end.
