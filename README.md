# Orka: Fast Process Registry for Erlang

> **Branch Context**: This documentation covers the **Orka Core API** on the `main` branch. Orka uses a split-branch strategy where stable Core remains on `main` and extensions are on feature branches. Ensure you're on the correct branch for your use case.

Orka is a **high-performance, ETS-based process registry** for Erlang/OTP applications. It provides fast lock-free lookups, automatic process lifecycle management, rich metadata querying, and startup coordination features.

**Simple API**: 31 functions for registration, lookup, tagging, properties, batch operations, and startup coordination. **Lightweight**: Zero external dependencies, pure Erlang/OTP. **Fast**: ~1-2µs lookups (500K-1M queries/sec). **Reliable**: 74 tests passing, automatic cleanup on process crash, API stability guaranteed.

## Features

✅ **Fast registration & lookup** — O(1) lookups via ETS public tables  
✅ **Automatic cleanup** — Process monitors handle crashes  
✅ **Rich metadata** — Tags and properties for flexible querying  
✅ **Startup coordination** — Await/subscribe for service dependencies  
✅ **Batch operations** — Atomic multi-process registration  
✅ **Singleton pattern** — One-key-per-process constraint  
✅ **Lightweight queries** — Type/tag/property enumeration  
✅ **Liveness validation** — Process health checks  
✅ **Zero dependencies** — Pure Erlang/OTP, no external libs  
✅ **Fully tested** — 74 tests passing  

## Use Cases

- **Service registries** — Find services by name, type, or category
- **Connection pools** — Track workers and distribute load by capacity
- **Startup coordination** — Wait for dependencies before proceeding
- **Health monitoring** — Query process status and distribution
- **Resource tracking** — Manage resources with properties
- **User sessions** — Track multi-service per-user workloads
- **Process discovery** — Efficient lookup by key or metadata

## Quick Start

### Basic Registration

```erlang
%% Register a service
orka:register({global, service, translator}, Pid, #{
    tags => [online, critical],
    properties => #{capacity => 100}
}).

%% Lookup by key
{ok, {_Key, TranslatorPid, _Meta}} = orka:lookup({global, service, translator}).

%% Handle missing service
case orka:lookup({global, service, unknown}) of
    {ok, {_Key, Pid, _Meta}} -> {found, Pid};
    not_found -> {error, service_unavailable}
end.
```

### Query by Tag

```erlang
%% Find all online services
OnlineServices = orka:entries_by_tag(online),
lists:foreach(fun({_Key, Pid, _Meta}) ->
    gen_server:call(Pid, ping)
end, OnlineServices).

%% Count services by tag
OnlineCount = orka:count_by_tag(online).
```

### Query by Property

```erlang
%% Find workers with specific capacity
HighCapacityWorkers = orka:find_by_property(capacity, 100).

%% Load balance across workers
AllWorkers = orka:entries_by_type(worker),
Sorted = lists:sort(fun compare_load/2, AllWorkers),
[{_Key, BestWorker, _Meta}|_] = Sorted,
gen_server:call(BestWorker, {process_item, Item}).
```

### Startup Coordination

```erlang
%% Block until critical service appears (30 second timeout)
case orka:await({global, service, database}, 30000) of
    {ok, {_Key, DbPid, _Meta}} ->
        io:format("Database ready: ~p~n", [DbPid]);
    timeout ->
        io:format("Database startup timeout~n"),
        init:stop()
end.

%% Subscribe to optional service (non-blocking)
orka:subscribe({global, service, cache}),
receive
    {orka_registered, {global, service, cache}, {_K, CachePid, _Meta}} ->
        io:format("Cache became available: ~p~n", [CachePid])
after 0 ->
    io:format("Cache not available, continuing without it~n")
end.
```

### Atomic Batch Operations

```erlang
%% Register multiple services atomically - all succeed or all fail
{ok, Entries} = orka:register_batch([
    {{global, portfolio, user1}, PortfolioPid, #{tags => [user1, portfolio]}},
    {{global, orders, user1}, OrdersPid, #{tags => [user1, orders]}},
    {{global, risk, user1}, RiskPid, #{tags => [user1, risk]}}
]).

%% Get all services for a user via tag
UserServices = orka:entries_by_tag(user1),
io:format("User has ~p services~n", [length(UserServices)]).
```

## Key Patterns

**Supervisor Registers Child**
```erlang
init([]) ->
    {ok, Pid} = my_service:start_link(),
    orka:register({global, service, my_service}, Pid, 
        #{tags => [service, online]}),
    {ok, {specs}}.
```

**Service Self-Registers**  
Service registers itself during `gen_server:init/1` — autonomous and testable in isolation.

**Singleton Services**
```erlang
case orka:register_single({global, service, config_server}, 
    #{tags => [critical]}) of
    {ok, _} -> {ok, started_as_singleton};
    {error, {already_registered_under_key, _}} -> 
        ignore  %% Another instance is active
end.
```

