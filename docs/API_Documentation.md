# Orka API Documentation

> **Note**: This documentation covers the **Orka Core API** on the `main` branch. Orka uses a split-branch strategy where the stable Core remains on `main`, and extensions are developed on separate branches. Ensure you're on the correct branch for your use case. See [../README.md](../README.md) for branch information.

Complete reference for Orka's process registry functions, types, and modules.

---

## Description

**Orka** is a high-performance, ETS-based process registry for Erlang/OTP. It provides:
- **Lock-free lookups** via public ETS tables
- **Automatic lifecycle management** with process monitors
- **Rich metadata** through tags and properties
- **Startup coordination** with await/subscribe patterns
- **Batch operations** for atomic multi-process registration
- **Zero external dependencies** — pure Erlang/OTP

The registry stores entries in ETS with two access patterns:
1. **Direct lookup** — by exact key (O(1))
2. **Tag/Property queries** — filter by metadata (O(n) with small n)

Process crashes are detected via monitors and entries are automatically cleaned up.

---

## Modules

**orka** — Main module with all 31 exported functions:
- Registration & lifecycle (register, unregister, monitor)
- Lookup & validation (lookup, lookup_alive, lookup_all)
- Tag system (add_tag, remove_tag, entries_by_tag, etc.)
- Property system (register_property, find_by_property, etc.)
- Startup coordination (await, subscribe, unsubscribe)
- Batch operations (register_batch, unregister_batch)
- Query by type (entries_by_type, keys_by_type, count_by_type)
- Utility (count/0, entries/0)

---

## Function Reference

### Summary Table

| Function | Purpose | Category |
|----------|---------|----------|
| `register/2` | Self-register calling process | Registration |
| `register/3` | Register explicit Pid | Registration |
| `register_single/2` | Self-register with singleton constraint | Registration |
| `register_single/3` | Register explicit Pid with singleton constraint | Registration |
| `register_with/3` | Atomically start and register process | Registration |
| `register_batch/1` | Atomically register multiple processes | Batch |
| `unregister/1` | Remove registration by key | Registration |
| `unregister_batch/1` | Remove multiple registrations | Batch |
| `lookup/1` | Lookup by key | Lookup |
| `lookup_alive/1` | Lookup with liveness validation | Lookup |
| `lookup_all/1` | Lookup all entries (may include dead) | Lookup |
| `add_tag/2` | Add tag to existing registration | Tags |
| `remove_tag/2` | Remove tag from registration | Tags |
| `entries_by_tag/1` | Get all entries with tag | Tags |
| `keys_by_tag/1` | Get keys with tag (lightweight) | Tags |
| `count_by_tag/1` | Count entries with tag | Tags |
| `register_property/3` | Register property value for Pid | Properties |
| `find_by_property/2` | Find entries by property value | Properties |
| `find_by_property/3` | Find entries by type + property value | Properties |
| `find_keys_by_property/2` | Find keys by property (lightweight) | Properties |
| `find_keys_by_property/3` | Find keys by type + property (lightweight) | Properties |
| `count_by_property/2` | Count entries with property value | Properties |
| `property_stats/2` | Get distribution of property values | Properties |
| `entries_by_type/1` | Get all entries with type | Type |
| `keys_by_type/1` | Get keys by type (lightweight) | Type |
| `count_by_type/1` | Count entries by type | Type |
| `await/2` | Block until key registered with timeout | Coordination |
| `subscribe/1` | Receive registration notifications | Coordination |
| `unsubscribe/1` | Stop receiving notifications | Coordination |
| `entries/0` | Get all registry entries | Query |
| `count/0` | Get total entry count | Query |

### Types

```erlang
%% Key format - recommending {Scope, Type, Name}
-type key() :: any().

%% Entry tuple
-type entry() :: {Key :: key(), Pid :: pid(), Metadata :: metadata()}.

%% Metadata with tags and properties
-type metadata() :: #{
    tags => [atom()],           % Categories for querying
    properties => #{atom() => any()}  % Arbitrary key-value pairs
}.

%% Registration result
-type registration_result() :: 
    {ok, entry()} |
    {error, any()}.

%% Lookup result
-type lookup_result() ::
    {ok, entry()} |
    not_found.
```

