# Orka Process Groups - Global Group Manager

Orka can function as a **Global Process Group manager**, similar to syn's group functionality. This document shows how to use orka's tag and property system to implement process groups with rich querying capabilities.

## Overview

Process groups allow you to:
1. **Register a process under a group key** - managed by orka with `register/2`
2. **Query all processes in a group** - via `entries_by_tag/1` or `find_by_property/2`
3. **Get group membership** - filter by tags or properties
4. **Monitor group membership** - automatic cleanup on process crash

## Implementation Pattern 1: Tag-Based Groups (Simplest)

**Best for**: Simple groups without metadata requirements.

```erlang
-module(process_group).
-export([join/1, leave/1, members/1]).

%% Join a group
join(GroupName) ->
    Key = {global, group, {GroupName, self()}},
    orka:register(Key, self(), #{
        tags => [GroupName, group_member],
        properties => #{group => GroupName}
    }).

%% Leave group
leave(GroupName) ->
    Key = {global, group, {GroupName, self()}},
    orka:unregister(Key).

%% Get all members of group
members(GroupName) ->
    Entries = orka:entries_by_tag(GroupName),
    [Pid || {_Key, Pid, _Meta} <- Entries].
```

**Usage**:
```erlang
%% Process joins a group
process_group:join(workers),
process_group:join(workers),
process_group:join(workers),

%% Query members
Pids = process_group:members(workers),
%% Result: [Pid1, Pid2, Pid3]
```

**Pros**:
- Simple, direct mapping to orka's tag system
- Automatic cleanup on process crash
- Fast queries with `entries_by_tag/1`

**Cons**:
- Limited member metadata
- Same process in multiple groups requires multiple registrations

## Implementation Pattern 2: Property-Based Groups (Rich Querying)

**Best for**: Groups with member metadata, role-based access, filtering.

```erlang
-module(process_group).
-export([join/2, leave/2, members/1, members_with_role/2, group_stats/1]).

%% Join a group with metadata
join(GroupName, Metadata) ->
    Key = {global, group, {GroupName, self()}},
    orka:register(Key, self(), maps:merge(
        #{tags => [group_member],
          properties => #{group => GroupName}},
        Metadata
    )).

%% Leave a group
leave(GroupName, _Metadata) ->
    Key = {global, group, {GroupName, self()}},
    orka:unregister(Key).

%% Get all members of a group
members(GroupName) ->
    Entries = orka:find_by_property(group, GroupName),
    [Pid || {_Key, Pid, _Meta} <- Entries].

%% Get members with specific role
members_with_role(GroupName, Role) ->
    AllMembers = orka:find_by_property(group, GroupName),
    [Pid || {_Key, Pid, Meta} <- AllMembers,
            maps:get(role, Meta, undefined) =:= Role].

%% Get statistics on group
group_stats(GroupName) ->
    Entries = orka:find_by_property(group, GroupName),
    #{
        size => length(Entries),
        members => [Pid || {_Key, Pid, _Meta} <- Entries],
        distribution => get_role_distribution(Entries)
    }.

get_role_distribution(Entries) ->
    Roles = [maps:get(role, Meta, unknown) || {_K, _Pid, Meta} <- Entries],
    lists:foldl(fun(Role, Acc) ->
        maps:update_with(Role, fun(C) -> C + 1 end, 1, Acc)
    end, #{}, Roles).
```

**Usage**:
```erlang
%% Members join with metadata
process_group:join(workers, #{role => compute, region => us_west}),
process_group:join(workers, #{role => io, region => us_east}),
process_group:join(workers, #{role => compute, region => eu}),

%% Query groups
Workers = process_group:members(workers),
ComputeWorkers = process_group:members_with_role(workers, compute),
Stats = process_group:group_stats(workers),
%% Result: #{
%%     size => 3,
%%     members => [Pid1, Pid2, Pid3],
%%     distribution => #{compute => 2, io => 1}
%% }
```

**Pros**:
- Rich member metadata (role, status, region, etc.)
- Query by multiple properties
- Group statistics via `property_stats/2`
- Flexible filtering

**Cons**:
- Slightly more overhead (both tag and property registration)
- More complex membership queries

## Implementation Pattern 3: Hybrid with Group Registry (Full Syn-Like)

**Best for**: Complex scenarios with group metadata, creation/deletion, and full lifecycle management.

