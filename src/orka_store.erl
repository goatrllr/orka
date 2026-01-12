%% File: apps/orka/src/orka_store.erl
-module(orka_store).

-export_type([store/0, entry/0, key/0, meta/0, scope/0, type/0]).

-type scope() :: local | global.
-type type()  :: term().
-type key()   :: term().
-type meta()  :: map().
-type entry() :: {key(), pid(), meta()}.

%% Store handle is backend-specific opaque state.
-opaque store() :: term().

%% Backend lifecycle
-callback init(Opts :: map()) -> {ok, store()} | {error, term()}.
-callback terminate(Reason :: term(), Store :: store()) -> ok.

%% Core CRUD
-callback get(Key :: key(), Store :: store()) ->
    {ok, entry()} | not_found.

-callback put(Key :: key(), Pid :: pid(), Meta :: meta(), Store :: store()) ->
    {ok, entry(), Store1 :: store()} | {error, term()}.

-callback del(Key :: key(), Store :: store()) ->
    {ok, Store1 :: store()} | {not_found, Store1 :: store()} | {error, term()}.

%% Queries (backend may optimize however it wants)
-callback select_by_type(Type :: type(), Store :: store()) -> [entry()].
-callback select_by_tag(Tag :: term(), Store :: store()) -> [entry()].
-callback select_by_property(Prop :: term(), Value :: term(), Store :: store()) -> [entry()].
-callback select_by_property(Type :: type(), Prop :: term(), Value :: term(), Store :: store()) -> [entry()].

%% Counts/stats
-callback count_by_type(Type :: type(), Store :: store()) -> non_neg_integer().
-callback count_by_tag(Tag :: term(), Store :: store()) -> non_neg_integer().
-callback count_by_property(Prop :: term(), Value :: term(), Store :: store()) -> non_neg_integer().

-callback property_stats(Type :: type(), Prop :: term(), Store :: store()) -> map().

%% Full scan
-callback all(Store :: store()) -> [entry()].

%% Optional: bulk ops (RA will love this; ETS can implement efficiently too)
-callback put_many(Items :: [{key(), pid(), meta()}], Store :: store()) ->
    {ok, [entry()], Store1 :: store()} | {error, term()}.

-callback del_many(Keys :: [key()], Store :: store()) ->
    {ok, Store1 :: store()} | {error, term()}.
