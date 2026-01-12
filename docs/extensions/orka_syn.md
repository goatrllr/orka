# Orka + Syn: Hybrid Architecture for Distributed Environments

This document describes patterns for integrating orka (local, fast registry) with syn (distributed, eventually consistent) to handle multi-node deployments while maintaining both performance and eventual consistency.

## The Challenge

**Orka alone**: Fast local registry, no distribution.
**Syn alone**: Distributed but eventually consistent, can be slower.
**Combined**: Get the best of both worlds.

```
Node A                          Node B
┌─────────────────┐            ┌─────────────────┐
│ Local Orka      │            │ Local Orka      │
│ ┌─────────────┐ │            │ ┌─────────────┐ │
│ │ Portfolio   │ │            │ │ Portfolio   │ │
│ │ Technical   │ │            │ │ Technical   │ │
│ └─────────────┘ │            │ └─────────────┘ │
└────────┬────────┘            └────────┬────────┘
         │                              │
         └──────────┬───────────────────┘
                    │
            ┌───────▼──────┐
            │  Syn Cluster │
            │  (Global)    │
            └──────────────┘
```

## Core Principle

**Local-first with eventual consistency for discovery**:

1. Service registers locally via orka (immediate, fast)
2. Service also joins syn group (eventual consistency across cluster)
3. Queries prefer local orka, fall back to syn when needed

---

## Implementation Strategy

### Integration Layer: orka_syn_bridge

```erlang
%% orka_syn_bridge.erl - Integration layer
-module(orka_syn_bridge).
-export([register_service/3, lookup_service/2, get_all_services/1]).
-export([subscribe_remote/1, unsubscribe_remote/1]).

%% Register a service both locally and globally
%% Immediate local availability + eventual global consistency
register_service(Key, Pid, Metadata) ->
    %% 1. Register locally (immediate)
    {ok, LocalEntry} = orka:register(Key, Pid, Metadata),
    
    %% 2. Join syn group (eventually consistent)
    GroupKey = extract_group_key(Key),
    syn:join(GroupKey, Pid, #{
        metadata => Metadata,
        registered_at => erlang:system_time(millisecond),
        node => node()
    }),
    
    {ok, LocalEntry}.

%% Extract group identifier from key
%% {global, service, translator} -> {service, translator}
extract_group_key({global, Type, Name}) ->
    {Type, Name};
extract_group_key({global, {Type, SubType}, Name}) ->
    {Type, SubType, Name}.

%% Lookup: Try local first, then query globally if needed
lookup_service(Key, Strategy) ->
    case orka:lookup(Key) of
        {ok, Entry} ->
            {ok, local, Entry};
        not_found when Strategy =:= local_only ->
            {error, not_found};
        not_found when Strategy =:= global ->
            %% Query syn for remote instances
            lookup_global(Key)
    end.

lookup_global(Key) ->
    GroupKey = extract_group_key(Key),
    case syn:get_members(GroupKey) of
        [] ->
            {error, not_found};
        Members ->
            %% Return first available (eventually consistent)
            Pid = hd(Members),
            {ok, remote, {Key, Pid, #{remote => true}}}
    end.

%% Get all services of a type (local + remote)
get_all_services(Type) ->
    %% Local services
    LocalEntries = orka:entries_by_tag(Type),
    LocalPids = [Pid || {_Key, Pid, _Meta} <- LocalEntries],
    
    %% Remote services from syn
    RemoteMembers = get_remote_services(Type),
    RemotePids = [Pid || Pid <- RemoteMembers, not lists:member(Pid, LocalPids)],
    
    {ok, #{
        local => LocalPids,
        remote => RemotePids,
        all => LocalPids ++ RemotePids,
        total => length(LocalPids) + length(RemotePids)
    }}.

get_remote_services(Type) ->
    %% Query all syn groups matching the type
    AllGroups = syn:list_groups(),
    MatchingGroups = [G || G <- AllGroups, element(1, G) =:= Type],
    lists:flatmap(fun(Group) ->
        syn:get_members(Group)
    end, MatchingGroups).
```

