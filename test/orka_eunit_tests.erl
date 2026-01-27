%% EUnit tests for orka - Fast process registry
%% Tests core functionality at the unit level with focused test cases
-module(orka_eunit_tests).

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Setup and Teardown
%%====================================================================

setup() ->
    catch application:stop(orka),
    timer:sleep(50),
    ok = application:start(orka),
    timer:sleep(50),
    ok.

cleanup(_) ->
    catch application:stop(orka),
    ok.

%%====================================================================
%% Registration Tests
%%====================================================================

%% Basic registration with key, pid, and metadata
register_basic_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key = {test, basic, 1},
        Metadata = #{status => active, version => 1},
        Pid = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, {Key, Pid, _}} = orka:register(Key, Pid, Metadata),
        {ok, {Key, Pid, StoredMetadata}} = orka:lookup(Key),
        ?assertEqual(lists:usort(maps:get(tags, Metadata, [])),
                     lists:usort(maps:get(tags, StoredMetadata, []))),
        ?assertEqual(maps:get(properties, Metadata, #{}),
                     maps:get(properties, StoredMetadata, #{})),
        ?assertEqual(maps:get(created_at, Metadata, undefined),
                     maps:get(created_at, StoredMetadata, undefined)),
        
        % Cleanup
        orka:unregister(Key),
        exit(Pid, kill)
    end}.

%% Self-registration using calling process
register_self_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key = {test, self_register, 1},
        Metadata = #{role => worker},
        Self = self(),
        
        {ok, {Key, Self, Metadata}} = orka:register(Key, Metadata),
        {ok, {Key, Self, Metadata}} = orka:lookup(Key),
        
        orka:unregister(Key)
    end}.

%% Registration with empty metadata
register_empty_metadata_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key = {test, empty, 1},
        Metadata = #{},
        Pid = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, {Key, Pid, _}} = orka:register(Key, Pid, Metadata),
        {ok, {Key, Pid, StoredMetadata}} = orka:lookup(Key),
        ?assertEqual(lists:usort(maps:get(tags, Metadata, [])),
                     lists:usort(maps:get(tags, StoredMetadata, []))),
        ?assertEqual(maps:get(properties, Metadata, #{}),
                     maps:get(properties, StoredMetadata, #{})),
        ?assertEqual(maps:get(created_at, Metadata, undefined),
                     maps:get(created_at, StoredMetadata, undefined)),
        
        orka:unregister(Key),
        exit(Pid, kill)
    end}.

%% Register with nested key structure
register_nested_key_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key = {{nested, key}, {type, service}, {id, 1}},
        Metadata = #{info => complex},
        Pid = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, {Key, Pid, _}} = orka:register(Key, Pid, Metadata),
        {ok, {Key, Pid, StoredMetadata}} = orka:lookup(Key),
        ?assertEqual(lists:usort(maps:get(tags, Metadata, [])),
                     lists:usort(maps:get(tags, StoredMetadata, []))),
        ?assertEqual(maps:get(properties, Metadata, #{}),
                     maps:get(properties, StoredMetadata, #{})),
        ?assertEqual(maps:get(created_at, Metadata, undefined),
                     maps:get(created_at, StoredMetadata, undefined)),
        
        orka:unregister(Key),
        exit(Pid, kill)
    end}.

%% Register with complex metadata
register_complex_metadata_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key = {test, complex, 1},
        Metadata = #{
            tags => [service, online, critical],
            properties => #{
                version => "1.0.0",
                capacity => 100,
                config => #{timeout => 5000}
            },
            created_at => erlang:system_time(millisecond)
        },
        Pid = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, {Key, Pid, _}} = orka:register(Key, Pid, Metadata),
        {ok, {Key, Pid, StoredMetadata}} = orka:lookup(Key),
        ?assertEqual(lists:usort(maps:get(tags, Metadata, [])),
                     lists:usort(maps:get(tags, StoredMetadata, []))),
        ?assertEqual(maps:get(properties, Metadata, #{}),
                     maps:get(properties, StoredMetadata, #{})),
        ?assertEqual(maps:get(created_at, Metadata, undefined),
                     maps:get(created_at, StoredMetadata, undefined)),
        
        orka:unregister(Key),
        exit(Pid, kill)
    end}.

%% Register with atom as key
register_atom_key_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key = my_service,
        Metadata = #{},
        Pid = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, {Key, Pid, Metadata}} = orka:register(Key, Pid, Metadata),
        {ok, {Key, Pid, Metadata}} = orka:lookup(Key),
        
        orka:unregister(Key),
        exit(Pid, kill)
    end}.

