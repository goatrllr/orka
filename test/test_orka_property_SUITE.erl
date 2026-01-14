-module(test_orka_property_SUITE).

%% Common Test callbacks
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([init_per_testcase/2, end_per_testcase/2]).

-include_lib("common_test/include/ct.hrl").
-include_lib("proper/include/proper.hrl").

%% Test cases
-export([
    test_properties_gen_produces_valid_data/1,
    test_value_gen_produces_normalizable_values/1,
    test_name_gen_produces_atoms/1,
    test_check_props_with_empty_props/1,
    test_check_props_with_single_property/1,
    test_check_props_with_multiple_properties/1,
    test_register_with_empty_properties/1,
    test_register_with_single_property/1,
    test_register_with_multiple_properties/1,
    test_property_index_lookup_finds_registered_entry/1,
    test_property_index_lookup_distinguishes_entries/1,
    test_property_value_normalization_consistency/1,
    test_concurrent_registrations_maintain_index/1,
    test_property_storage_preserves_all_keys/1,
    test_property_storage_respects_input_properties/1,
    test_property_lookup_after_normalization/1,
    test_empty_properties_not_indexed/1,
    test_property_lookup_with_different_value_types/1,
    test_property_index_after_delayed_lookup/1,
    test_multiple_registrations_same_property_different_values/1,
    test_property_normalization_idempotent/1
]).


all() ->
    [
        test_properties_gen_produces_valid_data,
        test_value_gen_produces_normalizable_values,
        test_name_gen_produces_atoms,
        test_check_props_with_empty_props,
        test_check_props_with_single_property,
        test_check_props_with_multiple_properties,
        test_register_with_empty_properties,
        test_register_with_single_property,
        test_register_with_multiple_properties,
        test_property_index_lookup_finds_registered_entry,
        test_property_index_lookup_distinguishes_entries,
        test_property_value_normalization_consistency,
        test_concurrent_registrations_maintain_index,
        test_property_storage_preserves_all_keys,
        test_property_storage_respects_input_properties,
        test_property_lookup_after_normalization,
        test_empty_properties_not_indexed,
        test_property_lookup_with_different_value_types,
        test_property_index_after_delayed_lookup,
        test_multiple_registrations_same_property_different_values,
        test_property_normalization_idempotent
    ].

init_per_suite(Config) ->
    application:unset_env(orka, local_store_opts),
    application:unset_env(orka, global_store_opts),
    catch application:stop(orka),
    timer:sleep(50),
    ok = application:start(orka),
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
    ok = application:start(orka),
    timer:sleep(100),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%% Tests for generators
test_properties_gen_produces_valid_data(_Config) ->
    Props = proper:quickcheck(
        proper:numtests(20, ?FORALL(P, properties_gen(), is_map(P)))),
    true = Props.

test_value_gen_produces_normalizable_values(_Config) ->
    Opts = meta_opts(),
    Valid = proper:quickcheck(
        proper:numtests(30, ?FORALL(V, value_gen(),
            case orka_meta:normalize_prop_val(V, Opts) of
                {ok, _} -> true;
                _ -> false
            end))),
    true = Valid.

test_name_gen_produces_atoms(_Config) ->
    Valid = proper:quickcheck(
        proper:numtests(20, ?FORALL(N, name_gen(), is_atom(N)))),
    true = Valid.

