-module(orca_registry_SUITE).

%% Callbacks
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% Tests
-export([
	test_register_and_lookup/1,
	test_register_with_pid/1,
	test_self_register/1,
	test_lookup_not_found/1,
	test_unregister/1,
	test_unregister_not_found/1,
	test_lookup_all/1,
	test_process_cleanup_on_exit/1,
	test_multiple_services_per_user/1,
	test_nested_keys/1,
	test_re_register_same_key/1,
	test_metadata_preservation/1
]).

-include_lib("common_test/include/ct.hrl").

%%====================================================================
%% Common Test Callbacks
%%====================================================================

all() ->
	[
		test_register_and_lookup,
		test_register_with_pid,
		test_self_register,
		test_lookup_not_found,
		test_unregister,
		test_unregister_not_found,
		test_lookup_all,
		test_process_cleanup_on_exit,
		test_multiple_services_per_user,
		test_nested_keys,
		test_re_register_same_key,
		test_metadata_preservation
	].

init_per_suite(Config) ->
	%% Start the orca application
	ok = application:start(orca),
	%% Wait for registry to initialize
	timer:sleep(100),
	Config.

end_per_suite(_Config) ->
	application:stop(orca),
	ok.

init_per_testcase(_TestCase, Config) ->
	%% Clear registry before each test
	case ets:info(orca_registry_table) of
		undefined -> ok;
		_ -> ets:delete_all_objects(orca_registry_table)
	end,
	Config.

end_per_testcase(_TestCase, _Config) ->
	ok.

%%====================================================================
%% Test Cases
%%====================================================================

%% @doc Test basic registration and lookup
test_register_and_lookup(Config) ->
	Key = {user1, service_a},
	Pid = spawn(fun() -> timer:sleep(10000) end),
	Metadata = #{status => active, version => 1},

	ok = orca_registry:register(Key, Pid, Metadata),

	{ok, {Key, Pid, Metadata}} = orca_registry:lookup(Key),

	ct:log("✓ Successfully registered and looked up entry"),
	Config.

%% @doc Test registration with explicit Pid (supervisor registration)
test_register_with_pid(Config) ->
	Key = {user2, service_b},
	Pid = spawn(fun() -> timer:sleep(10000) end),
	Metadata = #{role => worker},

	ok = orca_registry:register(Key, Pid, Metadata),

	{ok, {Key, Pid, Metadata}} = orca_registry:lookup(Key),

	ct:log("✓ Supervisor-style registration works"),
	Config.

%% @doc Test self-registration (2-argument form)
test_self_register(Config) ->
	Key = {user3, service_c},
	Metadata = #{auto_register => true},

	ok = orca_registry:register(Key, Metadata),

	{ok, {Key, Self, Metadata}} = orca_registry:lookup(Key),
	Self = self(),

	ct:log("✓ Self-registration works"),
	Config.

%% @doc Test lookup of non-existent key
test_lookup_not_found(Config) ->
	Key = {user_nonexistent, service},

	not_found = orca_registry:lookup(Key),

	ct:log("✓ Lookup returns not_found for missing key"),
	Config.

%% @doc Test unregistration
test_unregister(Config) ->
	Key = {user4, service_d},
	Pid = spawn(fun() -> timer:sleep(10000) end),
	Metadata = #{temp => true},

	ok = orca_registry:register(Key, Pid, Metadata),
	{ok, _} = orca_registry:lookup(Key),

	ok = orca_registry:unregister(Key),

	not_found = orca_registry:lookup(Key),

	ct:log("✓ Unregister removes entry from registry"),
	Config.

%% @doc Test unregistration of non-existent key
test_unregister_not_found(Config) ->
	Key = {user_nonexistent, service},

	not_found = orca_registry:unregister(Key),

	ct:log("✓ Unregister returns not_found for missing key"),
	Config.

