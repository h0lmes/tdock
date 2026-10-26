unit itemregistryu;

{$mode delphi}

interface
uses itemviewu;

type
  { Compatibility names. Native bindings live only in itemviewu. }
  TItemIdentity = itemviewu.TItemIdentity;
  TItemIdentities = itemviewu.TItemIdentities;
  TItemOwnershipEvent = itemviewu.TItemOwnershipEvent;
  TItemRegistry = itemviewu.TItemViewAdapter;

function ItemRegistry: TItemRegistry;
implementation
function ItemRegistry: TItemRegistry;
begin Result := ItemViews; end;
end.