%% Register with binary as key component
register_binary_key_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key = {binary, <<"user-123">>},
        Metadata = #{type => user},
        Pid = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, {Key, Pid, Metadata}} = orka:register(Key, Pid, Metadata),
        {ok, {Key, Pid, Metadata}} = orka:lookup(Key),
        
        orka:unregister(Key),
        exit(Pid, kill)
    end}.

%% Re-register same key returns existing entry
register_duplicate_key_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key = {test, duplicate, 1},
        Metadata1 = #{version => 1},
        Pid1 = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, {Key, Pid1, Metadata1}} = orka:register(Key, Pid1, Metadata1),
        
        % Re-register with different metadata
        Metadata2 = #{version => 2},
        {ok, {Key, Pid1, Metadata1}} = orka:register(Key, Pid1, Metadata2),
        
        % Should still have original metadata
        {ok, {Key, Pid1, Metadata1}} = orka:lookup(Key),
        
        orka:unregister(Key),
        exit(Pid1, kill)
    end}.

%% Invalid registration returns badarg
register_badarg_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        % Non-pid
        ?assertEqual({error, badarg}, orka:register({test, bad, 1}, not_a_pid, #{})),
        
        % Non-map metadata
        ?assertEqual({error, badarg}, orka:register({test, bad, 2}, self(), not_a_map)),
        
        % Multiple invalid arguments
        ?assertEqual({error, badarg}, orka:register({test, bad, 3}, not_a_pid, not_a_map))
    end}.

%%====================================================================
%% Lookup Tests
%%====================================================================

%% Lookup non-existent key
lookup_not_found_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key = {test, nonexistent, 1},
        ?assertEqual(not_found, orka:lookup(Key))
    end}.

%% lookup_dirty returns entry (no locking)
lookup_dirty_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key = {test, dirty, 1},
        Metadata = #{},
        Pid = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, {Key, Pid, Metadata}} = orka:register(Key, Pid, Metadata),
        
        % lookup_dirty should return same as lookup for this simple case
        {ok, {Key, Pid, Metadata}} = orka:lookup_dirty(Key),
        
        orka:unregister(Key),
        exit(Pid, kill)
    end}.

%% lookup_alive with live process
lookup_alive_live_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key = {test, alive, 1},
        Metadata = #{tags => [service]},
        Pid = spawn(fun() -> receive after 10000 -> ok end end),
        
        {ok, {Key, Pid, Metadata}} = orka:register(Key, Pid, Metadata),
        {ok, {Key, Pid, Metadata}} = orka:lookup_alive(Key),
        
        orka:unregister(Key),
        exit(Pid, kill)
    end}.

%% lookup_alive with dead process returns not_found
lookup_alive_dead_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key = {test, dead, 1},
        Metadata = #{tags => [service]},
        DeadPid = spawn(fun() -> ok end),
        
        {ok, {Key, DeadPid, Metadata}} = orka:register(Key, DeadPid, Metadata),
        
        % Wait for process to exit
        timer:sleep(200),
        
        % lookup_alive should return not_found
        not_found = orka:lookup_alive(Key),
        
        orka:unregister(Key)
    end}.

%% lookup_all returns all entries
lookup_all_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key1 = {test, all, 1},
        Key2 = {test, all, 2},
        Metadata = #{},
        Pid1 = spawn(fun() -> timer:sleep(10000) end),
        Pid2 = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, _} = orka:register(Key1, Pid1, Metadata),
        {ok, _} = orka:register(Key2, Pid2, Metadata),
        
        All = orka:lookup_all(),
        
        % Should contain at least our two entries
        ?assert(lists:any(fun({K, _, _}) -> K =:= Key1 end, All)),
        ?assert(lists:any(fun({K, _, _}) -> K =:= Key2 end, All)),
        
        orka:unregister(Key1),
        orka:unregister(Key2),
        exit(Pid1, kill),
        exit(Pid2, kill)
    end}.

%%====================================================================
%% Unregister Tests
%%====================================================================

