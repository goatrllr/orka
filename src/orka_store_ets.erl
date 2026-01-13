%% File: apps/orka/src/orka_store_ets.erl
-module(orka_store_ets).
-behaviour(orka_store).

-include_lib("stdlib/include/ms_transform.hrl").
-compile({parse_transform, ms_transform}).

-export([init/1, terminate/2]).
-export([get/2, put/4, del/2]).
-export([select_by_type/2, select_by_tag/2,
         select_by_property/3, select_by_property/4]).
-export([count_by_type/2, count_by_tag/2, count_by_property/3,
         property_stats/3]).
-export([all/1]).
-export([put_many/2, del_many/2]).

-define(REGISTRY, orka_table).
-define(TAG_IDX,  orka_tag_index).
-define(PROP_IDX, orka_property_index).

-record(store, {
    reg_tab  :: ets:tid(),
    tag_tab  :: ets:tid(),
    prop_tab :: ets:tid()
}).

init(Opts) ->
    {RegName, TagName, PropName} = table_names(maps:get(table_prefix, Opts, undefined)),
    Reg = ensure_table(RegName, [set, private, named_table]),
    Tag = ensure_table(TagName,  [bag, private, named_table]),
    Prop= ensure_table(PropName, [bag, private, named_table]),
    {ok, #store{reg_tab=Reg, tag_tab=Tag, prop_tab=Prop}}.

terminate(_Reason, _Store) ->
    ok.

get(Key, #store{reg_tab=Reg}) ->
    case ets:lookup(Reg, Key) of
        [Entry] -> {ok, Entry};
        [] -> not_found
    end.

put(Key, Pid, Meta, Store=#store{reg_tab=Reg, tag_tab=Tag, prop_tab=Prop}) ->
    Entry = {Key, Pid, Meta},
    ets:insert(Reg, Entry),
    %% rebuild indexes for this Key
    ets:match_delete(Tag,  {{tag, '$1'}, Key}),
    ets:match_delete(Prop, {{property, '$1', '$2'}, Key}),
    index_tags(Key, Meta, Tag),
    index_props(Key, Meta, Prop),
    {ok, Entry, Store}.

del(Key, Store=#store{reg_tab=Reg, tag_tab=Tag, prop_tab=Prop}) ->
    case ets:lookup(Reg, Key) of
        [] ->
            {not_found, Store};
        [_] ->
            ets:delete(Reg, Key),
            ets:match_delete(Tag,  {{tag, '$1'}, Key}),
            ets:match_delete(Prop, {{property, '$1', '$2'}, Key}),
            {ok, Store}
    end.

%% queries + counts use matchspecs/select_count

select_by_type(Type, #store{reg_tab=Reg}) ->
    ets:select(Reg, ets:fun2ms(fun({Key, Pid, Meta}) when
        is_tuple(Key) andalso size(Key) >= 2 andalso element(2, Key) =:= Type
    -> {Key, Pid, Meta} end)).

select_by_tag(Tag, #store{reg_tab=Reg, tag_tab=TagTab}) ->
    Keys = ets:select(TagTab, [{{{tag, Tag}, '$1'}, [], ['$1']}]),
    lists:filtermap(fun(Key) ->
        case ets:lookup(Reg, Key) of
            [Entry] -> {true, Entry};
            [] -> false
        end
    end, Keys).

select_by_property(Prop, Value, #store{reg_tab=Reg, prop_tab=PropTab}) ->
    Keys = ets:match_object(PropTab, {{property, Prop, Value}, '$1'}),
    lists:filtermap(fun({{property, _, _}, Key}) ->
        case ets:lookup(Reg, Key) of
            [Entry] -> {true, Entry};
            [] -> false
        end
    end, Keys).

select_by_property(Type, Prop, Value, #store{reg_tab=Reg, prop_tab=PropTab}) ->
    Keys = ets:match_object(PropTab, {{property, Prop, Value}, '$1'}),
    lists:filtermap(fun({{property, _, _}, Key}) ->
        case ets:lookup(Reg, Key) of
            [{RegKey, _Pid, _Meta} = Entry] when is_tuple(RegKey), size(RegKey) >= 2,
                                               element(2, RegKey) =:= Type ->
                {true, Entry};
            _ ->
                false
        end
    end, Keys).

all(#store{reg_tab=Reg}) ->
    ets:tab2list(Reg).

count_by_type(Type, #store{reg_tab=Reg}) ->
    ets:select_count(Reg, ets:fun2ms(fun({Key, _Pid, _Meta}) when
        is_tuple(Key) andalso size(Key) >= 2 andalso element(2, Key) =:= Type
    -> true end)).

count_by_tag(Tag, #store{tag_tab=TagTab}) ->
    ets:select_count(TagTab, [{{{tag, Tag}, '_'}, [], [true]}]).

count_by_property(Prop, Value, #store{prop_tab=PropTab}) ->
    ets:select_count(PropTab, [{{{property, Prop, Value}, '_'}, [], [true]}]).

property_stats(Type, Prop, #store{reg_tab=Reg, prop_tab=PropTab}) ->
    Entries = ets:match_object(PropTab, {{property, Prop, '$1'}, '$2'}),
    lists:foldl(fun({{property, _, Value}, Key}, Acc) ->
        case ets:lookup(Reg, Key) of
            [{RegKey, _Pid, _Meta}] when is_tuple(RegKey), size(RegKey) >= 2,
                                         element(2, RegKey) =:= Type ->
                maps:put(Value, maps:get(Value, Acc, 0) + 1, Acc);
            _ ->
                Acc
        end
    end, #{}, Entries).

put_many(Items, Store) ->
    case lists:foldl(fun({Key, Pid, Meta}, {ok, AccEntries, AccStore}) ->
        case put(Key, Pid, Meta, AccStore) of
            {ok, Entry, NewStore} ->
                {ok, [Entry | AccEntries], NewStore};
            {error, Reason} ->
                {error, Reason, AccStore}
        end;
    (_, {error, Reason, AccStore}) ->
        {error, Reason, AccStore}
    end, {ok, [], Store}, Items) of
        {ok, Entries, Store1} ->
            {ok, lists:reverse(Entries), Store1};
        {error, Reason, _Store1} ->
            {error, Reason}
    end.

del_many(Keys, Store) ->
    case lists:foldl(fun(Key, {ok, AccStore}) ->
        case del(Key, AccStore) of
            {ok, NewStore} -> {ok, NewStore};
            {not_found, NewStore} -> {ok, NewStore};
            {error, Reason} -> {error, Reason}
        end;
    (_, {error, Reason}) ->
        {error, Reason}
    end, {ok, Store}, Keys) of
        {ok, Store1} -> {ok, Store1};
        {error, Reason} -> {error, Reason}
    end.
index_tags(Key, Meta, TagTab) ->
    Tags = maps:get(tags, Meta, []),
    lists:foreach(fun(T) -> ets:insert(TagTab, {{tag, T}, Key}) end, Tags).

index_props(Key, Meta, PropTab) ->
    case maps:get(properties, Meta, #{}) of
        Props when is_map(Props) ->
            maps:foreach(
              fun(P, V) -> ets:insert(PropTab, {{property, P, V}, Key}) end,
              Props);
        _ ->
            ok
    end.

ensure_table(Name, Opts) ->
    case ets:whereis(Name) of
        undefined -> ets:new(Name, Opts);
        Tid -> Tid
    end.

table_names(undefined) ->
    {?REGISTRY, ?TAG_IDX, ?PROP_IDX};
table_names(Prefix) when is_atom(Prefix) ->
    {suffix_name(Prefix, "_table"),
     suffix_name(Prefix, "_tag_index"),
     suffix_name(Prefix, "_property_index")};
table_names(Prefix) when is_list(Prefix) ->
    table_names(list_to_atom(Prefix));
table_names(Prefix) when is_binary(Prefix) ->
    table_names(binary_to_atom(Prefix, latin1)).

suffix_name(Prefix, Suffix) ->
    list_to_atom(atom_to_list(Prefix) ++ Suffix).