---

## Three Integration Patterns

### Pattern 1: Local-First with Remote Fallover

Prefer local instances (fast, strong consistency), fall back to remote if local unavailable.

```erlang
%% app_translator.erl
-module(app_translator).

%% Get translator service with fallback
get_translator_service(Strategy) ->
    case orka:lookup({global, service, translator}) of
        {ok, {_Key, Pid, _Meta}} ->
            {ok, local, Pid};
        not_found when Strategy =:= failover ->
            %% Try remote
            case syn:get_members({service, translator}) of
                [RemotePid | _] ->
                    {ok, remote, RemotePid};
                [] ->
                    {error, no_service_available}
            end;
        not_found ->
            {error, no_local_service}
    end.

%% Usage
translate(Text) ->
    case get_translator_service(failover) of
        {ok, _Source, Pid} ->
            translator:translate(Pid, Text);
        {error, _} ->
            {error, no_translator_available}
    end.
```

**Use case**: Load balancing within a node with graceful degradation across nodes.

---

### Pattern 2: Eventually Consistent Discovery

Register service locally and in global group, query across cluster.

```erlang
%% trading_workspace.erl
-module(trading_workspace).

%% Register user service both locally and globally
register_user_service(UserId, ServiceType) ->
    {ok, Entry} = orka_syn_bridge:register_service(
        {global, {user, UserId}, ServiceType},
        self(),
        #{
            tags => [UserId, ServiceType, user_service],
            properties => #{service_type => ServiceType, node => node()}
        }
    ),
    {ok, Entry}.

%% Query all instances across cluster (eventual consistency)
get_user_services_global(UserId) ->
    GroupKey = {user, UserId},
    
    %% Local (immediate)
    LocalEntries = orka:entries_by_tag(UserId),
    LocalPids = [Pid || {_Key, Pid, _Meta} <- LocalEntries],
    
    %% Remote (eventual)
    RemotePids = syn:get_members(GroupKey),
    
    AllPids = lists:usort(LocalPids ++ RemotePids),
    {ok, AllPids}.

%% Get specific service type for user
get_user_service(UserId, ServiceType) ->
    case orka:lookup({global, {user, UserId}, ServiceType}) of
        {ok, {_K, Pid, _M}} ->
            {ok, local, Pid};
        not_found ->
            %% Check remote
            GroupKey = {user, UserId},
            Members = syn:get_members(GroupKey),
            case Members of
                [] -> {error, not_found};
                [Pid | _] -> {ok, remote, Pid}
            end
    end.
```

**Use case**: Multi-node user workspaces where services may be on any node.

---

### Pattern 3: Hybrid Queries with Consistency Levels

Choose consistency level based on use case.

```erlang
%% distributed_trader.erl
-module(distributed_trader).

%% Strong consistency: Local only
%% Perfect for: Configuration, critical state
get_portfolio(UserId) ->
    case orka:await({global, portfolio, UserId}, 5000) of
        {ok, {_K, Pid, _Meta}} -> 
            {ok, Pid};
        {error, timeout} -> 
            {error, portfolio_not_ready}
    end.

%% Eventual consistency: Local + remote
%% Perfect for: Discovery, multi-instance lookups
get_all_execution_nodes(UserId) ->
    %% Local executions
    LocalExecs = orka:entries_by_tag({execution, UserId}),
    LocalPids = [P || {_K, P, _M} <- LocalExecs],
    
    %% Remote executions (might be slightly stale)
    RemoteExecs = syn:get_members({execution, UserId}),
    
    AllExecs = lists:usort(LocalPids ++ RemoteExecs),
    {ok, AllExecs}.

%% Query with timeout: try local first, then remote
get_service_with_timeout(ServiceKey, Timeout) ->
    LocalDeadline = erlang:system_time(millisecond) + (Timeout div 2),
    
    case orka:lookup(ServiceKey) of
        {ok, Entry} ->
            {ok, local, Entry};
        not_found ->
            %% Try remote with remaining timeout
            RemoteTimeout = Timeout - (erlang:system_time(millisecond) - LocalDeadline),
            case query_remote(ServiceKey, RemoteTimeout) of
                {ok, Pid} -> 
                    {ok, remote, Pid};
                {error, _} -> 
                    {error, service_timeout}
            end
    end.

query_remote(ServiceKey, Timeout) ->
    GroupKey = extract_group_key(ServiceKey),
    case syn:get_members(GroupKey) of
        [] -> 
            {error, not_found};
        Members ->
            %% Pick healthiest/nearest remote
            choose_best_remote(Members, Timeout)
    end.

choose_best_remote(Members, _Timeout) ->
    %% Implement your strategy: nearest, healthiest, load-balanced, etc.
    {ok, hd(Members)}.

extract_group_key({global, Type, Name}) ->
    {Type, Name};
extract_group_key({global, {Type, SubType}, Name}) ->
    {Type, SubType, Name}.
```

