-module(orka_property_SUITE).

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
	application:unset_env(orka, local_store_opts),
	application:unset_env(orka, global_store_opts),
	catch application:stop(orka),
	timer:sleep(100),
	case application:ensure_all_started(orka) of
		{ok, _} -> ok;
		{error, Reason} -> 
			% ct:log("Failed to start orka application: ~p", [Reason]),
			exit({application_start_failed, Reason})
	end,
	timer:sleep(100),
	Config.

end_per_suite(_Config) ->
	application:stop(orka),
	ok.

init_per_testcase(_TestCase, Config) ->
	application:unset_env(orka, local_store_opts),
	application:unset_env(orka, global_store_opts),
	catch application:stop(orka),
	timer:sleep(100),
	case application:ensure_all_started(orka) of
		{ok, _} -> ok;
		{error, {already_started, orka}} -> ok;
		{error, Reason} -> 
			% ct:log("Failed to start orka application in testcase: ~p", [Reason]),
			exit({application_start_failed, Reason})
	end,
	timer:sleep(100),
	Config.

end_per_testcase(_TestCase, _Config) ->
	ok.

%% @doc Property: tag index is consistent with metadata tags
test_prop_tag_index_consistent(Config) ->
	ok = ensure_orka_started(),
	true = proper:quickcheck(prop_tag_index_consistent(), [{numtests, 50}]),
	Config.

%% @doc Property: property index is consistent with metadata properties
test_prop_property_index_consistent(Config) ->
	ok = ensure_orka_started(),
	true = proper:quickcheck(prop_property_index_consistent(), [{numtests, 50}]),
	Config.

ensure_orka_started() ->
	case whereis(orka) of
		undefined ->
			case application:ensure_all_started(orka) of
				{ok, _} -> ok;
				{error, {already_started, orka}} -> ok;
				{error, Reason} -> 
					% ct:log("ensure_orka_started failed: ~p", [Reason]),
					exit({orka_start_failed, Reason})
			end,
			timer:sleep(50),
			ok;
		_ ->
			ok
	end.

prop_tag_index_consistent() ->
	?FORALL({Id, Tags0}, {pos_integer(), limited_tags_gen()},
		begin
			ok = ensure_orka_started(),
			Key = {local, service, {Id, make_ref()}},
			Tags = lists:usort(Tags0),
			Meta = #{tags => Tags},
			{ok, _} = orka:register(Key, self(), Meta),
			TagChecks = lists:all(fun(Tag) ->
				Entries = orka:entries_by_tag(Tag),
				lists:any(fun({K, _, _}) -> K =:= Key end, Entries)
			end, Tags),
			ok = orka:unregister(Key),
			TagChecks
		end).

prop_property_index_consistent() ->
	?FORALL({Id, Props}, {pos_integer(), properties_gen()},
		begin
			ok = ensure_orka_started(),
			Key = {local, service, {Id, make_ref()}},
			Meta = #{properties => Props},
			% ct:log("Generated props: ~p", [Props]),
			{ok, {_, _, StoredMeta}} = orka:register(Key, self(), Meta),
			StoredProps = maps:get(properties, StoredMeta, #{}),
			% ct:log("Stored props: ~p", [StoredProps]),
			timer:sleep(150),  %% Allow index updates
			PropChecks = check_props(Key, StoredProps),
			% ct:log("PropChecks result: ~p", [PropChecks]),
			ok = orka:unregister(Key),
			PropChecks
		end).

tag_gen() ->
	elements([online, offline, critical, service, user, resource, beta, alpha]).

properties_gen() ->
	?LET(Names, limited_names_gen(),
		begin
			UniqueNames = lists:usort(Names),
			?LET(Values, vector(length(UniqueNames), value_gen()),
				maps:from_list(lists:zip(UniqueNames, Values)))
		end).

limited_tags_gen() ->
	?SUCHTHAT(Tags, list(tag_gen()), length(Tags) =< 20).

limited_names_gen() ->
	?SUCHTHAT(Names, list(name_gen()), length(Names) =< 20).

name_gen() ->
	elements([region, status, version, capacity, tier]).

value_gen() ->
	elements([100, online, <<"us-east">>, 42, active, <<"test-value">>]).

meta_opts() ->
	Opts = application:get_env(orka, meta_opts, #{}),
	case is_map(Opts) of
		true -> orka_meta_policy:merge_opts(Opts);
		false -> orka_meta_policy:merge_opts(#{})
	end.

check_props(Key, Props) ->
	Opts = meta_opts(),
	lists:all(fun({Name, Value}) ->
		{ok, NormValue} = orka_meta:normalize_prop_val(Value, Opts),
		case find_key_by_property(Key, Name, NormValue, 3) of
			true ->
				true;
			false ->
				Entries = orka:find_by_property(Name, NormValue),
				ct:log("prop_property_index_consistent failed: key=~p name=~p value=~p norm_value=~p entries=~p props=~p",
					[Key, Name, Value, NormValue, Entries, Props]),
				false
		end
	end, maps:to_list(Props)).

find_key_by_property(_Key, _Name, _Value, 0) ->
	false;
find_key_by_property(Key, Name, Value, Attempts) ->
	Entries = orka:find_by_property(Name, Value),
	case lists:any(fun({K, _, _}) -> K =:= Key end, Entries) of
		true ->
			true;
		false when Attempts > 1 ->
			timer:sleep(50),
			find_key_by_property(Key, Name, Value, Attempts - 1);
		false ->
			false
	end.