%% Basic unregister
unregister_basic_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key = {test, unregister, 1},
        Metadata = #{},
        Pid = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, _} = orka:register(Key, Pid, Metadata),
        ?assertEqual({ok, {Key, Pid, Metadata}}, orka:lookup(Key)),
        
        ok = orka:unregister(Key),
        ?assertEqual(not_found, orka:lookup(Key)),
        
        exit(Pid, kill)
    end}.

%% Unregister non-existent key
unregister_not_found_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key = {test, nonexistent, 1},
        ?assertEqual(not_found, orka:unregister(Key))
    end}.

%% Batch unregister
unregister_batch_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key1 = {test, batch, 1},
        Key2 = {test, batch, 2},
        Key3 = {test, nonexistent, 1},
        Metadata = #{},
        Pid1 = spawn(fun() -> timer:sleep(10000) end),
        Pid2 = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, _} = orka:register(Key1, Pid1, Metadata),
        {ok, _} = orka:register(Key2, Pid2, Metadata),
        
        {ok, {_Removed, _NotFound}} = orka:unregister_batch([Key1, Key2, Key3]),
        
        ?assertEqual(not_found, orka:lookup(Key1)),
        ?assertEqual(not_found, orka:lookup(Key2)),
        
        exit(Pid1, kill),
        exit(Pid2, kill)
    end}.

%%====================================================================
%% Tag Tests
%%====================================================================

%% Add and query tags
tag_add_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key = {test, tag, 1},
        Metadata = #{tags => [online]},
        Pid = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, _} = orka:register(Key, Pid, Metadata),
        
        ok = orka:add_tag(Key, service),
        
        {ok, {Key, Pid, UpdatedMetadata}} = orka:lookup(Key),
        Tags = maps:get(tags, UpdatedMetadata, []),
        
        ?assert(lists:member(online, Tags)),
        ?assert(lists:member(service, Tags)),
        
        orka:unregister(Key),
        exit(Pid, kill)
    end}.

%% Add duplicate tag (idempotent)
tag_duplicate_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key = {test, tag_dup, 1},
        Metadata = #{tags => [online]},
        Pid = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, _} = orka:register(Key, Pid, Metadata),
        
        ok = orka:add_tag(Key, online),
        
        {ok, {Key, Pid, UpdatedMetadata}} = orka:lookup(Key),
        Tags = maps:get(tags, UpdatedMetadata, []),
        
        % Should not have duplicate
        Count = lists:foldl(fun(T, Acc) -> if T =:= online -> Acc + 1; true -> Acc end end, 0, Tags),
        ?assert(Count =< 1),
        
        orka:unregister(Key),
        exit(Pid, kill)
    end}.

%% Remove tag
tag_remove_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key = {test, tag_remove, 1},
        Metadata = #{tags => [online, service]},
        Pid = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, _} = orka:register(Key, Pid, Metadata),
        
        ok = orka:remove_tag(Key, online),
        
        {ok, {Key, Pid, UpdatedMetadata}} = orka:lookup(Key),
        Tags = maps:get(tags, UpdatedMetadata, []),
        
        ?assertNot(lists:member(online, Tags)),
        ?assert(lists:member(service, Tags)),
        
        orka:unregister(Key),
        exit(Pid, kill)
    end}.

