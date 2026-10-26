unit applifecycleu;

{$mode delphi}

interface

type
  TApplicationPhase = (apStarting, apRunning, apClosing, apClosed);
  TApplicationLifecycle = class
  private
    FPhase: TApplicationPhase;
    FOperationDepth: Integer;
    FCloseRequested, FClosePosted: Boolean;
  public
    procedure EnterOperation;
    procedure LeaveOperation;
    procedure RequestClose;
    function TakeCloseRequest: Boolean;
    property ClosePending: Boolean read FCloseRequested;
    property OperationDepth: Integer read FOperationDepth;
    procedure Started;
    function QueryEndSession: Boolean;
    function BeginClose: Boolean;
    procedure EndClose;
    property Phase: TApplicationPhase read FPhase;
  end;

implementation

procedure TApplicationLifecycle.EnterOperation;
begin
  Inc(FOperationDepth);
end;

procedure TApplicationLifecycle.LeaveOperation;
begin
  if FOperationDepth > 0 then Dec(FOperationDepth);
end;

procedure TApplicationLifecycle.RequestClose;
begin
  if FPhase in [apStarting, apRunning] then FCloseRequested := True;
end;

function TApplicationLifecycle.TakeCloseRequest: Boolean;
begin
  Result := FCloseRequested and not FClosePosted and (FOperationDepth = 0);
  if Result then FClosePosted := True;
end;

procedure TApplicationLifecycle.Started;
begin
  if FPhase = apStarting then FPhase := apRunning;
end;

function TApplicationLifecycle.QueryEndSession: Boolean;
begin
  Result := True;
end;

function TApplicationLifecycle.BeginClose: Boolean;
begin
  if FOperationDepth > 0 then
  begin
    RequestClose;
    Exit(False);
  end;
  Result := FPhase in [apStarting, apRunning];
  if Result then
  begin FPhase := apClosing; FCloseRequested := False; FClosePosted := False; end;
end;

procedure TApplicationLifecycle.EndClose;
begin
  FPhase := apClosed;
end;

end.
