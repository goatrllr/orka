-module(orka_gpt_regression_SUITE).

%% Common Test callbacks
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% Tests
-export([
	test_await_timeout_cleans_subscription/1,
	test_property_stats_filters_by_type/1,
	test_register_property_overwrites_previous_value/1
]).

-include_lib("common_test/include/ct.hrl").

all() ->
	[
		test_await_timeout_cleans_subscription,
		test_property_stats_filters_by_type,
		test_register_property_overwrites_previous_value
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

%% @doc await/2 should unsubscribe after timeout; current implementation leaves subscription and later registrations still notify.
test_await_timeout_cleans_subscription(Config) ->
	Key = {global, service, late_register},

	{error, timeout} = orka:await(Key, 50),

	%% Register after timeout; should NOT deliver a notification because caller timed out
	{ok, _} = orka:register(Key, #{}),

	%% Fails today: message still arrives because subscription is not removed when timeout message is received
	timeout = receive_timeout(200),
	Config.

%% @doc property_stats/2 docs imply filtering by type; current code ignores the second argument and aggregates everything.
test_property_stats_filters_by_type(Config) ->
	Svc1 = {global, service, cache_a},
	Svc2 = {global, service, cache_b},
	Res1 = {global, resource, db_a},

	{ok, _} = orka:register(Svc1, #{tags => [service]}),
	ok = orka:register_property(Svc1, self(), #{property => status, value => healthy}),

	{ok, _} = orka:register(Svc2, #{tags => [service]}),
	ok = orka:register_property(Svc2, self(), #{property => status, value => healthy}),

	{ok, _} = orka:register(Res1, #{tags => [resource]}),
	ok = orka:register_property(Res1, self(), #{property => status, value => healthy}),

	%% Expect only services to be counted; actual code returns 3 because it ignores the filter.
	StatsForServices = orka:property_stats(service, status),
	2 = maps:get(<<"healthy">>, StatsForServices),
	Config.

%% @doc Re-registering the same property should replace the previous value; current code accumulates both values in the index.
test_register_property_overwrites_previous_value(Config) ->
	Key = {global, service, rolling_update},

	{ok, _} = orka:register(Key, #{tags => [service]}),
	ok = orka:register_property(Key, self(), #{property => version, value => <<"1.0.0">>}),
	ok = orka:register_property(Key, self(), #{property => version, value => <<"2.0.0">>}),

	%% Expect only the latest value to be visible; current code still returns the old one.
	[] = orka:find_by_property(version, <<"1.0.0">>),
	[{Key, _Pid, _}] = orka:find_by_property(version, <<"2.0.0">>),
	Config.

%% Local helper
receive_timeout(Timeout) ->
	receive
		Msg -> Msg
	after Timeout -> timeout
	end.