---

## Registration Functions

### `register(Key, Metadata) → {ok, Entry} | error`

Self-register the calling process with metadata.

**Spec:**
```erlang
-spec register(key(), metadata()) -> {ok, entry()} | error.
```

**Parameters:**
- `Key` — Registration key (any term, recommend `{Scope, Type, Name}`)
- `Metadata` — Map with `tags` (list of atoms) and optional `properties`

**Returns:**
- `{ok, {Key, Pid, Metadata}}` — Successfully registered (Pid = self())
- If key already registered with live process: returns existing entry
- If key registered but process dead: cleans up and re-registers

**Example:**
```erlang
{ok, {Key, MyPid, Meta}} = orka:register(
    {global, user, "alice@example.com"},
    #{tags => [user, online], properties => #{region => "us-west"}}
).
```

---

### `register(Key, Pid, Metadata) → {ok, Entry} | error`

Register a specific process (useful in supervisors).

**Spec:**
```erlang
-spec register(key(), pid(), metadata()) -> {ok, entry()} | error.
```

**Parameters:**
- `Key` — Registration key
- `Pid` — Process ID to register
- `Metadata` — Metadata map

**Returns:**
- `{ok, {Key, Pid, Metadata}}` — Successfully registered

**Example:**
```erlang
{ok, Entry} = orka:register(
    {global, service, translator},
    WorkerPid,
    #{tags => [service, translator, online]}
).
```

---

### `register_single(Key, Metadata) → {ok, Entry} | {error, Reason}`

Self-register with singleton constraint — process cannot have multiple keys.

**Spec:**
```erlang
-spec register_single(key(), metadata()) -> 
    {ok, entry()} | 
    {error, {already_registered_under_key, key()}} |
    {error, {already_registered, [key()]}}.
```

**Parameters:**
- `Key` — Singleton registration key
- `Metadata` — Metadata map

**Returns:**
- `{ok, {Key, Pid, Metadata}}` — Successfully registered as singleton
- `{error, {already_registered_under_key, ExistingKey}}` — Process already registered under different key
- `{error, {already_registered, Keys}}` — Process has non-singleton registrations

**Behavior:**
- Process can only be registered under ONE key when using `register_single`
- Attempting to register same process under different key fails
- Re-registering under same key updates metadata
- Constraint released on process crash or unregister

**Example:**
```erlang
%% Only one translator instance allowed
{ok, Entry} = orka:register_single(
    {local, service, translator},
    #{tags => [service, critical]}
).

%% This will fail - same process can't have two singleton keys
{error, {already_registered_under_key, {local, service, translator}}} =
    orka:register_single(
        {local, service, translator_backup},
        #{tags => [service]}
    ).
```

---

### `register_single(Key, Pid, Metadata) → {ok, Entry} | {error, Reason}`

Register explicit Pid with singleton constraint.

**Spec:**
```erlang
-spec register_single(key(), pid(), metadata()) ->
    {ok, entry()} |
    {error, {already_registered_under_key, key()}} |
    {error, {already_registered, [key()]}}.
```

Same as `register_single/2` but with explicit Pid instead of self().

---

### `register_with(Key, Metadata, {M, F, A}) → {ok, Pid} | {error, Reason}`

Atomically start a process via MFA and register it (no race conditions).

**Spec:**
```erlang
-spec register_with(key(), metadata(), mfa()) -> {ok, pid()} | {error, any()}.
```

**Parameters:**
- `Key` — Registration key
- `Metadata` — Metadata map
- `{M, F, A}` — Module, function, arguments

**Returns:**
- `{ok, Pid}` — Process started and registered
- `{error, Reason}` — Start failed or registration failed

