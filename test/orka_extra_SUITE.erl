-module(orka_extra_SUITE).

%% Callbacks
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% Tests
-export([
		 test_find_by_property_with_scoped_key_type/1,
	test_property_stats_uses_property_name/1,
	test_register_with_preserves_live_tags/1,
	test_register_single_returns_existing/1
	]).

-include_lib("common_test/include/ct.hrl").

%%====================================================================
%% Common Test Callbacks
%%====================================================================

all() ->
	[
		test_find_by_property_with_scoped_key_type,
	test_property_stats_uses_property_name,
	test_register_with_preserves_live_tags,
	test_register_single_returns_existing
	].

init_per_suite(Config) ->
	application:stop(orka),
	timer:sleep(50),
	ok = application:start(orka),
	timer:sleep(100),
	Config.

end_per_suite(_Config) ->
	application:stop(orka),
	ok.

init_per_testcase(_TestCase, Config) ->
	catch application:stop(orka),
	timer:sleep(100),
	ok = application:start(orka),
	timer:sleep(100),
	Config.

end_per_testcase(_TestCase, _Config) ->
	ok.

%%====================================================================
%% Test Cases
%%====================================================================

%% @doc find_by_property/3 should filter by Type for {Scope, Type, Name} keys.
%% This fails because the implementation checks element(1) instead of element(2).
test_find_by_property_with_scoped_key_type(Config) ->
	Key1 = {global, service, cache_1},
	Key2 = {local, service, cache_2},
	Key3 = {global, resource, db_1},

	Pid1 = spawn(fun() -> timer:sleep(10000) end),
	Pid2 = spawn(fun() -> timer:sleep(10000) end),
	Pid3 = spawn(fun() -> timer:sleep(10000) end),

	{ok, _} = orka:register(Key1, Pid1, #{tags => [cache]}),
	ok = orka:register_property(Key1, Pid1, #{property => status, value => "healthy"}),

	{ok, _} = orka:register(Key2, Pid2, #{tags => [cache]}),
	ok = orka:register_property(Key2, Pid2, #{property => status, value => "healthy"}),

	{ok, _} = orka:register(Key3, Pid3, #{tags => [db]}),
	ok = orka:register_property(Key3, Pid3, #{property => status, value => "healthy"}),

	Entries = orka:find_by_property(service, status, "healthy"),
	2 = length(Entries),
	true = lists:any(fun({K, _, _}) -> K =:= Key1 end, Entries),
	true = lists:any(fun({K, _, _}) -> K =:= Key2 end, Entries),
	false = lists:any(fun({K, _, _}) -> K =:= Key3 end, Entries),

	ct:log("✓ find_by_property/3 filters by type for scoped keys"),
	Config.

%% @doc property_stats/2 should use the second argument as property name.
%% This fails because the implementation uses the first argument as the property name.
test_property_stats_uses_property_name(Config) ->
	Key1 = {global, service, s1},
	Key2 = {global, service, s2},
	Key3 = {global, service, s3},

	Pid1 = spawn(fun() -> timer:sleep(10000) end),
	Pid2 = spawn(fun() -> timer:sleep(10000) end),
	Pid3 = spawn(fun() -> timer:sleep(10000) end),

	{ok, _} = orka:register(Key1, Pid1, #{tags => [service]}),
	ok = orka:register_property(Key1, Pid1, #{property => region, value => "us-west"}),

	{ok, _} = orka:register(Key2, Pid2, #{tags => [service]}),
	ok = orka:register_property(Key2, Pid2, #{property => region, value => "us-west"}),

	{ok, _} = orka:register(Key3, Pid3, #{tags => [service]}),
	ok = orka:register_property(Key3, Pid3, #{property => region, value => "us-east"}),

	Stats = orka:property_stats(service, region),
	#{"us-west" := 2, "us-east" := 1} = Stats,

	ct:log("✓ property_stats/2 counts by property name"),
	Config.

%% @doc register_with/3 should not mutate tags for a live registration.
test_register_with_preserves_live_tags(Config) ->
	Key = {global, service, tag_index_test},
	Pid1 = spawn(fun() -> timer:sleep(10000) end),

	{ok, _} = orka:register(Key, Pid1, #{tags => [old_tag]}),
	{ok, {Key, Pid1, _}} = orka:register_with(Key, #{tags => [new_tag]},
		{erlang, spawn, [fun() -> timer:sleep(10000) end]}),

	OldEntries = orka:entries_by_tag(old_tag),
	NewEntries = orka:entries_by_tag(new_tag),

	true = lists:any(fun({K, _, _}) -> K =:= Key end, OldEntries),
	false = lists:any(fun({K, _, _}) -> K =:= Key end, NewEntries),

	ct:log("✓ register_with/3 leaves tags unchanged for live entries"),
	Config.

%% @doc Re-registering a singleton should return the existing entry unchanged.
test_register_single_returns_existing(Config) ->
	Key = {global, service, singleton_meta},
	Meta1 = #{tags => [service], version => 1},
	Meta2 = #{tags => [service, updated], version => 2},

	{ok, {Key, Pid, Meta1}} = orka:register_single(Key, Meta1),
	{ok, {Key, Pid, Meta1}} = orka:register_single(Key, Pid, Meta2),

	{ok, {Key, Pid, Meta1}} = orka:lookup(Key),

	ct:log("✓ register_single/3 returns existing entry on idempotent call"),
	Config.
