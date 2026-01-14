%% File: apps/orka/test/orka_meta_tests.erl
-module(orka_meta_tests).

-include_lib("eunit/include/eunit.hrl").

normalize_tags_atoms_and_binaries_test() ->
    Meta0 = #{tags => [critical, <<"db">>, <<"primary">>, critical]},
    {ok, Meta1} = orka_meta:normalize(Meta0, #{}),
    Tags = maps:get(tags, Meta1),
    ?assertEqual([<<"critical">>, <<"db">>, <<"primary">>], Tags).

normalize_tags_strings_coerce_test() ->
    Meta0 = #{tags => ["alpha", "beta"]},
    {ok, Meta1} = orka_meta:normalize(Meta0, #{coerce_strings => true}),
    ?assertEqual([<<"alpha">>, <<"beta">>], maps:get(tags, Meta1)).

normalize_tags_strings_strict_reject_test() ->
    Meta0 = #{tags => ["alpha"]},
    {error, _} = orka_meta:normalize(Meta0, #{coerce_strings => false}),
    ok.

normalize_tags_limit_test() ->
    Tags = lists:seq(1, 5),
    Meta0 = #{tags => Tags},
    {error, {too_many_tags, _N, 3}} = orka_meta:normalize(Meta0, #{max_tags => 3}),
    ok.

normalize_tags_size_limit_test() ->
    Big = binary:copy(<<"a">>, 200),
    Meta0 = #{tags => [Big]},
    {error, {too_large, tag, 200, 128}} = orka_meta:normalize(Meta0, #{max_tag_bytes => 128}),
    ok.

normalize_properties_keys_atoms_to_binary_test() ->
    Meta0 = #{properties => #{role => primary, <<"shard">> => 2}},
    {ok, Meta1} = orka_meta:normalize(Meta0, #{}),
    Props = maps:get(properties, Meta1),
    ?assertEqual(<<"primary">>, maps:get(<<"role">>, Props)),
    ?assertEqual(2, maps:get(<<"shard">>, Props)).

normalize_properties_string_keys_coerce_test() ->
    Meta0 = #{properties => #{"region" => "us-east-1"}},
    {ok, Meta1} = orka_meta:normalize(Meta0, #{coerce_strings => true}),
    Props = maps:get(properties, Meta1),
    ?assertEqual(<<"us-east-1">>, maps:get(<<"region">>, Props)).

normalize_properties_string_keys_strict_reject_test() ->
    Meta0 = #{properties => #{"region" => <<"x">>}},
    {error, _} = orka_meta:normalize(Meta0, #{coerce_strings => false}),
    ok.

normalize_properties_disallow_pid_value_test() ->
    Meta0 = #{properties => #{<<"pid">> => self()}},
    {error, {invalid_property_value, _K0, {disallowed_type, pid}}} =
        orka_meta:normalize(Meta0, #{}),
    ok.

normalize_properties_disallow_map_value_test() ->
    Meta0 = #{properties => #{<<"m">> => #{a => 1}}},
    {error, {invalid_property_value, _K0, {disallowed_type, map}}} =
        orka_meta:normalize(Meta0, #{}),
    ok.

normalize_properties_binary_value_limit_test() ->
    Big = binary:copy(<<"b">>, 2000),
    Meta0 = #{properties => #{<<"blob">> => Big}},
    {error, {invalid_property_value, _K0, {too_large, prop_value_binary, 2000, 100}}} =
        orka_meta:normalize(Meta0, #{max_prop_bin_bytes => 100}),
    ok.

normalize_properties_null_allowed_test() ->
    Meta0 = #{properties => #{<<"x">> => null}},
    {ok, Meta1} = orka_meta:normalize(Meta0, #{allow_null_values => true}),
    ?assertEqual(null, maps:get(<<"x">>, maps:get(properties, Meta1))).

normalize_properties_null_disallowed_test() ->
    Meta0 = #{properties => #{<<"x">> => null}},
    {error, {invalid_property_value, _K0, {disallowed_type, unknown}}} =
        orka_meta:normalize(Meta0, #{allow_null_values => false}),
    ok.

reserved_keys_defaulted_test() ->
    {ok, Meta1} = orka_meta:normalize(#{}, #{}),
    ?assertEqual([], maps:get(tags, Meta1)),
    ?assertEqual(#{}, maps:get(properties, Meta1)).

extract_indexables_test() ->
    Meta0 = #{tags => [a, <<"b">>], properties => #{role => primary, <<"n">> => 1}},
    {ok, {Tags, Pairs}} = orka_meta:extract_indexables(Meta0, #{}),
    ?assertEqual([<<"a">>, <<"b">>], Tags),
    %% property map order not guaranteed; check via maps
    Props = maps:from_list(Pairs),
    ?assertEqual(<<"primary">>, maps:get(<<"role">>, Props)),
    ?assertEqual(1, maps:get(<<"n">>, Props)).
