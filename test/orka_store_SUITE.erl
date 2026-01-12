%% Store backend contract tests for orka_store behaviour.
-module(orka_store_SUITE).

%% Common Test callbacks
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% Tests
-export([
    test_put_get_del/1,
    test_select_by_type/1,
    test_select_by_tag/1,
    test_select_by_property/1,
    test_counts/1,
    test_property_stats/1,
    test_put_many_del_many/1
]).

-include_lib("common_test/include/ct.hrl").

-define(REGISTRY, orka_table).
-define(TAG_IDX,  orka_tag_index).
-define(PROP_IDX, orka_property_index).

all() ->
    [
        test_put_get_del,
        test_select_by_type,
        test_select_by_tag,
        test_select_by_property,
        test_counts,
        test_property_stats,
        test_put_many_del_many
    ].

init_per_suite(Config) ->
    cleanup_tables(),
    Config.

end_per_suite(_Config) ->
    cleanup_tables(),
    ok.

init_per_testcase(_TestCase, Config) ->
    cleanup_tables(),
    {ok, Store} = orka_store_ets:init(#{}),
    [{store, Store} | Config].

end_per_testcase(_TestCase, _Config) ->
    cleanup_tables(),
    ok.

test_put_get_del(Config) ->
    Store = proplists:get_value(store, Config),
    Key = {global, service, store_put_get},
    Pid = self(),
    Meta = #{tags => [service], properties => #{region => "us-west"}},

    {ok, {Key, Pid, Meta}, Store1} = orka_store_ets:put(Key, Pid, Meta, Store),
    {ok, {Key, Pid, Meta}} = orka_store_ets:get(Key, Store1),
    {ok, Store2} = orka_store_ets:del(Key, Store1),
    not_found = orka_store_ets:get(Key, Store2),
    {not_found, _} = orka_store_ets:del(Key, Store2),
    Config.

test_select_by_type(Config) ->
    Store = proplists:get_value(store, Config),
    Pid = self(),
    {ok, _, Store1} = orka_store_ets:put({global, service, a}, Pid, #{}, Store),
    {ok, _, Store2} = orka_store_ets:put({global, user, b}, Pid, #{}, Store1),
    Entries = orka_store_ets:select_by_type(service, Store2),
    true = lists:any(fun({{global, service, a}, _, _}) -> true; (_) -> false end, Entries),
    false = lists:any(fun({{global, user, _}, _, _}) -> true; (_) -> false end, Entries),
    Config.

test_select_by_tag(Config) ->
    Store = proplists:get_value(store, Config),
    Pid = self(),
    {ok, _, Store1} = orka_store_ets:put({global, service, t1}, Pid, #{tags => [alpha]}, Store),
    {ok, _, Store2} = orka_store_ets:put({global, service, t2}, Pid, #{tags => [alpha, beta]}, Store1),
    Entries = orka_store_ets:select_by_tag(alpha, Store2),
    Keys = lists:sort([K || {K, _, _} <- Entries]),
    [{global, service, t1}, {global, service, t2}] = Keys,
    Config.

test_select_by_property(Config) ->
    Store = proplists:get_value(store, Config),
    Pid = self(),
    {ok, _, Store1} = orka_store_ets:put({global, service, p1}, Pid, #{properties => #{region => "us-west"}}, Store),
    {ok, _, Store2} = orka_store_ets:put({global, service, p2}, Pid, #{properties => #{region => "us-east"}}, Store1),
    Entries = orka_store_ets:select_by_property(region, "us-west", Store2),
    [{global, service, p1}] = [K || {K, _, _} <- Entries],
    Typed = orka_store_ets:select_by_property(service, region, "us-west", Store2),
    [{global, service, p1}] = [K || {K, _, _} <- Typed],
    Config.

test_counts(Config) ->
    Store = proplists:get_value(store, Config),
    Pid = self(),
    {ok, _, Store1} = orka_store_ets:put({global, service, c1}, Pid, #{tags => [alpha]}, Store),
    {ok, _, Store2} = orka_store_ets:put({global, service, c2}, Pid, #{tags => [alpha, beta]}, Store1),
    {ok, _, Store3} = orka_store_ets:put({global, user, c3}, Pid, #{properties => #{region => "us-west"}}, Store2),
    2 = orka_store_ets:count_by_tag(alpha, Store3),
    2 = orka_store_ets:count_by_type(service, Store3),
    1 = orka_store_ets:count_by_property(region, "us-west", Store3),
    Config.

test_property_stats(Config) ->
    Store = proplists:get_value(store, Config),
    Pid = self(),
    {ok, _, Store1} = orka_store_ets:put({global, service, s1}, Pid, #{properties => #{region => "us-west"}}, Store),
    {ok, _, Store2} = orka_store_ets:put({global, service, s2}, Pid, #{properties => #{region => "us-west"}}, Store1),
    {ok, _, Store3} = orka_store_ets:put({global, service, s3}, Pid, #{properties => #{region => "us-east"}}, Store2),
    Stats = orka_store_ets:property_stats(service, region, Store3),
    2 = maps:get("us-west", Stats),
    1 = maps:get("us-east", Stats),
    Config.

test_put_many_del_many(Config) ->
    Store = proplists:get_value(store, Config),
    Pid = self(),
    Items = [
        {{global, service, m1}, Pid, #{tags => [bulk]}},
        {{global, service, m2}, Pid, #{tags => [bulk]}}
    ],
    {ok, Entries, Store1} = orka_store_ets:put_many(Items, Store),
    2 = length(Entries),
    {ok, Store2} = orka_store_ets:del_many([{global, service, m1}, {global, service, m2}], Store1),
    not_found = orka_store_ets:get({global, service, m1}, Store2),
    Config.

cleanup_tables() ->
    cleanup_table(?REGISTRY),
    cleanup_table(?TAG_IDX),
    cleanup_table(?PROP_IDX).

cleanup_table(Name) ->
    case ets:whereis(Name) of
        undefined -> ok;
        Tid -> ets:delete(Tid)
    end.
