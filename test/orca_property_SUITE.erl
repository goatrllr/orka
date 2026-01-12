-module(orca_property_SUITE).

%% Common Test callbacks
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% Tests
-export([
	test_prop_tag_index_consistent/1,
	test_prop_property_index_consistent/1
]).

-include_lib("common_test/include/ct.hrl").
-include_lib("proper/include/proper.hrl").

all() ->
	[
		test_prop_tag_index_consistent,
		test_prop_property_index_consistent
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

%% @doc Property: tag index is consistent with metadata tags
test_prop_tag_index_consistent(Config) ->
	ok = ensure_orca_started(),
	true = proper:quickcheck(prop_tag_index_consistent(), [{numtests, 50}]),
	Config.

%% @doc Property: property index is consistent with metadata properties
test_prop_property_index_consistent(Config) ->
	ok = ensure_orca_started(),
	true = proper:quickcheck(prop_property_index_consistent(), [{numtests, 50}]),
	Config.

ensure_orca_started() ->
	case whereis(orca) of
		undefined ->
			case application:ensure_all_started(orca) of
				{ok, _} -> ok;
				{error, {already_started, orca}} -> ok;
				{error, Reason} -> exit({orca_start_failed, Reason})
			end,
			timer:sleep(50),
			ok;
		_ ->
			ok
	end.

prop_tag_index_consistent() ->
	?FORALL({Id, Tags0}, {pos_integer(), list(tag_gen())},
		begin
			ok = ensure_orca_started(),
			Key = {global, service, {Id, make_ref()}},
			Tags = lists:usort(Tags0),
			Meta = #{tags => Tags},
			{ok, _} = orca:register(Key, self(), Meta),
			TagChecks = lists:all(fun(Tag) ->
				Entries = orca:entries_by_tag(Tag),
				lists:any(fun({K, _, _}) -> K =:= Key end, Entries)
			end, Tags),
			ok = orca:unregister(Key),
			TagChecks
		end).

prop_property_index_consistent() ->
	?FORALL({Id, Props}, {pos_integer(), properties_gen()},
		begin
			ok = ensure_orca_started(),
			Key = {global, service, {Id, make_ref()}},
			Meta = #{properties => Props},
			{ok, _} = orca:register(Key, self(), Meta),
			PropChecks = maps:fold(fun(Name, Value, Acc) ->
				Entries = orca:find_by_property(Name, Value),
				Acc andalso lists:any(fun({K, _, _}) -> K =:= Key end, Entries)
			end, true, Props),
			ok = orca:unregister(Key),
			PropChecks
		end).

tag_gen() ->
	elements([online, offline, critical, service, user, resource, beta, alpha]).

properties_gen() ->
	?LET(Names, list(name_gen()),
		maps:from_list([{N, value_gen()} || N <- lists:usort(Names)])).

name_gen() ->
	elements([region, status, version, capacity, tier]).

value_gen() ->
	oneof([integer(), atom(), binary()]).