**Behavior:**
- Calls `apply(M, F, A)` to start process
- Atomically registers result
- If key already registered with live process: returns that Pid
- If MFA returns `{ok, Pid}`: registers that Pid
- If MFA fails: error propagated

**Example:**
```erlang
{ok, TranslatorPid} = orka:register_with(
    {global, service, translator},
    #{tags => [service, online]},
    {translator_server, start_link, []}
).
```

---

### `register_batch(Entries) → {ok, [Entry]} | {error, Reason}`

Atomically register multiple processes in one operation.

**Spec:**
```erlang
-spec register_batch([{key(), pid(), metadata()}]) -> 
    {ok, [entry()]} | {error, any()}.
```

**Parameters:**
- `Entries` — List of `{Key, Pid, Metadata}` tuples

**Returns:**
- `{ok, [Entries]}` — All successfully registered (all-or-nothing)
- `{error, Reason}` — Entire batch rejected if any fails

**Behavior:**
- All registrations happen atomically
- No partial registrations on failure
- Useful for per-user service groups

**Example:**
```erlang
{ok, Entries} = orka:register_batch([
    {{global, portfolio, user1}, PortfolioPid, #{tags => [portfolio, user1]}},
    {{global, orders, user1}, OrdersPid, #{tags => [orders, user1]}},
    {{global, risk, user1}, RiskPid, #{tags => [risk, user1]}}
]).
```

---

## Lookup Functions

### `lookup(Key) → {ok, Entry} | not_found`

Lookup an entry by exact key (lock-free ETS read).

**Spec:**
```erlang
-spec lookup(key()) -> {ok, entry()} | not_found.
```

**Parameters:**
- `Key` — Registration key

**Returns:**
- `{ok, {Key, Pid, Metadata}}` — Entry found
- `not_found` — Key not registered (or process dead)

**Performance:** O(1) — lock-free public ETS table read

**Example:**
```erlang
case orka:lookup({global, service, translator}) of
    {ok, {_Key, Pid, Meta}} -> 
        io:format("Found translator: ~p~n", [Pid]);
    not_found ->
        io:format("Translator not registered~n")
end.
```

---

### `lookup_alive(Key) → {ok, Entry} | not_found`

Lookup with automatic process liveness validation.

**Spec:**
```erlang
-spec lookup_alive(key()) -> {ok, entry()} | not_found.
```

**Parameters:**
- `Key` — Registration key

**Returns:**
- `{ok, Entry}` — Entry found and process is alive
- `not_found` — Key not registered or process dead

**Behavior:**
- Performs lookup then validates process is still alive
- Cleans up dead entries asynchronously
- Slightly slower than `lookup/1` (adds process liveness check)

**Example:**
```erlang
case orka:lookup_alive({global, service, db}) of
    {ok, {_K, DbPid, _M}} -> 
        ok = db:query(DbPid, Sql);
    not_found ->
        io:format("Database not available~n")
end.
```

---

### `lookup_all(Key) → {ok, Entry} | not_found`

Lookup without automatic cleanup (may return dead processes).

**Spec:**
```erlang
-spec lookup_all(key()) -> {ok, entry()} | not_found.
```

**Returns:**
- Entry including dead processes (for debugging/auditing)

**Note:** Use `lookup/1` for normal operations. `lookup_all` is for introspection.

---

## Unregistration Functions

### `unregister(Key) → ok | not_found`

Remove a registration by key.

**Spec:**
```erlang
-spec unregister(key()) -> ok | not_found.
```

**Parameters:**
- `Key` — Registration key to remove

**Returns:**
- `ok` — Successfully unregistered
- `not_found` — Key was not registered

**Example:**
```erlang
ok = orka:unregister({global, user, "alice@example.com"}).
```

---

### `unregister_batch(Keys) → ok | {error, [key()]}`

Atomically unregister multiple keys.

**Spec:**
```erlang
-spec unregister_batch([key()]) -> ok | {error, [key()]}.
```

