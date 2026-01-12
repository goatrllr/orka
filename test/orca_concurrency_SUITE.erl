-module(orca_concurrency_SUITE).

%% Common Test callbacks
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% Tests
-export([
	test_concurrent_register_with_same_key/1,
	test_concurrent_awaiters/1
]).

-include_lib("common_test/include/ct.hrl").

all() ->
	[
		test_concurrent_register_with_same_key,
		test_concurrent_awaiters
	].

init_per_suite(Config) ->
	catch application:stop(orca),
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

%% @doc Concurrent register_with calls for same key should return same entry
test_concurrent_register_with_same_key(Config) ->
	Key = {global, service, concurrent_register_with},
	Metadata = #{tags => [service]},
	Parent = self(),
	Caller = fun() ->
		Result = orca:register_with(Key, Metadata,
			{erlang, spawn, [fun() -> timer:sleep(10000) end]}),
		Parent ! {register_with_result, Result}
	end,

	Pids = [spawn(Caller) || _ <- lists:seq(1, 5)],
	Results = gather_results(length(Pids), []),
	5 = length(Results),
	PidList = [extract_pid(R) || R <- Results],
	[FirstPid | _] = PidList,
	true = lists:all(fun(P) -> P =:= FirstPid end, PidList),
	{ok, {Key, FirstPid, _}} = orca:lookup(Key),

	ct:log("✓ concurrent register_with/3 returns same entry"),
	Config.

%% @doc Multiple awaiters should all receive registration notification
test_concurrent_awaiters(Config) ->
	Key = {global, service, concurrent_await},
	Metadata = #{tags => [service, await]},
	Parent = self(),
	Awaiter = fun() ->
		Result = orca:await(Key, 5000),
		Parent ! {await_result, Result}
	end,

	_ = [spawn(Awaiter) || _ <- lists:seq(1, 5)],
	timer:sleep(100),
	{ok, {Key, _Pid, _}} = orca:register(Key, Metadata),

	Results = gather_await_results(5, []),
	5 = length(Results),
	true = lists:all(fun(R) ->
		case R of
			{ok, {Key, _, _}} -> true;
			_ -> false
		end
	end, Results),

	ct:log("✓ concurrent await/2 notifies all waiters"),
	Config.

gather_results(0, Acc) ->
	lists:reverse(Acc);
gather_results(N, Acc) ->
	receive
		{register_with_result, Result} ->
			gather_results(N - 1, [Result | Acc])
	after 5000 ->
			Acc
	end.

gather_await_results(0, Acc) ->
	lists:reverse(Acc);
gather_await_results(N, Acc) ->
	receive
		{await_result, Result} ->
			gather_await_results(N - 1, [Result | Acc])
	after 5000 ->
			Acc
	end.

extract_pid({ok, Pid}) when is_pid(Pid) ->
	Pid;
extract_pid({ok, {_, Pid, _}}) when is_pid(Pid) ->
	Pid.
