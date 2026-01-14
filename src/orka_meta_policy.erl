%% File: apps/orka/src/orka_meta_policy.erl
-module(orka_meta_policy).

-export([defaults/0, merge_opts/1]).

-type opts() :: map().

-spec defaults() -> opts().
defaults() ->
    #{
        %% Canonical output is binaries-first; allow atoms at boundary.
        allow_atoms => true,

        %% Accept "strings"/chardata at boundary and coerce to UTF-8 binaries.
        coerce_strings => true,

        %% Convert non-boolean/non-null atoms used as values to binaries.
        %% e.g. role => primary   => <<"primary">>
        coerce_atoms_to_binary_values => true,

        %% Validation limits (defensive for ETS + RA)
        max_tags => 64,
        max_tag_bytes => 128,

        max_properties => 64,
        max_prop_key_bytes => 128,
        max_prop_bin_bytes => 1024,

        %% Tag rules
        allow_empty_tags => false,

        %% Property rules
        allow_null_values => true,
        null_atom => null
    }.

-spec merge_opts(opts()) -> opts().
merge_opts(UserOpts) when is_map(UserOpts) ->
    maps:merge(defaults(), UserOpts).
