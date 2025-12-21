-module(orca_app_SUITE).

%% Callbacks
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% Tests
-export([
	test_application_start/1,
	test_application_stop/1,
	test_supervisor_tree/1,
	test_registry_available_after_start/1
]).

-include_lib("common_test/include/ct.hrl").

%%====================================================================
%% Common Test Callbacks
%%====================================================================

all() ->
	[
		test_application_start,
		test_application_stop,
		test_supervisor_tree,
		test_registry_available_after_start
	].

init_per_suite(Config) ->
	%% Ensure application is stopped before tests
	application:stop(orca),
	timer:sleep(100),
	Config.

end_per_suite(_Config) ->
	application:stop(orca),
	ok.

init_per_testcase(_TestCase, Config) ->
	Config.

end_per_testcase(_TestCase, _Config) ->
	application:stop(orca),
	timer:sleep(100),
	ok.

%%====================================================================
%% Test Cases
%%====================================================================

%% @doc Test that application starts successfully
test_application_start(Config) ->
	ok = application:start(orca),
	timer:sleep(100),

	%% Verify registry is running
	true = is_pid(whereis(orca)),

	ct:log("✓ Application started successfully"),
	Config.

%% @doc Test that application stops cleanly
test_application_stop(Config) ->
	ok = application:start(orca),
	timer:sleep(100),

	ok = application:stop(orca),
	timer:sleep(100),

	ct:log("✓ Application stopped successfully"),
	Config.

%% @doc Test supervisor tree structure
test_supervisor_tree(Config) ->
	ok = application:start(orca),
	timer:sleep(100),

	%% Verify supervisor is running
	true = is_pid(whereis(orca_sup)),

	%% Verify registry GenServer is running
	true = is_pid(whereis(orca)),

	%% Check that supervisor has orca as a child
	Pids = supervisor:which_children(orca_sup),
	true = length(Pids) >= 1,

	%% Verify orca is in the children list
	ChildIds = [Id || {Id, _Pid, _Type, _Modules} <- Pids],
	true = lists:member(orca, ChildIds),

	ct:log("✓ Supervisor tree correctly configured"),
	Config.

%% @doc Test that registry is available after application starts
test_registry_available_after_start(Config) ->
	ok = application:start(orca),
	timer:sleep(100),

	%% Try to register something
	Key = test_key,
	Pid = self(),
	Metadata = #{test => true},

	{ok, {Key, Pid, Metadata}} = orca:register(Key, Pid, Metadata),

	%% Verify we can look it up
	{ok, {Key, Pid, Metadata}} = orca:lookup(Key),

	ct:log("✓ Registry is fully operational after start"),
	Config.
