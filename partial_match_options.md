# Orca Partial Match Options for Multi-Process Lookups

This document explores patterns for looking up all processes registered for a user/context when using hierarchical key structures and batch registration.

## The Problem

When you batch register multiple services per user:

```erlang
{ok, _Entries} = orca:register_batch([
    {{global, portfolio, UserId}, Meta1},
    {{global, technical, UserId}, Meta2},
    {{global, orders, UserId}, Meta3},
    {{global, risk, UserId}, Meta4}
]),
```

How do you later retrieve all services for a given user? Three approaches:

## Approach 1: Tag-Based Lookup (Recommended)

Use a common tag for all user services, enabling prefix-like queries via tags.

```erlang
%% Registration
register_user_services(UserId) ->
    {ok, _Entries} = orca:register_batch([
        {{global, portfolio, UserId}, #{
            tags => [UserId, portfolio, user_service],
            properties => #{user_id => UserId, service_type => portfolio}
        }},
        {{global, technical, UserId}, #{
            tags => [UserId, technical, user_service],
            properties => #{user_id => UserId, service_type => technical}
        }},
        {{global, orders, UserId}, #{
            tags => [UserId, orders, user_service],
            properties => #{user_id => UserId, service_type => orders}
        }},
        {{global, risk, UserId}, #{
            tags => [UserId, risk, user_service],
            properties => #{user_id => UserId, service_type => risk}
        }}
    ]).

%% Queries - All existing orca functions work!

%% Get all services for a user (fast - O(1) with tag index)
all_services_for_user(UserId) ->
    orca:entries_by_tag(UserId).

%% Get all portfolio services (across all users)
all_portfolio_services() ->
    orca:entries_by_tag(portfolio).

%% Get only portfolio service for a specific user
portfolio_for_user(UserId) ->
    AllUserServices = orca:entries_by_tag(UserId),
    [Pid || {_Key, Pid, Meta} <- AllUserServices,
            lists:member(portfolio, maps:get(tags, Meta, []))].

%% Count services for a user
user_service_count(UserId) ->
    orca:count_by_tag(UserId).

%% Get "healthy" services for a user (assuming you add healthy tag)
healthy_user_services(UserId) ->
    UserServices = orca:entries_by_tag(UserId),
    [Pid || {_Key, Pid, Meta} <- UserServices,
            lists:member(healthy, maps:get(tags, Meta, []))].

%% Get service distribution by user
service_stats_for_user(UserId) ->
    Entries = orca:entries_by_tag(UserId),
    #{
        total => length(Entries),
        by_type => count_by_service_type(Entries)
    }.

count_by_service_type(Entries) ->
    lists:foldl(fun({_Key, _Pid, Meta}, Acc) ->
        ServiceType = maps:get(service_type, maps:get(properties, Meta, #{})),
        maps:update_with(ServiceType, fun(C) -> C + 1 end, 1, Acc)
    end, #{}, Entries).
```

**Pros**:
- ✓ Uses existing orca functions (no new code)
- ✓ Fast: O(1) via tag index
- ✓ Flexible: Can query by user OR by service type OR both
- ✓ Rich filtering: Combine with other tags
- ✓ Automatic cleanup: Tags cleaned up with process
- ✓ Simple to understand and maintain

**Cons**:
- ✗ Slightly more metadata per entry

**Best for**: Most use cases. Clean, efficient, leverages orca's strengths.

---

## Approach 2: Metadata Storage (Not Recommended)

Store a list of Pids in metadata for the user's "workspace" entry.

```erlang
register_user_workspace(UserId) ->
    %% Register a workspace coordinator process
    {ok, WorkspacePid} = user_workspace:start_link(UserId),
    
    %% Register all services for this user
    {ok, ServiceEntries} = orca:register_batch([
        {{global, portfolio, UserId}, #{tags => [UserId]}},
        {{global, technical, UserId}, #{tags => [UserId]}},
        {{global, orders, UserId}, #{tags => [UserId]}},
        {{global, risk, UserId}, #{tags => [UserId]}}
    ]),
    
    %% Extract Pids from entries
    ServicePids = [Pid || {_Key, Pid, _Meta} <- ServiceEntries],
    
    %% Store reference in workspace metadata
    orca:register({global, user_workspace, UserId}, WorkspacePid, #{
        tags => [user, workspace],
        properties => #{
            child_services => ServicePids,
            child_count => length(ServicePids)
        }
    }),
    
    {ok, {WorkspacePid, ServicePids}}.

%% Later: lookup workspace to get services
get_user_services(UserId) ->
    case orca:lookup({global, user_workspace, UserId}) of
        {ok, {_Key, _Pid, Meta}} ->
            maps:get(child_services, maps:get(properties, Meta, #{}), []);
        not_found ->
            []
    end.
```

