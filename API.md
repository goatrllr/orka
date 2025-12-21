# Orca Registry API Documentation

Orca is a production-ready **ETS-based process registry** for Erlang/OTP applications. It provides fast, lock-free lookups with features for registration, metadata management, tags, properties, and startup coordination.

**Status**: ✅ Fully tested (35/35 tests passing) | **Latest**: Batch registration support | **License**: MIT

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
%% Start the orca application
{ok, _} = application:ensure_all_started(orca).

%% Register a process with metadata
orca:register({global, service, translator}, MyPid, #{
    tags => [service, translator, online],
    properties => #{version => "2.1.0"}
}).

%% Lookup a process
{ok, {Key, Pid, Metadata}} = orca:lookup({global, service, translator}).

%% Query by tag
OnlineServices = orca:entries_by_tag(online).

%% Unregister
ok = orca:unregister({global, service, translator}).
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
    tags => [atom1, atom2, ...],           %% Categories for querying
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
{ok, {Key, Pid, Metadata}} = orca:register(
    {global, user, "alice@example.com"},
    #{tags => [user, online], properties => #{region => "us-west"}}
).
```

#### `register(Key, Pid, Metadata) -> {ok, Entry} | error`

Register a specific process (useful in supervisors).

```erlang
%% Supervisor registering a child
{ok, {Key, Pid, Metadata}} = orca:register(
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
{ok, TranslatorPid} = orca:register_with(
    {global, service, translator},
    #{tags => [service, translator, critical]},
    {translator_server, start_link, []}
).

%% If registration fails, process is automatically terminated
```

**Benefits**:
- Atomic startup + registration (no races)
- Automatic cleanup if registration fails
- Ideal for dynamic supervisor specifications

#### `register_batch(Registrations) -> {ok, [Entry]} | error`

Register multiple processes in a single atomic call. All succeed or all fail.

```erlang
%% Register 5 trading services for a user
UserId = user123,
{ok, Entries} = orca:register_batch([
    {{global, portfolio, UserId}, #{tags => [portfolio, user]}},
    {{global, technical, UserId}, #{tags => [technical, user]}},
    {{global, orders, UserId}, #{tags => [orders, user]}},
    {{global, risk, UserId}, #{tags => [risk, user]}},
    {{global, monitoring, UserId}, #{tags => [monitoring, user]}}
]).

%% Or with explicit Pids
{ok, Entries} = orca:register_batch([
    {{global, worker, job1}, Pid1, #{tags => [worker]}},
    {{global, worker, job2}, Pid2, #{tags => [worker]}},
    {{global, worker, job3}, Pid3, #{tags => [worker]}}
]).
```

**Use cases**:
- Multi-process per-user workloads (trading app: 5 services per user)
- Batch worker registration
- Atomic multi-service startup

#### `register_single(Key, Metadata) -> {ok, Entry} | error`
#### `register_single(Key, Pid, Metadata) -> {ok, Entry} | error`

Register with singleton constraint: **one key per Pid**. A process can only be registered under one key at a time.

```erlang
%% Register config server as singleton
{ok, Entry} = orca:register_single(
    {global, service, config_server},
    #{tags => [service, config, critical]}
).

%% Attempting to register same Pid under different key fails
{error, {already_registered_under_key, ExistingKey}} = 
    orca:register_single(
        {global, service, app_config},
        ConfigPid,
        Metadata
    ).

%% Re-registering under same key is idempotent
{ok, Entry} = orca:register_single(
    {global, service, config_server},
    ConfigPid,
    NewMetadata
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

Fast, lock-free lookup of a single entry by key.

```erlang
case orca:lookup({global, service, translator}) of
    {ok, {_Key, Pid, _Meta}} -> 
        %% Service found
        ok;
    not_found -> 
        %% Service not registered or process crashed
        error
end.
```

#### `lookup_all() -> [{Key, Pid, Metadata}]`

Retrieve all registered entries.

```erlang
AllEntries = orca:lookup_all(),
io:format("~w entries registered~n", [length(AllEntries)]).
```

#### `entries_by_type(Type) -> [{Key, Pid, Metadata}]`

Find all entries matching a key type (second element of 3-tuple key).

```erlang
%% Register some services
orca:register({global, service, translator}, Pid1, Meta1),
orca:register({global, service, cache}, Pid2, Meta2),
orca:register({global, user, "alice@example.com"}, Pid3, Meta3),

%% Find all services
Services = orca:entries_by_type(service),
%% Returns 2 entries

%% Find all users
Users = orca:entries_by_type(user),
%% Returns 1 entry
```

#### `entries_by_tag(Tag) -> [{Key, Pid, Metadata}]`

Find all entries with a specific tag in their metadata.

```erlang
%% Find all online services
OnlineServices = orca:entries_by_tag(online),

%% Find all critical processes
CriticalProcesses = orca:entries_by_tag(critical),

%% Find all processes for a specific user
UserServices = orca:entries_by_tag(user_123),
```

**Complexity**: O(n) where n = entries with that tag (usually small)

#### `count_by_type(Type) -> integer()`

Count entries by type.

```erlang
ServiceCount = orca:count_by_type(service),
UserCount = orca:count_by_type(user).
```

#### `count_by_tag(Tag) -> integer()`

Count entries with a specific tag.

```erlang
OnlineCount = orca:count_by_tag(online),
CriticalCount = orca:count_by_tag(critical).
```

---

### Unregister

#### `unregister(Key) -> ok | not_found`

Remove an entry from the registry. Automatic cleanup happens when process crashes.

```erlang
ok = orca:unregister({global, service, translator}),
not_found = orca:unregister({global, service, nonexistent}).
```

**Cleanup**:
- Removes entry from registry
- Removes all tags for entry
- Removes all properties for entry
- Automatic cleanup on process crash (via monitor)

---

## Advanced Features

### Startup Coordination: Await & Subscribe

#### `await(Key, Timeout) -> {ok, Entry} | {error, timeout}`

**Blocking** wait for a service to be registered with timeout.

```erlang
%% Wait up to 30 seconds for database service
case orca:await({global, service, database}, 30000) of
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
    Results = [orca:await(K, T) || {K, T} <- Services],
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

**Non-blocking** subscription to key registration. Receive `{orca_registered, Key, Entry}` message when registered.

```erlang
%% In gen_server init
init([]) ->
    %% Subscribe to optional cache service
    orca:subscribe({global, service, cache}),
    {ok, #state{cache_ready = false}}.

%% In handle_info
handle_info({orca_registered, Key, {_, CachePid, _Meta}}, State) ->
    io:format("Cache service appeared: ~p~n", [CachePid]),
    {noreply, State#state{cache_ready = true, cache = CachePid}}.
```

**Multiple subscriptions**:

```erlang
init([]) ->
    orca:subscribe({global, service, cache}),
    orca:subscribe({global, service, metrics}),
    orca:subscribe({global, service, tracing}),
    {ok, #state{optional_services = #{}}}.

handle_info({orca_registered, Key, {_, Pid, _}}, State) ->
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
    orca:unsubscribe({global, service, cache}),
    {noreply, State}.
```

---

### Metadata Management

#### `add_tag(Key, Tag) -> ok | error`

Add a tag to an existing entry.

```erlang
ok = orca:add_tag({global, service, translator}, critical),
{error, tag_already_exists} = orca:add_tag({global, service, translator}, critical).
```

#### `remove_tag(Key, Tag) -> ok | error`

Remove a tag from an entry.

```erlang
ok = orca:remove_tag({global, service, translator}, critical),
{error, tag_not_found} = orca:remove_tag({global, service, translator}, critical).
```

#### `update_metadata(Key, NewMetadata) -> ok | not_found`

Update metadata while preserving existing tags.

```erlang
ok = orca:update_metadata(
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
orca:register_property(
    {global, service, translator_1},
    TranslatorPid1,
    #{property => capacity, value => 100}
).

orca:register_property(
    {global, service, translator_2},
    TranslatorPid2,
    #{property => capacity, value => 150}
).

%% Register database replicas by region
orca:register_property({global, resource, db_1}, DbPid1, 
    #{property => region, value => "us-west"}).
orca:register_property({global, resource, db_2}, DbPid2, 
    #{property => region, value => "us-east"}).
```

#### `find_by_property(PropertyName, PropertyValue) -> [{Key, Pid, Metadata}]`

Find all entries with a specific property value.

```erlang
%% Find all services in us-west region
WestServices = orca:find_by_property(region, "us-west"),

%% Find all translators with capacity >= 150
HighCapacity = orca:find_by_property(capacity, 150).
```

#### `find_by_property(Type, PropertyName, PropertyValue) -> [{Key, Pid, Metadata}]`

Find entries by type AND property.

```erlang
%% Find all database resources in us-west (not services)
WestDatabases = orca:find_by_property(resource, region, "us-west").
```

#### `count_by_property(PropertyName, PropertyValue) -> integer()`

Count entries with a property value.

```erlang
WestCount = orca:count_by_property(region, "us-west"),
io:format("~w services in us-west~n", [WestCount]).
```

#### `property_stats(PropertyName, _) -> #{Value => Count}`

Get distribution statistics for a property.

```erlang
%% Get all regions and their counts
RegionStats = orca:property_stats(region, _),
%% Result: #{"us-west" => 3, "us-east" => 2, "eu-central" => 1}

%% Get capacity distribution
CapacityStats = orca:property_stats(capacity, _),
%% Result: #{100 => 2, 150 => 3, 200 => 1}
```

**Use cases**:
- Geographic load balancing
- Health monitoring by region
- Resource pool distribution
- Feature flag queries
- Capacity planning

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
    {ok, _} = orca:register(
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
{ok, Pid} = orca:register_with(
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
{ok, _} = orca:register_single(
    {global, service, config},
    #{tags => [service, config, critical]}
).

%% Re-registering same Pid with different key fails
{error, {already_registered_under_key, _}} = 
    orca:register_single(
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
    {ok, Entries} = orca:register_batch([
        {{global, portfolio, UserId}, #{
            tags => [UserId, portfolio, trading]
        }},
        {{global, technical, UserId}, #{
            tags => [UserId, technical, trading]
        }},
        {{global, orders, UserId}, #{
            tags => [UserId, orders, trading]
        }},
        {{global, risk, UserId}, #{
            tags => [UserId, risk, trading]
        }},
        {{global, monitoring, UserId}, #{
            tags => [UserId, monitoring, trading]
        }}
    ]),
    {ok, Entries}.

%% Query all services for user
get_user_services(UserId) ->
    Services = orca:entries_by_tag(UserId),
    [Pid || {_Key, Pid, _Meta} <- Services].

%% Query specific service type for user
get_portfolio_service(UserId) ->
    case orca:lookup({global, portfolio, UserId}) of
        {ok, {_Key, Pid, _Meta}} -> Pid;
        not_found -> error
    end.
```

### Pattern 5: Startup Coordination

Wait for dependencies to be ready:

```erlang
%% Application initialization
start(normal, _) ->
    application:ensure_all_started(orca),
    
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
        case orca:await(Key, Timeout) of
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
    {ok, {_K, DbPid, _M}} = orca:await({global, service, database}, 30000),
    
    %% Optional: subscribe to cache if available
    orca:subscribe({global, service, cache}),
    
    {ok, #state{db = DbPid, cache = undefined}}.

%% Cache appears later
handle_info({orca_registered, {global, service, cache}, {_, CachePid, _}}, State) ->
    io:format("Cache service ready~n", []),
    {noreply, State#state{cache = CachePid}}.
```

### Pattern 7: Health Monitoring

Monitor system health via tags and properties:

```erlang
%% Health check function
check_system_health() ->
    OnlineServices = orca:count_by_tag(online),
    CriticalServices = orca:count_by_tag(critical),
    
    case {OnlineServices, CriticalServices} of
        {_, 0} -> {error, critical_services_down};
        {N, M} when N < 2 -> {warning, low_availability};
        _ -> ok
    end.

%% Geo-distribution check
check_geo_distribution() ->
    RegionStats = orca:property_stats(region, _),
    io:format("Services by region: ~p~n", [RegionStats]).
```

### Pattern 8: Load Balancing

Use properties for load-aware routing:

```erlang
%% Register translators with capacity
register_translators([Pid1, Pid2, Pid3]) ->
    orca:register({global, service, translator}, Pid1, 
        #{tags => [translator, available]}),
    orca:register_property({global, service, translator}, Pid1,
        #{property => available_slots, value => 50}),
    
    orca:register({global, service, translator}, Pid2, 
        #{tags => [translator, available]}),
    orca:register_property({global, service, translator}, Pid2,
        #{property => available_slots, value => 75}).

%% Pick least-loaded translator
get_translator() ->
    Available = orca:find_by_property(available_slots, 75),
    case Available of
        [{_K, Pid, _M} | _] -> Pid;
        [] -> error(no_available_translators)
    end.
```

---

## Design Principles

### 1. Lock-Free Reads

All `lookup_*` operations use ETS public tables without locking. Only writes (registration, unregistration) go through the gen_server.

```erlang
%% These are fast, lock-free
Entry = orca:lookup(Key),
All = orca:lookup_all(),
Tagged = orca:entries_by_tag(online),
Count = orca:count_by_type(service).
```

### 2. Automatic Cleanup

Process crashes are detected via monitors and entries are automatically removed. Manual cleanup is optional.

```erlang
%% Automatic cleanup when process exits
orca:register({global, user, alice}, AlicePid, Meta),
exit(AlicePid, kill),  %% Process dies
timer:sleep(100),
not_found = orca:lookup({global, user, alice}).  %% Entry gone
```

### 3. Three Key Patterns

**Tags** — For categorization and querying groups:
```erlang
#{tags => [online, critical, translator]}  %% Multiple categories
orca:entries_by_tag(critical).              %% Find by category
```

**Properties** — For searchable metadata:
```erlang
orca:register_property(Key, Pid, #{property => region, value => "us-west"})
orca:find_by_property(region, "us-west").  %% Find by attribute
```

**Key structure** — For hierarchical lookups:
```erlang
{global, service, translator}  %% Easily identify scope/type/name
orca:entries_by_type(service). %% Query by type
```

### 4. Consistency Model

- **Local consistency**: Strong (ETS is immediate)
- **Distributed consistency**: Not supported (use syn for that)
- **Process lifecycle**: Automatic (monitors)
- **Await/Subscribe**: Guaranteed delivery (with optional timeouts)

---

## FAQ

### Q: What's the difference between tags and properties?

**Tags** are for categorization (online, critical, translator, user).
```erlang
tags => [online, critical, translator]
orca:entries_by_tag(online).  %% Get all online
```

**Properties** are for searchable attributes (region: "us-west", capacity: 100).
```erlang
orca:register_property(Key, Pid, #{property => region, value => "us-west"})
orca:find_by_property(region, "us-west").  %% Get all in us-west
```

### Q: Should I use await or subscribe?

- **await**: Blocking wait for critical dependencies (use sparingly)
  ```erlang
  {ok, Entry} = orca:await({global, service, database}, 30000).
  ```

- **subscribe**: Non-blocking optional dependencies
  ```erlang
  orca:subscribe({global, service, cache}).
  %% Receive {orca_registered, Key, Entry} when ready
  ```

### Q: How do I query all services for a user?

Use tags to group per-user services:

```erlang
%% Register with user ID as tag
orca:register({global, portfolio, user123}, Pid, #{tags => [user123, portfolio]}),
orca:register({global, orders, user123}, Pid, #{tags => [user123, orders]}),

%% Query all
AllUserServices = orca:entries_by_tag(user123).
```

### Q: What happens if a process crashes?

Automatic cleanup via monitors:

```erlang
orca:register({global, service, translator}, Pid, Meta),
exit(Pid, kill),           %% Process crashes
timer:sleep(100),          %% Wait for monitor notification
not_found = orca:lookup(Key).  %% Entry removed automatically
```

### Q: Can I use orca with a distributed system?

Orca is local-node only. For distributed process groups, see the [orca_syn integration patterns documentation](docs/extensions/orca_syn.md).

### Q: How do I test my code that uses orca?

Common Test is recommended for orca because it handles:
- Real process lifecycle management
- Timing-dependent tests (awaits, timeouts)
- Concurrent process scenarios
- Monitor and crash handling

Property-based testing (PropEr) is less suitable because orca's challenges are concurrency and timing, not input space exploration.

### Q: What's the performance overhead?

- **Lookup**: ~1-2 microseconds (ETS public table)
- **Registration**: ~10-20 microseconds (gen_server call + ETS insert + monitor)
- **Tag query**: O(n) where n = entries with tag (typically small)

Not suitable for per-message operations, but fine for service startup and occasional queries.

---

## Further Reading

The following detailed guides and examples are in the `docs/` directory:

- **[Usage Patterns](docs/usage_patterns.md)** — 8 detailed patterns for service startup
- **[Singleton Examples](docs/singleton_examples.md)** — Single-instance services
- **[Property Examples](docs/property_examples.md)** — Rich querying with properties
- **[Await/Subscribe Examples](docs/await_examples.md)** — Startup coordination deep-dive
- **[Comparison with Alternatives](docs/comparison.md)** — gproc vs syn vs orca

