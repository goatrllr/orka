# Orka Developer Reference

> **Note**: This documentation covers **Orka Core API** on the `main` branch. Orka uses a **split-branch strategy**: Core remains on `main` (stable, no breaking changes), while extensions are developed on feature branches. This document is for developers building on Core or creating extensions. Ensure you're on the correct branch for your use case. See [../README.md](../README.md) for branch overview.

Comprehensive guide to Orka's design, architecture, and extension patterns. For developers building on Orka or creating extensions.

---

## Rationale

### The Problem

Erlang applications often need to find processes by name or metadata:
- Service discovery — "Where is the authentication service?"
- Connection pools — "Find an available worker"
- Message routing — "Which processes are interested in this event?"
- Health monitoring — "How many services are online?"

Traditional solutions like **gproc** provide this but with:
- Complex API with many features (counters, named values, etc.)
- Higher overhead for simple use cases
- Not optimized for the most common query pattern (tag/property lookups)

### The Solution: Orka

Orka fills the gap with:
- **Focused design** — Process registration, lookup, metadata, coordination
- **High performance** — Lock-free reads via ETS, ~1-2µs lookups
- **Rich metadata** — Tags (boolean markers) and properties (arbitrary values)
- **Atomic operations** — Batch registration, singleton constraints
- **Zero dependencies** — Pure Erlang/OTP, no external libraries
- **Extensible foundation** — Core provides mechanisms, extensions add policies

### When to Use Orka

✅ **Single-node service discovery** — Best for local registries  
✅ **High-read workloads** — Lock-free lookups excel with 10K+ lookups/sec  
✅ **Simple metadata queries** — Tags and properties sufficient  
✅ **Extension base** — Custom registries built on Core  

❌ **Multi-node deployments** — Use extension like orka_syn for clustering  
❌ **Global counters** — Use gproc or custom solution  
❌ **Complex constraints** — May need custom policies in extension  

---

## Design Principles

### 1. **API Stability**

Core functions maintain backward compatibility across versions:
- Never remove exported functions
- Never change function signatures
- Only add new functions or optimization
- Extensions depend on this stability

**Implication**: Code written for Orka 1.0 works unchanged in Orka 1.x

### 2. **No Policy Enforcement**

Core provides mechanisms, never mandates usage policies:

```erlang
%% Core: Mechanism - just stores and returns metadata
orka:entries_by_tag(online).  % Get entries with tag

%% Extension: Policy - adds business logic
my_health_monitor:healthy_services() ->
    OnlineServices = orka:entries_by_tag(online),
    lists:filter(fun is_healthy/1, OnlineServices).
```

**Implication**: Orka is composable with other policies without conflict

### 3. **Lock-Free Reads**

All lookups use ETS public tables without locks:
- `lookup/1` — Direct ETS read, O(1)
- `entries_by_tag/1` — ETS match_spec, O(n) with locks only on writes
- `find_by_property/2` — ETS traversal, lock-free

**Implication**: Safe for high-contention read-heavy workloads

### 4. **Automatic Cleanup**

Process monitors detect crashes and automatically remove entries:
- Dead processes are removed from registry
- No stale entries on unexpected termination
- No manual cleanup code needed

**Implication**: Simple mental model — registry stays consistent

### 5. **Minimal Scope**

Core includes only universally useful features:
- Registration & lookup
- Tags for boolean metadata
- Properties for arbitrary values
- Startup coordination
- Batch operations
- Singleton constraint

**Implication**: Small API surface (31 functions), fast to learn

### 6. **Composability**

Functions compose naturally without state tangling:

```erlang
%% Get online services and filter/sort (Erlang style with intermediate variables)
Entries = orka:entries_by_tag(online),
Workers = lists:filter(fun has_capacity/1, Entries),
Sorted = lists:sort(fun compare_load/2, Workers),
OnlineServiceWorkers = Sorted.

%% Alternative: Nested calls
OnlineServiceWorkers = lists:sort(
    fun compare_load/2,
    lists:filter(fun has_capacity/1, orka:entries_by_tag(online))
).

%% Helper functions for filtering and sorting
has_capacity({_K, _P, Meta}) ->
    Capacity = maps:get(capacity, maps:get(properties, Meta, #{}), 0),
    Capacity > 50.

compare_load({_K1, _P1, M1}, {_K2, _P2, M2}) ->
    Load1 = maps:get(current_load, maps:get(properties, M1, #{}), 0),
    Load2 = maps:get(current_load, maps:get(properties, M2, #{}), 0),
    Load1 =< Load2.
```

**Key principle**: Erlang's strength is in pattern matching and functional composition through function application, not operator-based piping. Use intermediate variables for clarity (preferred) or nested calls for conciseness.

---

## Architecture

### Storage Model

Orka uses three ETS tables:

```erlang
%% 1. entries: {Key} -> {Key, Pid, Metadata}
%% Public table, lock-free reads via ETS match_spec
%%
%% 2. tags: {Tag} -> [{Key, Pid, Metadata}]  
%% Index for fast tag-based queries
%%
%% 3. properties: {PropertyName, PropertyValue} -> [{Key, Pid, Metadata}]
%% Index for fast property-based queries
```

