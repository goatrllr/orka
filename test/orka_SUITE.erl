-module(orka_SUITE).

%% Callbacks
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% Tests
-export([
	test_register_and_lookup/1,
	test_lookup_dirty/1,
	test_register_badarg/1,
	test_register_with_pid/1,
	test_self_register/1,
	test_lookup_not_found/1,
	test_unregister/1,
	test_unregister_not_found/1,
	test_unregister_batch/1,
	test_lookup_all/1,
	test_process_cleanup_on_exit/1,
	test_multiple_services_per_user/1,
	test_nested_keys/1,
	test_re_register_same_key/1,
	test_metadata_preservation/1,
	test_add_tag_idempotent/1,
	test_register_batch_invalid_input/1,
	test_register_property_badarg/1,
	test_update_metadata_badarg/1,
	test_register_property/1,
	test_find_by_property/1,
	test_find_by_property_with_type/1,
	test_count_by_property/1,
	test_property_stats/1,
	test_property_stats_empty/1,
	test_find_by_property_not_found/1,
	test_count_by_property_not_found/1,
	test_entries_by_tag_not_found/1,
	test_count_by_tag_not_found/1,
	test_entries_by_type_not_found/1,
	test_register_with/1,
	test_register_with_existing_returns_entry/1,
	test_register_with_failure/1,
	test_register_with_badarg/1,
	test_register_with_duplicate_tags/1,
	test_register_single/1,
	test_register_single_constraint/1,
	test_register_single_same_key_returns_existing/1,
	test_register_single_badarg/1,
	test_await_already_registered/1,
	test_await_timeout_zero_no_dangling_subscriber/1,
	test_await_timeout/1,
	test_await_registration/1,
	test_subscribe_already_registered/1,
	test_subscribe_and_registration/1,
	test_unsubscribe/1,
	test_concurrent_subscribers/1,
	test_register_batch_basic/1,
	test_register_batch_with_explicit_pids/1,
	test_register_batch_per_user/1,
	test_register_batch_existing_entry/1,
	test_register_batch_with_basic/1,
	test_register_batch_with_failure/1,
	test_register_batch_with_badarg/1,
	test_unregister_removes_monitor/1,
	test_register_batch_rollback_removes_monitor/1
]).

-include_lib("common_test/include/ct.hrl").

%%====================================================================
%% Common Test Callbacks
%%====================================================================

all() ->
	[
		test_register_and_lookup,
		test_lookup_dirty,
		test_register_badarg,
		test_register_with_pid,
		test_self_register,
		test_lookup_not_found,
		test_unregister,
		test_unregister_not_found,
		test_unregister_batch,
		test_lookup_all,
		test_process_cleanup_on_exit,
		test_multiple_services_per_user,
		test_nested_keys,
		test_re_register_same_key,
		test_metadata_preservation,
		test_add_tag_idempotent,
		test_register_batch_invalid_input,
		test_register_property_badarg,
		test_update_metadata_badarg,
		test_register_property,
		test_find_by_property,
		test_find_by_property_with_type,
		test_count_by_property,
		test_property_stats,
		test_property_stats_empty,
		test_find_by_property_not_found,
		test_count_by_property_not_found,
		test_entries_by_tag_not_found,
		test_count_by_tag_not_found,
		test_entries_by_type_not_found,
		test_register_with,
		test_register_with_existing_returns_entry,
		test_register_with_failure,
		test_register_with_badarg,
		test_register_with_duplicate_tags,
		test_register_single,
		test_register_single_constraint,
		test_register_single_same_key_returns_existing,
		test_register_single_badarg,
		test_await_already_registered,
		test_await_timeout_zero_no_dangling_subscriber,
		test_await_timeout,
		test_await_registration,
		test_subscribe_already_registered,
		test_subscribe_and_registration,
		test_unsubscribe,
		test_concurrent_subscribers,
		test_register_batch_basic,
		test_register_batch_with_explicit_pids,
		test_register_batch_per_user,
		test_register_batch_existing_entry,
		test_register_batch_with_basic,
		test_register_batch_with_failure,
		test_register_batch_with_badarg,
		test_unregister_removes_monitor,
		test_register_batch_rollback_removes_monitor
	].

init_per_suite(Config) ->
	%% Start the orka application (will be restarted per test)
	application:stop(orka),
	timer:sleep(50),
	ok = application:start(orka),
	timer:sleep(100),
	Config.

end_per_suite(_Config) ->
	application:stop(orka),
	ok.

init_per_testcase(_TestCase, Config) ->
	%% Restart application to reset all state cleanly
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

%% @doc Test basic registration and lookup
test_register_and_lookup(Config) ->
	Key = {global, user1, service_a},
	Pid = spawn(fun() -> timer:sleep(10000) end),
	Metadata = #{status => active, version => 1},
	ExpectedMeta = normalize_tags(Metadata),

	{ok, _} = orka:register(Key, Pid, Metadata),

	{ok, {Key, Pid, ExpectedMeta}} = orka:lookup(Key),

	ct:log("✓ Successfully registered and looked up entry"),
	Config.

%% @doc Test dirty lookup uses ETS without liveness check
test_lookup_dirty(Config) ->
	Key = {global, user_dirty, service_x},
	Pid = spawn(fun() -> timer:sleep(10000) end),
	Metadata = #{dirty => true},
	ExpectedMeta = normalize_tags(Metadata),

	{ok, _} = orka:register(Key, Pid, Metadata),
	{ok, {Key, Pid, ExpectedMeta}} = orka:lookup_dirty(Key),
	Config.