%% @doc Test lookup_all returns all entries
test_lookup_all(Config) ->
	Key1 = {user1, svc1},
	Key2 = {user2, svc2},
	Key3 = {user3, svc3},

	Pid1 = spawn(fun() -> timer:sleep(10000) end),
	Pid2 = spawn(fun() -> timer:sleep(10000) end),
	Pid3 = spawn(fun() -> timer:sleep(10000) end),

	ok = orca_registry:register(Key1, Pid1, #{id => 1}),
	ok = orca_registry:register(Key2, Pid2, #{id => 2}),
	ok = orca_registry:register(Key3, Pid3, #{id => 3}),

	AllEntries = orca_registry:lookup_all(),

	3 = length(AllEntries),
	true = lists:member({Key1, Pid1, #{id => 1}}, AllEntries),
	true = lists:member({Key2, Pid2, #{id => 2}}, AllEntries),
	true = lists:member({Key3, Pid3, #{id => 3}}, AllEntries),

	ct:log("✓ lookup_all returns all registered entries"),
	Config.

%% @doc Test automatic cleanup when process exits
test_process_cleanup_on_exit(Config) ->
	Key = {user5, service_e},
	Pid = spawn(fun() -> timer:sleep(50) end),
	Metadata = #{cleanup_test => true},

	ok = orca_registry:register(Key, Pid, Metadata),
	{ok, {Key, Pid, Metadata}} = orca_registry:lookup(Key),

	%% Wait for process to exit
	timer:sleep(200),

	%% Entry should be automatically removed
	not_found = orca_registry:lookup(Key),

	ct:log("✓ Automatic cleanup on process exit works"),
	Config.

%% @doc Test multiple services registered for same user
test_multiple_services_per_user(Config) ->
	User = user123,
	ServiceA = {User, service_a},
	ServiceB = {User, service_b},
	ServiceC = {User, service_c},

	PidA = spawn(fun() -> timer:sleep(10000) end),
	PidB = spawn(fun() -> timer:sleep(10000) end),
	PidC = spawn(fun() -> timer:sleep(10000) end),

	ok = orca_registry:register(ServiceA, PidA, #{service => a}),
	ok = orca_registry:register(ServiceB, PidB, #{service => b}),
	ok = orca_registry:register(ServiceC, PidC, #{service => c}),

	{ok, {ServiceA, PidA, _}} = orca_registry:lookup(ServiceA),
	{ok, {ServiceB, PidB, _}} = orca_registry:lookup(ServiceB),
	{ok, {ServiceC, PidC, _}} = orca_registry:lookup(ServiceC),

	%% Unregister one service, others should remain
	ok = orca_registry:unregister(ServiceB),

	{ok, {ServiceA, PidA, _}} = orca_registry:lookup(ServiceA),
	not_found = orca_registry:lookup(ServiceB),
	{ok, {ServiceC, PidC, _}} = orca_registry:lookup(ServiceC),

	ct:log("✓ Multiple services per user work independently"),
	Config.

%% @doc Test nested keys (hierarchical structure)
test_nested_keys(Config) ->
	%% Support complex nested keys like {{user, "Alice"}, {service, "translator"}}
	UserId = {user, "Alice"},
	ServiceId = {service, "translator"},
	Key = {UserId, ServiceId},

	Pid = spawn(fun() -> timer:sleep(10000) end),
	Metadata = #{language => french},

	ok = orca_registry:register(Key, Pid, Metadata),

	{ok, {Key, Pid, Metadata}} = orca_registry:lookup(Key),

	ct:log("✓ Nested keys work correctly"),
	Config.

%% @doc Test re-registering same key with new Pid and metadata
test_re_register_same_key(Config) ->
	Key = {user6, service_f},
	Pid1 = spawn(fun() -> timer:sleep(10000) end),
	Pid2 = spawn(fun() -> timer:sleep(10000) end),

	ok = orca_registry:register(Key, Pid1, #{version => 1}),
	{ok, {Key, Pid1, #{version := 1}}} = orca_registry:lookup(Key),

	%% Re-register with new pid and metadata
	ok = orca_registry:register(Key, Pid2, #{version => 2}),
	{ok, {Key, Pid2, #{version := 2}}} = orca_registry:lookup(Key),

	%% Only one entry should exist for this key
	AllEntries = orca_registry:lookup_all(),
	Matches = [E || E <- AllEntries, element(1, E) =:= Key],
	1 = length(Matches),

	ct:log("✓ Re-registration updates entry correctly"),
	Config.

%% @doc Test metadata preservation with various types
test_metadata_preservation(Config) ->
	Key = {user7, service_g},
	Pid = spawn(fun() -> timer:sleep(10000) end),
	Metadata = #{
		count => 42,
		list => [a, b, c],
		map => #{nested => true},
		binary => <<"test">>,
		atom => ok,
		tuple => {x, y, z}
	},

	ok = orca_registry:register(Key, Pid, Metadata),

	{ok, {Key, Pid, RetrievedMetadata}} = orca_registry:lookup(Key),

	Metadata = RetrievedMetadata,

	ct:log("✓ Complex metadata types preserved correctly"),
	Config.