### Write Path

1. **Call gen_server** with registration request
2. **Acquire single writer lock** (gen_server serializes writes)
3. **Add monitor** on Pid (for automatic cleanup)
4. **Write to ETS** — entries table
5. **Update indexes** — tags and properties tables
6. **Return Entry** to caller

### Read Path

1. **Direct ETS access** — no locking
2. For `lookup/1`: Single key lookup, O(1)
3. For tag/property queries: Match_spec on index, O(n)

### Cleanup Path

1. **Monitor fires** when Pid dies
2. **gen_server receives DOWN message**
3. **Remove entry** from ETS and indexes
4. **Clean tags/properties** for that entry

```
Pid spawned
    ↓
register(Key, Pid, ...)   ← gen_server adds monitor
    ↓
[Live - ETS tables]
    ↓
Pid crashes
    ↓
Process DOWN signal
    ↓
gen_server removes from ETS
```

---

## Core Guarantees

### No Breaking Changes

Exported API remains stable:
- ✅ Can add new functions
- ✅ Can optimize implementation
- ✅ Cannot remove functions
- ✅ Cannot change signatures
- ✅ Cannot change return types

### Lazy Cleanup on Reads

When reading a dead entry:
- `lookup/1` returns `not_found` (entry may still be in ETS)
- `lookup_alive/1` validates liveness and async cleans up
- Dead entries gradually cleaned as they're accessed

### Property Values by Exact Match

Properties match by Erlang term equality:
```erlang
%% These don't match (different term types):
find_by_property(region, {lat, 40.7128})  %% Tuple
find_by_property(region, "[40.7128]")      %% String

%% These match:
register_property(K, P, #{property => region, value => {lat, 40.7128}})
find_by_property(region, {lat, 40.7128})  %% OK
```

---

## Extension Pattern

Extensions should follow this pattern:

```erlang
%% Extension: orka_health

-module(orka_health).
-export([healthy_entries/1, health_status/0]).

%% Policy: "healthy" = process explicitly marked healthy + still alive
healthy_entries(Tag) ->
    Entries = orka:entries_by_tag(Tag),
    lists:filter(fun is_healthy/1, Entries).

is_healthy({_Key, Pid, Meta}) ->
    HasHealthyTag = lists:member(healthy, maps:get(tags, Meta, [])),
    IsAlive = is_process_alive(Pid),
    HasHealthyTag andalso IsAlive.

%% Query: Aggregate health status
health_status() ->
    All = orka:count(),
    Healthy = length(orka:entries_by_tag(healthy)),
    #{total => All, healthy => Healthy, ratio => Healthy / All}.
```

**Guidelines**:
1. Use Core functions, don't bypass ETS
2. Add policies (business logic), not mechanisms
3. Don't modify Core's data structures
4. Keep functions pure (no side effects except registration)
5. Document dependencies clearly

---

## Project Structure

```
orka/
├── src/
│   └── orka.erl              # Core implementation (31 exported functions)
│
├── test/
│   └── orka_SUITE.erl        # 74 passing tests covering all functions
│
├── docs/
│   ├── API_Documentation.md  # Complete API reference [YOU ARE HERE]
│   ├── Developer_Reference.md # Design and architecture [YOU ARE HERE]
│   ├── Examples_&_Use_Cases.md # Patterns and code examples
│   ├── usage_patterns.md      # 8 fundamental patterns
│   ├── singleton_examples.md  # 7 singleton use cases
│   ├── property_examples.md   # 6 property-based queries
│   ├── await_examples.md      # 7 startup coordination examples
│   ├── comparison.md          # Comparison with gproc/syn
│   └── extensions/            # Extension ideas (designs, not implemented)
│       ├── orka_syn.md        # Hybrid orka+syn architecture
│       ├── groups_examples.md # Process group patterns
│       ├── message_systems.md # Kafka/RabbitMQ clone patterns
│       ├── partial_match_options.md # Query patterns
│       └── README.md          # Extension ideas overview
│
├── README.md                 # Project overview & quick start
├── Makefile                  # Build and test targets
├── rebar.config              # Dependencies (none)
└── ebin/                     # Compiled modules
```

---

## Roadmap & Future Directions

### Completed Core Features

✅ **Baseline Registry** — Registration, lookup, tags, properties  
✅ **Batch Operations** — Atomic multi-process registration  
✅ **Singleton Pattern** — One-key-per-process constraint  
✅ **Startup Coordination** — await/subscribe for dependencies  
✅ **Lightweight Queries** — keys_by_tag/keys_by_type for memory efficiency  
✅ **Property Statistics** — Distribution analysis of property values  
✅ **Liveness Validation** — lookup_alive with async cleanup  

### Potential Extensions (Design Phase)

These are **not** in Core, but documented as extension patterns:

📋 **orka_syn** — Multi-node hybrid architecture  
📋 **orka_groups** — Process group management  
📋 **orka_router** — Message routing with caching  
📋 **orka_pubsub** — Pub/sub optimization over Core  
📋 **orka_metrics** — Registry statistics and monitoring  