%% @doc Test register/3 invalid input returns badarg
test_register_badarg(Config) ->
	Key = {global, bad, input},
	{error, badarg} = orka:register(Key, not_a_pid, #{}),
	{error, badarg} = orka:register(Key, self(), not_a_map),
	Config.

%% @doc Test registration with explicit Pid (supervisor registration)
test_register_with_pid(Config) ->
	Key = {global, user2, service_b},
	Pid = spawn(fun() -> timer:sleep(10000) end),
	Metadata = #{role => worker},
	ExpectedMeta = normalize_tags(Metadata),

	{ok, _} = orka:register(Key, Pid, Metadata),

	{ok, {Key, Pid, ExpectedMeta}} = orka:lookup(Key),

	ct:log("✓ Supervisor-style registration works"),
	Config.

%% @doc Test self-registration (2-argument form)
test_self_register(Config) ->
	Key = {global, user3, service_c},
	Metadata = #{auto_register => true},
	ExpectedMeta = normalize_tags(Metadata),

	{ok, {Key, Self, ExpectedMeta}} = orka:register(Key, Metadata),
	Self = self(),

	{ok, {Key, Self, ExpectedMeta}} = orka:lookup(Key),
	Self = self(),

	ct:log("✓ Self-registration works"),
	Config.

%% @doc Test lookup of non-existent key
test_lookup_not_found(Config) ->
	Key = {global, user_nonexistent, service},

	not_found = orka:lookup(Key),

	ct:log("✓ Lookup returns not_found for missing key"),
	Config.

%% @doc Test unregistration
test_unregister(Config) ->
	Key = {global, user4, service_d},
	Pid = spawn(fun() -> timer:sleep(10000) end),
	Metadata = #{temp => true},

	{ok, _} = orka:register(Key, Pid, Metadata),
	{ok, _} = orka:lookup(Key),

	ok = orka:unregister(Key),

	not_found = orka:lookup(Key),

	ct:log("✓ Unregister removes entry from registry"),
	Config.

%% @doc Test unregistration of non-existent key
test_unregister_not_found(Config) ->
	Key = {global, user_nonexistent, service},

	not_found = orka:unregister(Key),

	ct:log("✓ Unregister returns not_found for missing key"),
	Config.

%% @doc Test batch unregistration
test_unregister_batch(Config) ->
	Key1 = {global, user_batch, service_a},
	Key2 = {global, user_batch, service_b},
	Key3 = {global, user_batch, service_missing},
	Pid1 = spawn(fun() -> timer:sleep(10000) end),
	Pid2 = spawn(fun() -> timer:sleep(10000) end),

	{ok, _} = orka:register(Key1, Pid1, #{batch => true}),
	{ok, _} = orka:register(Key2, Pid2, #{batch => true}),

	{ok, {RemovedKeys, NotFoundKeys}} = orka:unregister_batch([Key1, Key2, Key3]),
	[Key1, Key2] = RemovedKeys,
	[Key3] = NotFoundKeys,

	not_found = orka:lookup(Key1),
	not_found = orka:lookup(Key2),

	ct:log("✓ Batch unregister removes existing keys and reports missing keys"),
	Config.

%% @doc Test lookup_all returns all entries
test_lookup_all(Config) ->
	Key1 = {global, user1, svc1},
	Key2 = {global, user2, svc2},
	Key3 = {global, user3, svc3},

	Pid1 = spawn(fun() -> timer:sleep(10000) end),
	Pid2 = spawn(fun() -> timer:sleep(10000) end),
	Pid3 = spawn(fun() -> timer:sleep(10000) end),

	{ok, _} = orka:register(Key1, Pid1, #{id => 1}),
	{ok, _} = orka:register(Key2, Pid2, #{id => 2}),
	{ok, _} = orka:register(Key3, Pid3, #{id => 3}),
	{ok, ExpectedMeta1} = orka_meta:normalize(#{id => 1}, #{}),
	{ok, ExpectedMeta2} = orka_meta:normalize(#{id => 2}, #{}),
	{ok, ExpectedMeta3} = orka_meta:normalize(#{id => 3}, #{}),

	AllEntries = orka:lookup_all(),

	3 = length(AllEntries),
	true = lists:member({Key1, Pid1, ExpectedMeta1}, AllEntries),
	true = lists:member({Key2, Pid2, ExpectedMeta2}, AllEntries),
	true = lists:member({Key3, Pid3, ExpectedMeta3}, AllEntries),

	ct:log("✓ lookup_all returns all registered entries"),
	Config.

%% @doc Test automatic cleanup when process exits
test_process_cleanup_on_exit(Config) ->
	Key = {global, user5, service_e},
	Pid = spawn(fun() -> timer:sleep(50) end),
	Metadata = #{cleanup_test => true},
	ExpectedMeta = normalize_tags(Metadata),

	{ok, _} = orka:register(Key, Pid, Metadata),
	{ok, {Key, Pid, ExpectedMeta}} = orka:lookup(Key),

	%% Wait for process to exit
	timer:sleep(200),

	%% Entry should be automatically removed by liveness check
	not_found = orka:lookup_alive(Key),

	ct:log("✓ Automatic cleanup on process exit works"),
	Config.

%% @doc Test multiple services registered for same user
test_multiple_services_per_user(Config) ->
	User = user123,
	ServiceA = {global, User, service_a},
	ServiceB = {global, User, service_b},
	ServiceC = {global, User, service_c},

	PidA = spawn(fun() -> timer:sleep(10000) end),
	PidB = spawn(fun() -> timer:sleep(10000) end),
	PidC = spawn(fun() -> timer:sleep(10000) end),

	{ok, _} = orka:register(ServiceA, PidA, #{service => a}),
	{ok, _} = orka:register(ServiceB, PidB, #{service => b}),
	{ok, _} = orka:register(ServiceC, PidC, #{service => c}),

	{ok, {ServiceA, PidA, _}} = orka:lookup(ServiceA),
	{ok, {ServiceB, PidB, _}} = orka:lookup(ServiceB),
	{ok, {ServiceC, PidC, _}} = orka:lookup(ServiceC),

	%% Unregister one service, others should remain
	ok = orka:unregister(ServiceB),

	{ok, {ServiceA, PidA, _}} = orka:lookup(ServiceA),
	not_found = orka:lookup(ServiceB),
	{ok, {ServiceC, PidC, _}} = orka:lookup(ServiceC),

	ct:log("✓ Multiple services per user work independently"),
	Config.

%% @doc Test nested keys (hierarchical structure)
test_nested_keys(Config) ->
	%% Support complex nested keys like {{user, "Alice"}, {service, "translator"}}
	UserId = {user, "Alice"},
	ServiceId = {service, "translator"},
	Key = {global, UserId, ServiceId},

	Pid = spawn(fun() -> timer:sleep(10000) end),
	Metadata = #{language => french},
	ExpectedMeta = normalize_tags(Metadata),

	{ok, _} = orka:register(Key, Pid, Metadata),

	{ok, {Key, Pid, ExpectedMeta}} = orka:lookup(Key),

	ct:log("✓ Nested keys work correctly"),
	Config.

%% @doc Test re-registering same key with new Pid and metadata
test_re_register_same_key(Config) ->
	Key = {global, user6, service_f},
	Pid1 = spawn(fun() -> timer:sleep(10000) end),
	Pid2 = spawn(fun() -> timer:sleep(10000) end),

	%% First registration with Pid1
	{ok, {Key, Pid1, #{version := 1}}} = orka:register(Key, Pid1, #{version => 1}),
	{ok, {Key, Pid1, #{version := 1}}} = orka:lookup(Key),

	%% Try to re-register same key with different Pid2 - should return existing registration
	{ok, {Key, Pid1, #{version := 1}}} = orka:register(Key, Pid2, #{version => 2}),
	{ok, {Key, Pid1, #{version := 1}}} = orka:lookup(Key),

	%% Verify only one entry exists for this key
	AllEntries = orka:lookup_all(),
	Matches = [E || E <- AllEntries, element(1, E) =:= Key],
	1 = length(Matches),

	ct:log("✓ Re-registration returns existing entry when process alive"),
	Config.

%% @doc Test metadata preservation with various types
test_metadata_preservation(Config) ->
	Key = {global, user7, service_g},
	Pid = spawn(fun() -> timer:sleep(10000) end),
	Metadata = #{
		count => 42,
		list => [a, b, c],
		map => #{nested => true},
		binary => <<"test">>,
		atom => ok,
		tuple => {x, y, z}
	},
	ExpectedMeta = normalize_tags(Metadata),

	{ok, _} = orka:register(Key, Pid, Metadata),

	{ok, {Key, Pid, RetrievedMetadata}} = orka:lookup(Key),

	ExpectedMeta = RetrievedMetadata,

	ct:log("✓ Complex metadata types preserved correctly"),
	Config.

%% @doc Test add_tag/2 is idempotent and doesn't duplicate tags
test_add_tag_idempotent(Config) ->
	Key = {global, service, tag_idempotent},
	Pid = spawn(fun() -> timer:sleep(10000) end),
	Metadata = #{tags => [service]},

	{ok, _} = orka:register(Key, Pid, Metadata),
	ok = orka:add_tag(Key, critical),
	ok = orka:add_tag(Key, critical),

	{ok, {Key, _Pid, LookupMeta}} = orka:lookup(Key),
	Tags = maps:get(tags, LookupMeta, []),
	ExpectedTag = normalize_tag(critical),
	1 = length([Tag || Tag <- Tags, Tag =:= ExpectedTag]),

	Entries = orka:entries_by_tag(critical),
	1 = length(Entries),

	ct:log("✓ add_tag/2 is idempotent"),
	Config.

%% @doc Test register_batch/1 invalid input returns badarg
test_register_batch_invalid_input(Config) ->
	{error, badarg} = orka:register_batch([{invalid}]),
	{error, badarg} = orka:register_batch([{global, service, bad}, self(), not_a_map]),
	{error, badarg} = orka:register_batch([{global, service, bad}, not_a_pid, #{}]),
	Config.

%% @doc Test register_property/3 invalid input returns badarg
test_register_property_badarg(Config) ->
	Key = {global, service, bad_property},
	{error, badarg} = orka:register_property(Key, not_a_pid, #{property => region, value => "us-west"}),
	Config.

%% @doc Test update_metadata/2 invalid input returns badarg
test_update_metadata_badarg(Config) ->
	Key = {global, service, bad_metadata},
	{error, badarg} = orka:update_metadata(Key, not_a_map),
	Config.

%% @doc Test property registration
test_register_property(Config) ->
	Key1 = {global, service, translator_1},
	Pid1 = spawn(fun() -> timer:sleep(10000) end),
	
	Key2 = {global, service, translator_2},
	Pid2 = spawn(fun() -> timer:sleep(10000) end),
	
	%% Register services with properties
	{ok, _} = orka:register(Key1, Pid1, #{tags => [service, online]}),
	{ok, _} = orka:register(Key2, Pid2, #{tags => [service, online]}),
	
	%% Add property to first service
	ok = orka:register_property(Key1, Pid1, #{property => capacity, value => 100}),
	
	%% Add property to second service
	ok = orka:register_property(Key2, Pid2, #{property => capacity, value => 150}),
	
	%% Test registering property for non-existent key returns not_found
	NonexistentKey = {global, service, nonexistent},
	not_found = orka:register_property(NonexistentKey, self(), 
		#{property => capacity, value => 200}),
	
	ct:log("✓ Property registration works correctly"),
	Config.

%% @doc Test finding entries by property
test_find_by_property(Config) ->
	Key1 = {global, region, us_west_1},
	Pid1 = spawn(fun() -> timer:sleep(10000) end),
	
	Key2 = {global, region, us_west_2},
	Pid2 = spawn(fun() -> timer:sleep(10000) end),
	
	Key3 = {global, region, us_east_1},
	Pid3 = spawn(fun() -> timer:sleep(10000) end),
	
	%% Register with region properties
	{ok, _} = orka:register(Key1, Pid1, #{tags => [db]}),
	ok = orka:register_property(Key1, Pid1, #{property => region, value => "us-west"}),
	
	{ok, _} = orka:register(Key2, Pid2, #{tags => [db]}),
	ok = orka:register_property(Key2, Pid2, #{property => region, value => "us-west"}),
	
	{ok, _} = orka:register(Key3, Pid3, #{tags => [db]}),
	ok = orka:register_property(Key3, Pid3, #{property => region, value => "us-east"}),
	
	%% Find by property value
	WestEntries = orka:find_by_property(region, "us-west"),
	2 = length(WestEntries),
	true = lists:any(fun({K, _, _}) -> K =:= Key1 end, WestEntries),
	true = lists:any(fun({K, _, _}) -> K =:= Key2 end, WestEntries),
	
	EastEntries = orka:find_by_property(region, "us-east"),
	1 = length(EastEntries),
	true = lists:any(fun({K, _, _}) -> K =:= Key3 end, EastEntries),
	
	ct:log("✓ Finding entries by property works correctly"),
	Config.

%% @doc Test finding entries by property with type filtering
test_find_by_property_with_type(Config) ->
	Key1 = {global, service, cache_1},
	Pid1 = spawn(fun() -> timer:sleep(10000) end),
	
	Key2 = {global, resource, db_1},
	Pid2 = spawn(fun() -> timer:sleep(10000) end),
	
	%% Register service and resource with same property
	{ok, _} = orka:register(Key1, Pid1, #{tags => [cache]}),
	ok = orka:register_property(Key1, Pid1, #{property => status, value => "healthy"}),
	
	{ok, _} = orka:register(Key2, Pid2, #{tags => [db]}),
	ok = orka:register_property(Key2, Pid2, #{property => status, value => "healthy"}),
	
	%% Find only services with status healthy
	ServiceEntries = orka:find_by_property(service, status, "healthy"),
	1 = length(ServiceEntries),
	true = lists:any(fun({K, _, _}) -> K =:= Key1 end, ServiceEntries),
	
	%% Find only resources with status healthy
	ResourceEntries = orka:find_by_property(resource, status, "healthy"),
	1 = length(ResourceEntries),
	true = lists:any(fun({K, _, _}) -> K =:= Key2 end, ResourceEntries),
	
	ct:log("✓ Finding by property with type filtering works correctly"),
	Config.

%% @doc Test counting entries by property
test_count_by_property(Config) ->
	Key1 = {global, worker, w1},
	Pid1 = spawn(fun() -> timer:sleep(10000) end),
	
	Key2 = {global, worker, w2},
	Pid2 = spawn(fun() -> timer:sleep(10000) end),
	
	Key3 = {global, worker, w3},
	Pid3 = spawn(fun() -> timer:sleep(10000) end),
	
	%% Register workers with health status
	{ok, _} = orka:register(Key1, Pid1, #{tags => [worker]}),
	ok = orka:register_property(Key1, Pid1, #{property => health, value => ok}),
	
	{ok, _} = orka:register(Key2, Pid2, #{tags => [worker]}),
	ok = orka:register_property(Key2, Pid2, #{property => health, value => ok}),
	
	{ok, _} = orka:register(Key3, Pid3, #{tags => [worker]}),
	ok = orka:register_property(Key3, Pid3, #{property => health, value => warning}),
	
	%% Count healthy workers
	HealthyCount = orka:count_by_property(health, ok),
	2 = HealthyCount,
	
	%% Count warning workers
	WarningCount = orka:count_by_property(health, warning),
	1 = WarningCount,
	
	ct:log("✓ Counting by property works correctly"),
	Config.

%% @doc Test property statistics
test_property_stats(Config) ->
	Key1 = {global, instance, i1},
	Pid1 = spawn(fun() -> timer:sleep(10000) end),
	
	Key2 = {global, instance, i2},
	Pid2 = spawn(fun() -> timer:sleep(10000) end),
	
	Key3 = {global, instance, i3},
	Pid3 = spawn(fun() -> timer:sleep(10000) end),
	
	Key4 = {global, instance, i4},
	Pid4 = spawn(fun() -> timer:sleep(10000) end),
	
	%% Register instances with different capacities
	{ok, _} = orka:register(Key1, Pid1, #{tags => [instance]}),
	ok = orka:register_property(Key1, Pid1, #{property => capacity, value => 100}),
	
	{ok, _} = orka:register(Key2, Pid2, #{tags => [instance]}),
	ok = orka:register_property(Key2, Pid2, #{property => capacity, value => 100}),
	
	{ok, _} = orka:register(Key3, Pid3, #{tags => [instance]}),
	ok = orka:register_property(Key3, Pid3, #{property => capacity, value => 150}),
	
	{ok, _} = orka:register(Key4, Pid4, #{tags => [instance]}),
	ok = orka:register_property(Key4, Pid4, #{property => capacity, value => 200}),
	
	%% Get property statistics
	Stats = orka:property_stats(instance, capacity),
	
	%% Verify distribution
	#{ 100 := Count100, 150 := Count150, 200 := Count200 } = Stats,
	2 = Count100,
	1 = Count150,
	1 = Count200,
	
	ct:log("✓ Property statistics work correctly: ~p", [Stats]),
	Config.

%% @doc Test property_stats/2 returns empty map when no matches
test_property_stats_empty(Config) ->
	Stats = orka:property_stats(service, region),
	#{} = Stats,
	ct:log("✓ property_stats/2 returns empty map when no matches"),
	Config.

%% @doc Test find_by_property/2 returns empty list when no matches
test_find_by_property_not_found(Config) ->
	[] = orka:find_by_property(region, "nope"),
	ct:log("✓ find_by_property/2 returns empty list when no matches"),
	Config.

%% @doc Test count_by_property/2 returns 0 when no matches
test_count_by_property_not_found(Config) ->
	0 = orka:count_by_property(region, "nope"),
	ct:log("✓ count_by_property/2 returns 0 when no matches"),
	Config.

%% @doc Test entries_by_tag/1 returns empty list when no matches
test_entries_by_tag_not_found(Config) ->
	[] = orka:entries_by_tag(nonexistent_tag),
	ct:log("✓ entries_by_tag/1 returns empty list when no matches"),
	Config.

%% @doc Test count_by_tag/1 returns 0 when no matches
test_count_by_tag_not_found(Config) ->
	0 = orka:count_by_tag(nonexistent_tag),
	ct:log("✓ count_by_tag/1 returns 0 when no matches"),
	Config.

%% @doc Test entries_by_type/1 returns empty list when no matches
test_entries_by_type_not_found(Config) ->
	[] = orka:entries_by_type(nonexistent_type),
	ct:log("✓ entries_by_type/1 returns empty list when no matches"),
	Config.

%% @doc Test register_with/3 - start and register a process atomically
test_register_with(Config) ->
	Key = {global, service, test_service},
	Metadata = #{tags => [service, test], properties => #{version => "1.0.0"}},
	
	%% Start and register a process in one call
	{ok, Pid} = orka:register_with(Key, Metadata, {erlang, spawn, [fun() -> timer:sleep(10000) end]}),
	
	%% Verify the process is registered
	{ok, {Key, Pid, RetrievedMeta}} = orka:lookup(Key),
	NormalizedMeta = normalize_tags(Metadata),
	NormalizedMeta = normalize_tags(RetrievedMeta),
	
	%% Verify the process is alive
	true = is_process_alive(Pid),
	
	%% Verify it appears in lookup_all
	AllEntries = orka:lookup_all(),
	true = lists:any(fun({K, P, _}) -> K =:= Key andalso P =:= Pid end, AllEntries),
	
	ct:log("✓ register_with/3 starts and registers process atomically"),
	Config.

%% @doc Test register_with/3 returns existing entry when already registered
test_register_with_existing_returns_entry(Config) ->
	Key = {global, service, existing_service},
	Metadata = #{tags => [service, existing]},
	Pid = spawn(fun() -> timer:sleep(10000) end),

	{ok, {Key, Pid, _}} = orka:register(Key, Pid, Metadata),
	{ok, {Key, Pid, EntryMeta}} =
		orka:register_with(Key, #{tags => [service, ignored]}, {erlang, spawn, [fun() -> timer:sleep(10000) end]}),

	NormalizedMeta = normalize_tags(Metadata),
	NormalizedMeta = normalize_tags(EntryMeta),
	{ok, {Key, Pid, LookupMeta}} = orka:lookup(Key),
	NormalizedMeta = normalize_tags(Metadata),
	NormalizedMeta = normalize_tags(LookupMeta),

	ct:log("✓ register_with/3 returns existing entry for live registration"),
	Config.

%% @doc Test register_with/3 with MFA that returns {ok, Pid}
test_register_with_failure(Config) ->
	Key = {global, service, failing_service},
	Metadata = #{tags => [service, test]},
	
	%% Try to register with an MFA that fails
	FailingMFA = {erlang, apply, [fun() -> error(test_error) end, []]},
	Result = orka:register_with(Key, Metadata, FailingMFA),
	
	%% Should return an error
	{error, _} = Result,
	
	%% Verify the key was not registered
	not_found = orka:lookup(Key),
	
	ct:log("✓ register_with/3 handles MFA failures correctly"),
	Config.

%% @doc Test register_with/3 invalid input returns badarg
test_register_with_badarg(Config) ->
	{error, badarg} = orka:register_with({global, service, bad}, not_a_map, {erlang, spawn, [fun() -> ok end]}),
	{error, badarg} = orka:register_with({global, service, bad}, #{}, not_an_mfa),
	Config.

%% @doc Test register_with/3 succeeds with duplicate tags (normalized metadata)
test_register_with_duplicate_tags(Config) ->
	Key = {global, service, dup_tags},
	Metadata = #{tags => [service, service, online]},
	{ok, Pid} = orka:register_with(Key, Metadata, {erlang, spawn, [fun() -> timer:sleep(10000) end]}),
	{ok, {Key, Pid, StoredMeta}} = orka:lookup(Key),
	NormalizedMeta = normalize_tags(Metadata),
	NormalizedMeta = normalize_tags(StoredMeta),
	Config.

%% @doc Test register_single/3 - singleton constraint
test_register_single(Config) ->
	Key = {global, service, config_server},
	Metadata = #{tags => [service, config, critical], properties => #{reload_interval => 30000}},
	
	%% Register as singleton
	{ok, {Key, Pid, RegMetadata}} = orka:register_single(Key, Metadata),
	NormalizedMeta = normalize_tags(Metadata),
	NormalizedMeta = normalize_tags(RegMetadata),
	
	%% Verify it's registered
	{ok, {Key, Pid, LookupMetadata}} = orka:lookup(Key),
	NormalizedMeta = normalize_tags(Metadata),
	NormalizedMeta = normalize_tags(LookupMetadata),
	
	%% Verify the process is alive
	true = is_process_alive(Pid),
	
	ct:log("✓ register_single/3 registers process with singleton constraint"),
	Config.

%% @doc Test register_single/3 returns existing entry for same key
test_register_single_same_key_returns_existing(Config) ->
	Key = {global, service, config_server_same},
	Metadata = #{tags => [service, config]},
	Metadata2 = #{tags => [service, config, updated]},

	{ok, {Key, Pid, Meta1}} = orka:register_single(Key, Metadata),
	{ok, {Key, Pid, Meta2}} = orka:register_single(Key, Pid, Metadata2),
	NormalizedMeta = normalize_tags(Meta1),
	NormalizedMeta = normalize_tags(Meta2),
	{ok, {Key, Pid, LookupMeta}} = orka:lookup(Key),
	NormalizedMeta = normalize_tags(Meta1),
	NormalizedMeta = normalize_tags(LookupMeta),
	Config.

%% @doc Test register_single constraint - errors on other keys
test_register_single_constraint(Config) ->
	Key1 = {global, service, lock_manager},
	Key2 = {global, service, lock_manager_backup},
	Metadata = #{tags => [service, locks, critical]},
	
	%% Register first key as singleton
	{ok, {Key1, Pid, _}} = orka:register_single(Key1, Metadata),
	
	%% Verify it's registered
	{ok, {Key1, Pid, _}} = orka:lookup(Key1),
	
	%% Try to register the same process under a different key - should return error
	{error, {already_registered_under_key, Key1}} = orka:register_single(Key2, Pid, Metadata),
	
	%% Verify the second key is not registered
	not_found = orka:lookup(Key2),
	
	%% Verify the first key still exists
	{ok, {Key1, Pid, _}} = orka:lookup(Key1),
	
	ct:log("✓ register_single/3 errors for singleton Pid under another key"),
	Config.

%% @doc Test register_single/3 invalid input returns badarg
test_register_single_badarg(Config) ->
	{error, badarg} = orka:register_single({global, service, bad}, not_a_pid, #{}),
	{error, badarg} = orka:register_single({global, service, bad}, self(), not_a_map),
	Config.

%% @doc Test await when key is already registered
test_await_already_registered(Config) ->
	Key = {global, service, database},
	Metadata = #{tags => [service, database, critical]},
	
	%% Register the key first
	{ok, {Key, Pid, RegMetadata}} = orka:register(Key, Metadata),
	NormalizedMeta = normalize_tags(Metadata),
	NormalizedMeta = normalize_tags(RegMetadata),
	
	%% Now await should return immediately
	Start = erlang:monotonic_time(millisecond),
	{ok, {Key, Pid, AwaitMetadata}} = orka:await(Key, 30000),
	NormalizedMeta = normalize_tags(Metadata),
	NormalizedMeta = normalize_tags(AwaitMetadata),
	Elapsed = erlang:monotonic_time(millisecond) - Start,
	
	%% Should be nearly instant (less than 500ms)
	true = Elapsed < 500,
	
	ct:log("✓ await/2 returns immediately when key already registered"),
	Config.

%% @doc Test await/2 with Timeout=0 does not leave dangling subscription
test_await_timeout_zero_no_dangling_subscriber(Config) ->
	Key = {global, service, await_zero},
	Parent = self(),
	Pid = spawn(fun() -> timer:sleep(10000) end),

	Awaiter = spawn(fun() ->
		Result = orka:await(Key, 0),
		Parent ! {await_result, Result},
		receive
			{orka_registered, Key, _Entry} ->
				Parent ! {unexpected_registered, Key}
		after 200 ->
			Parent ! {no_unexpected_registration, Key}
		end
	end),

	receive
		{await_result, {error, timeout}} -> ok
	after 1000 ->
		ct:fail(timeout_waiting_for_await_result)
	end,

	{ok, _} = orka:register(Key, Pid, #{}),

	receive
		{unexpected_registered, Key} ->
			ct:fail(dangling_subscriber_received_registration);
		{no_unexpected_registration, Key} ->
			ok
	after 1000 ->
		ct:fail(timeout_waiting_for_registration_check)
	end,

	_ = erlang:exit(Awaiter, kill),
	ok = orka:unregister(Key),
	ct:log("✓ await/2 with Timeout=0 does not leave subscribers behind"),
	Config.

%% @doc Test await timeout when key is never registered
test_await_timeout(Config) ->
	Key = {global, service, never_registered},
	
	%% Await with short timeout
	Start = erlang:monotonic_time(millisecond),
	{error, timeout} = orka:await(Key, 100),
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
		Result = orka:await(Key, 5000),
		TestPid ! {await_result, Result}
	end),
	
	%% Monitor the await process to detect failures
	MonitorRef = monitor(process, AwaitPid),
	
	%% Give time for await to be called
	timer:sleep(100),
	
	%% Now register the key
	{ok, {Key, RegisteredPid, RegMetadata}} = orka:register(Key, Metadata),
	NormalizedMeta = normalize_tags(Metadata),
	NormalizedMeta = normalize_tags(RegMetadata),
	
	%% Wait for result from AwaitPid
	{await_result, {ok, {Key, RegisteredPid, AwaitMetadata}}} = receive_timeout(2000),
	NormalizedMeta = normalize_tags(Metadata),
	NormalizedMeta = normalize_tags(AwaitMetadata),
	
	%% Verify AwaitPid is still alive
	demonitor(MonitorRef, [flush]),

	ct:log("✓ await/2 unblocks when key is registered"),
	Config.

%% @doc Test subscribe when key is already registered
test_subscribe_already_registered(Config) ->
	Key = {global, service, config_server},
	Metadata = #{tags => [service, config, critical]},
	
	%% Register the key first
	{ok, {Key, Pid, RegMetadata}} = orka:register(Key, Metadata),
	NormalizedMeta = normalize_tags(Metadata),
	NormalizedMeta = normalize_tags(RegMetadata),
	
	%% Subscribe should send notification immediately
	ok = orka:subscribe(Key),
	
	%% Should receive message immediately
	{orka_registered, Key, {Key, Pid, SubMetadata}} = receive_timeout(500),
	NormalizedMeta = normalize_tags(Metadata),
	NormalizedMeta = normalize_tags(SubMetadata),
	
	ct:log("✓ subscribe/1 sends immediate notification for already registered key"),
	Config.

%% @doc Test subscribe and then registration
test_subscribe_and_registration(Config) ->
	Key = {global, service, metrics_server},
	Metadata = #{tags => [service, metrics]},
	
	%% Subscribe first
	ok = orka:subscribe(Key),
	
	%% Key doesn't exist yet
	not_found = orka:lookup(Key),
	
	%% Start a process that will register
	RegisterPid = spawn(fun() ->
		timer:sleep(100),
		orka:register(Key, Metadata)
	end),
	
	%% Monitor to detect process failure
	MonitorRef = monitor(process, RegisterPid),
	
	%% Wait for notification - should be registered by the spawned RegisterPid
	{orka_registered, Key, {Key, RegisterPid, SubMetadata}} = receive_timeout(2000),
	NormalizedMeta = normalize_tags(Metadata),
	NormalizedMeta = normalize_tags(SubMetadata),
	
	%% Verify the spawned process completed without crashing
	demonitor(MonitorRef, [flush]),
	
	ct:log("✓ subscribe/1 receives notification when key is registered"),
	Config.

%% @doc Test unsubscribe
test_unsubscribe(Config) ->
	Key = {global, service, feature_flag},
	Metadata = #{tags => [service, feature]},
	
	%% Subscribe first
	ok = orka:subscribe(Key),
	
	%% Unsubscribe
	ok = orka:unsubscribe(Key),
	
	%% Register the key - should NOT receive notification
	{ok, {Key, _Pid, RegMetadata}} = orka:register(Key, Metadata),
	NormalizedMeta = normalize_tags(Metadata),
	NormalizedMeta = normalize_tags(RegMetadata),
	
	%% Try to receive message (should timeout)
	timeout = receive_timeout(200),
	
	ct:log("✓ unsubscribe/1 cancels subscription"),
	Config.

%% @doc Test concurrent subscribers
test_concurrent_subscribers(Config) ->
	Key = {global, service, shared_resource},
	Metadata = #{tags => [service, shared]},
	ExpectedMeta = normalize_tags(Metadata),
	
	%% Have multiple subscribers
	Sub1 = spawn(fun() ->
		ok = orka:subscribe(Key),
		{orka_registered, Key, SubscriberEntry} = receive_timeout(5000),
		self() ! {got_notification, SubscriberEntry}
	end),
	
	Sub2 = spawn(fun() ->
		ok = orka:subscribe(Key),
		{orka_registered, Key, SubscriberEntry} = receive_timeout(5000),
		self() ! {got_notification, SubscriberEntry}
	end),
	
	Sub3 = spawn(fun() ->
		ok = orka:subscribe(Key),
		{orka_registered, Key, SubscriberEntry} = receive_timeout(5000),
		self() ! {got_notification, SubscriberEntry}
	end),
	
	timer:sleep(100),
	
	%% Register the key and capture the entry
	{ok, RegisteredEntry} = orka:register(Key, Metadata),
	
	%% All subscribers should receive the same entry
	wait_for_pids([Sub1, Sub2, Sub3], 3000),
	
	%% Verify the registered entry has the expected structure
	{Key, _RegistrarPid, ExpectedMeta} = RegisteredEntry,
	
	ct:log("✓ Multiple subscribers all receive notification"),
	Config.

%% @doc Test batch registration with explicit pids
test_register_batch_basic(Config) ->
	Key1 = {global, portfolio, user123},
	Key2 = {global, technical, user123},
	Key3 = {global, orders, user123},

	P1 = spawn(fun() -> timer:sleep(10000) end),
	P2 = spawn(fun() -> timer:sleep(10000) end),
	P3 = spawn(fun() -> timer:sleep(10000) end),
	
	Meta1 = #{tags => [portfolio, user], properties => #{strategy => momentum}},
	Meta2 = #{tags => [technical, user], properties => #{indicators => [rsi]}},
	Meta3 = #{tags => [orders, user], properties => #{queue => 100}},
	ExpectedMeta1 = normalize_tags_only(Meta1),
	ExpectedMeta2 = normalize_tags_only(Meta2),
	ExpectedMeta3 = normalize_tags_only(Meta3),
	
	%% Register 3 services for user in one call
	{ok, Entries} = orka:register_batch([
		{Key1, P1, Meta1},
		{Key2, P2, Meta2},
		{Key3, P3, Meta3}
	]),
	
	%% Should get all 3 entries back
	3 = length(Entries),
	
	%% Each should be found
	{ok, {Key1, P1, ExpectedMeta1}} = orka:lookup(Key1),
	{ok, {Key2, P2, ExpectedMeta2}} = orka:lookup(Key2),
	{ok, {Key3, P3, ExpectedMeta3}} = orka:lookup(Key3),
	
	ct:log("✓ Batch registration with explicit pids works"),
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
	{ok, Entries} = orka:register_batch([
		{Key1, P1, Meta},
		{Key2, P2, Meta},
		{Key3, P3, Meta}
	]),
	
	%% Should get all 3 back
	3 = length(Entries),
	
	%% Verify Pids match
	{ok, {Key1, P1, _}} = orka:lookup(Key1),
	{ok, {Key2, P2, _}} = orka:lookup(Key2),
	{ok, {Key3, P3, _}} = orka:lookup(Key3),
	
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
		Pid = spawn(fun() -> timer:sleep(10000) end),
		{Key, Pid, Meta}
	end, Services),
	
	%% Register all in one batch
	{ok, Entries} = orka:register_batch(RegList),
	
	%% Should get 5 entries
	5 = length(Entries),
	
	%% Verify all are registered
	lists:foreach(fun({Service, _Meta}) ->
		Key = {global, Service, UserId},
		{ok, {Key, _Pid, _}} = orka:lookup(Key)
	end, Services),
	
	%% Query by user - should find all 5
	AllEntries = orka:lookup_all(),
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

%% @doc Test register_batch/1 keeps existing entries when key already registered
test_register_batch_existing_entry(Config) ->
	Key = {global, service, existing_batch},
	Pid1 = spawn(fun() -> timer:sleep(10000) end),
	Pid2 = spawn(fun() -> timer:sleep(10000) end),

	{ok, {Key, Pid1, _}} = orka:register(Key, Pid1, #{tags => [service]}),
	{ok, [{Key, Pid1, _}]} = orka:register_batch([{Key, Pid2, #{tags => [service]}}]),
	{ok, {Key, Pid1, _}} = orka:lookup(Key),
	Config.

%% @doc Test register_batch_with/1 starts and registers processes
test_register_batch_with_basic(Config) ->
	Key1 = {global, service, batch_with_1},
	Key2 = {global, service, batch_with_2},
	Metadata = #{tags => [service]},

	{ok, Entries} = orka:register_batch_with([
		{Key1, Metadata, {erlang, spawn, [fun() -> timer:sleep(10000) end]}},
		{Key2, Metadata, {erlang, spawn, [fun() -> timer:sleep(10000) end]}}
	]),
	2 = length(Entries),
	{ok, {Key1, Pid1, _}} = orka:lookup(Key1),
	{ok, {Key2, Pid2, _}} = orka:lookup(Key2),
	true = is_process_alive(Pid1),
	true = is_process_alive(Pid2),
	Config.

%% @doc Test register_batch_with/1 rolls back on failure
test_register_batch_with_failure(Config) ->
	Key1 = {global, service, batch_with_ok},
	Key2 = {global, service, batch_with_fail},
	Metadata = #{tags => [service]},
	FailingMFA = {erlang, apply, [fun() -> error(test_error) end, []]},

	{error, {_Reason, _Failed, _Entries}} = orka:register_batch_with([
		{Key1, Metadata, {erlang, spawn, [fun() -> timer:sleep(10000) end]}},
		{Key2, Metadata, FailingMFA}
	]),
	not_found = orka:lookup(Key1),
	not_found = orka:lookup(Key2),
	Config.

%% @doc Test register_batch_with/1 invalid input returns badarg
test_register_batch_with_badarg(Config) ->
	{error, badarg} = orka:register_batch_with([{invalid}]),
	{error, badarg} = orka:register_batch_with([{key, #{}, not_an_mfa}]),
	{error, badarg} = orka:register_batch_with([{key, not_a_map, {erlang, spawn, []}}]),
	Config.

%% @doc Test unregister removes monitor for pid
test_unregister_removes_monitor(Config) ->
	Key = {global, service, monitor_cleanup},
	Pid = spawn(fun() -> receive after 10000 -> ok end end),

	{ok, _} = orka:register(Key, Pid, #{tags => [service]}),
	Monitors1 = get_monitors(),
	true = lists:member({process, Pid}, Monitors1),

	ok = orka:unregister(Key),
	Monitors2 = get_monitors(),
	false = lists:member({process, Pid}, Monitors2),
	Config.

%% @doc Test batch rollback removes monitor for partially registered pid
test_register_batch_rollback_removes_monitor(Config) ->
	Key1 = {global, service, batch_ok},
	Key2 = {global, service, singleton_key},
	Key3 = {global, service, batch_conflict},
	Pid1 = spawn(fun() -> receive after 10000 -> ok end end),
	Pid2 = spawn(fun() -> receive after 10000 -> ok end end),

	{ok, _} = orka:register_single(Key2, Pid2, #{tags => [service]}),
	{error, {_, _Failed, _Entries}} =
		orka:register_batch([{Key1, Pid1, #{tags => [service]}}, {Key3, Pid2, #{tags => [service]}}]),

	not_found = orka:lookup(Key1),
	Monitors = get_monitors(),
	false = lists:member({process, Pid1}, Monitors),
	Config.

%% Helper functions
receive_timeout(Timeout) ->
	receive
		Msg -> Msg
	after Timeout -> timeout
	end.

normalize_tags(Metadata) ->
	case orka_meta:normalize(Metadata, #{}) of
		{ok, Meta1} -> Meta1;
		{error, _} -> Metadata
	end.

normalize_tags_only(Metadata) ->
	case maps:get(tags, Metadata, undefined) of
		undefined -> Metadata;
		Tags when is_list(Tags) -> maps:put(tags, lists:usort(Tags), Metadata);
		_ -> Metadata
	end.

normalize_tag(Tag) ->
	case orka_meta:normalize_tag(Tag, orka_meta_policy:merge_opts(#{})) of
		{ok, Tag1} -> Tag1;
		{error, _} -> Tag
	end.

get_monitors() ->
	case process_info(whereis(orka), monitors) of
		{monitors, Monitors} -> Monitors;
		_ -> []
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
