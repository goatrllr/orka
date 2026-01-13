# Orka Registry API Documentation

<div align="center">

![Orka Logo](docs/images/orka_logo.png)

</div>

Orka is a production-ready **pluggable process registry** for Erlang/OTP applications. It provides fast lookups via pluggable backends (ETS-based by default), with features for registration, metadata management, tags, properties, and startup coordination. Built with a pathway to distribution-aware backends.

**Status**: ✅ Fully tested (85/85 tests passing) | **Latest**: Pluggable backend architecture | **License**: MIT

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Core API](#core-api)
3. [Advanced Features](#advanced-features)
4. [Usage Patterns](#usage-patterns)
5. [Design Principles](#design-principles)
6. [FAQ](#faq)

---

## Quick Start

### Basic Registration

```erlang
%% Start the orka application
{ok, _} = application:ensure_all_started(orka).

%% Register a process with metadata
orka:register({global, service, translator}, MyPid, #{
    tags => [service, translator, online],
    properties => #{version => "2.1.0"}
}).

%% Lookup a process
{ok, {Key, Pid, Metadata}} = orka:lookup({global, service, translator}).

%% Query by tag
OnlineServices = orka:entries_by_tag(online).

%% Unregister
ok = orka:unregister({global, service, translator}).
```

### Key Format Convention

We recommend the 3-tuple key structure for clarity and consistency:

```erlang
{Scope, Type, Name}

%% Examples:
{global, user, "alice@example.com"}       %% User process
{global, service, translator}              %% Named service
{global, resource, {db, primary}}          %% Resource with sub-type
{local, queue, job_processor_1}            %% Local to node
```

### Metadata Format

```erlang
#{
    tags => [atom1, atom2, ...],           %% Categories for querying (duplicates removed)
    properties => #{                        %% Custom structured data
        version => "1.0.0",
        capacity => 100,
        region => "us-west"
    },
    created_at => erlang:system_time(ms),  %% Optional custom fields
    owner => "supervisor_1"
}
```

---

## Core API

### Registration Functions

#### `register(Key, Metadata) -> {ok, Entry} | error`

Self-register the calling process.

```erlang
%% User registering itself
{ok, {Key, Pid, Metadata}} = orka:register(
    {global, user, "alice@example.com"},
    #{tags => [user, online], properties => #{region => "us-west"}}
).
```

#### `register(Key, Pid, Metadata) -> {ok, Entry} | error`

Register a specific process (useful in supervisors).

```erlang
%% Supervisor registering a child
{ok, {Key, Pid, Metadata}} = orka:register(
    {global, service, translator},
    TranslatorPid,
    #{tags => [service, translator, critical]}
).
```

**Returns**:
- `{ok, {Key, Pid, Metadata}}` - Successfully registered
- If key already registered with live process: returns existing entry
- If key registered but process dead: cleans up and re-registers

#### `register_with(Key, Metadata, {M, F, A}) -> {ok, Pid} | error`

Atomically start a process and register it. Ensures no race conditions between startup and registration.

```erlang
%% Supervisor starting and registering in one call
{ok, TranslatorPid} = orka:register_with(
    {global, service, translator},
    #{tags => [service, translator, critical]},
    {translator_server, start_link, []}
).

%% If the key is already registered with a live process, returns {ok, Pid} from the started process
%% If registration fails, process is automatically terminated
%% If the MFA returns a Pid directly (not {ok, Pid}), that is also accepted
```

**Benefits**:
- Atomic startup + registration (no races)
- Automatic cleanup if registration fails
- Ideal for dynamic supervisor specifications

#### `register_batch(Registrations) -> {ok, [Entry]} | {error, {Reason, FailedKeys, SuccessfulEntries}}`

Register multiple processes in a single atomic call. All succeed or all fail and are rolled back.

```erlang
%% Register 5 trading services for a user (explicit Pids)
UserId = user123,
{ok, Entries} = orka:register_batch([
    {{global, portfolio, UserId}, Pid1, #{tags => [portfolio, user]}},
    {{global, technical, UserId}, Pid2, #{tags => [technical, user]}},
    {{global, orders, UserId}, Pid3, #{tags => [orders, user]}},
    {{global, risk, UserId}, Pid4, #{tags => [risk, user]}},
    {{global, monitoring, UserId}, Pid5, #{tags => [monitoring, user]}}
]).

%% On error, returns tuple with reason, list of failed keys, and list of entries that succeeded (before rollback)
{error, {Reason, FailedKeys, SuccessfulEntries}} = orka:register_batch([...]).
```

**Behavior**:
- If a key is **already registered with a live process**, the existing entry is returned in the results and batch continues (similar to `register/3`)
- If a key's process is **dead**, the entry is cleaned up and the new Pid is registered
- On any registration failure, all **newly registered entries from this batch** are rolled back
- Dead processes are automatically cleaned up via monitors

**Rollback behavior**: If any new registration fails, all previously registered entries from this batch are immediately removed from the registry. Entries that were already registered before the call remain in the registry.

**Use cases**:
- Multi-process per-user workloads (trading app: 5 services per user)
- Batch worker registration
- Atomic multi-service startup

#### `register_batch_with(Registrations) -> {ok, [Entry]} | {error, {Reason, FailedKeys, SuccessfulEntries}}`

Start multiple processes via `{Module, Function, Arguments}` and register them atomically.

```erlang
%% Start and register 3 workers in a single atomic call
{ok, Entries} = orka:register_batch_with([
    {{global, worker, job1}, #{tags => [worker]}, {worker_sup, start_job, [job1]}},
    {{global, worker, job2}, #{tags => [worker]}, {worker_sup, start_job, [job2]}},
    {{global, worker, job3}, #{tags => [worker]}, {worker_sup, start_job, [job3]}}
]).

%% On error, returns tuple with reason, list of failed keys, and list of entries that succeeded (before rollback)
{error, {Reason, FailedKeys, SuccessfulEntries}} = orka:register_batch_with([...]).
```

**Behavior**:
- If a key is **already registered with a live process**, the existing entry is returned and batch continues (MFA not executed)
- If a key's process is **dead**, the entry is cleaned up, MFA is executed, and new Pid is registered
- On any failure (MFA error, registration error, invalid return), all **newly started and registered processes from this batch** are rolled back and terminated
- Only processes started in this batch are terminated on rollback; previously registered processes remain

**Rollback behavior**: If any MFA fails or returns invalid value, all previously registered entries from this batch are removed and all processes started by this batch are terminated. Entries that were already registered before the call remain unaffected.

#### `register_single(Key, Metadata) -> {ok, Entry} | error`
#### `register_single(Key, Pid, Metadata) -> {ok, Entry} | error`

Register with singleton constraint: **one key per Pid**. A process can only be registered under one key at a time.

```erlang
%% Register config server as singleton
{ok, Entry} = orka:register_single(
    {global, service, config_server},
    #{tags => [service, config, critical]}
).

%% Attempting to register same Pid under different key fails
{error, {already_registered_under_key, ExistingKey}} = 
    orka:register_single(
        {global, service, app_config},
        ConfigPid,
        Metadata
    ).

%% Re-registering under same key returns the existing entry
{ok, Entry} = orka:register_single(
    {global, service, config_server},
    ConfigPid,
    UpdatedMetadata
).
```

**Use cases**:
- Single-instance services (translator, config server)
- Distributed locks
- Event buses / message routers
- Resource managers requiring exclusive access

---

### Lookup Functions

#### `lookup(Key) -> {ok, {Key, Pid, Metadata}} | not_found`

Fast lookup of a single entry by key (does not check liveness).

```erlang
case orka:lookup({global, service, translator}) of
    {ok, {_Key, Pid, _Meta}} -> 
        %% Service found
        ok;
    not_found -> 
        %% Service not registered
        error
end.
```

#### `lookup_alive(Key) -> {ok, {Key, Pid, Metadata}} | not_found`

Lookup that verifies the registered Pid is alive. If the process is dead, the
entry is removed and `not_found` is returned.

```erlang
case orka:lookup_alive({global, service, translator}) of
    {ok, {_Key, Pid, _Meta}} ->
        %% Service found and alive
        ok;
    not_found ->
        %% Service not registered or process crashed
        error
end.
```

#### `lookup_dirty(Key) -> {ok, {Key, Pid, Metadata}} | not_found | {error, not_supported}`

Lock-free ETS lookup (no liveness check). Only supported for the ETS backend.

```erlang
case orka:lookup_dirty({global, service, translator}) of
    {ok, {_Key, Pid, _Meta}} ->
        %% Service found (no liveness check)
        ok;
    not_found ->
        %% Service not registered
        error
end.
```

#### `lookup_all() -> [{Key, Pid, Metadata}]`

Retrieve all registered entries.

```erlang
AllEntries = orka:lookup_all(),
io:format("~w entries registered~n", [length(AllEntries)]).
```

#### `entries_by_type(Type) -> [{Key, Pid, Metadata}]`

Find all entries matching a key type (second element of 3-tuple key).

```erlang
%% Register some services
orka:register({global, service, translator}, Pid1, Meta1),
orka:register({global, service, cache}, Pid2, Meta2),
orka:register({global, user, "alice@example.com"}, Pid3, Meta3),

%% Find all services
Services = orka:entries_by_type(service),
%% Returns 2 entries

%% Find all users
Users = orka:entries_by_type(user),
%% Returns 1 entry
```

#### `entries_by_tag(Tag) -> [{Key, Pid, Metadata}]`

Find all entries with a specific tag in their metadata.

```erlang
%% Find all online services
OnlineServices = orka:entries_by_tag(online),

%% Find all critical processes
CriticalProcesses = orka:entries_by_tag(critical),

%% Find all processes for a specific user
UserServices = orka:entries_by_tag(user_123),
```

**Complexity**: O(n) where n = entries with that tag (usually small)

#### `count_by_type(Type) -> integer()`

Count entries by type.

```erlang
ServiceCount = orka:count_by_type(service),
UserCount = orka:count_by_type(user).
```

#### `count_by_tag(Tag) -> integer()`

Count entries with a specific tag.

```erlang
OnlineCount = orka:count_by_tag(online),
CriticalCount = orka:count_by_tag(critical).
```

### Tag Normalization

**Behavior**: Tags in metadata are automatically normalized (deduplicated and sorted) when registered via `register/2,3`, `register_with/3`, or `register_batch/1`. For example, `tags => [online, critical, online]` becomes `tags => [critical, online]`. This ensures consistent tag ordering and eliminates duplicates without explicit user action.

### Process Cleanup

**Automatic cleanup**: When a registered process crashes, its entry is automatically removed from the registry. This is achieved via process monitors that trigger cleanup when a process exits. All associated tags and properties are also removed automatically. No explicit demonitor or cleanup code is needed.

---

### Unregister

#### `unregister(Key) -> ok | not_found`

Remove an entry from the registry. Automatic cleanup happens when process crashes.

```erlang
ok = orka:unregister({global, service, translator}),
not_found = orka:unregister({global, service, nonexistent}).
```

**Cleanup**:
- Removes entry from registry
- Removes all tags for entry
- Removes all properties for entry
- Automatic cleanup on process crash (via monitor)

---

#### `unregister_batch(Keys) -> {ok, {RemovedKeys, NotFoundKeys}} | {error, badarg}`

Remove multiple entries in a single call. All keys are processed independently; success/failure of one key doesn't affect others.

```erlang
%% Clean up all services for a user
UserId = user_123,
Keys = [
    {global, service, translator_1},
    {global, service, cache_1},
    {global, service, missing_1}  %% This key doesn't exist
],
{ok, {RemovedKeys, NotFoundKeys}} = orka:unregister_batch(Keys).

%% RemovedKeys = [{global, service, translator_1}, {global, service, cache_1}]
%% NotFoundKeys = [{global, service, missing_1}]
```

**Benefits**:
- Single GenServer call instead of one per key (better performance for bulk cleanup)
- Works with entries registered any way (individual register, batch, etc.)
- Clear reporting of what was removed vs not found
- Automatic cleanup: all associated tags and properties removed

**Use cases**:
- Cleaning up all services for a user/workspace that's shutting down
- Removing batch-registered workloads
- Bulk cleanup operations
- Paired with `register_batch/1` for lifecycle management

**Cleanup behavior**:
- Removes entry from registry
- Removes all tags for each removed entry
- Removes all properties for each removed entry
- Process monitors remain active (automatic cleanup happens when process crashes)

**Comparison with individual unregister**:
- `unregister/1`: Single key, returns `ok | not_found`
- `unregister_batch/1`: Multiple keys, returns detailed breakdown of removed vs not found

---

## Advanced Features

### Startup Coordination: Await & Subscribe

#### `await(Key, Timeout) -> {ok, Entry} | {error, timeout}`

**Blocking** wait for a service to be registered with timeout.

```erlang
%% Wait up to 30 seconds for database service
case orka:await({global, service, database}, 30000) of
    {ok, {_Key, DbPid, _Meta}} -> 
        io:format("Database ready: ~p~n", [DbPid]);
    {error, timeout} -> 
        io:format("Database startup timeout~n", []),
        {stop, database_timeout}
end.
```

**Multi-service startup**:

```erlang
init([]) ->
    %% Wait for critical services in parallel
    case await_all_services([
        {{global, service, database}, 30000},
        {{global, service, cache}, 30000},
        {{global, service, queue}, 30000}
    ]) of
        {ok, Services} -> 
            {ok, #state{services = Services}};
        {error, timeout} -> 
            {stop, startup_timeout}
    end.

await_all_services(Services) ->
    Results = [orka:await(K, T) || {K, T} <- Services],
    case lists:all(fun(R) -> R =/= {error, timeout} end, Results) of
        true -> {ok, Results};
        false -> {error, timeout}
    end.
```

**Use cases**:
- Blocking on critical dependencies during startup
- Multi-service initialization sequence
- Ensuring system is ready before proceeding

#### `subscribe(Key) -> ok`

**Non-blocking** subscription to key registration. Receive `{orka_registered, Key, Entry}` message when registered.

```erlang
%% In gen_server init
init([]) ->
    %% Subscribe to optional cache service
    orka:subscribe({global, service, cache}),
    {ok, #state{cache_ready = false}}.

%% In handle_info
handle_info({orka_registered, Key, {_, CachePid, _Meta}}, State) ->
    io:format("Cache service appeared: ~p~n", [CachePid]),
    {noreply, State#state{cache_ready = true, cache = CachePid}}.
```

**Multiple subscriptions**:

```erlang
init([]) ->
    orka:subscribe({global, service, cache}),
    orka:subscribe({global, service, metrics}),
    orka:subscribe({global, service, tracing}),
    {ok, #state{optional_services = #{}}}.

handle_info({orka_registered, Key, {_, Pid, _}}, State) ->
    NewServices = maps:put(Key, Pid, State#state.optional_services),
    {noreply, State#state{optional_services = NewServices}}.
```

**Use cases**:
- Optional dependencies
- Long-running services that may start after your process
- Non-critical enhancements

#### `unsubscribe(Key) -> ok`

Cancel a subscription.

```erlang
handle_cast({disable_feature}, State) ->
    orka:unsubscribe({global, service, cache}),
    {noreply, State}.
```

---

### Metadata Management

#### `add_tag(Key, Tag) -> ok | error`

Add a tag to an existing entry.

```erlang
ok = orka:add_tag({global, service, translator}, critical),
ok = orka:add_tag({global, service, translator}, critical).
```

#### `remove_tag(Key, Tag) -> ok | error`

Remove a tag from an entry.

```erlang
ok = orka:remove_tag({global, service, translator}, critical),
{error, tag_not_found} = orka:remove_tag({global, service, translator}, critical).
```

#### `update_metadata(Key, NewMetadata) -> ok | not_found`

Update metadata while preserving existing tags.

```erlang
ok = orka:update_metadata(
    {global, service, translator},
    #{capacity => 200, version => "2.2.0"}
).
```

---

### Properties: Queryable Custom Data

Properties enable rich querying by arbitrary attributes (version, region, capacity, etc.).

#### `register_property(Key, Pid, #{property => Name, value => Value}) -> ok | error`

Register a property value for a process.

```erlang
%% Register load balancer instances with capacity
orka:register_property(
    {global, service, translator_1},
    TranslatorPid1,
    #{property => capacity, value => 100}
).

orka:register_property(
    {global, service, translator_2},
    TranslatorPid2,
    #{property => capacity, value => 150}
).

%% Register database replicas by region
orka:register_property({global, resource, db_1}, DbPid1, 
    #{property => region, value => "us-west"}).
orka:register_property({global, resource, db_2}, DbPid2, 
    #{property => region, value => "us-east"}).
```

#### `find_by_property(PropertyName, PropertyValue) -> [{Key, Pid, Metadata}]`

Find all entries with a specific property value. Matches use exact Erlang term equality (e.g., `"us-west"` matches only `"us-west"`, not `us_west`).

```erlang
%% Find all services in us-west region
WestServices = orka:find_by_property(region, "us-west"),

%% Find all translators with capacity of exactly 150
HighCapacity = orka:find_by_property(capacity, 150).
```

#### `find_by_property(Type, PropertyName, PropertyValue) -> [{Key, Pid, Metadata}]`

Find entries with a specific property value, filtered by key type. The `Type` parameter matches the second element of the key tuple (e.g., `service`, `resource`). Property matching uses exact Erlang term equality.

```erlang
%% Find all database resources in us-west (not services)
WestDatabases = orka:find_by_property(resource, region, "us-west").

%% Find all services (Type) with specific configuration (Property)
ConfiguredServices = orka:find_by_property(service, config, #{timeout => 5000, retries => 3}).
```

#### `count_by_property(PropertyName, PropertyValue) -> integer()`

Count entries with a property value.

```erlang
WestCount = orka:count_by_property(region, "us-west"),
io:format("~w services in us-west~n", [WestCount]).
```

#### `property_stats(Type, PropertyName) -> #{Value => Count}`

Get distribution statistics for a property across entries of a specific type. Aggregates counts by property value.

```erlang
%% Get region distribution for all services (counts per region)
RegionStats = orka:property_stats(service, region),
%% Result: #{"us-west" => 3, "us-east" => 2, "eu-central" => 1}

%% Get capacity distribution for all resources (counts per capacity level)
CapacityStats = orka:property_stats(resource, capacity),
%% Result: #{100 => 2, 150 => 3, 200 => 1}

%% Get distribution of configuration objects (aggregated by unique config value)
ConfigStats = orka:property_stats(service, config),
%% Result: #{#{timeout => 5000, retries => 3} => 2, #{timeout => 10000, retries => 5} => 1}
```

**Use cases**:
- Geographic load balancing by service type (how many services per region)
- Health monitoring by region for specific types
- Resource pool distribution analysis
- Feature flag queries per type
- Capacity planning
- Monitoring property value distribution

**Note**: Returns a map where keys are property values (any Erlang term) and values are counts of processes with that property value. For example, if 3 services have `region => "us-west"`, the result includes `#{"us-west" => 3}`.

---

## Usage Patterns

### Pattern 1: Supervisor Registration

Register supervisor children in a gen_server callback:

```erlang
%% In supervisor_SUITE.erl or supervisor init

start_link() ->
    supervisor:start_link({local, my_sup}, ?MODULE, []).

init([]) ->
    Children = [
        {translator_sup, 
         {translator_sup, start_link, []},
         permanent, 5000, supervisor, [translator_sup]}
    ],
    {ok, {#{}, Children}}.

%% In child module - register when starting
start_link() ->
    gen_server:start_link(?MODULE, [], []).

init([]) ->
    %% Register this service
    {ok, _} = orka:register(
        {global, service, translator},
        self(),
        #{tags => [service, translator, online]}
    ),
    {ok, #state{}}.
```

### Pattern 2: Atomic Process Startup

Use `register_with` to ensure registration happens atomically with process startup:

```erlang
%% Start and register in supervisor
{ok, Pid} = orka:register_with(
    {global, service, database},
    #{tags => [service, database, critical]},
    {db_server, start_link, []}
).

%% Process will be terminated if registration fails
```

### Pattern 3: Singleton Services

Enforce single-instance constraint:

```erlang
%% Config server - only one allowed
{ok, _} = orka:register_single(
    {global, service, config},
    #{tags => [service, config, critical]}
).

%% Re-registering same Pid with different key fails
{error, {already_registered_under_key, _}} = 
    orka:register_single(
        {global, service, app_config},
        SamePid,
        Metadata
    ).
```

### Pattern 4: Batch Per-User Registration

Register 5 trading services per user atomically:

```erlang
%% In trading_app
create_user_workspace(UserId) ->
    {ok, Entries} = orka:register_batch([
        {{global, portfolio, UserId}, Pid1, #{
            tags => [UserId, portfolio, trading]
        }},
        {{global, technical, UserId}, Pid2, #{
            tags => [UserId, technical, trading]
        }},
        {{global, orders, UserId}, Pid3, #{
            tags => [UserId, orders, trading]
        }},
        {{global, risk, UserId}, Pid4, #{
            tags => [UserId, risk, trading]
        }},
        {{global, monitoring, UserId}, Pid5, #{
            tags => [UserId, monitoring, trading]
        }}
    ]),
    {ok, Entries}.

%% Query all services for user
get_user_services(UserId) ->
    Services = orka:entries_by_tag(UserId),
    [Pid || {_Key, Pid, _Meta} <- Services].

%% Query specific service type for user
get_portfolio_service(UserId) ->
    case orka:lookup({global, portfolio, UserId}) of
        {ok, {_Key, Pid, _Meta}} -> Pid;
        not_found -> error
    end.
```

### Pattern 5: Startup Coordination

Wait for dependencies to be ready:

```erlang
%% Application initialization
start(normal, _) ->
    application:ensure_all_started(orka),
    
    %% Start main services
    my_sup:start_link(),
    
    %% Wait for all critical services
    case wait_for_services([database, cache, queue], 30000) of
        ok -> 
            io:format("System ready~n", []);
        {error, timeout} -> 
            io:format("Startup timeout~n", []),
            {error, startup_timeout}
    end.

wait_for_services(Services, Timeout) ->
    lists:foldl(fun(Service, ok) ->
        Key = {global, service, Service},
        case orka:await(Key, Timeout) of
            {ok, _} -> ok;
            {error, timeout} -> {error, timeout}
        end
    end, ok, Services).
```

### Pattern 6: Optional Dependencies

Subscribe to optional services without blocking:

```erlang
%% In gen_server init
init([]) ->
    %% Critical: wait for database
    {ok, {_K, DbPid, _M}} = orka:await({global, service, database}, 30000),
    
    %% Optional: subscribe to cache if available
    orka:subscribe({global, service, cache}),
    
    {ok, #state{db = DbPid, cache = undefined}}.

%% Cache appears later
handle_info({orka_registered, {global, service, cache}, {_, CachePid, _}}, State) ->
    io:format("Cache service ready~n", []),
    {noreply, State#state{cache = CachePid}}.
```

### Pattern 7: Health Monitoring

Monitor system health via tags and properties:

```erlang
%% Health check function
check_system_health() ->
    OnlineServices = orka:count_by_tag(online),
    CriticalServices = orka:count_by_tag(critical),
    
    case {OnlineServices, CriticalServices} of
        {_, 0} -> {error, critical_services_down};
        {N, M} when N < 2 -> {warning, low_availability};
        _ -> ok
    end.

%% Geo-distribution check
check_geo_distribution() ->
    RegionStats = orka:property_stats(service, region),
    io:format("Services by region: ~p~n", [RegionStats]).
```

### Pattern 8: Load Balancing

Use properties for load-aware routing:

```erlang
%% Register translators with capacity
register_translators([Pid1, Pid2, Pid3]) ->
    orka:register({global, service, translator}, Pid1, 
        #{tags => [translator, available]}),
    orka:register_property({global, service, translator}, Pid1,
        #{property => available_slots, value => 50}),
    
    orka:register({global, service, translator}, Pid2, 
        #{tags => [translator, available]}),
    orka:register_property({global, service, translator}, Pid2,
        #{property => available_slots, value => 75}).

%% Pick least-loaded translator
get_translator() ->
    Available = orka:find_by_property(available_slots, 75),
    case Available of
        [{_K, Pid, _M} | _] -> Pid;
        [] -> error(no_available_translators)
    end.
```

---

## Backend Architecture

Orka's core is **backend-agnostic**: the registry logic is decoupled from storage, allowing different backends for different use cases.

### Current Implementation

- **`orka_store_ets`** — Default backend (ETS-based)
  - Separate stores for `local` and `global` scoped entries
  - Protected named ETS tables (supports `lookup_dirty/1`)
  - Efficient indices for tags and properties
  - Single-node performance: ~1-2 microseconds for lookups

### Pluggable Backend Interface

Backends implement the `orka_store` behaviour:

```erlang
%% Lifecycle
-callback init(Opts :: map()) -> {ok, store()}.
-callback terminate(Reason, Store) -> ok.

%% Core CRUD operations
-callback get(Key, Store) -> {ok, entry()} | not_found.
-callback put(Key, Pid, Meta, Store) -> {ok, entry(), Store1}.
-callback del(Key, Store) -> {ok, Store1} | {not_found, Store1}.

%% Queries
-callback select_by_type(Type, Store) -> [entry()].
-callback select_by_tag(Tag, Store) -> [entry()].
-callback select_by_property(Prop, Value, Store) -> [entry()].
-callback count_by_type(Type, Store) -> non_neg_integer().
-callback property_stats(Type, Prop, Store) -> map().

%% Bulk operations
-callback put_many(Items, Store) -> {ok, [entry()], Store1}.
-callback del_many(Keys, Store) -> {ok, Store1}.
```

### Future Backend Extensions

- **RA** — Replicated state machine for cluster-wide registries
- **Khepri** — Tree-structured database for distributed registries
- **Riak Core** — Distributed hashtree for high-availability systems
- **Custom** — User-defined backends for domain-specific needs

See [docs/extensions/](docs/extensions/) for implementation guides.

---

## Design Principles

### 1. Backend Abstraction

The registry interface is independent of storage. Swap backends to change consistency/performance trade-offs without changing your code:
- **ETS** — Local-only, ultra-fast
- **RA/Khepri** — Distributed, replicated, eventual consistency

```erlang
%% These are fast, backend-specific reads
Entry = orka:lookup(Key),
All = orka:lookup_all(),
Tagged = orka:entries_by_tag(online),
Count = orka:count_by_type(service).
```

### 2. Backend-Specific Read Semantics

Read behavior depends on the configured backend. The default ETS backend uses
named tables behind a store abstraction, and reads go through the gen_server
for consistent routing and optional liveness checks (see `lookup_alive/1`).

```erlang
%% Automatic cleanup when process exits
orka:register({global, user, alice}, AlicePid, Meta),
exit(AlicePid, kill),  %% Process dies
timer:sleep(100),
not_found = orka:lookup_alive({global, user, alice}).  %% Entry gone
```

### 3. Automatic Cleanup via Monitors

Process crashes are detected via monitors and entries are automatically removed. Manual cleanup is optional.

### 4. Three Key Patterns for Metadata

**Tags** — For categorization and querying groups:
```erlang
#{tags => [online, critical, translator]}  %% Multiple categories
orka:entries_by_tag(critical).              %% Find by category
```

**Properties** — For searchable metadata:
```erlang
orka:register_property(Key, Pid, #{property => region, value => "us-west"})
orka:find_by_property(region, "us-west").  %% Find by attribute
```

**Key structure** — For hierarchical lookups:
```erlang
{global, service, translator}  %% Easily identify scope/type/name
orka:entries_by_type(service). %% Query by type
```

### 5. Consistency Model (Backend-Dependent)

**ETS Backend (Default)**:
- **Local consistency**: Strong (ETS is immediate)
- **Distributed consistency**: Not supported
- **Scope**: Single-node registries only

**Planned Distributed Backends**:
- **RA/Khepri**: Replicated state machine for cluster-wide consistency
- **Custom**: User-defined consistency models

**Universal**:
- **Process lifecycle**: Automatic (monitors)
- **Await/Subscribe**: Guaranteed delivery (with optional timeouts)

---

## FAQ

### Q: What's the difference between tags and properties?

**Tags** are for categorization (online, critical, translator, user).
```erlang
tags => [online, critical, translator]
orka:entries_by_tag(online).  %% Get all online
```

**Properties** are for searchable attributes (region: "us-west", capacity: 100).
```erlang
orka:register_property(Key, Pid, #{property => region, value => "us-west"})
orka:find_by_property(region, "us-west").  %% Get all in us-west
```

### Q: Should I use await or subscribe?

- **await**: Blocking wait for critical dependencies (use sparingly)
  ```erlang
  {ok, Entry} = orka:await({global, service, database}, 30000).
  ```

- **subscribe**: Non-blocking optional dependencies
  ```erlang
  orka:subscribe({global, service, cache}).
  %% Receive {orka_registered, Key, Entry} when ready
  ```

### Q: How do I query all services for a user?

Use tags to group per-user services:

```erlang
%% Register with user ID as tag
orka:register({global, portfolio, user123}, Pid, #{tags => [user123, portfolio]}),
orka:register({global, orders, user123}, Pid, #{tags => [user123, orders]}),

%% Query all
AllUserServices = orka:entries_by_tag(user123).
```

### Q: What happens if a process crashes?

Automatic cleanup via monitors:

```erlang
orka:register({global, service, translator}, Pid, Meta),
exit(Pid, kill),           %% Process crashes
timer:sleep(100),          %% Wait for monitor notification
not_found = orka:lookup(Key).  %% Entry removed automatically
```

### Q: What happens when I batch register a key that's already registered?

If a key is already registered with a **live process**, the existing entry is returned and the batch continues (similar to regular `register/3`):

```erlang
%% First batch
{ok, [E1, E2, E3]} = orka:register_batch([
    {{global, service, api}, Pid1, #{tags => [service]}},
    {{global, service, cache}, Pid2, #{tags => [service]}},
    {{global, service, db}, Pid3, #{tags => [service]}}
]).

%% Re-run same batch with new Pid for api (different process)
{ok, [E1_existing, E2_new, E3_new]} = orka:register_batch([
    {{global, service, api}, Pid1, Meta},  %% Returns existing E1 (Pid1 still registered)
    {{global, service, cache}, Pid2_new, Meta},  %% Registers new Pid2_new
    {{global, service, db}, Pid3_new, Meta}  %% Registers new Pid3_new
]).
```

This allows safe batch re-registration - existing services aren't replaced if still running. If you need to replace a running process, unregister it first or use `register/3` with a specific Pid.

### Q: Can I use orka in a distributed system?

**Currently**: Orka is local-node only. The default ETS backend handles single-node registries.

**Planned**: Future extensions will support distributed backends:
- **RA backend** — Replicated state machine for cluster-wide registries
- **Khepri backend** — Tree-structured database for high-availability systems
- **Custom backends** — Implement the `orka_store` behaviour for domain-specific needs

See [docs/extensions/](docs/extensions/) for implementation guides and roadmap.

### Q: How do backends work?

Orka decouples the registry logic from storage. The `orka_store` behaviour defines the interface:

```erlang
-callback get(Key, Store) -> {ok, entry()} | not_found.
-callback put(Key, Pid, Meta, Store) -> {ok, entry(), Store1}.
-callback select_by_type(Type, Store) -> [entry()].
-callback select_by_tag(Tag, Store) -> [entry()].
%% ... etc
```

You implement this behaviour for different storage engines:
- **ETS**: Single-node, ultra-fast
- **RA**: Replicated, eventual consistency
- **Custom**: Your own consistency model

Same API, different backends.

### Q: How do I test my code that uses orka?

Common Test is recommended for orka because it handles:
- Real process lifecycle management
- Timing-dependent tests (awaits, timeouts)
- Concurrent process scenarios
- Monitor and crash handling

Property-based testing (PropEr) is less suitable because orka's challenges are concurrency and timing, not input space exploration.

### Q: What's the performance overhead?

**ETS backend (default)**:
- **Lookup**: ~1-2 microseconds (ETS public table)
- **Registration**: ~10-20 microseconds (gen_server call + ETS insert + monitor)
- **Tag query**: O(n) where n = entries with tag (typically small)

**Other backends**: Performance varies by implementation (see [docs/extensions/](docs/extensions/)).

Not suitable for per-message operations, but fine for service startup and occasional queries.

---

## Further Reading

The following detailed guides and examples are in the `docs/` directory:

- **[Usage Patterns](docs/usage_patterns.md)** — 8 detailed patterns for service startup
- **[Singleton Examples](docs/singleton_examples.md)** — Single-instance services
- **[Property Examples](docs/property_examples.md)** — Rich querying with properties
- **[Await/Subscribe Examples](docs/await_examples.md)** — Startup coordination deep-dive
- **[Comparison with Alternatives](docs/comparison.md)** — gproc vs syn vs orka