See [docs/extensions/](docs/extensions/) for detailed designs.

---

## Comparison with Alternatives

### Orka vs. Gproc

| Feature | Orka | Gproc |
|---------|------|-------|
| Process registration | ✅ | ✅ |
| Properties (arbitrary) | ✅ | ✅ |
| Tag-based queries | ✅ | ✗ |
| Properties without uniqueness | ✅ | ✗ |
| Property statistics | ✅ | ✗ |
| Singleton pattern | ✅ | ✗ |
| Global counters | ✗ | ✅ |
| Named values | ✗ | ✅ |
| ETS-based | ✅ | ✅ |
| Lock-free reads | ✅ | ✅ |
| API surface | 31 functions | 100+ functions |

**When to use Orka**: Service discovery, tag/property queries, singleton services  
**When to use Gproc**: Global counters, named values, when you need all features

### Orka vs. Syn

| Feature | Orka | Syn |
|---------|------|-----|
| Local-node registry | ✅ | ✅ |
| Multi-node clustering | ✗ | ✅ |
| Group management | ✗ | ✅ |
| ETS-based | ✅ | ✗ |
| Lock-free reads | ✅ | ✗ |
| Process monitoring | ✅ | ✅ |
| API simplicity | High | Medium |
| Lookup performance | ~1-2µs | ~10-50µs |

**When to use Orka**: Single-node, high-read workloads, simple metadata  
**When to use Syn**: Multi-node, distributed groups, eventual consistency OK

---

## Testing Strategy

### Test Coverage

All 31 exported functions tested with:
- ✅ 74 Common Test cases passing
- ✅ Unit tests for basic operations
- ✅ Integration tests for complex scenarios
- ✅ Edge cases (empty results, timeouts, dead processes)
- ✅ Concurrency tests (simultaneous registrations)

### Test Structure

```erlang
%% orka_SUITE.erl
-module(orka_SUITE).

%% Test groups
-export([all/0, groups/0, init_per_suite/1, end_per_suite/1]).

%% Registration tests
-export([test_register_self/1, test_register_explicit/1, test_register_batch/1]).

%% Lookup tests
-export([test_lookup_found/1, test_lookup_not_found/1, test_lookup_alive/1]).

%% Tag tests
-export([test_add_tag/1, test_entries_by_tag/1, test_count_by_tag/1]).

%% Property tests
-export([test_register_property/1, test_find_by_property/1]).

%% Coordination tests
-export([test_await_timeout/1, test_subscribe_registration/1]).

%% Cleanup tests
-export([test_automatic_cleanup_on_crash/1]).
```

### Running Tests

```bash
# All tests
make ct

# Specific test group
make ct SUITES=orka_SUITE

# Single test
make ct SUITES=orka_SUITE TESTS=test_register_self
```

---

## Key Implementation Notes

### Process Monitoring

Orka uses `erlang:monitor/2` for each registered process:
- Monitor fires when Pid dies or is killed
- gen_server handler removes entry from ETS
- No stale entries accumulate

### Tag Deduplication

Tags are deduplicated automatically:
```erlang
register({key1}, #{tags => [online, service, online]})
%% Stored as: #{tags => [online, service]}  (duplicates removed)
```

### Property Value Equality

Property values match by exact Erlang term equality:
```erlang
%% Number 100 only matches 100
register_property(k, p, #{property => capacity, value => 100})
find_by_property(capacity, 100)     %% OK
find_by_property(capacity, 100.0)   %% Not found (different type)
```

### Await/Subscribe Race Handling

When using `await/2`:
1. Process subscribes to key
2. Timer set for timeout
3. Registration message sent when key registered
4. Timeout message sent on expiry
5. Receiving process gets first message (could be either)

For critical dependencies, prefer synchronous patterns or handle both messages.

---

## Performance Characteristics

### Latency

| Operation | Latency | Notes |
|-----------|---------|-------|
| `lookup/1` | ~1-2 µs | ETS single-key lookup |
| `register/2` | ~10-20 µs | gen_server call + monitor |
| `entries_by_tag/1` | ~1-5 µs | O(n) ETS match_spec |
| `find_by_property/2` | ~1-5 µs | O(n) ETS traversal |
| `add_tag/2` | ~10-20 µs | Write + index update |

### Throughput

**Lookups**: 500K-1M lookups/sec (lock-free)  
**Registrations**: 50K-100K registrations/sec (single writer)  
**Tag queries**: 100K-500K queries/sec (tag-dependent)  

### Scalability

Suitable for registries with:
- Up to ~100K entries
- Lookups every millisecond (1000s combined)
- Small tag/property sets (< 100 values)

For larger scales, consider:
- Distributed registry (syn, orka_syn extension)
- Sharded registry (multiple instances)
- Caching layer (orka_router extension)

---

## See Also

- [../README.md](../README.md) — Project overview and quick start
- [API_Documentation.md](API_Documentation.md) — Complete function reference
- [Examples_&_Use_Cases.md](Examples_&_Use_Cases.md) — Practical patterns and code