**Use case**: Services where you need both local guarantees and global visibility.

---

## Complete Trading App Example

Multi-node trading workspace with per-user distributed service groups.

```erlang
%% trading_workspace_distributed.erl
-module(trading_workspace_distributed).
-export([
    create_workspace/1, 
    get_workspace_services/1, 
    broadcast_to_workspace/2,
    broadcast_to_workspace_global/2
]).

%% Create workspace: register on local node + join global group
create_workspace(UserId) ->
    {ok, Entries} = orka:register_batch([
        {{global, portfolio, UserId}, PortfolioPid, #{
            tags => [UserId, portfolio],
            properties => #{service_type => portfolio, node => node()}
        }},
        {{global, technical, UserId}, TechnicalPid, #{
            tags => [UserId, technical],
            properties => #{service_type => technical, node => node()}
        }},
        {{global, orders, UserId}, OrdersPid, #{
            tags => [UserId, orders],
            properties => #{service_type => orders, node => node()}
        }},
        {{global, risk, UserId}, RiskPid, #{
            tags => [UserId, risk],
            properties => #{service_type => risk, node => node()}
        }},
        {{global, monitoring, UserId}, MonitoringPid, #{
            tags => [UserId, monitoring],
            properties => #{service_type => monitoring, node => node()}
        }}
    ]),
    
    %% Join distributed group for each service
    GroupKey = {user_workspace, UserId},
    WorkspacePids = [Pid || {_K, Pid, _M} <- Entries],
    lists:foreach(fun(Pid) ->
        ServiceType = get_service_type(Pid, Entries),
        syn:join(GroupKey, Pid, #{
            service_type => ServiceType,
            node => node(),
            registered_at => erlang:system_time(millisecond)
        })
    end, WorkspacePids),
    
    {ok, Entries}.

%% Get services: local (fast) + remote (eventual)
get_workspace_services(UserId) ->
    %% Local (immediate, strong consistency)
    LocalEntries = orka:entries_by_tag(UserId),
    LocalPids = [{local, Pid, ServiceType} || {_K, Pid, Meta} <- LocalEntries,
                                               ServiceType <- [get_service_type_from_meta(Meta)]],
    
    %% Remote (eventual consistency)
    RemoteMembers = syn:get_members({user_workspace, UserId}),
    LocalOnlyPids = [P || {_K, P, _M} <- LocalEntries],
    RemotePids = [{remote, P} || P <- RemoteMembers, not lists:member(P, LocalOnlyPids)],
    
    {ok, #{
        local => LocalPids,
        remote => RemotePids,
        all => LocalPids ++ RemotePids,
        total => length(LocalPids) + length(RemotePids)
    }}.

%% Broadcast to local workspace (guaranteed delivery)
broadcast_to_workspace(UserId, Message) ->
    LocalServices = orka:entries_by_tag(UserId),
    lists:foreach(fun({_Key, Pid, _Meta}) ->
        Pid ! {workspace_message, UserId, Message}
    end, LocalServices).

%% Broadcast globally (eventual consistency)
broadcast_to_workspace_global(UserId, Message) ->
    Members = syn:get_members({user_workspace, UserId}),
    lists:foreach(fun(Pid) ->
        Pid ! {workspace_message, UserId, Message}
    end, Members).

get_service_type(Pid, Entries) ->
    case [T || {_K, P, Meta} <- Entries, 
               P =:= Pid,
               T <- [get_service_type_from_meta(Meta)]] of
        [Type | _] -> Type;
        [] -> unknown
    end.

get_service_type_from_meta(Meta) ->
    maps:get(service_type, maps:get(properties, Meta, #{}), unknown).
```

