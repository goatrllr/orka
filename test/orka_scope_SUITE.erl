%% Scope behavior tests for local/global stores.
-module(orka_scope_SUITE).

%% Common Test callbacks
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% Tests
-export([
    test_scope_lookup_isolation/1,
    test_scope_entries_by_tag/1,
    test_scope_counts_and_property_stats/1
]).

-include_lib("common_test/include/ct.hrl").

-define(LOCAL_PREFIX, orka_local).
-define(GLOBAL_PREFIX, orka_global).

all() ->
    [
        test_scope_lookup_isolation,
        test_scope_entries_by_tag,
        test_scope_counts_and_property_stats
    ].

init_per_suite(Config) ->
    cleanup_tables(),
    Config.

end_per_suite(_Config) ->
    cleanup_tables(),
    ok.

init_per_testcase(_TestCase, Config) ->
    cleanup_tables(),
    application:unset_env(orka, local_store_opts),
    application:unset_env(orka, global_store_opts),
    application:set_env(orka, local_store_opts, #{table_prefix => ?LOCAL_PREFIX}),
    application:set_env(orka, global_store_opts, #{table_prefix => ?GLOBAL_PREFIX}),
    catch application:stop(orka),
    timer:sleep(50),
    ok = application:start(orka),
    timer:sleep(50),
    Config.

end_per_testcase(_TestCase, _Config) ->
    catch application:stop(orka),
    application:unset_env(orka, local_store_opts),
    application:unset_env(orka, global_store_opts),
    cleanup_tables(),
    ok.

test_scope_lookup_isolation(Config) ->
    LocalKey = {local, service, local_one},
    GlobalKey = {global, service, global_one},
    LocalPid = spawn(fun() -> timer:sleep(10000) end),
    GlobalPid = spawn(fun() -> timer:sleep(10000) end),
    Meta = #{tags => [alpha], properties => #{region => "us"}},

    {ok, _} = orka:register(LocalKey, LocalPid, Meta),
    {ok, _} = orka:register(GlobalKey, GlobalPid, Meta),

    {ok, {LocalKey, LocalPid, _}} = orka:lookup(LocalKey),
    {ok, {GlobalKey, GlobalPid, _}} = orka:lookup(GlobalKey),

    LocalEntries = orka:lookup_all(),
    true = has_key(LocalKey, LocalEntries),
    false = has_key(GlobalKey, LocalEntries),

    GlobalEntries = orka:lookup_all(global),
    true = has_key(GlobalKey, GlobalEntries),
    false = has_key(LocalKey, GlobalEntries),

    AllEntries = orka:lookup_all(all),
    true = has_key(LocalKey, AllEntries),
    true = has_key(GlobalKey, AllEntries),
    Config.

test_scope_entries_by_tag(Config) ->
    LocalKey = {local, service, tag_local},
    GlobalKey = {global, service, tag_global},
    LocalPid = spawn(fun() -> timer:sleep(10000) end),
    GlobalPid = spawn(fun() -> timer:sleep(10000) end),

    {ok, _} = orka:register(LocalKey, LocalPid, #{tags => [alpha]}),
    {ok, _} = orka:register(GlobalKey, GlobalPid, #{tags => [alpha]}),

    LocalEntries = orka:entries_by_tag(alpha),
    true = has_key(LocalKey, LocalEntries),
    false = has_key(GlobalKey, LocalEntries),

    GlobalEntries = orka:entries_by_tag(alpha, global),
    true = has_key(GlobalKey, GlobalEntries),
    false = has_key(LocalKey, GlobalEntries),

    AllEntries = orka:entries_by_tag(alpha, all),
    true = has_key(LocalKey, AllEntries),
    true = has_key(GlobalKey, AllEntries),
    Config.

test_scope_counts_and_property_stats(Config) ->
    LocalKey = {local, service, prop_local},
    GlobalKey = {global, service, prop_global},
    LocalPid = spawn(fun() -> timer:sleep(10000) end),
    GlobalPid = spawn(fun() -> timer:sleep(10000) end),

    {ok, _} = orka:register(LocalKey, LocalPid, #{properties => #{region => us}}),
    {ok, _} = orka:register(GlobalKey, GlobalPid, #{properties => #{region => us}}),

    1 = orka:count_by_type(service),
    1 = orka:count_by_type(service, global),
    2 = orka:count_by_type(service, all),

    #{<<"us">> := 1} = orka:property_stats(service, region),
    #{<<"us">> := 1} = orka:property_stats(service, region, global),
    #{<<"us">> := 2} = orka:property_stats(service, region, all),

    GlobalEntries = orka:find_by_property(service, region, us, global),
    true = has_key(GlobalKey, GlobalEntries),
    false = has_key(LocalKey, GlobalEntries),
    Config.

has_key(Key, Entries) ->
    lists:any(fun({EntryKey, _Pid, _Meta}) -> EntryKey =:= Key end, Entries).

cleanup_tables() ->
    cleanup_prefix(?LOCAL_PREFIX),
    cleanup_prefix(?GLOBAL_PREFIX),
    ok.

cleanup_prefix(Prefix) ->
    delete_table(table_name(Prefix, "_table")),
    delete_table(table_name(Prefix, "_tag_index")),
    delete_table(table_name(Prefix, "_property_index")).

delete_table(Name) ->
    case ets:whereis(Name) of
        undefined -> ok;
        Tid -> ets:delete(Tid)
    end.

table_name(Prefix, Suffix) ->
    list_to_atom(atom_to_list(Prefix) ++ Suffix).