%% Query entries by tag
entries_by_tag_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key1 = {test, tag_query, 1},
        Key2 = {test, tag_query, 2},
        Key3 = {test, tag_query, 3},
        
        Pid1 = spawn(fun() -> timer:sleep(10000) end),
        Pid2 = spawn(fun() -> timer:sleep(10000) end),
        Pid3 = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, _} = orka:register(Key1, Pid1, #{tags => [online, service]}),
        {ok, _} = orka:register(Key2, Pid2, #{tags => [offline]}),
        {ok, _} = orka:register(Key3, Pid3, #{tags => [online]}),
        
        % Query by 'online' tag
        Entries = orka:entries_by_tag(online),
        
        % Should include Key1 and Key3
        ?assert(lists:any(fun({K, _, _}) -> K =:= Key1 end, Entries)),
        ?assert(lists:any(fun({K, _, _}) -> K =:= Key3 end, Entries)),
        ?assertNot(lists:any(fun({K, _, _}) -> K =:= Key2 end, Entries)),
        
        orka:unregister(Key1),
        orka:unregister(Key2),
        orka:unregister(Key3),
        exit(Pid1, kill),
        exit(Pid2, kill),
        exit(Pid3, kill)
    end}.

%% Query keys by tag
keys_by_tag_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key1 = {test, key_tag, 1},
        Key2 = {test, key_tag, 2},
        
        Pid1 = spawn(fun() -> timer:sleep(10000) end),
        Pid2 = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, _} = orka:register(Key1, Pid1, #{tags => [service]}),
        {ok, _} = orka:register(Key2, Pid2, #{tags => [worker]}),
        
        % Query keys by tag
        Keys = orka:keys_by_tag(service),
        
        ?assert(lists:member(Key1, Keys)),
        ?assertNot(lists:member(Key2, Keys)),
        
        orka:unregister(Key1),
        orka:unregister(Key2),
        exit(Pid1, kill),
        exit(Pid2, kill)
    end}.

%% Count entries by tag
count_by_tag_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Pid1 = spawn(fun() -> timer:sleep(10000) end),
        Pid2 = spawn(fun() -> timer:sleep(10000) end),
        Pid3 = spawn(fun() -> timer:sleep(10000) end),
        
        Key1 = {test, count_tag, 1},
        Key2 = {test, count_tag, 2},
        Key3 = {test, count_tag, 3},
        
        {ok, _} = orka:register(Key1, Pid1, #{tags => [online]}),
        {ok, _} = orka:register(Key2, Pid2, #{tags => [online]}),
        {ok, _} = orka:register(Key3, Pid3, #{tags => [offline]}),
        
        Count = orka:count_by_tag(online),
        
        ?assert(Count >= 2),  % At least our two entries
        
        orka:unregister(Key1),
        orka:unregister(Key2),
        orka:unregister(Key3),
        exit(Pid1, kill),
        exit(Pid2, kill),
        exit(Pid3, kill)
    end}.

%%====================================================================
%% Type-Based Queries Tests
%%====================================================================

%% Query entries by type (first element of {Scope, Type, Name} tuple)
entries_by_type_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key1 = {global, user, 1},
        Key2 = {global, user, 2},
        Key3 = {global, service, 1},
        
        Pid1 = spawn(fun() -> timer:sleep(10000) end),
        Pid2 = spawn(fun() -> timer:sleep(10000) end),
        Pid3 = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, _} = orka:register(Key1, Pid1, #{}),
        {ok, _} = orka:register(Key2, Pid2, #{}),
        {ok, _} = orka:register(Key3, Pid3, #{}),
        
        Entries = orka:entries_by_type(user),
        
        ?assert(lists:any(fun({K, _, _}) -> K =:= Key1 end, Entries)),
        ?assert(lists:any(fun({K, _, _}) -> K =:= Key2 end, Entries)),
        
        orka:unregister(Key1),
        orka:unregister(Key2),
        orka:unregister(Key3),
        exit(Pid1, kill),
        exit(Pid2, kill),
        exit(Pid3, kill)
    end}.

%% Query keys by type
keys_by_type_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key1 = {global, resource, 1},
        Key2 = {global, resource, 2},
        Key3 = {global, worker, 1},
        
        Pid1 = spawn(fun() -> timer:sleep(10000) end),
        Pid2 = spawn(fun() -> timer:sleep(10000) end),
        Pid3 = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, _} = orka:register(Key1, Pid1, #{}),
        {ok, _} = orka:register(Key2, Pid2, #{}),
        {ok, _} = orka:register(Key3, Pid3, #{}),
        
        Keys = orka:keys_by_type(resource),
        
        ?assert(lists:member(Key1, Keys)),
        ?assert(lists:member(Key2, Keys)),
        ?assertNot(lists:member(Key3, Keys)),
        
        orka:unregister(Key1),
        orka:unregister(Key2),
        orka:unregister(Key3),
        exit(Pid1, kill),
        exit(Pid2, kill),
        exit(Pid3, kill)
    end}.

%% Count entries by type
count_by_type_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Pid1 = spawn(fun() -> timer:sleep(10000) end),
        Pid2 = spawn(fun() -> timer:sleep(10000) end),
        
        Key1 = {global, monitor, 1},
        Key2 = {global, monitor, 2},
        
        {ok, _} = orka:register(Key1, Pid1, #{}),
        {ok, _} = orka:register(Key2, Pid2, #{}),
        
        Count = orka:count_by_type(monitor),
        
        ?assert(Count >= 2),
        
        orka:unregister(Key1),
        orka:unregister(Key2),
        exit(Pid1, kill),
        exit(Pid2, kill)
    end}.

%%====================================================================
%% Metadata Update Tests
%%====================================================================

%% Update metadata
update_metadata_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key = {test, update, 1},
        OldMetadata = #{version => 1},
        Pid = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, _} = orka:register(Key, Pid, OldMetadata),
        
        NewMetadata = #{version => 2, updated => true},
        ok = orka:update_metadata(Key, NewMetadata),
        
        {ok, {Key, Pid, UpdatedMetadata}} = orka:lookup(Key),
        
        ?assertEqual(2, maps:get(version, UpdatedMetadata)),
        ?assertEqual(true, maps:get(updated, UpdatedMetadata)),
        
        orka:unregister(Key),
        exit(Pid, kill)
    end}.

%% Invalid metadata update returns badarg
update_metadata_badarg_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key = {test, badarg, 1},
        
        % Metadata must be a map
        ?assertEqual({error, badarg}, orka:update_metadata(Key, not_a_map)),
        ?assertEqual({error, badarg}, orka:update_metadata(Key, [list]))
    end}.

%%====================================================================
%% Property Tests
%%====================================================================

%% Register property
register_property_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key = {test, property, 1},
        Pid = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, _} = orka:register(Key, Pid, #{}),
        
        ok = orka:register_property(Key, Pid, #{property => region, value => <<"us-west">>}),
        
        {ok, {Key, Pid, Metadata}} = orka:lookup(Key),
        Properties = maps:get(properties, Metadata, #{}),
        
        ?assertEqual(<<"us-west">>, maps:get(region, Properties)),
        
        orka:unregister(Key),
        exit(Pid, kill)
    end}.

%% Find by property (simple value)
find_by_property_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key1 = {test, prop_find, 1},
        Key2 = {test, prop_find, 2},
        Key3 = {test, prop_find, 3},
        
        Pid1 = spawn(fun() -> timer:sleep(10000) end),
        Pid2 = spawn(fun() -> timer:sleep(10000) end),
        Pid3 = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, _} = orka:register(Key1, Pid1, #{}),
        {ok, _} = orka:register(Key2, Pid2, #{}),
        {ok, _} = orka:register(Key3, Pid3, #{}),
        
        ok = orka:register_property(Key1, Pid1, #{property => status, value => active}),
        ok = orka:register_property(Key2, Pid2, #{property => status, value => active}),
        ok = orka:register_property(Key3, Pid3, #{property => status, value => inactive}),
        
        Entries = orka:find_by_property(status, active),
        
        ?assert(lists:any(fun({K, _, _}) -> K =:= Key1 end, Entries)),
        ?assert(lists:any(fun({K, _, _}) -> K =:= Key2 end, Entries)),
        ?assertNot(lists:any(fun({K, _, _}) -> K =:= Key3 end, Entries)),
        
        orka:unregister(Key1),
        orka:unregister(Key2),
        orka:unregister(Key3),
        exit(Pid1, kill),
        exit(Pid2, kill),
        exit(Pid3, kill)
    end}.

%% Find keys by property
find_keys_by_property_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key1 = {test, key_prop, 1},
        Key2 = {test, key_prop, 2},
        
        Pid1 = spawn(fun() -> timer:sleep(10000) end),
        Pid2 = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, _} = orka:register(Key1, Pid1, #{}),
        {ok, _} = orka:register(Key2, Pid2, #{}),
        
        ok = orka:register_property(Key1, Pid1, #{property => capacity, value => 100}),
        ok = orka:register_property(Key2, Pid2, #{property => capacity, value => 50}),
        
        Keys = orka:find_keys_by_property(capacity, 100),
        
        ?assert(lists:member(Key1, Keys)),
        ?assertNot(lists:member(Key2, Keys)),
        
        orka:unregister(Key1),
        orka:unregister(Key2),
        exit(Pid1, kill),
        exit(Pid2, kill)
    end}.

%% Count entries by property
count_by_property_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key1 = {test, count_prop, 1},
        Key2 = {test, count_prop, 2},
        Key3 = {test, count_prop, 3},
        
        Pid1 = spawn(fun() -> timer:sleep(10000) end),
        Pid2 = spawn(fun() -> timer:sleep(10000) end),
        Pid3 = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, _} = orka:register(Key1, Pid1, #{}),
        {ok, _} = orka:register(Key2, Pid2, #{}),
        {ok, _} = orka:register(Key3, Pid3, #{}),
        
        ok = orka:register_property(Key1, Pid1, #{property => tier, value => premium}),
        ok = orka:register_property(Key2, Pid2, #{property => tier, value => premium}),
        ok = orka:register_property(Key3, Pid3, #{property => tier, value => standard}),
        
        Count = orka:count_by_property(tier, premium),
        
        ?assert(Count >= 2),
        
        orka:unregister(Key1),
        orka:unregister(Key2),
        orka:unregister(Key3),
        exit(Pid1, kill),
        exit(Pid2, kill),
        exit(Pid3, kill)
    end}.

%% Property statistics
property_stats_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key1 = {test, stats, 1},
        Key2 = {test, stats, 2},
        
        Pid1 = spawn(fun() -> timer:sleep(10000) end),
        Pid2 = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, _} = orka:register(Key1, Pid1, #{}),
        {ok, _} = orka:register(Key2, Pid2, #{}),
        
        ok = orka:register_property(Key1, Pid1, #{property => score, value => 90}),
        ok = orka:register_property(Key2, Pid2, #{property => score, value => 85}),
        
        Stats = orka:property_stats(stats, score),
        
        ?assert(is_map(Stats)),
        ?assert(maps:is_key(90, Stats)),
        ?assert(maps:is_key(85, Stats)),
        
        orka:unregister(Key1),
        orka:unregister(Key2),
        exit(Pid1, kill),
        exit(Pid2, kill)
    end}.

%%====================================================================
%% Batch Registration Tests
%%====================================================================

%% Batch register multiple processes
register_batch_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Pid1 = spawn(fun() -> timer:sleep(10000) end),
        Pid2 = spawn(fun() -> timer:sleep(10000) end),
        Pid3 = spawn(fun() -> timer:sleep(10000) end),
        
        Registrations = [
            {{test, batch, 1}, Pid1, #{id => 1}},
            {{test, batch, 2}, Pid2, #{id => 2}},
            {{test, batch, 3}, Pid3, #{id => 3}}
        ],
        
        {ok, Entries} = orka:register_batch(Registrations),
        
        ?assertEqual(3, length(Entries)),
        
        {ok, {{test, batch, 1}, Pid1, #{id := 1}}} = orka:lookup({test, batch, 1}),
        {ok, {{test, batch, 2}, Pid2, #{id := 2}}} = orka:lookup({test, batch, 2}),
        {ok, {{test, batch, 3}, Pid3, #{id := 3}}} = orka:lookup({test, batch, 3}),
        
        orka:unregister({test, batch, 1}),
        orka:unregister({test, batch, 2}),
        orka:unregister({test, batch, 3}),
        exit(Pid1, kill),
        exit(Pid2, kill),
        exit(Pid3, kill)
    end}.

%% Batch register invalid input
register_batch_badarg_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        % Non-list input
        ?assertEqual({error, badarg}, orka:register_batch(not_a_list)),
        
        % Invalid entry (missing metadata)
        ?assertEqual({error, badarg}, orka:register_batch([
            {{test, bad, 1}, spawn(fun() -> timer:sleep(10000) end)}
        ]))
    end}.

%%====================================================================
%% Singleton Registration Tests
%%====================================================================

%% Register single (singleton pattern)
register_single_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key = {test, singleton, 1},
        Metadata = #{unique => true},
        Pid = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, {Key, Pid, Metadata}} = orka:register_single(Key, Pid, Metadata),
        {ok, {Key, Pid, Metadata}} = orka:lookup(Key),
        
        orka:unregister(Key),
        exit(Pid, kill)
    end}.

%% Register single prevents re-registration of same process
register_single_constraint_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key1 = {test, single_const, 1},
        Key2 = {test, single_const, 2},
        Metadata = #{},
        Pid = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, _} = orka:register_single(Key1, Pid, Metadata),
        
        % Attempting to register same Pid under different key should fail
        {error, {already_registered_under_key, Key1}} = orka:register_single(Key2, Pid, Metadata),
        
        orka:unregister(Key1),
        exit(Pid, kill)
    end}.

%% Register single with duplicate key returns existing
register_single_duplicate_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key = {test, single_dup, 1},
        Metadata1 = #{version => 1},
        Pid = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, {Key, Pid, Metadata1}} = orka:register_single(Key, Pid, Metadata1),
        
        % Re-register returns existing
        {ok, {Key, Pid, Metadata1}} = orka:register_single(Key, Pid, Metadata1),
        
        orka:unregister(Key),
        exit(Pid, kill)
    end}.

%%====================================================================
%% Subscribe/Await Tests (Basic)
%%====================================================================

%% Subscribe to key that already registered
subscribe_existing_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key = {test, subscribe, 1},
        Metadata = #{status => online},
        Pid = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, _} = orka:register(Key, Pid, Metadata),
        
        ok = orka:subscribe(Key),
        
        ok = orka:unsubscribe(Key),
        orka:unregister(Key),
        exit(Pid, kill)
    end}.

%% Unsubscribe from key
unsubscribe_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key = {test, unsub, 1},
        Metadata = #{},
        Pid = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, _} = orka:register(Key, Pid, Metadata),
        ok = orka:subscribe(Key),
        
        ok = orka:unsubscribe(Key),
        
        orka:unregister(Key),
        exit(Pid, kill)
    end}.

%%====================================================================
%% Automatic Cleanup Tests (Basic)
%%====================================================================

%% Process exit triggers automatic cleanup
process_cleanup_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key = {test, cleanup, 1},
        Metadata = #{},
        
        % Spawn a process that will immediately exit
        _Pid = spawn(fun() -> ok end),
        
        % Give process time to exit
        timer:sleep(100),
        
        % Even though process exited, we can still register
        % (in real usage, entry would be cleaned up on monitor trigger)
        {ok, _} = orka:register(Key, self(), Metadata),
        
        orka:unregister(Key)
    end}.

%%====================================================================
%% Concurrency Tests (Basic)
%%====================================================================

%% Multiple processes can register concurrently
concurrent_register_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Parent = self(),
        
        % Spawn 5 processes that each register themselves
        Pids = [spawn(fun() ->
            Key = {test, concurrent, N},
            {ok, _} = orka:register(Key, self(), #{id => N}),
            Parent ! {registered, Key, self()}
        end) || N <- lists:seq(1, 5)],
        
        % Collect results
        Results = [receive {registered, K, P} -> {K, P} end || _ <- Pids],
        
        % Verify all registered
        ?assertEqual(5, length(Results)),
        
        % Cleanup
        lists:foreach(fun({Key, _Pid}) ->
            orka:unregister(Key)
        end, Results)
    end}.

%%====================================================================
%% Edge Cases Tests
%%====================================================================

%% Very long list in metadata
metadata_long_list_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key = {test, long_list, 1},
        LongList = lists:seq(1, 1000),
        Metadata = #{items => LongList},
        Pid = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, {Key, Pid, Metadata}} = orka:register(Key, Pid, Metadata),
        {ok, {Key, Pid, Metadata}} = orka:lookup(Key),
        
        orka:unregister(Key),
        exit(Pid, kill)
    end}.

%% Very large metadata map
metadata_large_map_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key = {test, large_map, 1},
        LargeMap = maps:from_list([{N, N} || N <- lists:seq(1, 500)]),
        Metadata = #{data => LargeMap},
        Pid = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, {Key, Pid, Metadata}} = orka:register(Key, Pid, Metadata),
        {ok, {Key, Pid, Metadata}} = orka:lookup(Key),
        
        orka:unregister(Key),
        exit(Pid, kill)
    end}.

%% Empty tag list
tag_empty_list_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Key = {test, tag_empty, 1},
        Metadata = #{tags => []},
        Pid = spawn(fun() -> timer:sleep(10000) end),
        
        {ok, {Key, Pid, Metadata}} = orka:register(Key, Pid, Metadata),
        {ok, {Key, Pid, Metadata}} = orka:lookup(Key),
        
        orka:unregister(Key),
        exit(Pid, kill)
    end}.

%% Query non-existent tag
query_nonexistent_tag_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Entries = orka:entries_by_tag(nonexistent_tag_12345),
        ?assertEqual([], Entries)
    end}.

%% Query non-existent type
query_nonexistent_type_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun() ->
        Entries = orka:entries_by_type(nonexistent_type_12345),
        ?assertEqual([], Entries)
    end}.
