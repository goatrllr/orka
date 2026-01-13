%% File: apps/orka/src/orka_scope.erl
-module(orka_scope).

-export([route/1, store_for/2, default_scope/1, get_store/2, put_store/3]).

-include("orka.hrl").

-type scope() :: local | global.

%% NOTE: This module is intentionally dumb: no ETS, no RA calls.
%% It is pure policy / routing.

-spec route(term()) -> scope().
route(Key) ->
    case Key of
        {local, _Type, _Name}  -> local;
        {global, _Type, _Name} -> global;
        %% Common compatibility forms:
        {local, _Any}  -> local;
        {global, _Any} -> global;
        _Other ->
            %% Unscoped keys are routed by policy (default local)
            default_scope(Key)
    end.

%% You can evolve this later to be configurable, e.g. application env.
-spec default_scope(term()) -> scope().
default_scope(_Key) ->
    local.

%% `State` is the orka gen_server state. Keep this function tiny and fast.
-spec store_for(scope(), State :: #orka_state{}) -> {module(), term()}.
store_for(Scope, State) ->
    get_store(Scope, State).

-spec get_store(scope(), State :: #orka_state{}) -> {module(), term()}.
get_store(local, #orka_state{local_store = Store}) -> Store;
get_store(global, #orka_state{global_store = Store}) -> Store.

-spec put_store(scope(), {module(), term()}, #orka_state{}) -> #orka_state{}.
put_store(local, Store, State) ->
    State#orka_state{local_store = Store};
put_store(global, Store, State) ->
    State#orka_state{global_store = Store}.