**Parameters:**
- `Keys` — List of keys to remove

**Returns:**
- `ok` — All successfully unregistered
- `{error, NotFound}` — Some keys not found (partial success)

**Example:**
```erlang
ok = orka:unregister_batch([
    {global, portfolio, user1},
    {global, orders, user1},
    {global, risk, user1}
]).
```

---

## Tag Functions

Tags are arbitrary atoms associated with registrations for grouping and querying.

### `add_tag(Key, Tag) → {ok, Entry} | not_found`

Add tag to an existing registration.

**Spec:**
```erlang
-spec add_tag(key(), atom()) -> {ok, entry()} | not_found.
```

**Example:**
```erlang
{ok, {_K, _P, Meta}} = orka:add_tag({global, user, alice}, online).
```

---

### `remove_tag(Key, Tag) → {ok, Entry} | not_found`

Remove tag from registration.

**Spec:**
```erlang
-spec remove_tag(key(), atom()) -> {ok, entry()} | not_found.
```

---

### `entries_by_tag(Tag) → [Entry]`

Get all entries with a specific tag.

**Spec:**
```erlang
-spec entries_by_tag(atom()) -> [entry()].
```

**Returns:** List of all entries (Pids, metadata) with the tag

**Performance:** O(n) where n = entries with tag (usually small)

**Example:**
```erlang
OnlineUsers = orka:entries_by_tag(online),
OnlineCount = length(OnlineUsers).
```

---

### `keys_by_tag(Tag) → [Key]`

Get keys with a tag (lightweight alternative to `entries_by_tag`).

**Spec:**
```erlang
-spec keys_by_tag(atom()) -> [key()].
```

**Returns:** List of keys only (no Pids or metadata)

**Use when:** You only need keys, not full entries (reduces memory)

---

### `count_by_tag(Tag) → non_neg_integer()`

Count entries with a tag.

**Spec:**
```erlang
-spec count_by_tag(atom()) -> non_neg_integer().
```

**Example:**
```erlang
OnlineCount = orka:count_by_tag(online).
```

---

## Property Functions

Properties are arbitrary key-value pairs for rich metadata queries.

### `register_property(Key, Pid, #{property => Name, value => Value}) → ok`

Register a property value for a process.

**Spec:**
```erlang
-spec register_property(key(), pid(), #{property => atom(), value => any()}) -> ok.
```

**Parameters:**
- `Key` — Registration key
- `Pid` — Process ID
- `Metadata` — Map with `property` and `value`

**Example:**
```erlang
ok = orka:register_property(
    {global, service, translator_1},
    TranslatorPid,
    #{property => capacity, value => 100}
).
```

---

### `find_by_property(PropertyName, PropertyValue) → [Entry]`

Find all entries with a specific property value.

**Spec:**
```erlang
-spec find_by_property(atom(), any()) -> [entry()].
```

**Example:**
```erlang
HighCapacity = orka:find_by_property(capacity, 100).
```

---

### `find_by_property(Type, PropertyName, PropertyValue) → [Entry]`

Find entries filtered by type and property value.

**Spec:**
```erlang
-spec find_by_property(any(), atom(), any()) -> [entry()].
```

**Parameters:**
- `Type` — Filter by type (second element of key tuple `{Scope, Type, Name}`)
- `PropertyName` — Property to match
- `PropertyValue` — Value to match

**Example:**
```erlang
UsWestServices = orka:find_by_property(service, region, "us-west").
```

---

### `find_keys_by_property/2,3`

Lightweight versions returning only keys.

**Specs:**
```erlang
-spec find_keys_by_property(atom(), any()) -> [key()].
-spec find_keys_by_property(any(), atom(), any()) -> [key()].
```

---

### `count_by_property(PropertyName, PropertyValue) → non_neg_integer()`

Count entries with a property value.

**Spec:**
```erlang
-spec count_by_property(atom(), any()) -> non_neg_integer().
```

---

