# Orka Split-Branch Strategy

## Overview

Orka implements a **split-branch architecture** that separates the stable **Core API** from future **extensions**. This ensures:

- ✅ **API Stability** — Core functions remain unchanged across versions
- ✅ **Backward Compatibility** — No breaking changes to existing code
- ✅ **Extension Flexibility** — New features added as extensions without core modification
- ✅ **Performance Guarantee** — Core never degrades from new features
- ✅ **Clear Architecture** — Core + Extensions pattern prevents tangled code

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                      Orka Core (1.0)                         │
│                                                               │
│  • Registration functions (register, register_with, etc.)    │
│  • Lookup functions (lookup, lookup_alive, lookup_all)       │
│  • Tag metadata (add_tag, remove_tag, entries_by_tag, etc.)  │
│  • Property metadata (register_property, find_by_property)   │
│  • Startup coordination (await, subscribe, unsubscribe)      │
│  • Batch operations (register_batch, unregister_batch)       │
│  • Query by type (entries_by_type, keys_by_type, etc.)       │
│                                                               │
│  ✅ 31 exported functions                                     │
│  ✅ 61/61 tests passing                                       │
│  ✅ Zero external dependencies                               │
│  ✅ Pure Erlang/OTP                                           │
└──────────────────────────────────────────────────────────────┘
         │
         ├─────────────────┬──────────────────┬─────────────────┐
         │                 │                  │                 │
         ▼                 ▼                  ▼                 ▼
    ┌─────────┐    ┌──────────────┐  ┌─────────────┐   ┌───────────┐
    │ Ext: Services   │ Ext: Groups      │ Ext: Distributed │ Ext: Metrics │
    │                 │                  │                 │           │
    │ • Discovery     │ • Named groups   │ • Multi-node    │ • Telemetry │
    │ • Policies      │ • Collections    │ • Sync           │ • Dashboards│
    │ • Routing       │ • Batch ops      │ • Replication    │ • Alerts    │
    └─────────┘    └──────────────┘  └─────────────┘   └───────────┘
```

## Core Guarantees

### 1. **No Breaking Changes**
- Exported functions remain stable
- Function signatures unchanged
- Behavior maintained across versions
- Return types consistent

### 2. **No Policy Enforcement**
Core provides mechanisms, extensions define policies:

```erlang
%% Core: Mechanism only
orka:entries_by_tag(online).          %% Lists entries with tag

%% Extension: Add policy
my_services:find_healthy_online() ->  %% Filter by health, retry, etc.
    Services = orka:entries_by_tag(online),
    lists:filter(fun is_healthy/1, Services).
```

### 3. **Lock-Free Reads Always**
All lookups use ETS public tables, never blocking.

### 4. **Automatic Cleanup Always**
Process monitors ensure dead entries are removed.

## New Functions in Core

The following functions were added to Core as they're universally useful:

### Lightweight Query Functions
- **`keys_by_type/1`** — Get keys without full entries (O(n) with lower overhead)
- **`keys_by_tag/1`** — Get keys by tag (useful for filtering before detailed ops)
- **`find_keys_by_property/2,3`** — Get keys by property (property-based filtering)

**Use**: When you only need keys, not full entries. Reduces memory and processing.

### Liveness Functions
- **`lookup_alive/1`** — Lookup with automatic dead entry cleanup

**Use**: Validate process liveness before use. Async cleanup of dead entries.

## Extension Pattern

Extensions should:

1. **Use Core functions only** — No direct gen_server calls
2. **Add policy, not mechanism** — Build filters, validation, business logic
3. **Preserve core assumptions** — Maintain key format, metadata structure
4. **Document compatibility** — State which core functions used

**Example: Service Discovery Extension**

```erlang
-module(orka_services).

%% Uses Core API, adds policy
discover_service(ServiceType, Attributes) ->
    %% Core: Get entries by type
    Services = orka:entries_by_type(ServiceType),
    
    %% Extension: Filter by attributes
    lists:filter(fun(Entry) ->
        matches_attributes(Entry, Attributes)
    end, Services).

matches_attributes({_Key, _Pid, Meta}, Attrs) ->
    Properties = maps:get(properties, Meta, #{}),
    lists:all(fun({K, V}) ->
        maps:get(K, Properties) =:= V
    end, Attrs).
```

## Documentation Strategy

### Readme-Core.md
- **Purpose**: Reference for Core API (stable, unchanging)
- **Content**: All 31 functions with examples
- **Audience**: Developers building on Core
- **Updates**: New core functions only (rare), never removes

### README.md
- **Purpose**: Project overview and quick start
- **Content**: Links to Core API, highlights extensions
- **Audience**: New users, project overview
- **Updates**: Can reference extensions and new features

### API.md
- **Purpose**: Complete API documentation
- **Content**: All functions with detailed examples
- **Audience**: Detailed API reference
- **Updates**: When Core functions documented in API.md

## Test Coverage

### Core Tests (61/61 passing)
- `orka_SUITE.erl`: Registration, lookup, tags, properties, coordination
- Each test suite covers one aspect of Core functionality

### Why No Tests Are Run During Development
Extensions may add their own test suites. Core tests are stable and should pass unchanged unless Core is modified.

## Building Extensions

### Step 1: Identify Policy
What decision/filtering does your extension add?

```erlang
%% Example: Service health policy
is_healthy(Pid, ThresholdFailures) ->
    Failures = orka:find_by_property(failures, Pid),
    Failures =< ThresholdFailures.
```

### Step 2: Use Core Queries
Select which Core functions to build on:

```erlang
orka:entries_by_tag(online)            %% Mechanism: Get online services
orka:find_by_property(region, "us-west") %% Mechanism: Property filtering
```

### Step 3: Add Your Logic
Implement the extension policy:

```erlang
healthy_services(Type, HealthThreshold) ->
    Candidates = orka:entries_by_type(Type),
    lists:filter(fun({_K, _P, Meta}) ->
        get_health_score(Meta) > HealthThreshold
    end, Candidates).
```

## FAQ

**Q: Can I modify Core functions?**  
No. Core is stable. Build extensions that wrap Core functions.

**Q: What if Core is missing a function I need?**  
Request it for Core (if universally useful) or build it as an extension wrapper.

**Q: How do I version extensions?**  
Independently. Extensions are separate modules that depend on Core 1.0.

**Q: Can multiple extensions coexist?**  
Yes! They all use Core without conflicts since they don't modify Core.

**Q: What if two extensions have conflicting policies?**  
Compose them explicitly in your code: `Extension1.filter(Extension2.filter(Results))`.

## Core Principles

1. **Minimalism** — Only universally useful functions in Core
2. **Stability** — No breaking changes ever
3. **Composability** — Extensions build cleanly on Core
4. **Performance** — Core overhead never increases
5. **Clarity** — Core is mechanism, extensions are policy

## Migration Path

If you have code that was using older versions of Orka:

- **Core 1.0**: All functions are compatible with previous versions
- **New functions**: Added for convenience (`lookup_alive`, `keys_by_*`, `find_keys_by_property`)
- **Opt-in**: Use new functions when beneficial, no requirement to migrate

---

**Summary**: Orka Core is the stable, minimal, fast foundation. Extensions build on Core without modification, ensuring compatibility and enabling clean composition of features.