---

## Consistency Guarantees

| Operation | Local (Orka) | Global (Syn) | Hybrid Approach |
|-----------|--------------|--------------|-----------------|
| **Register** | Immediate | Eventual (~100ms) | Atomic locally, async globally |
| **Lookup** | Strong ✓ | Eventual | Local-first, remote fallback |
| **Query All** | Strong ✓ | Eventual | Combined view (hybrid) |
| **Cleanup on crash** | Immediate | Eventual | Process death handled by both |
| **Broadcast Local** | Guaranteed ✓ | — | 100% delivery to local services |
| **Broadcast Global** | — | Best-effort | Local guaranteed, global best-effort |

---

## Key Design Decisions

### 1. **Local-First Always**
Orka is the source of truth for the local node. Never rely solely on syn for local operations.

```erlang
%% GOOD: Try local first
case orka:lookup(Key) of
    {ok, Entry} -> Entry;
    not_found -> syn:get_members(GroupKey)
end.

%% BAD: Skip local and go to syn
syn:get_members(GroupKey).  %% Might miss local services!
```

### 2. **Syn for Discovery**
Use syn when you need to find services on other nodes or get a complete cluster-wide view.

```erlang
%% Find any service (local preferred, remote fallback)
get_service(Key) ->
    case orka:lookup(Key) of
        {ok, Entry} -> {ok, local, Entry};
        not_found -> {ok, remote, get_remote(Key)}
    end.
```

### 3. **Accept Eventual Consistency**
Global state may lag. This is acceptable for discovery but not for critical operations.

```erlang
%% OK: Finding a pool of workers (eventual consistency acceptable)
AllWorkers = orka:entries_by_tag(worker) ++ syn:get_members(worker_group),

%% NOT OK: Getting the one portfolio (needs strong consistency)
orka:await({global, portfolio, UserId}, 5000).
```

### 4. **No Replication**
Each node has an independent orka registry. Don't try to replicate data across nodes manually.

```erlang
%% CORRECT: Each node registers its own services
orka:register({global, portfolio, UserId}, PortfolioPid, Meta),
syn:join({user, UserId}, PortfolioPid, Meta).

%% WRONG: Don't store lists of remote Pids
orka:register(user_key, WorkspacePid, #{
    child_pids => [RemotePid1, RemotePid2, ...]  %% Gets stale!
}).
```

### 5. **Failover Strategy**
Always have a fallback when using remote services.

```erlang
get_service(Key) ->
    case orka:lookup(Key) of
        {ok, {_K, Pid, _M}} -> 
            Pid;
        not_found -> 
            case syn:get_members(extract_group(Key)) of
                [Pid | _] -> Pid;
                [] -> error(no_service)
            end
    end.
```

---

## Implementation Checklist

### 1. Application Startup

```erlang
%% In your_app.erl
start(normal, _Args) ->
    {ok, _} = application:ensure_all_started(orka),
    {ok, _} = application:ensure_all_started(syn),
    {ok, _} = application:ensure_all_started(your_app),
    
    your_sup:start_link().
```

### 2. Register Services

```erlang
%% Local registration (both orka + syn)
orka_syn_bridge:register_service(
    {global, portfolio, UserId},
    PortfolioPid,
    #{tags => [UserId, portfolio]}
).
```