**Pros**:
- ✓ Single lookup to get all Pids
- ✓ Explicit parent-child relationship

**Cons**:
- ✗ Redundant data (already in registry)
- ✗ Gets stale: Child processes crash → metadata not updated
- ✗ Manual tracking required
- ✗ Can't query services without workspace entry
- ✗ More code to maintain

**Best for**: Only if you have a dedicated workspace coordinator process that manages the group.

---

## Approach 3: Partial Key Matching (Optional Enhancement)

Add a `lookup_prefix/1` function to orca for hierarchical key structures.

```erlang
%% Add to orca.erl exports
-export([lookup_prefix/1]).

%% New function
%% @doc Find all entries matching a key prefix.
%% 
%% Useful for hierarchical key structures where you want all entries
%% starting with a specific key prefix.
%% 
%% Example:
%%   lookup_prefix({global, user, user123})
%%   Returns all entries with keys like:
%%   {global, user, user123, service1}
%%   {global, user, user123, service2}
%%   etc.
-spec lookup_prefix(tuple()) -> [Entry].

lookup_prefix(Prefix) when is_tuple(Prefix) ->
    %% Convert prefix to ETS match pattern
    Size = size(Prefix),
    Pattern = build_pattern(Prefix, Size),
    ets:match_object(?REGISTRY_TABLE, {Pattern, '$1', '$2'}).

%% Helper to build match pattern
build_pattern(Prefix, Size) ->
    %% Start with wildcard tuple of size+1 (for the key)
    Base = erlang:make_tuple(size(Prefix) + 1, '_'),
    %% Fill in prefix elements
    fill_pattern(Base, Prefix, 1).

fill_pattern(Pattern, _Prefix, Pos) when Pos > size(Pattern) ->
    Pattern;
fill_pattern(Pattern, Prefix, Pos) when Pos =< size(Prefix) ->
    NewPattern = setelement(Pos, Pattern, element(Pos, Prefix)),
    fill_pattern(NewPattern, Prefix, Pos + 1);
fill_pattern(Pattern, _Prefix, _Pos) ->
    Pattern.

%% Usage examples:

%% Get all services for a user (with hierarchical keys)
user_services_hierarchical(UserId) ->
    orca:lookup_prefix({global, user, UserId}).

%% Get all jobs in a specific job queue
jobs_in_queue(QueueId) ->
    orca:lookup_prefix({global, job_queue, QueueId}).

%% Get all sessions for a specific app
sessions_for_app(AppId) ->
    orca:lookup_prefix({global, session, AppId}).
```

**Key Structure for this to work**:
```erlang
%% Keys must follow hierarchical pattern
{{global, user, user123, portfolio}, PortfolioPid, Meta},
{{global, user, user123, technical}, TechnicalPid, Meta},
{{global, user, user123, orders}, OrdersPid, Meta},
{{global, user, user123, risk}, RiskPid, Meta}

%% Then query with:
orca:lookup_prefix({global, user, user123})
%% Returns all 4 entries
```

**Pros**:
- ✓ Direct key-based lookup (fastest possible)
- ✓ Works with ETS native operations
- ✓ No extra metadata needed
- ✓ Clear intent in code