```erlang
-module(process_group).
-export([
    create_group/2,
    delete_group/1,
    join/3,
    leave/2,
    members/1,
    broadcast/2,
    group_info/1
]).

%% Create a group (with optional metadata)
create_group(GroupName, GroupMetadata) ->
    orka:register(
        {global, group_registry, GroupName},
        self(),
        maps:merge(
            #{tags => [group, registry], properties => #{type => group}},
            GroupMetadata
        )
    ).

%% Delete a group (and all members)
delete_group(GroupName) ->
    orka:unregister({global, group_registry, GroupName}),
    Entries = orka:entries_by_tag(GroupName),
    lists:foreach(fun({Key, _Pid, _Meta}) ->
        orka:unregister(Key)
    end, Entries).

%% Join a group
join(GroupName, MemberKey, MemberMetadata) ->
    Key = {global, group_member, {GroupName, MemberKey}},
    orka:register(Key, self(), maps:merge(
        #{tags => [GroupName, group_member],
          properties => #{group => GroupName}},
        MemberMetadata
    )).

%% Leave a group
leave(GroupName, MemberKey) ->
    Key = {global, group_member, {GroupName, MemberKey}},
    orka:unregister(Key).

%% Get all members of group
members(GroupName) ->
    Entries = orka:entries_by_tag(GroupName),
    [Pid || {_Key, Pid, _Meta} <- Entries, is_pid(Pid)].

%% Broadcast message to all members
broadcast(GroupName, Message) ->
    Members = members(GroupName),
    lists:foreach(fun(Pid) ->
        Pid ! {group_broadcast, GroupName, Message}
    end, Members).

%% Get group information
group_info(GroupName) ->
    case orka:lookup({global, group_registry, GroupName}) of
        {ok, {_Key, _Pid, Metadata}} ->
            Members = members(GroupName),
            #{
                name => GroupName,
                metadata => Metadata,
                member_count => length(Members),
                members => Members
            };
        not_found ->
            {error, group_not_found}
    end.
```

**Usage**:
```erlang
%% Create a group
process_group:create_group(workers, #{
    created_at => erlang:system_time(millisecond),
    max_members => 100
}),

%% Members join
Worker1 = spawn(fun worker_loop/0),
Worker2 = spawn(fun worker_loop/0),
Worker3 = spawn(fun worker_loop/0),

process_group:join(workers, worker1, #{role => compute, started => now()}),
process_group:join(workers, worker2, #{role => io, started => now()}),
process_group:join(workers, worker3, #{role => compute, started => now()}),

%% Query group
Members = process_group:members(workers),
Info = process_group:group_info(workers),
%% Result: #{
%%     name => workers,
%%     metadata => #{created_at => ..., max_members => 100},
%%     member_count => 3,
%%     members => [Pid1, Pid2, Pid3]
%% }

%% Broadcast to group
process_group:broadcast(workers, {task, calculate, Data}),

%% Leave group
process_group:leave(workers, worker1),

%% Delete group
process_group:delete_group(workers).
```

**Pros**:
- Full lifecycle management (create, join, leave, delete)
- Group-level metadata
- Broadcast messaging
- Rich querying
- Automatic cleanup

**Cons**:
- More code/complexity
- Requires managing group registry process

## Real-World Example 1: Distributed Chat Rooms

```erlang
-module(chat_room).
-export([create_room/1, join_room/3, leave_room/2, send_message/3, room_members/1]).

%% Create a chat room
create_room(RoomId) ->
    orka:register(
        {global, chatroom, RoomId},
        self(),
        #{
            tags => [chat, room],
            properties => #{
                created_at => erlang:system_time(millisecond),
                message_count => 0
            }
        }
    ).

%% Join a room with user info
join_room(RoomId, UserId, UserName) ->
    Key = {global, chatroom_member, {RoomId, UserId}},
    orka:register(Key, self(), #{
        tags => [RoomId, chat_member],
        properties => #{
            room_id => RoomId,
            user_id => UserId,
            user_name => UserName,
            joined_at => erlang:system_time(millisecond)
        }
    }).

%% Leave a room
leave_room(RoomId, UserId) ->
    Key = {global, chatroom_member, {RoomId, UserId}},
    orka:unregister(Key).

%% Send message to room (broadcast)
send_message(RoomId, UserId, Message) ->
    Entries = orka:entries_by_tag(RoomId),
    Members = [Pid || {_Key, Pid, _Meta} <- Entries],
    lists:foreach(fun(Pid) ->
        Pid ! {chat_message, RoomId, UserId, Message}
    end, Members).

%% Get room members with usernames
room_members(RoomId) ->
    Entries = orka:entries_by_tag(RoomId),
    [{UserId, UserName, Pid} || {_Key, Pid, Meta} <- Entries,
                                UserId <- [maps:get(user_id, Meta)],
                                UserName <- [maps:get(user_name, Meta)]].
```