### 3. Query Services

```erlang
%% Local-first strategy
case orka:lookup(Key) of
    {ok, Entry} -> handle_local(Entry);
    not_found -> handle_remote(Key)
end.
```

### 4. Broadcast

```erlang
%% Local: guaranteed delivery
broadcast_to_local_workspace(UserId, Message),

%% Global: eventual delivery
broadcast_to_global_workspace(UserId, Message).
```

---

## Comparison: Orka vs Syn vs Hybrid

| Feature | Orka | Syn | Hybrid |
|---------|------|-----|--------|
| **Speed** | ⚡⚡⚡ Fast | ⚡⚡ Medium | ⚡⚡⚡ Fast locally, medium globally |
| **Consistency** | Strong local | Eventual | Hybrid per operation |
| **Distribution** | None | Global | Local + global |
| **Failure handling** | Automatic cleanup | Automatic cleanup | Both |
| **Query flexibility** | Tags + properties | Matching | Tags + properties + global |
| **Network overhead** | None | Low | Minimal |
| **Complexity** | Low | Low | Medium |
| **Best for** | Single-node, multi-node local | Distributed lookups | Multi-node with local preference |

---

## Real-World Scenario: Trading Platform

### Architecture

- **Node A (Primary)**: All trader management
- **Node B (Backup)**: Standby services
- **Node C (Execution)**: Order execution engines

### Registration

```erlang
%% Node A: Create trader workspace
trading_workspace_distributed:create_workspace(trader_001),
%% Registers locally + joins global group {user_workspace, trader_001}

%% Node C: Register execution engine
orka_syn_bridge:register_service(
    {global, execution, trader_001},
    ExecutionPid,
    #{tags => [trader_001, execution, trading]}
).
```

### Queries

```erlang
%% Node A: Get portfolio (local strong consistency)
get_portfolio(trader_001) ->
    orka:await({global, portfolio, trader_001}, 5000).

%% Node B: Find any execution engine for trader (eventual consistency)
get_execution_engine(trader_001) ->
    case orka:lookup({global, execution, trader_001}) of
        {ok, Entry} -> {ok, local, Entry};
        not_found ->
            Members = syn:get_members({execution, trader_001}),
            case Members of
                [Pid | _] -> {ok, remote, Pid};
                [] -> {error, no_engine}
            end
    end.

%% Any node: Broadcast order to all execution nodes for trader
broadcast_order(trader_001, Order) ->
    %% Local (guaranteed)
    trading_workspace_distributed:broadcast_to_workspace(trader_001, Order),
    %% Global (eventual)
    trading_workspace_distributed:broadcast_to_workspace_global(trader_001, Order).
```

---

## Migration Path

### Phase 1: Single-node (Orka only)
```erlang
orka:register({global, portfolio, user_id}, Pid, Meta).
orka:lookup({global, portfolio, user_id}).
```

### Phase 2: Add Distribution (Orka + Syn)
```erlang
orka_syn_bridge:register_service({global, portfolio, user_id}, Pid, Meta).
orka_syn_bridge:lookup_service({global, portfolio, user_id}, global).
```

### Phase 3: Optimize Queries
```erlang
%% Use local-first strategy
case orka:lookup(Key) of
    {ok, Entry} -> Entry;
    not_found -> {ok, _Src, RemoteEntry} = orka_syn_bridge:lookup_service(Key, global)
end.
```

---

## Troubleshooting

### Issue: Service visible in syn but not found locally
**Cause**: Eventual consistency lag or node partition
**Solution**: Always check local first, then remote. Accept eventual consistency for global queries.

### Issue: Broadcast not reaching all services
**Cause**: Mixing orka broadcast (local) and syn broadcast (eventual)
**Solution**: Use separate functions for different consistency needs.

### Issue: Too much metadata duplication
**Cause**: Storing same metadata in both orka and syn
**Solution**: Store minimal metadata in syn, use tags for filtering.