**Cons**:
- ✗ Requires specific key structure
- ✗ New function to implement and test
- ✗ Less flexible than tags (can't query by service type easily)
- ✗ Tag approach already works well

**Best for**: If you prefer hierarchical keys and want absolute performance.

---

## Approach 4: Property-Based Lookup (Alternative)

Use properties with `find_by_property/3` for multi-dimensional queries.

```erlang
register_user_services(UserId) ->
    {ok, Entries} = orca:register_batch([
        {{global, portfolio, UserId}, #{
            tags => [user_service],
            properties => #{
                user_id => UserId,
                service_type => portfolio,
                status => active
            }
        }},
        {{global, technical, UserId}, #{
            tags => [user_service],
            properties => #{
                user_id => UserId,
                service_type => technical,
                status => active
            }
        }},
        {{global, orders, UserId}, #{
            tags => [user_service],
            properties => #{
                user_id => UserId,
                service_type => orders,
                status => active
            }
        }},
        {{global, risk, UserId}, #{
            tags => [user_service],
            properties => #{
                user_id => UserId,
                service_type => risk,
                status => active
            }
        }}
    ]).

%% Queries

%% Get all services for user
all_services_for_user(UserId) ->
    orca:find_by_property(user_service, user_id, UserId).

%% Get active services for user
active_services_for_user(UserId) ->
    AllServices = orca:find_by_property(user_service, user_id, UserId),
    [Pid || {_Key, Pid, Meta} <- AllServices,
            maps:get(status, maps:get(properties, Meta, #{}), undefined) =:= active].

%% Get specific service type for user
portfolio_for_user(UserId) ->
    AllUserServices = orca:find_by_property(user_service, user_id, UserId),
    [Pid || {_Key, Pid, Meta} <- AllUserServices,
            maps:get(service_type, maps:get(properties, Meta, #{})) =:= portfolio].

%% Get all users (unique user_ids from property index)
all_users() ->
    Stats = orca:property_stats(user_service, user_id),
    maps:keys(Stats).

%% Get user service count
user_service_count(UserId) ->
    Services = orca:find_by_property(user_service, user_id, UserId),
    length(Services).
```

**Pros**:
- ✓ Very flexible: Can filter by any property
- ✓ Can get statistics: `property_stats(user_service, user_id)`
- ✓ Works well for multi-dimensional queries
- ✓ Can update properties without re-registering

**Cons**:
- ✗ Slightly slower than tags (uses fun2ms match specs)
- ✗ More verbose queries
- ✗ Still need to filter in Erlang for AND queries

**Best for**: Complex filtering needs, need statistics on dimensions.

---

## Recommendation Summary

| Approach | Speed | Flexibility | Code Complexity | Recommended |
|----------|-------|-------------|-----------------|-------------|
| 1: Tags | Fast | High | Low | **YES** ✓ |
| 2: Metadata | Fast | Low | High | No ✗ |
| 3: Prefix Match | Fastest | Medium | Medium | Maybe |
| 4: Properties | Medium | Highest | Medium | Alternative |

### **Use Approach 1 (Tags) for your trading app:**

```erlang
-module(user_trading_workspace).

%% Register all trading services for a user
create_workspace(UserId) ->
    {ok, Entries} = orca:register_batch([
        {{global, portfolio, UserId}, #{
            tags => [UserId, portfolio, trading],
            properties => #{service_type => portfolio}
        }},
        {{global, technical, UserId}, #{
            tags => [UserId, technical, trading],
            properties => #{service_type => technical}
        }},
        {{global, fundamental, UserId}, #{
            tags => [UserId, fundamental, trading],
            properties => #{service_type => fundamental}
        }},
        {{global, orders, UserId}, #{
            tags => [UserId, orders, trading],
            properties => #{service_type => orders}
        }},
        {{global, risk, UserId}, #{
            tags => [UserId, risk, trading],
            properties => #{service_type => risk}
        }}
    ]),
    {ok, Entries}.

%% Query patterns

%% All services for a user
all_user_services(UserId) ->
    orca:entries_by_tag(UserId).

%% Specific service for user
get_user_service(UserId, ServiceType) ->
    AllUserServices = orca:entries_by_tag(UserId),
    [Pid || {_Key, Pid, Meta} <- AllUserServices,
            maps:get(service_type, maps:get(properties, Meta, #{})) =:= ServiceType].

%% All portfolio services (across all users)
all_portfolios() ->
    orca:entries_by_tag(portfolio).

%% Statistics
user_service_count(UserId) ->
    orca:count_by_tag(UserId).
```

**Why Approach 1 is best**:
- ✓ Uses orca's strongest feature: tag indexing
- ✓ No new code needed
- ✓ Fast O(1) lookups
- ✓ Can query by user OR by service type
- ✓ Automatic cleanup
- ✓ Already thoroughly tested
