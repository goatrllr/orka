-module(orca_SUITE).

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
	test_metadata_preservation/1,
	test_register_property/1,
	test_find_by_property/1,
	test_find_by_property_with_type/1,
	test_count_by_property/1,
	test_property_stats/1,
	test_register_with/1,
	test_register_with_failure/1,
	test_register_single/1,
	test_register_single_constraint/1,
	test_await_already_registered/1,
	test_await_timeout/1,
	test_await_registration/1,
	test_subscribe_already_registered/1,
	test_subscribe_and_registration/1,
	test_unsubscribe/1,
	test_concurrent_subscribers/1,
	test_register_batch_basic/1,
	test_register_batch_with_explicit_pids/1,
	test_register_batch_per_user/1
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
		test_metadata_preservation,
		test_register_property,
		test_find_by_property,
		test_find_by_property_with_type,
		test_count_by_property,
		test_property_stats,
		test_register_with,
		test_register_with_failure,
		test_register_single,
		test_register_single_constraint,
		test_await_already_registered,
		test_await_timeout,
		test_await_registration,
		test_subscribe_already_registered,
		test_subscribe_and_registration,
		test_unsubscribe,
		test_concurrent_subscribers,
		test_register_batch_basic,
		test_register_batch_with_explicit_pids,
		test_register_batch_per_user
	].

init_per_suite(Config) ->
	%% Start the orca application (will be restarted per test)
	application:stop(orca),
	timer:sleep(50),
	ok = application:start(orca),
	timer:sleep(100),
	Config.

end_per_suite(_Config) ->
	application:stop(orca),
	ok.

init_per_testcase(_TestCase, Config) ->
	%% Restart application to reset all state cleanly
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

%% @doc Test basic registration and lookup
test_register_and_lookup(Config) ->
	Key = {user1, service_a},
	Pid = spawn(fun() -> timer:sleep(10000) end),
	Metadata = #{status => active, version => 1},

	{ok, _} = orca:register(Key, Pid, Metadata),

	{ok, {Key, Pid, Metadata}} = orca:lookup(Key),

	ct:log("✓ Successfully registered and looked up entry"),
	Config.

%% @doc Test registration with explicit Pid (supervisor registration)
test_register_with_pid(Config) ->
	Key = {user2, service_b},
	Pid = spawn(fun() -> timer:sleep(10000) end),
	Metadata = #{role => worker},

	{ok, _} = orca:register(Key, Pid, Metadata),

	{ok, {Key, Pid, Metadata}} = orca:lookup(Key),

	ct:log("✓ Supervisor-style registration works"),
	Config.

%% @doc Test self-registration (2-argument form)
test_self_register(Config) ->
	Key = {user3, service_c},
	Metadata = #{auto_register => true},

	{ok, {Key, Self, Metadata}} = orca:register(Key, Metadata),
	Self = self(),

	{ok, {Key, Self, Metadata}} = orca:lookup(Key),
	Self = self(),

	ct:log("✓ Self-registration works"),
	Config.

%% @doc Test lookup of non-existent key
test_lookup_not_found(Config) ->
	Key = {user_nonexistent, service},

	not_found = orca:lookup(Key),

	ct:log("✓ Lookup returns not_found for missing key"),
	Config.

%% @doc Test unregistration
test_unregister(Config) ->
	Key = {user4, service_d},
	Pid = spawn(fun() -> timer:sleep(10000) end),
	Metadata = #{temp => true},

	{ok, _} = orca:register(Key, Pid, Metadata),
	{ok, _} = orca:lookup(Key),

	ok = orca:unregister(Key),

	not_found = orca:lookup(Key),

	ct:log("✓ Unregister removes entry from registry"),
	Config.