**Per-User Service Groups**  
Register all user services with shared tag for atomic startup and cleanup.

For additional patterns and detailed examples, see [Examples & Use Cases](docs/Examples_&_Use_Cases.md).

## API Overview

**Registration** (5 functions)
- `register/2,3` — Register a process
- `register_with/3` — Atomically start and register
- `register_single/2,3` — Singleton constraint (one process per key)

**Lookup** (3 functions)
- `lookup/1` — Fast key-based lookup (O(1))
- `lookup_alive/1` — Lookup with liveness validation
- `lookup_all/0` — Get all entries in registry

**Unregistration** (2 functions)
- `unregister/1` — Remove entry by key
- `unregister_batch/1` — Atomically remove multiple entries

**Tags** (5 functions)
- `add_tag/2` — Add category to process
- `remove_tag/2` — Remove category
- `entries_by_tag/1` — Get all entries with tag
- `keys_by_tag/1` — Get keys only (lightweight)
- `count_by_tag/1` — Count entries with tag

**Properties** (6 functions)
- `register_property/3` — Register queryable attribute
- `find_by_property/2,3` — Find entries by property value
- `find_keys_by_property/2,3` — Find keys by property (lightweight)
- `count_by_property/2` — Count entries with property value
- `property_stats/2` — Get distribution of property values

**Type Queries** (3 functions)
- `entries_by_type/1` — Get all entries of a key type
- `keys_by_type/1` — Get keys only (lightweight)
- `count_by_type/1` — Count entries by type

**Startup Coordination** (3 functions)
- `await/2` — Block until key registered (with timeout)
- `subscribe/1` — Receive registration notifications
- `unsubscribe/1` — Stop receiving notifications

**Batch Operations** (2 functions)
- `register_batch/1` — Atomically register multiple processes
- (included: `unregister_batch/1` above)

**Utility** (2 functions)
- `entries/0` — Get all registry entries
- `count/0` — Get total entry count

For complete documentation with specs and examples, see [API Documentation](docs/API_Documentation.md).

## Comparison with Alternatives

| Feature | Orka | Gproc | Syn |
|---------|------|-------|-----|
| **Local Registry** | ✅ | ✅ | ✅ |
| **Distributed** | ❌ | ❌ | ✅ |
| **Lock-free Reads** | ✅ Fast (~1-2µs) | ✅ Good | ⚠️ Process calls |
| **Tags** | ✅ | ✅ | ❌ |
| **Properties** | ✅ | ❌ | ❌ |
| **Singleton Pattern** | ✅ | ❌ | ❌ |
| **Batch Operations** | ✅ | ❌ | ❌ |
| **Startup Coordination** | ✅ (await/subscribe) | ❌ | ❌ |
| **Global Counters** | ❌ | ✅ | ❌ |
| **Named Values** | ❌ | ✅ | ❌ |

**When to Use Orka**
- Single-node service discovery with high-read workloads
- Need property-drive routing or singleton constraints
- Prefer simple, focused API over feature richness

**Use Gproc for**
- Global counters, named shared values
- Battle-tested, mature, complex patterns

**Use Syn for**
- Multi-node distributed clustering
- Event notifications on registration changes
- Eventually consistent distributed registry

## Documentation


Orka documentation is organized into four comprehensive guides:

1. **[Examples & Use Cases](docs/Examples_&_Use_Cases_orka.md)** — Real-world patterns, use cases, and working code examples
2. **[API Documentation](docs/API_Documentation_orka.md)** — Complete reference for all 31 functions with specs and examples
3. **[Developer Reference](docs/Developer_Reference_orka.md)** — Design principles, architecture, testing, and extension patterns
4. **[README.md](README.md)** (this file) — Project overview and quick start


## Testing

```bash
make ct        # Run Common Test suite
make eunit     # Run EUnit tests
make clean     # Clean build artifacts
make erl       # Start Erlang shell with orka loaded
```

**Test Coverage**: 74 tests passing, covering all 31 functions, edge cases, and concurrent scenarios.

## Installation

Add to your `rebar.config`:

```erlang
{deps, [
    {orka, {git, "https://github.com/goatrllr/orka.git", {branch, "main"}}}
]}.
```

Then in your application supervisor:

```erlang
{ok, _} = application:ensure_all_started(orka).
```

## License

MIT - See [LICENCE](LICENCE) file for details.

## Contributing

Contributions welcome! Please ensure tests pass (`make ct`) and update documentation for new features.

## Acknowledgments

- Inspired by gproc and syn process registries
- ETS-based architecture for performance
- Erlang/OTP community for excellent patterns

---

**Status**: Production Ready | **Tests**: 74/74 passing | **License**: MIT | **Erlang**: OTP 24+
