%% File: apps/orka/src/orka_meta.erl
-module(orka_meta).

-export([
    normalize/1, normalize/2,
    normalize_tag/2,
    normalize_prop_key/2,
    normalize_prop_val/2,
    extract_indexables/2
]).

-type meta() :: map().
-type opts() :: map().

-spec normalize(meta()) -> {ok, meta()} | {error, term()}.
normalize(Meta) ->
    normalize(Meta, #{}).

-spec normalize(meta(), opts()) -> {ok, meta()} | {error, term()}.
normalize(Meta0, UserOpts) when is_map(Meta0), is_map(UserOpts) ->
    Opts = orka_meta_policy:merge_opts(UserOpts),

    %% Reserved keys: tags (list), properties (map)
    Tags0 = maps:get(tags, Meta0, []),
    Props0 = maps:get(properties, Meta0, #{}),

    case normalize_tags(Tags0, Opts) of
        {ok, Tags1} ->
            case normalize_properties(Props0, Opts) of
                {ok, Props1} ->
                    %% Ensure canonical reserved keys exist
                    Meta1 = Meta0#{tags => Tags1, properties => Props1},
                    {ok, Meta1};
                {error, R2} ->
                    {error, R2}
            end;
        {error, R1} ->
            {error, R1}
    end;
normalize(_Meta0, _UserOpts) ->
    {error, {meta_not_a_map}}.

%% Return canonical tags list and property pairs for indexing convenience.
-spec extract_indexables(meta(), opts()) ->
    {ok, {[binary()], [{binary(), term()}]}} | {error, term()}.
extract_indexables(Meta0, UserOpts) ->
    case normalize(Meta0, UserOpts) of
        {ok, Meta1} ->
            Tags = maps:get(tags, Meta1, []),
            Props = maps:get(properties, Meta1, #{}),
            {ok, {Tags, maps:to_list(Props)}};
        {error, R} ->
            {error, R}
    end.

%% ----------------------
%% Tags
%% ----------------------

-spec normalize_tags(term(), opts()) -> {ok, [binary()]} | {error, term()}.
normalize_tags(Tags0, Opts) ->
    case Tags0 of
        [] ->
            {ok, []};
        L when is_list(L) ->
            MaxTags = maps:get(max_tags, Opts),
            case length_limited(L, MaxTags) of
                ok ->
                    case normalize_each_tag(L, Opts, []) of
                        {ok, Tags1} ->
                            %% sort + unique canonical
                            {ok, lists:usort(Tags1)};
                        {error, R} ->
                            {error, R}
                    end;
                {error, RLen} ->
                    {error, RLen}
            end;
        _ ->
            {error, {tags_not_a_list}}
    end.

-spec normalize_each_tag([term()], opts(), [binary()]) -> {ok, [binary()]} | {error, term()}.
normalize_each_tag([], _Opts, Acc) ->
    {ok, lists:reverse(Acc)};
normalize_each_tag([T | Rest], Opts, Acc) ->
    case normalize_tag(T, Opts) of
        {ok, T1} ->
            normalize_each_tag(Rest, Opts, [T1 | Acc]);
        {error, R} ->
            {error, R}
    end.

-spec normalize_tag(term(), opts()) -> {ok, binary()} | {error, term()}.
normalize_tag(Tag0, Opts) ->
    AllowAtoms = maps:get(allow_atoms, Opts),
    CoerceStrings = maps:get(coerce_strings, Opts),
    AllowEmpty = maps:get(allow_empty_tags, Opts),
    MaxBytes = maps:get(max_tag_bytes, Opts, #{}),

    case Tag0 of
        B when is_binary(B) ->
            validate_bin(B, MaxBytes, AllowEmpty, tag);
        A when is_atom(A), AllowAtoms =:= true ->
            validate_bin(atom_to_binary(A, utf8), MaxBytes, AllowEmpty, tag);
        L when is_list(L), CoerceStrings =:= true ->
            case safe_to_utf8_binary(L) of
                {ok, B2} -> validate_bin(B2, MaxBytes, AllowEmpty, tag);
                {error, R} -> {error, {tag_not_chardata, R}}
            end;
        _ ->
            {error, {invalid_tag, Tag0}}
    end.

%% ----------------------
%% Properties
%% ----------------------

-spec normalize_properties(term(), opts()) -> {ok, map()} | {error, term()}.
normalize_properties(Props0, Opts) ->
    case Props0 of
        P when is_map(P) ->
            MaxProps = maps:get(max_properties, Opts),
            if
                map_size(P) =< MaxProps ->
                    normalize_properties_kv(maps:to_list(P), Opts, #{});
                true ->
                    {error, {too_many_properties, map_size(P), MaxProps}}
            end;
        #{} ->
            {ok, #{}};
        _ ->
            {error, {properties_not_a_map}}
    end.

-spec normalize_properties_kv([{term(), term()}], opts(), map()) -> {ok, map()} | {error, term()}.
normalize_properties_kv([], _Opts, Acc) ->
    {ok, Acc};
normalize_properties_kv([{K0, V0} | Rest], Opts, Acc) ->
    case normalize_prop_key(K0, Opts) of
        {ok, K1} ->
            case normalize_prop_val(V0, Opts) of
                {ok, V1} ->
                    normalize_properties_kv(Rest, Opts, Acc#{K1 => V1});
                {error, Rv} ->
                    {error, {invalid_property_value, K0, Rv}}
            end;
        {error, Rk} ->
            {error, {invalid_property_key, K0, Rk}}
    end.

-spec normalize_prop_key(term(), opts()) -> {ok, binary()} | {error, term()}.
normalize_prop_key(Key0, Opts) ->
    AllowAtoms = maps:get(allow_atoms, Opts),
    CoerceStrings = maps:get(coerce_strings, Opts),
    MaxBytes = maps:get(max_prop_key_bytes, Opts),

    case Key0 of
        B when is_binary(B) ->
            validate_bin(B, MaxBytes, false, prop_key);
        A when is_atom(A), AllowAtoms =:= true ->
            validate_bin(atom_to_binary(A, utf8), MaxBytes, false, prop_key);
        L when is_list(L), CoerceStrings =:= true ->
            case safe_to_utf8_binary(L) of
                {ok, B2} -> validate_bin(B2, MaxBytes, false, prop_key);
                {error, R} -> {error, {prop_key_not_chardata, R}}
            end;
        _ ->
            {error, {invalid_prop_key, Key0}}
    end.

-spec normalize_prop_val(term(), opts()) -> {ok, term()} | {error, term()}.
normalize_prop_val(Val0, Opts) ->
    CoerceStrings = maps:get(coerce_strings, Opts),
    CoerceAtomsToBin = maps:get(coerce_atoms_to_binary_values, Opts),
    MaxBin = maps:get(max_prop_bin_bytes, Opts),
    AllowNull = maps:get(allow_null_values, Opts),
    NullAtom = maps:get(null_atom, Opts),

    case Val0 of
        true -> {ok, true};
        false -> {ok, false};
        NullAtom when AllowNull =:= true -> {ok, NullAtom};

        I when is_integer(I) -> {ok, I};
        F when is_float(F) -> {ok, F};

        B when is_binary(B) ->
            validate_bin_value(B, MaxBin);

        A when is_atom(A), A =/= true, A =/= false, A =/= NullAtom ->
            if
                CoerceAtomsToBin =:= true ->
                    validate_bin_value(atom_to_binary(A, utf8), MaxBin);
                true ->
                    {error, {atom_value_not_allowed, A}}
            end;

        L when is_list(L), CoerceStrings =:= true ->
            case safe_to_utf8_binary(L) of
                {ok, B2} -> validate_bin_value(B2, MaxBin);
                {error, R} -> {error, {prop_value_not_chardata, R}}
            end;

        %% Disallowed for RA safety + ETS index sanity
        Pid when is_pid(Pid) -> {error, {disallowed_type, pid}};
        Ref when is_reference(Ref) -> {error, {disallowed_type, reference}};
        Fun when is_function(Fun) -> {error, {disallowed_type, 'fun'}};
        Port when is_port(Port) -> {error, {disallowed_type, port}};
        Map when is_map(Map) -> {error, {disallowed_type, map}};
        Tuple when is_tuple(Tuple) -> {error, {disallowed_type, tuple}};
        _ ->
            {error, {disallowed_type, unknown}}
    end.

%% ----------------------
%% Helpers
%% ----------------------

-spec validate_bin(binary(), non_neg_integer(), boolean(), tag | prop_key) ->
    {ok, binary()} | {error, term()}.
validate_bin(B, MaxBytes, AllowEmpty, Kind) ->
    case byte_size(B) of
        0 when AllowEmpty =:= false ->
            {error, {empty_not_allowed, Kind}};
        Sz when Sz =< MaxBytes ->
            {ok, B};
        Sz ->
            {error, {too_large, Kind, Sz, MaxBytes}}
    end.

-spec validate_bin_value(binary(), non_neg_integer()) -> {ok, binary()} | {error, term()}.
validate_bin_value(B, MaxBytes) ->
    case byte_size(B) of
        Sz when Sz =< MaxBytes ->
            {ok, B};
        Sz ->
            {error, {too_large, prop_value_binary, Sz, MaxBytes}}
    end.

%% Avoid O(n) length on giant lists; stop at limit+1.
-spec length_limited(list(), non_neg_integer()) -> ok | {error, term()}.
length_limited(List, Max) ->
    case length_limited(List, Max, 0) of
        ok -> ok;
        {error, _}=E -> E
    end.

length_limited([], _Max, _N) ->
    ok;
length_limited([_ | _], Max, N) when N >= Max ->
    {error, {too_many_tags, N + 1, Max}};
length_limited([_ | Rest], Max, N) ->
    length_limited(Rest, Max, N + 1).

-spec safe_to_utf8_binary(term()) -> {ok, binary()} | {error, term()}.
safe_to_utf8_binary(Chardata) ->
    try
        %% unicode:characters_to_binary/1 throws on invalid sequences
        {ok, unicode:characters_to_binary(Chardata)}
    catch
        C:R ->
            {error, {C, R}}
    end.