%% @doc Test unregistration of non-existent key
test_unregister_not_found(Config) ->
	Key = {user_nonexistent, service},

	not_found = orca:unregister(Key),

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

	{ok, _} = orca:register(Key1, Pid1, #{id => 1}),
	{ok, _} = orca:register(Key2, Pid2, #{id => 2}),
	{ok, _} = orca:register(Key3, Pid3, #{id => 3}),

	AllEntries = orca:lookup_all(),

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

	{ok, _} = orca:register(Key, Pid, Metadata),
	{ok, {Key, Pid, Metadata}} = orca:lookup(Key),

	%% Wait for process to exit
	timer:sleep(200),

	%% Entry should be automatically removed
	not_found = orca:lookup(Key),

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

	{ok, _} = orca:register(ServiceA, PidA, #{service => a}),
	{ok, _} = orca:register(ServiceB, PidB, #{service => b}),
	{ok, _} = orca:register(ServiceC, PidC, #{service => c}),

	{ok, {ServiceA, PidA, _}} = orca:lookup(ServiceA),
	{ok, {ServiceB, PidB, _}} = orca:lookup(ServiceB),
	{ok, {ServiceC, PidC, _}} = orca:lookup(ServiceC),

	%% Unregister one service, others should remain
	ok = orca:unregister(ServiceB),

	{ok, {ServiceA, PidA, _}} = orca:lookup(ServiceA),
	not_found = orca:lookup(ServiceB),
	{ok, {ServiceC, PidC, _}} = orca:lookup(ServiceC),

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

	{ok, _} = orca:register(Key, Pid, Metadata),

	{ok, {Key, Pid, Metadata}} = orca:lookup(Key),

	ct:log("✓ Nested keys work correctly"),
	Config.

%% @doc Test re-registering same key with new Pid and metadata
test_re_register_same_key(Config) ->
	Key = {user6, service_f},
	Pid1 = spawn(fun() -> timer:sleep(10000) end),
	Pid2 = spawn(fun() -> timer:sleep(10000) end),

	%% First registration with Pid1
	{ok, {Key, Pid1, #{version := 1}}} = orca:register(Key, Pid1, #{version => 1}),
	{ok, {Key, Pid1, #{version := 1}}} = orca:lookup(Key),

	%% Try to re-register same key with different Pid2 - should return existing registration
	{ok, {Key, Pid1, #{version := 1}}} = orca:register(Key, Pid2, #{version => 2}),
	{ok, {Key, Pid1, #{version := 1}}} = orca:lookup(Key),

	%% Verify only one entry exists for this key
	AllEntries = orca:lookup_all(),
	Matches = [E || E <- AllEntries, element(1, E) =:= Key],
	1 = length(Matches),

	ct:log("✓ Re-registration returns existing entry when process alive"),
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

	{ok, _} = orca:register(Key, Pid, Metadata),

	{ok, {Key, Pid, RetrievedMetadata}} = orca:lookup(Key),

	Metadata = RetrievedMetadata,

	ct:log("✓ Complex metadata types preserved correctly"),
	Config.

%% @doc Test property registration
test_register_property(Config) ->
	Key1 = {service, translator_1},
	Pid1 = spawn(fun() -> timer:sleep(10000) end),
	
	Key2 = {service, translator_2},
	Pid2 = spawn(fun() -> timer:sleep(10000) end),
	
	%% Register services with properties
	{ok, _} = orca:register(Key1, Pid1, #{tags => [service, online]}),
	{ok, _} = orca:register(Key2, Pid2, #{tags => [service, online]}),
	
	%% Add property to first service
	ok = orca:register_property(Key1, Pid1, #{property => capacity, value => 100}),
	
	%% Add property to second service
	ok = orca:register_property(Key2, Pid2, #{property => capacity, value => 150}),
	
	%% Test registering property for non-existent key returns not_found
	NonexistentKey = {service, nonexistent},
	not_found = orca:register_property(NonexistentKey, self(), 
		#{property => capacity, value => 200}),
	
	ct:log("✓ Property registration works correctly"),
	Config.

%% @doc Test finding entries by property
test_find_by_property(Config) ->
	Key1 = {region, us_west_1},
	Pid1 = spawn(fun() -> timer:sleep(10000) end),
	
	Key2 = {region, us_west_2},
	Pid2 = spawn(fun() -> timer:sleep(10000) end),
	
	Key3 = {region, us_east_1},
	Pid3 = spawn(fun() -> timer:sleep(10000) end),
	
	%% Register with region properties
	{ok, _} = orca:register(Key1, Pid1, #{tags => [db]}),
	ok = orca:register_property(Key1, Pid1, #{property => region, value => "us-west"}),
	
	{ok, _} = orca:register(Key2, Pid2, #{tags => [db]}),
	ok = orca:register_property(Key2, Pid2, #{property => region, value => "us-west"}),
	
	{ok, _} = orca:register(Key3, Pid3, #{tags => [db]}),
	ok = orca:register_property(Key3, Pid3, #{property => region, value => "us-east"}),
	
	%% Find by property value
	WestEntries = orca:find_by_property(region, "us-west"),
	2 = length(WestEntries),
	true = lists:any(fun({K, _, _}) -> K =:= Key1 end, WestEntries),
	true = lists:any(fun({K, _, _}) -> K =:= Key2 end, WestEntries),
	
	EastEntries = orca:find_by_property(region, "us-east"),
	1 = length(EastEntries),
	true = lists:any(fun({K, _, _}) -> K =:= Key3 end, EastEntries),
	
	ct:log("✓ Finding entries by property works correctly"),
	Config.

%% @doc Test finding entries by property with type filtering
test_find_by_property_with_type(Config) ->
	Key1 = {service, cache_1},
	Pid1 = spawn(fun() -> timer:sleep(10000) end),
	
	Key2 = {resource, db_1},
	Pid2 = spawn(fun() -> timer:sleep(10000) end),
	
	%% Register service and resource with same property
	{ok, _} = orca:register(Key1, Pid1, #{tags => [cache]}),
	ok = orca:register_property(Key1, Pid1, #{property => status, value => "healthy"}),
	
	{ok, _} = orca:register(Key2, Pid2, #{tags => [db]}),
	ok = orca:register_property(Key2, Pid2, #{property => status, value => "healthy"}),
	
	%% Find only services with status healthy
	ServiceEntries = orca:find_by_property(service, status, "healthy"),
	1 = length(ServiceEntries),
	true = lists:any(fun({K, _, _}) -> K =:= Key1 end, ServiceEntries),
	
	%% Find only resources with status healthy
	ResourceEntries = orca:find_by_property(resource, status, "healthy"),
	1 = length(ResourceEntries),
	true = lists:any(fun({K, _, _}) -> K =:= Key2 end, ResourceEntries),
	
	ct:log("✓ Finding by property with type filtering works correctly"),
	Config.

%% @doc Test counting entries by property
test_count_by_property(Config) ->
	Key1 = {worker, w1},
	Pid1 = spawn(fun() -> timer:sleep(10000) end),
	
	Key2 = {worker, w2},
	Pid2 = spawn(fun() -> timer:sleep(10000) end),
	
	Key3 = {worker, w3},
	Pid3 = spawn(fun() -> timer:sleep(10000) end),
	
	%% Register workers with health status
	{ok, _} = orca:register(Key1, Pid1, #{tags => [worker]}),
	ok = orca:register_property(Key1, Pid1, #{property => health, value => ok}),
	
	{ok, _} = orca:register(Key2, Pid2, #{tags => [worker]}),
	ok = orca:register_property(Key2, Pid2, #{property => health, value => ok}),
	
	{ok, _} = orca:register(Key3, Pid3, #{tags => [worker]}),
	ok = orca:register_property(Key3, Pid3, #{property => health, value => warning}),
	
	%% Count healthy workers
	HealthyCount = orca:count_by_property(health, ok),
	2 = HealthyCount,
	
	%% Count warning workers
	WarningCount = orca:count_by_property(health, warning),
	1 = WarningCount,
	
	ct:log("✓ Counting by property works correctly"),
	Config.

%% @doc Test property statistics
test_property_stats(Config) ->
	Key1 = {instance, i1},
	Pid1 = spawn(fun() -> timer:sleep(10000) end),
	
	Key2 = {instance, i2},
	Pid2 = spawn(fun() -> timer:sleep(10000) end),
	
	Key3 = {instance, i3},
	Pid3 = spawn(fun() -> timer:sleep(10000) end),
	
	Key4 = {instance, i4},
	Pid4 = spawn(fun() -> timer:sleep(10000) end),
	
	%% Register instances with different capacities
	{ok, _} = orca:register(Key1, Pid1, #{tags => [instance]}),
	ok = orca:register_property(Key1, Pid1, #{property => capacity, value => 100}),
	
	{ok, _} = orca:register(Key2, Pid2, #{tags => [instance]}),
	ok = orca:register_property(Key2, Pid2, #{property => capacity, value => 100}),
	
	{ok, _} = orca:register(Key3, Pid3, #{tags => [instance]}),
	ok = orca:register_property(Key3, Pid3, #{property => capacity, value => 150}),
	
	{ok, _} = orca:register(Key4, Pid4, #{tags => [instance]}),
	ok = orca:register_property(Key4, Pid4, #{property => capacity, value => 200}),
	
	%% Get property statistics
	Stats = orca:property_stats(capacity, instance),
	
	%% Verify distribution
	#{ 100 := Count100, 150 := Count150, 200 := Count200 } = Stats,
	2 = Count100,
	1 = Count150,
	1 = Count200,
	
	ct:log("✓ Property statistics work correctly: ~p", [Stats]),
	Config.

%% @doc Test register_with/3 - start and register a process atomically
test_register_with(Config) ->
	Key = {global, service, test_service},
	Metadata = #{tags => [service, test], properties => #{version => "1.0.0"}},
	
	%% Start and register a process in one call
	{ok, Pid} = orca:register_with(Key, Metadata, {erlang, spawn, [fun() -> timer:sleep(10000) end]}),
	
	%% Verify the process is registered
	{ok, {Key, Pid, RetrievedMeta}} = orca:lookup(Key),
	RetrievedMeta = Metadata,
	
	%% Verify the process is alive
	true = is_process_alive(Pid),
	
	%% Verify it appears in lookup_all
	AllEntries = orca:lookup_all(),
	true = lists:any(fun({K, P, _}) -> K =:= Key andalso P =:= Pid end, AllEntries),
	
	ct:log("✓ register_with/3 starts and registers process atomically"),
	Config.

%% @doc Test register_with/3 with MFA that returns {ok, Pid}
test_register_with_failure(Config) ->
	Key = {global, service, failing_service},
	Metadata = #{tags => [service, test]},
	
	%% Try to register with an MFA that fails
	FailingMFA = {erlang, apply, [fun() -> error(test_error) end, []]},
	Result = orca:register_with(Key, Metadata, FailingMFA),
	
	%% Should return an error
	{error, _} = Result,
	
	%% Verify the key was not registered
	not_found = orca:lookup(Key),
	
	ct:log("✓ register_with/3 handles MFA failures correctly"),
	Config.

%% @doc Test register_single/3 - singleton constraint
test_register_single(Config) ->
	Key = {global, service, config_server},
	Metadata = #{tags => [service, config, critical], properties => #{reload_interval => 30000}},
	
	%% Register as singleton
	{ok, {Key, Pid, Metadata}} = orca:register_single(Key, Metadata),
	
	%% Verify it's registered
	{ok, {Key, Pid, Metadata}} = orca:lookup(Key),
	
	%% Verify the process is alive
	true = is_process_alive(Pid),
	
	ct:log("✓ register_single/3 registers process with singleton constraint"),
	Config.

%% @doc Test register_single constraint - prevents multiple aliases
test_register_single_constraint(Config) ->
	Key1 = {global, service, lock_manager},
	Key2 = {global, service, lock_manager_backup},
	Metadata = #{tags => [service, locks, critical]},
	
	%% Register first key as singleton
	{ok, {Key1, Pid, _}} = orca:register_single(Key1, Metadata),
	
	%% Verify it's registered
	{ok, {Key1, Pid, _}} = orca:lookup(Key1),
	
	%% Try to register the same process under a different key - should fail
	Result = orca:register_single(Key2, Pid, Metadata),
	{error, {already_registered_under_key, Key1}} = Result,
	
	%% Verify the second key is not registered
	not_found = orca:lookup(Key2),
	
	%% Verify the first key still exists
	{ok, {Key1, Pid, _}} = orca:lookup(Key1),
	
	ct:log("✓ register_single/3 enforces singleton constraint"),
	Config.

%% @doc Test await when key is already registered
test_await_already_registered(Config) ->
	Key = {global, service, database},
	Metadata = #{tags => [service, database, critical]},
	
	%% Register the key first
	{ok, {Key, Pid, Metadata}} = orca:register(Key, Metadata),
	
	%% Now await should return immediately
	Start = erlang:monotonic_time(millisecond),
	{ok, {Key, Pid, Metadata}} = orca:await(Key, 30000),
	Elapsed = erlang:monotonic_time(millisecond) - Start,
	
	%% Should be nearly instant (less than 500ms)
	true = Elapsed < 500,
	
	ct:log("✓ await/2 returns immediately when key already registered"),
	Config.

%% @doc Test await timeout when key is never registered
test_await_timeout(Config) ->
	Key = {global, service, never_registered},
	
	%% Await with short timeout
	Start = erlang:monotonic_time(millisecond),
	{error, timeout} = orca:await(Key, 100),
	Elapsed = erlang:monotonic_time(millisecond) - Start,
	
	%% Should take roughly the timeout duration
	true = Elapsed >= 90 andalso Elapsed < 500,
	
	ct:log("✓ await/2 times out correctly"),
	Config.

%% @doc Test await waiting for registration
test_await_registration(Config) ->
	Key = {global, service, slow_service},
	Metadata = #{tags => [service, slow]},
	
	%% Start a process that will register after a delay
	TestPid = self(),
	AwaitPid = spawn(fun() ->
		Result = orca:await(Key, 5000),
		TestPid ! {await_result, Result}
	end),
	
	%% Monitor the await process to detect failures
	MonitorRef = monitor(process, AwaitPid),
	
	%% Give time for await to be called
	timer:sleep(100),
	
	%% Now register the key
	{ok, {Key, RegisteredPid, Metadata}} = orca:register(Key, Metadata),
	
	%% Wait for result from AwaitPid
	{await_result, {ok, {Key, RegisteredPid, Metadata}}} = receive_timeout(2000),
	
	%% Verify AwaitPid is still alive
	demonitor(MonitorRef, [flush]),

	ct:log("✓ await/2 unblocks when key is registered"),
	Config.

%% @doc Test subscribe when key is already registered
test_subscribe_already_registered(Config) ->
	Key = {global, service, config_server},
	Metadata = #{tags => [service, config, critical]},
	
	%% Register the key first
	{ok, {Key, Pid, Metadata}} = orca:register(Key, Metadata),
	
	%% Subscribe should send notification immediately
	ok = orca:subscribe(Key),
	
	%% Should receive message immediately
	{orca_registered, Key, {Key, Pid, Metadata}} = receive_timeout(500),
	
	ct:log("✓ subscribe/1 sends immediate notification for already registered key"),
	Config.

%% @doc Test subscribe and then registration
test_subscribe_and_registration(Config) ->
	Key = {global, service, metrics_server},
	Metadata = #{tags => [service, metrics]},
	
	%% Subscribe first
	ok = orca:subscribe(Key),
	
	%% Key doesn't exist yet
	not_found = orca:lookup(Key),
	
	%% Start a process that will register
	RegisterPid = spawn(fun() ->
		timer:sleep(100),
		orca:register(Key, Metadata)
	end),
	
	%% Monitor to detect process failure
	MonitorRef = monitor(process, RegisterPid),
	
	%% Wait for notification - should be registered by the spawned RegisterPid
	{orca_registered, Key, {Key, RegisterPid, Metadata}} = receive_timeout(2000),
	
	%% Verify the spawned process completed without crashing
	demonitor(MonitorRef, [flush]),
	
	ct:log("✓ subscribe/1 receives notification when key is registered"),
	Config.

%% @doc Test unsubscribe
test_unsubscribe(Config) ->
	Key = {global, service, feature_flag},
	Metadata = #{tags => [service, feature]},
	
	%% Subscribe first
	ok = orca:subscribe(Key),
	
	%% Unsubscribe
	ok = orca:unsubscribe(Key),
	
	%% Register the key - should NOT receive notification
	{ok, {Key, _Pid, Metadata}} = orca:register(Key, Metadata),
	
	%% Try to receive message (should timeout)
	timeout = receive_timeout(200),
	
	ct:log("✓ unsubscribe/1 cancels subscription"),
	Config.

%% @doc Test concurrent subscribers
test_concurrent_subscribers(Config) ->
	Key = {global, service, shared_resource},
	Metadata = #{tags => [service, shared]},
	
	%% Have multiple subscribers
	Sub1 = spawn(fun() ->
		ok = orca:subscribe(Key),
		{orca_registered, Key, SubscriberEntry} = receive_timeout(5000),
		self() ! {got_notification, SubscriberEntry}
	end),
	
	Sub2 = spawn(fun() ->
		ok = orca:subscribe(Key),
		{orca_registered, Key, SubscriberEntry} = receive_timeout(5000),
		self() ! {got_notification, SubscriberEntry}
	end),
	
	Sub3 = spawn(fun() ->
		ok = orca:subscribe(Key),
		{orca_registered, Key, SubscriberEntry} = receive_timeout(5000),
		self() ! {got_notification, SubscriberEntry}
	end),
	
	timer:sleep(100),
	
	%% Register the key and capture the entry
	{ok, RegisteredEntry} = orca:register(Key, Metadata),
	
	%% All subscribers should receive the same entry
	wait_for_pids([Sub1, Sub2, Sub3], 3000),
	
	%% Verify the registered entry has the expected structure
	{Key, _RegistrarPid, Metadata} = RegisteredEntry,
	
	ct:log("✓ Multiple subscribers all receive notification"),
	Config.

%% @doc Test batch registration with implicit self() pids
test_register_batch_basic(Config) ->
	Key1 = {global, portfolio, user123},
	Key2 = {global, technical, user123},
	Key3 = {global, orders, user123},
	
	Meta1 = #{tags => [portfolio, user], properties => #{strategy => momentum}},
	Meta2 = #{tags => [technical, user], properties => #{indicators => [rsi]}},
	Meta3 = #{tags => [orders, user], properties => #{queue => 100}},
	
	%% Register 3 services for user in one call
	{ok, Entries} = orca:register_batch([
		{Key1, Meta1},
		{Key2, Meta2},
		{Key3, Meta3}
	]),
	
	%% Should get all 3 entries back
	3 = length(Entries),
	
	%% Each should be found
	{ok, {Key1, _, Meta1}} = orca:lookup(Key1),
	{ok, {Key2, _, Meta2}} = orca:lookup(Key2),
	{ok, {Key3, _, Meta3}} = orca:lookup(Key3),
	
	ct:log("✓ Batch registration with implicit pids works"),
	Config.

%% @doc Test batch registration with explicit Pids
test_register_batch_with_explicit_pids(Config) ->
	%% Start some dummy processes
	Pids = [spawn_link(fun() -> receive stop -> ok end end) || _ <- lists:seq(1, 3)],
	[P1, P2, P3] = Pids,
	
	Key1 = {global, worker, job1},
	Key2 = {global, worker, job2},
	Key3 = {global, worker, job3},
	
	Meta = #{tags => [worker, job]},
	
	%% Register all with explicit pids
	{ok, Entries} = orca:register_batch([
		{Key1, P1, Meta},
		{Key2, P2, Meta},
		{Key3, P3, Meta}
	]),
	
	%% Should get all 3 back
	3 = length(Entries),
	
	%% Verify Pids match
	{ok, {Key1, P1, _}} = orca:lookup(Key1),
	{ok, {Key2, P2, _}} = orca:lookup(Key2),
	{ok, {Key3, P3, _}} = orca:lookup(Key3),
	
	%% Cleanup
	lists:foreach(fun(P) -> P ! stop end, Pids),
	
	ct:log("✓ Batch registration with explicit pids works"),
	Config.

%% @doc Test batch registration for per-user services (like trading app)
test_register_batch_per_user(Config) ->
	UserId = trader_123,
	
	%% Create a supervisor to manage services (simplified)
	Services = [
		{portfolio, #{tags => [portfolio], properties => #{strategy => momentum}}},
		{technical, #{tags => [technical], properties => #{indicators => [rsi, macd]}}},
		{fundamental, #{tags => [fundamental], properties => #{sectors => [tech]}}},
		{orders, #{tags => [orders], properties => #{queue_depth => 100}}},
		{risk, #{tags => [risk], properties => #{max_position => 10000}}}
	],
	
	%% Build registration list for batch
	RegList = lists:map(fun({Service, Meta}) ->
		Key = {global, Service, UserId},
		{Key, Meta}
	end, Services),
	
	%% Register all in one batch
	{ok, Entries} = orca:register_batch(RegList),
	
	%% Should get 5 entries
	5 = length(Entries),
	
	%% Verify all are registered
	lists:foreach(fun({Service, _Meta}) ->
		Key = {global, Service, UserId},
		{ok, {Key, _Pid, _}} = orca:lookup(Key)
	end, Services),
	
	%% Query by user - should find all 5
	AllEntries = orca:lookup_all(),
	UserEntries = [E || E <- AllEntries, begin
		K = element(1, E),
		case K of
			{global, _, UserId} -> true;
			_ -> false
		end
	end],
	5 = length(UserEntries),
	
	ct:log("✓ Per-user batch registration (trading app pattern) works"),
	Config.

%% Helper functions
receive_timeout(Timeout) ->
	receive
		Msg -> Msg
	after Timeout -> timeout
	end.

wait_for_pids([], _Timeout) -> ok;
wait_for_pids([Pid | Rest], Timeout) ->
	case is_process_alive(Pid) of
		true ->
			timer:sleep(10),
			wait_for_pids([Pid | Rest], Timeout - 10);
		false ->
			wait_for_pids(Rest, Timeout)
	end.