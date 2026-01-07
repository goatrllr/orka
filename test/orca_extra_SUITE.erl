-module(orca_extra_SUITE).

%% Callbacks
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% Tests
-export([
		 test_find_by_property_with_scoped_key_type/1,
		 test_property_stats_uses_property_name/1,
		 test_register_with_cleans_tag_index/1,
		 test_register_single_updates_metadata/1
	]).

-include_lib("common_test/include/ct.hrl").

%%====================================================================
%% Common Test Callbacks
%%====================================================================

all() ->
	[
		test_find_by_property_with_scoped_key_type,
		test_property_stats_uses_property_name,
		test_register_with_cleans_tag_index,
		test_register_single_updates_metadata
	].

init_per_suite(Config) ->
	application:stop(orca),
	timer:sleep(50),
	ok = application:start(orca),
	timer:sleep(100),
	Config.

end_per_suite(_Config) ->
	application:stop(orca),
	ok.

init_per_testcase(_TestCase, Config) ->
	catch application:stop(orca),
	timer:sleep(100),
	ok = application:start(orca),
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

	{ok, _} = orca:register(Key1, Pid1, #{tags => [cache]}),
	ok = orca:register_property(Key1, Pid1, #{property => status, value => "healthy"}),

	{ok, _} = orca:register(Key2, Pid2, #{tags => [cache]}),
	ok = orca:register_property(Key2, Pid2, #{property => status, value => "healthy"}),

	{ok, _} = orca:register(Key3, Pid3, #{tags => [db]}),
	ok = orca:register_property(Key3, Pid3, #{property => status, value => "healthy"}),

	Entries = orca:find_by_property(service, status, "healthy"),
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

	{ok, _} = orca:register(Key1, Pid1, #{tags => [service]}),
	ok = orca:register_property(Key1, Pid1, #{property => region, value => "us-west"}),

	{ok, _} = orca:register(Key2, Pid2, #{tags => [service]}),
	ok = orca:register_property(Key2, Pid2, #{property => region, value => "us-west"}),

	{ok, _} = orca:register(Key3, Pid3, #{tags => [service]}),
	ok = orca:register_property(Key3, Pid3, #{property => region, value => "us-east"}),

	Stats = orca:property_stats(service, region),
	#{"us-west" := 2, "us-east" := 1} = Stats,

	ct:log("✓ property_stats/2 counts by property name"),
	Config.

%% @doc register_with/3 should not leave stale tags in the tag index.
%% This fails because do_register/4 doesn't clear previous tag index entries.
test_register_with_cleans_tag_index(Config) ->
	Key = {global, service, tag_index_test},
	Pid1 = spawn(fun() -> timer:sleep(10000) end),

	{ok, _} = orca:register(Key, Pid1, #{tags => [old_tag]}),
	{ok, _Pid2} = orca:register_with(Key, #{tags => [new_tag]},
		{erlang, spawn, [fun() -> timer:sleep(10000) end]}),

	OldEntries = orca:entries_by_tag(old_tag),
	NewEntries = orca:entries_by_tag(new_tag),

	false = lists:any(fun({K, _, _}) -> K =:= Key end, OldEntries),
	true = lists:any(fun({K, _, _}) -> K =:= Key end, NewEntries),

	ct:log("✓ register_with/3 updates tag index"),
	Config.

%% @doc Re-registering a singleton under the same key should update metadata.
%% This fails because the code returns the existing entry unchanged.
test_register_single_updates_metadata(Config) ->
	Key = {global, service, singleton_meta},
	Meta1 = #{tags => [service], version => 1},
	Meta2 = #{tags => [service, updated], version => 2},

	{ok, {Key, Pid, Meta1}} = orca:register_single(Key, Meta1),
	{ok, {Key, Pid, Meta2}} = orca:register_single(Key, Pid, Meta2),

	{ok, {Key, Pid, Meta2}} = orca:lookup(Key),

	ct:log("✓ register_single/3 updates metadata on idempotent call"),
	Config.
