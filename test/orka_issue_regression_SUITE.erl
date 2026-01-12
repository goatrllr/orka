-module(orka_issue_regression_SUITE).


% Implemented to fix and align singleton/property behavior. 
% Key changes are in orka.erl.

% What changed and why

% Enforced metadata validation on register/3, register_single/3, register_with/3, and update_metadata/2 to avoid map crashes, returning {error, badarg} instead.
% Singleton enforcement is now consistent: register/3 blocks non-singleton registrations for singleton PIDs, and unregister/1 only clears the singleton mapping when unregistering the singleton key.
% register_with/3 now checks existing entries first and returns the existing entry if alive (no overwrite, no new process spawned).
% Property semantics unified: metadata properties are now indexed on register/update, and register_property/3 updates metadata plus the index.
% register_single/3 now returns existing entry when already registered.

%% Common Test callbacks
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% Tests
-export([
	test_singleton_cannot_be_bypassed_via_register/1,
	test_register_with_does_not_overwrite/1,
	test_find_by_property_reads_metadata/1
]).

-include_lib("common_test/include/ct.hrl").

all() ->
	[
		test_singleton_cannot_be_bypassed_via_register,
		test_register_with_does_not_overwrite,
		test_find_by_property_reads_metadata
	].

init_per_suite(Config) ->
	catch application:stop(orka),
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

%% @doc A singleton registration should not be bypassable via register/3.
test_singleton_cannot_be_bypassed_via_register(Config) ->
	Key1 = {global, service, singleton_a},
	Key2 = {global, service, singleton_b},
	Pid = spawn(fun() -> receive after 10000 -> ok end end),

	{ok, _} = orka:register_single(Key1, Pid, #{tags => [service]}),
	Result = orka:register(Key2, Pid, #{tags => [service]}),
	case Result of
		{error, _} -> ok;
		_ -> ct:fail({expected_error, Result})
	end,
	Config.

%% @doc register_with/3 should not overwrite a live registration for the same key.
test_register_with_does_not_overwrite(Config) ->
	Key = {global, service, register_with_key},
	Pid1 = spawn(fun() -> receive after 10000 -> ok end end),

	{ok, _} = orka:register(Key, Pid1, #{tags => [service]}),
	SpawnFun = fun() -> receive after 10000 -> ok end end,
	{ok, {Key, Pid1, _}} = orka:register_with(Key, #{tags => [service]}, {erlang, spawn, [SpawnFun]}),

	{ok, {Key, LookupPid, _}} = orka:lookup(Key),
	case LookupPid =:= Pid1 of
		true -> ok;
		false -> ct:fail({expected_existing_pid, Pid1, got, LookupPid})
	end,
	Config.

%% @doc find_by_property/2 should search metadata properties without requiring register_property/3.
test_find_by_property_reads_metadata(Config) ->
	Key = {global, user, "meta_prop"},
	Metadata = #{tags => [user], properties => #{region => "us-west"}},

	{ok, _} = orka:register(Key, self(), Metadata),
	Entries = orka:find_by_property(region, "us-west"),
	case lists:keyfind(Key, 1, Entries) of
		false -> ct:fail({expected_entry, Key, Entries});
		_ -> ok
	end,
	Config.