%% Tests for check_props helper
test_check_props_with_empty_props(_Config) ->
    Key = {local, test, {1, make_ref()}},
    {ok, _} = orka:register(Key, self(), #{}),
    Result = check_props(Key, #{}),
    ok = orka:unregister(Key),
    true = Result.

test_check_props_with_single_property(_Config) ->
    Key = {local, test, {2, make_ref()}},
    Props = #{region => <<"us-east">>},
    {ok, {_, _, StoredMeta}} = orka:register(Key, self(), #{properties => Props}),
    StoredProps = maps:get(properties, StoredMeta, #{}),
    ct:log("Stored properties: ~p", [StoredProps]),
    Result = check_props(Key, StoredProps),
    ok = orka:unregister(Key),
    true = Result.

test_check_props_with_multiple_properties(_Config) ->
    Key = {local, test, {3, make_ref()}},
    Props = #{region => <<"us-west">>, status => <<"active">>, version => 2},
    {ok, {_, _, StoredMeta}} = orka:register(Key, self(), #{properties => Props}),
    StoredProps = maps:get(properties, StoredMeta, #{}),
    ct:log("Stored properties: ~p", [StoredProps]),
    Result = check_props(Key, StoredProps),
    ok = orka:unregister(Key),
    true = Result.

%% Integration tests for registration
test_register_with_empty_properties(_Config) ->
    Key = {local, test, {4, make_ref()}},
    {ok, {K, Pid, Meta}} = orka:register(Key, self(), #{properties => #{}}),
    K = Key,
    Pid = self(),
    Props = maps:get(properties, Meta, #{}),
    ok = orka:unregister(Key),
    #{} = Props.

test_register_with_single_property(_Config) ->
    Key = {local, test, {5, make_ref()}},
    InputProps = #{capacity => 100},
    {ok, {K, Pid, Meta}} = orka:register(Key, self(), #{properties => InputProps}),
    K = Key,
    Pid = self(),
    StoredProps = maps:get(properties, Meta, #{}),
    ct:log("Input: ~p, Stored: ~p", [InputProps, StoredProps]),
    true = maps:size(StoredProps) > 0,
    ok = orka:unregister(Key).

test_register_with_multiple_properties(_Config) ->
    Key = {local, test, {6, make_ref()}},
    InputProps = #{region => <<"eu-central">>, tier => premium, capacity => 500},
    {ok, {K, Pid, Meta}} = orka:register(Key, self(), #{properties => InputProps}),
    K = Key,
    Pid = self(),
    StoredProps = maps:get(properties, Meta, #{}),
    ct:log("Input: ~p, Stored: ~p", [InputProps, StoredProps]),
    true = maps:size(StoredProps) =:= maps:size(InputProps),
    ok = orka:unregister(Key).

%% Property index lookup tests
test_property_index_lookup_finds_registered_entry(_Config) ->
    Key = {local, test, {7, make_ref()}},
    Props = #{status => <<"online">>},
    {ok, {_, _, StoredMeta}} = orka:register(Key, self(), #{properties => Props}),
    StoredProps = maps:get(properties, StoredMeta, #{}),
    timer:sleep(50),
    
    Result = lists:foldl(fun({Name, Value}, Acc) ->
        Entries = orka:find_by_property(Name, Value),
        ct:log("Looking for property ~p=~p, found entries: ~p", [Name, Value, Entries]),
        Found = lists:any(fun({K, _, _}) -> K =:= Key end, Entries),
        Acc andalso Found
    end, true, maps:to_list(StoredProps)),
    
    ok = orka:unregister(Key),
    true = Result.

test_property_index_lookup_distinguishes_entries(_Config) ->
    Key1 = {local, test, {8, make_ref()}},
    Key2 = {local, test, {9, make_ref()}},
    
    {ok, _} = orka:register(Key1, self(), #{properties => #{region => <<"us">>}}),
    {ok, _} = orka:register(Key2, self(), #{properties => #{region => <<"eu">>}}),
    timer:sleep(50),
    
    Entries = orka:find_by_property(region, <<"us">>),
    Found1 = lists:any(fun({K, _, _}) -> K =:= Key1 end, Entries),
    NotFound2 = not lists:any(fun({K, _, _}) -> K =:= Key2 end, Entries),
    
    ok = orka:unregister(Key1),
    ok = orka:unregister(Key2),
    
    true = Found1 andalso NotFound2.

test_property_value_normalization_consistency(_Config) ->
    Key = {local, test, {10, make_ref()}},
    Value = 42,
    {ok, {_, _, StoredMeta}} = orka:register(Key, self(), #{properties => #{capacity => Value}}),
    StoredProps = maps:get(properties, StoredMeta, #{}),
    ct:log("Registered with value: ~p, stored properties: ~p", [Value, StoredProps]),
    timer:sleep(100),
    
    %% Verify property was actually stored
    case maps:size(StoredProps) of
        0 ->
            ok = orka:unregister(Key),
            ct:fail("Property not stored");
        _ ->
            %% Find stored value and verify lookup
            Opts = meta_opts(),
            {ok, CapacityKey} = orka_meta:normalize_prop_key(capacity, Opts),
            case maps:find(CapacityKey, StoredProps) of
                {ok, StoredValue} ->
                    ct:log("Original: ~p, Stored: ~p", [Value, StoredValue]),
                    Entries = orka:find_by_property(capacity, StoredValue),
                    Found = lists:any(fun({K, _, _}) -> K =:= Key end, Entries),
                    ok = orka:unregister(Key),
                    true = Found;
                error ->
                    ok = orka:unregister(Key),
                    ct:fail("Property capacity not in stored properties")
            end
    end.

test_concurrent_registrations_maintain_index(_Config) ->
    Keys = [
        {local, test, {11, make_ref()}},
        {local, test, {12, make_ref()}},
        {local, test, {13, make_ref()}}
    ],
    
    %% Register multiple entries with overlapping properties
    lists:foreach(fun(Key) ->
        {ok, _} = orka:register(Key, self(), #{properties => #{status => <<"online">>}})
    end, Keys),
    timer:sleep(100),
    
    %% Verify all are findable
    Entries = orka:find_by_property(status, <<"online">>),
    Result = lists:all(fun(Key) ->
        lists:any(fun({K, _, _}) -> K =:= Key end, Entries)
    end, Keys),
    
    %% Cleanup
    lists:foreach(fun(Key) -> orka:unregister(Key) end, Keys),
    
    true = Result.

%% NEW TESTS - Focus on property storage issues
test_property_storage_preserves_all_keys(_Config) ->
    Key = {local, test, {14, make_ref()}},
    InputProps = #{region => <<"us">>, status => <<"active">>, version => 3},
    {ok, {_, _, StoredMeta}} = orka:register(Key, self(), #{properties => InputProps}),
    StoredProps = maps:get(properties, StoredMeta, #{}),
    ct:log("Input keys: ~p, Stored keys: ~p", 
        [lists:sort(maps:keys(InputProps)), lists:sort(maps:keys(StoredProps))]),
    
    Opts = meta_opts(),
    {ok, NormMeta} = orka_meta:normalize(#{properties => InputProps}, Opts),
    NormalizedInputProps = maps:get(properties, NormMeta, #{}),
    InputKeys = sets:from_list(maps:keys(NormalizedInputProps)),
    StoredKeys = sets:from_list(maps:keys(StoredProps)),
    
    ok = orka:unregister(Key),
    
    %% All input keys must be present in stored properties
    true = sets:is_subset(InputKeys, StoredKeys).

test_property_storage_respects_input_properties(_Config) ->
    Key = {local, test, {15, make_ref()}},
    InputProps = #{capacity => 256, tier => <<"gold">>},
    {ok, {_, _, StoredMeta}} = orka:register(Key, self(), #{properties => InputProps}),
    StoredProps = maps:get(properties, StoredMeta, #{}),
    
    ct:log("Input properties: ~p", [InputProps]),
    ct:log("Stored properties: ~p", [StoredProps]),
    
    Size = maps:size(StoredProps),
    ok = orka:unregister(Key),
    
    %% Properties should not be empty
    true = Size > 0.

test_property_lookup_after_normalization(_Config) ->
    Key = {local, test, {16, make_ref()}},
    %% Use an integer value that should be normalizable
    {ok, {_, _, StoredMeta}} = orka:register(Key, self(), #{properties => #{capacity => 1024}}),
    StoredProps = maps:get(properties, StoredMeta, #{}),
    
    timer:sleep(150),
    
    %% Verify we can look up by the stored normalized value
    case maps:to_list(StoredProps) of
        [] ->
            ok = orka:unregister(Key),
            ct:fail("No properties were stored");
        PropList ->
            Results = lists:map(fun({Name, Value}) ->
                Entries = orka:find_by_property(Name, Value),
                ct:log("Lookup ~p=~p returned ~p entries", [Name, Value, length(Entries)]),
                lists:any(fun({K, _, _}) -> K =:= Key end, Entries)
            end, PropList),
            ok = orka:unregister(Key),
            true = lists:all(fun(X) -> X end, Results)
    end.

test_empty_properties_not_indexed(_Config) ->
    Key = {local, test, {17, make_ref()}},
    {ok, {_, _, StoredMeta}} = orka:register(Key, self(), #{properties => #{}}),
    StoredProps = maps:get(properties, StoredMeta, #{}),
    
    ok = orka:unregister(Key),
    
    %% Empty properties should remain empty
    #{} = StoredProps.

test_property_lookup_with_different_value_types(_Config) ->
    Keys = [
        {local, test, {18, make_ref()}},
        {local, test, {19, make_ref()}},
        {local, test, {20, make_ref()}}
    ],
    
    %% Test with different value types
    Props = [
        #{status => online},           %% atom
        #{version => 10},              %% integer
        #{region => <<"us-east">>}     %% binary
    ],
    
    lists:zipwith(fun(K, P) ->
        {ok, _} = orka:register(K, self(), #{properties => P})
    end, Keys, Props),
    timer:sleep(150),
    
    %% Verify each can be found by exact stored value
    Results = lists:zipwith(fun(K, P) ->
        {Name, Value} = hd(maps:to_list(P)),
        Entries = orka:find_by_property(Name, Value),
        Found = lists:any(fun({KeyReg, _, _}) -> KeyReg =:= K end, Entries),
        ct:log("Type ~p: lookup ~p=~p found=~p", [type_of(Value), Name, Value, Found]),
        Found
    end, Keys, Props),
    
    lists:foreach(fun(K) -> orka:unregister(K) end, Keys),
    
    true = lists:all(fun(X) -> X end, Results).

test_property_index_after_delayed_lookup(_Config) ->
    Key = {local, test, {21, make_ref()}},
    {ok, {_, _, StoredMeta}} = orka:register(Key, self(), #{properties => #{capacity => 512}}),
    StoredProps = maps:get(properties, StoredMeta, #{}),
    
    %% Wait longer to ensure index is updated
    timer:sleep(250),
    
    case maps:to_list(StoredProps) of
        [] ->
            ok = orka:unregister(Key),
            ct:fail("Properties not stored");
        [{Name, Value} | _] ->
            Entries = orka:find_by_property(Name, Value),
            Found = lists:any(fun({K, _, _}) -> K =:= Key end, Entries),
            ct:log("After 250ms delay: found=~p", [Found]),
            ok = orka:unregister(Key),
            true = Found
    end.

test_multiple_registrations_same_property_different_values(_Config) ->
    Key1 = {local, test, {22, make_ref()}},
    Key2 = {local, test, {23, make_ref()}},
    Key3 = {local, test, {24, make_ref()}},
    
    {ok, {_, _, M1}} = orka:register(Key1, self(), #{properties => #{tier => <<"bronze">>}}),
    {ok, {_, _, M2}} = orka:register(Key2, self(), #{properties => #{tier => <<"silver">>}}),
    {ok, {_, _, M3}} = orka:register(Key3, self(), #{properties => #{tier => <<"gold">>}}),
    
    P1 = maps:get(properties, M1, #{}),
    P2 = maps:get(properties, M2, #{}),
    _P3 = maps:get(properties, M3, #{}),
    
    timer:sleep(150),
    
    %% Verify each is found only for correct value
    Result1 = case maps:to_list(P1) of
        [] -> false;
        [{N1, V1} | _] ->
            Entries1 = orka:find_by_property(N1, V1),
            lists:any(fun({K, _, _}) -> K =:= Key1 end, Entries1) andalso
            not lists:any(fun({K, _, _}) -> K =:= Key2 end, Entries1)
    end,
    
    Result2 = case maps:to_list(P2) of
        [] -> false;
        [{N2, V2} | _] ->
            Entries2 = orka:find_by_property(N2, V2),
            lists:any(fun({K, _, _}) -> K =:= Key2 end, Entries2) andalso
            not lists:any(fun({K, _, _}) -> K =:= Key1 end, Entries2)
    end,
    
    lists:foreach(fun(K) -> orka:unregister(K) end, [Key1, Key2, Key3]),
    
    true = Result1 andalso Result2.

test_property_normalization_idempotent(_Config) ->
    Key = {local, test, {25, make_ref()}},
    OriginalValue = 999,
    {ok, {_, _, StoredMeta1}} = orka:register(Key, self(), #{properties => #{capacity => OriginalValue}}),
    P1 = maps:get(properties, StoredMeta1, #{}),
    
    {StoredValue1, _} = hd(maps:to_list(P1)),
    ct:log("First storage: original=~p, stored=~p", [OriginalValue, StoredValue1]),
    
    ok = orka:unregister(Key),
    timer:sleep(50),
    
    Key2 = {local, test, {26, make_ref()}},
    {ok, {_, _, StoredMeta2}} = orka:register(Key2, self(), #{properties => #{capacity => StoredValue1}}),
    P2 = maps:get(properties, StoredMeta2, #{}),
    
    {StoredValue2, _} = hd(maps:to_list(P2)),
    ct:log("Second storage: input=~p, stored=~p", [StoredValue1, StoredValue2]),
    
    ok = orka:unregister(Key2),
    
    %% Normalization should be idempotent
    true = StoredValue1 =:= StoredValue2.

%% Helper functions
type_of(X) when is_atom(X) -> atom;
type_of(X) when is_integer(X) -> integer;
type_of(X) when is_binary(X) -> binary;
type_of(_) -> unknown.

properties_gen() ->
    ?LET(Names, limited_names_gen(),
        begin
            UniqueNames = lists:usort(Names),
            ?LET(Values, vector(length(UniqueNames), value_gen()),
                maps:from_list(lists:zip(UniqueNames, Values)))
        end).

limited_names_gen() ->
    ?SUCHTHAT(Names, list(name_gen()), length(Names) =< 20).

name_gen() ->
    elements([region, status, version, capacity, tier]).

value_gen() ->
    Opts = meta_opts(),
    ?SUCHTHAT(Val, oneof([integer(), atom(), binary()]),
        case orka_meta:normalize_prop_val(Val, Opts) of
            {ok, _} -> true;
            _ -> false
        end).

meta_opts() ->
    Opts = application:get_env(orka, meta_opts, #{}),
    case is_map(Opts) of
        true -> orka_meta_policy:merge_opts(Opts);
        false -> orka_meta_policy:merge_opts(#{})
    end.

check_props(Key, Props) ->
    lists:all(fun({Name, Value}) ->
        Entries = orka:find_by_property(Name, Value),
        case lists:any(fun({K, _, _}) -> K =:= Key end, Entries) of
            true ->
                true;
            false ->
                ct:log("check_props failed: key=~p name=~p value=~p entries=~p",
                    [Key, Name, Value, Entries]),
                false
        end
    end, maps:to_list(Props)).