## Real-World Example 2: Worker Pool with Roles

```erlang
-module(worker_pool).
-export([register_worker/2, get_workers_by_role/1, assign_task/2, worker_stats/0]).

%% Register a worker with its capabilities
register_worker(WorkerId, Capabilities) ->
    Key = {global, worker, WorkerId},
    orka:register(Key, self(), #{
        tags => [worker_pool, active],
        properties => maps:merge(
            #{worker_id => WorkerId},
            Capabilities
        )
    }).

%% Get all workers with specific capability
get_workers_by_role(Role) ->
    Entries = orka:entries_by_tag(worker_pool),
    [Pid || {_Key, Pid, Meta} <- Entries,
            lists:member(Role, maps:get(capabilities, Meta, []))].

%% Assign task to worker
assign_task(WorkerId, Task) ->
    case orka:lookup({global, worker, WorkerId}) of
        {ok, {_Key, WorkerPid, _Meta}} ->
            WorkerPid ! {task, Task},
            {ok, WorkerPid};
        not_found ->
            {error, worker_not_found}
    end.

%% Get pool statistics
worker_stats() ->
    Entries = orka:entries_by_tag(worker_pool),
    #{
        total => length(Entries),
        by_role => compute_role_distribution(Entries),
        workers => [{WorkerId, Pid} || {_Key, Pid, Meta} <- Entries,
                                       WorkerId <- [maps:get(worker_id, Meta)]]
    }.

compute_role_distribution(Entries) ->
    lists:foldl(fun({_Key, _Pid, Meta}, Acc) ->
        Capabilities = maps:get(capabilities, Meta, []),
        lists:foldl(fun(Cap, Inner) ->
            maps:update_with(Cap, fun(C) -> C + 1 end, 1, Inner)
        end, Acc, Capabilities)
    end, #{}, Entries).
```

## Comparison: Orka vs Syn

| Feature | Syn | Orka | Notes |
|---------|-----|------|-------|
| Process registration | ✓ | ✓ | Orka via keys |
| Group membership | ✓ | ✓ | Orka via tags/properties |
| Dynamic groups | ✓ | ✓ | Both support |
| Distributed | ✓ | ✗ (planned) | Syn integrated with dist nodes |
| Monitoring | ✓ | ✓ | Both auto-cleanup on crash |
| Querying members | Limited | ✓✓ | Orka has rich query via properties |
| Broadcast to group | Plugin | Manual | Can wrap in orka module |
| Performance | Optimized | Good | Orka uses ETS, syn uses mnesia |

## When to Use Process Groups with Orka

**Use Orka Process Groups when**:
- ✓ You need local groups (same node/app)
- ✓ You want rich member metadata and filtering
- ✓ You're already using orka for process registry
- ✓ You need flexible querying (by role, region, status, etc.)
- ✓ You're building a trading app, chat system, or worker pool

**Use Syn when**:
- ✓ You need distributed groups (multiple nodes)
- ✓ You want optimized group operations
- ✓ You need dynamic group discovery across cluster
- ✓ You're building a full distributed Erlang system

## Hybrid Approach: Orka + Syn

For a distributed system, use both:

```erlang
%% Local groups managed by orka (single node, fast)
local_group:join(my_group, self()).

%% Distributed groups managed by syn (cluster-wide)
syn:join({global, my_group}, self()).

%% Best of both worlds - local performance + distributed discovery!
```

## Future: `orka_grp` Module

As mentioned in the architecture plan, this implementation pattern could eventually be extracted into a dedicated `orka_grp` module:

```erlang
%% Eventually: orka_grp module
-module(orka_grp).
-export([create/1, join/2, leave/2, members/1, broadcast/2]).

%% Implementation would be the hybrid pattern (Pattern 3)
%% But abstracted away from users
```

This keeps `orka.erl` focused on core registry operations while providing **higher-level group abstractions** in extension modules.

## Summary

Orka's tag and property system makes it an excellent **local process group manager**. The three patterns shown provide increasing levels of sophistication:

1. **Tags only** - Simple, fast, for basic groups
2. **Tags + Properties** - Rich metadata, flexible querying
3. **Group Registry** - Full lifecycle, group metadata, broadcast

Choose the pattern that matches your needs. For most applications, Pattern 2 (property-based) offers the best balance of features and simplicity.