### `property_stats(Type, PropertyName) → #{PropertyValue => Count}`

Get distribution of values for a property within a type.

**Spec:**
```erlang
-spec property_stats(any(), atom()) -> #{any() => non_neg_integer()}.
```

**Returns:** Map of `{PropertyValue => Count}`

**Example:**
```erlang
RegionStats = orka:property_stats(service, region).
%% Result: #{<<"us-west">> => 5, <<"eu">> => 3, <<"asia">> => 2}
```

---

## Type Functions

Type is the second element of the recommended key tuple `{Scope, Type, Name}`.

### `entries_by_type(Type) → [Entry]`

Get all entries with a specific type.

**Spec:**
```erlang
-spec entries_by_type(any()) -> [entry()].
```

**Example:**
```erlang
AllServices = orka:entries_by_type(service).
```

---

### `keys_by_type(Type) → [Key]`

Get keys by type (lightweight).

**Spec:**
```erlang
-spec keys_by_type(any()) -> [key()].
```

---

### `count_by_type(Type) → non_neg_integer()`

Count entries by type.

**Spec:**
```erlang
-spec count_by_type(any()) -> non_neg_integer().
```

---

## Startup Coordination Functions

### `await(Key, TimeoutMs) → {ok, Entry} | timeout`

Block until a key is registered with timeout.

**Spec:**
```erlang
-spec await(key(), non_neg_integer()) -> {ok, entry()} | timeout.
```

**Parameters:**
- `Key` — Key to wait for
- `TimeoutMs` — Timeout in milliseconds

**Returns:**
- `{ok, Entry}` — Key registered before timeout
- `timeout` — Key not registered within timeout

**Behavior:**
- Uses internal `subscribe/1` mechanism
- Blocks calling process (don't use in message-handling code)
- Cleans up subscription after returning

**Example:**
```erlang
%% Service startup waits for database
case orka:await({global, service, database}, 30000) of
    {ok, {_K, DbPid, _M}} ->
        io:format("Database available: ~p~n", [DbPid]);
    timeout ->
        io:format("Database startup timeout~n"),
        init:stop()
end.
```

---

### `subscribe(Key) → {ok, SubscriptionRef}`

Register interest in a key without blocking (receive notifications).

**Spec:**
```erlang
-spec subscribe(key()) -> {ok, reference()}.
```

**Parameters:**
- `Key` — Key to monitor

**Returns:**
- `{ok, Ref}` — Subscription reference

**Behavior:**
- Returns immediately
- Receiving process will get `{orka_registered, Key, Entry}` when key is registered
- Also gets message if key already registered when subscribing
- Cannot unsubscribe from key registered before subscription

**Message Received:**
```erlang
receive
    {orka_registered, Key, {_K, Pid, Meta}} ->
        io:format("Service available: ~p~n", [Pid])
end.
```

**Example:**
```erlang
{ok, Ref} = orka:subscribe({global, service, cache}).
% ... later ...
receive
    {orka_registered, {global, service, cache}, {_K, CachePid, _M}} ->
        % Use cache service
        ok
after 30000 ->
    io:format("Cache service timeout~n")
end.
```

---

### `unsubscribe(SubscriptionRef) → ok`

Cancel a subscription.

**Spec:**
```erlang
-spec unsubscribe(reference()) -> ok.
```

**Parameters:**
- `SubscriptionRef` — Reference from `subscribe/1`

---

## Utility Functions

### `entries() → [Entry]`

Get all registry entries.

**Spec:**
```erlang
-spec entries() -> [entry()].
```

---

### `count() → non_neg_integer()`

Get total number of entries in registry.

**Spec:**
```erlang
-spec count() -> non_neg_integer().
```

---

## See Also

- [../README.md](../README.md) — Quick start and project overview
- [Developer_Reference.md](Developer_Reference.md) — Design and architecture
- [Examples_&_Use_Cases.md](Examples_&_Use_Cases.md) — Practical patterns and code examples
