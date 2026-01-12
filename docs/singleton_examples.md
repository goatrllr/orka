# Orka Singleton Registration Examples

The Orka process registry supports singleton registration through `register_single/2` and `register_single/3`. These functions enforce a strict one-key-per-process constraint, preventing a Pid from being registered under multiple aliases.

## Key Concepts

- **Singleton Constraint**: A process registered with `register_single` can only have one registration key at a time
- **Safety**: Attempting to register the same process under a different key returns an error
- **Idempotent**: Re-registering under the same key returns the existing entry (metadata may be updated)
- **Cleanup**: The singleton constraint is automatically released when the process crashes or is unregistered
- **Contrast to `register/3`**: Regular `register/3` allows the same process to have multiple keys (aliases)

## API Overview

```erlang
%% Register a process with singleton constraint (self as Pid)
orka:register_single(Key, Metadata).

%% Register a process with singleton constraint (explicit Pid)
orka:register_single(Key, Pid, Metadata).
```

Returns:
- `{ok, {Key, Pid, Metadata}}` — Successfully registered as singleton
- `{ok, {Key, Pid, Metadata}}` — Already registered under the same key (existing entry returned)
- `{error, {already_registered_under_key, ExistingKey}}` — Pid already registered under a different key
- `{error, {already_registered, ExistingKeys}}` — Pid already has non-singleton registrations
- `not_found` — Key not registered (for unregister operations)

---

## Use Case 1: Unique Service Instance Per Node

Ensure only ONE instance of a critical service runs on the node. If another process somehow tries to register under a different key, it's rejected.

### Setup

```erlang
%% Start and register translator service as singleton
orka:register_single(
    {local, service, translator},
    TranslatorPid,
    #{
        tags => [service, translator, critical],
        properties => #{version => "2.1.0", capacity => 100}
    }
).
%% Result: {ok, {{local, service, translator}, <0.123.0>, {...}}}
```

### Enforcement

```erlang
%% Later, someone tries to register the same process under an alias
orka:register_single(
    {local, service, translator_backup},
    TranslatorPid,
    #{tags => [service, translator]}
).
%% Result: {error, {already_registered_under_key, {local, service, translator}}}

%% The process is STILL only registered under the original key
orka:lookup({local, service, translator}).
%% Result: {ok, {{local, service, translator}, <0.123.0>, {...}}}

orka:lookup({local, service, translator_backup}).
%% Result: not_found
```

### Error Pattern

```erlang
%% Common mistake: trying to create a failover alias
failover_translator(OriginalTranslatorPid) ->
    case orka:register_single(
        {local, service, translator_standby},
        OriginalTranslatorPid,
        #{tags => [service, translator, standby]}
    ) of
        {ok, Entry} -> 
            {ok, Entry};
        {error, {already_registered_under_key, Key}} ->
            %% OriginalTranslatorPid is already registered elsewhere
            %% Start a NEW process instead
            {NewPid, _} = start_translator_service(),
            orka:register_single(
                {local, service, translator_standby},
                NewPid,
                #{tags => [service, translator, standby]}
            );
        {error, Reason} ->
            {error, Reason}
    end.
```

---

## Use Case 2: Database Connection Pool Manager

Prevent duplicate pool managers that could cause connection leaks or consistency issues.

### Setup

```erlang
%% Only ONE connection pool manager should exist
orka:register_single(
    {global, resource, db_pool_manager},
    PoolManagerPid,
    #{
        tags => [resource, database, critical],
        properties => #{
            max_connections => 100,
            active_connections => 0,
            pool_name => "primary_db"
        }
    }
).
%% Result: {ok, {{global, resource, db_pool_manager}, <0.200.0>, {...}}}
```

### Enforcement

```erlang
%% Someone tries to create a "secondary" pool manager for the same process
orka:register_single(
    {global, resource, db_pool_manager_secondary},
    PoolManagerPid,
    #{tags => [resource, database]}
).
%% Result: {error, {already_registered_under_key, {global, resource, db_pool_manager}}}

%% This prevents subtle bugs where:
%% - Connection metrics would be duplicated
%% - Multiple managers could issue conflicting CLOSE commands
%% - Pool state could become inconsistent
```

---

## Use Case 3: Configuration Server

A single system configuration server that must not have aliases or replication.

### Setup

```erlang
%% Register config server as strict singleton
orka:register_single(
    {global, service, config_server},
    ConfigServerPid,
    #{
        tags => [service, config, critical],
        properties => #{
            reload_interval => 30000,
            last_reload => 1703171234567,
            version => "1.2.3"
        }
    }
).
%% Result: {ok, {{global, service, config_server}, <0.250.0>, {...}}}
```

### Why Singleton?

```erlang
%% BAD: Multiple service-specific config endpoints
%% If allowed (with register/3), each would cache independently:
orka:register({global, service, app_config}, ConfigServerPid, #{...}).
orka:register({global, service, api_config}, ConfigServerPid, #{...}).
orka:register({global, service, db_config}, ConfigServerPid, #{...}).

%% Now two services get different views when config reloads!
%% ConfigServerPid reloads internally, but services still see stale values

%% SOLUTION: Singleton forces a single registration point
orka:register_single({global, service, config_server}, ConfigServerPid, {...}).

%% All services must use the same key to get current config
Config = orka:lookup({global, service, config_server}).
```

---

## Use Case 4: Distributed Lock Manager

Ensure only ONE lock manager coordinates cluster-wide locks.

### Setup

```erlang
%% Register lock manager as strict singleton
orka:register_single(
    {global, resource, lock_manager},
    LockManagerPid,
    #{
        tags => [resource, locks, critical],
        properties => #{
            lock_timeout => 5000,
            max_locks => 10000,
            deadlock_detection => true
        }
    }
).
%% Result: {ok, {{global, resource, lock_manager}, <0.300.0>, {...}}}
```

### Enforcement

```erlang
%% Prevents accidental duplicate registrations that could cause deadlocks
orka:register_single(
    {global, resource, lock_manager_backup},
    LockManagerPid,
    #{tags => [resource, locks]}
).
%% Result: {error, {already_registered_under_key, {global, resource, lock_manager}}}

%% Lock consistency is guaranteed because there's only one source of truth
request_lock(ResourceId, Timeout) ->
    case orka:lookup({global, resource, lock_manager}) of
        {ok, {_Key, ManagerPid, _Meta}} ->
            gen_server:call(ManagerPid, {acquire_lock, ResourceId, Timeout});
        not_found ->
            {error, lock_manager_unavailable}
    end.
```

---

## Use Case 5: Event Bus / Message Router

A single event distribution system that shouldn't be replicated or aliased.

### Setup

```erlang
%% Register event bus as strict singleton
orka:register_single(
    {local, service, event_bus},
    EventBusPid,
    #{
        tags => [service, events, critical],
        properties => #{
            max_subscribers => 1000,
            message_queue_size => 0,
            throughput_limit => infinity
        }
    }
).
%% Result: {ok, {{local, service, event_bus}, <0.350.0>, {...}}}
```

### Why Singleton Matters

```erlang
%% Without singleton protection, someone might create "regional" aliases:
orka:register({local, service, event_bus_us_west}, EventBusPid, {...}).
orka:register({local, service, event_bus_us_east}, EventBusPid, {...}).

%% Now subscribers are split:
%% - east subscribers: published_event(<<"user.registered">>, ...)
%% - west subscribers: don't see the event!
%% - Cause: different subscribers registered for each alias

%% Singleton prevents this:
orka:register_single({local, service, event_bus_us_west}, EventBusPid, {...}).
%% Error: {already_registered_under_key, {local, service, event_bus}}

%% Forces single event bus coordinate all subscriptions
subscribe(EventType, CallbackFun) ->
    {ok, {_Key, BusPid, _Meta}} = orka:lookup({local, service, event_bus}),
    gen_server:call(BusPid, {subscribe, EventType, CallbackFun}).
```

---

## Use Case 6: Metrics Collector

A single system-wide metrics aggregator that must have one registration point.

### Setup

```erlang
%% Register metrics collector as strict singleton
orka:register_single(
    {local, service, metrics_collector},
    MetricsCollectorPid,
    #{
        tags => [service, monitoring, non_critical],
        properties => #{
            flush_interval => 10000,
            buffer_size => 5000,
            enabled => true
        }
    }
).
%% Result: {ok, {{local, service, metrics_collector}, <0.400.0>, {...}}}
```

### Enforcement

```erlang
%% Prevents duplicate collectors that would send duplicate metrics
orka:register_single(
    {local, service, metrics_collector_secondary},
    MetricsCollectorPid,
    #{tags => [service, monitoring]}
).
%% Result: {error, {already_registered_under_key, {local, service, metrics_collector}}}

%% Single source of truth for all metrics
emit_metric(MetricName, Value, Tags) ->
    {ok, {_Key, CollectorPid, _Meta}} = 
        orka:lookup({local, service, metrics_collector}),
    gen_server:cast(CollectorPid, {metric, MetricName, Value, Tags}).
```

---

## Use Case 7: Authentication/Authorization Server

Central security service that must not be replicated or have authorization bypass aliases.

### Setup

```erlang
%% Register auth server as strict singleton
orka:register_single(
    {global, service, auth_server},
    AuthServerPid,
    #{
        tags => [service, security, critical],
        properties => #{
            session_ttl => 3600000,
            password_min_length => 12,
            mfa_required => true
        }
    }
).
%% Result: {ok, {{global, service, auth_server}, <0.450.0>, {...}}}
```

### Security Implication

```erlang
%% Without singleton, someone might create a "backdoor" alias with relaxed settings:
%% BAD CODE (prevented by singleton):
%% orka:register({global, service, auth_server_dev}, AuthServerPid, #{
%%     tags => [service, security],
%%     properties => #{mfa_required => false}  %% Dangerous!
%% }).

%% Singleton prevents this:
orka:register_single(
    {global, service, auth_server_dev},
    AuthServerPid,
    #{tags => [service, security]}
).
%% Result: {error, {already_registered_under_key, {global, service, auth_server}}}

%% All authentication must go through the same registered instance
verify_credentials(Username, Password) ->
    {ok, {_Key, AuthPid, _Meta}} = 
        orka:lookup({global, service, auth_server}),
    gen_server:call(AuthPid, {verify, Username, Password}).
```

---

## Comparison: Singleton vs. Non-Singleton

### Singleton Pattern (register_single/3)

```erlang
%% One process, one key
orka:register_single({global, service, translator}, Pid, Meta).
%% {ok, Entry}

%% Try to add alias
orka:register_single({global, service, translator_2}, Pid, Meta).
%% {error, {already_registered_under_key, {global, service, translator}}}
```

**Use When:**
- Service must be unique (only one instance allowed)
- One key is the single source of truth
- Multiple aliases would cause consistency issues
- Safety/security critical components

### Multi-Register Pattern (register/3)

```erlang
%% One process, multiple keys allowed
orka:register({global, service, translator_1}, Pid, Meta).
%% {ok, Entry}

orka:register({global, service, translator_2}, Pid, Meta).
%% {ok, Entry} — Both keys now point to same Pid

%% Both keys are active
orka:lookup({global, service, translator_1}).  %% {ok, Entry}
orka:lookup({global, service, translator_2}).  %% {ok, Entry}
```

**Use When:**
- Load balancing (multiple interfaces to same service)
- Aliases for backward compatibility
- User sessions (one user, many device connections)
- Flexible routing/addressing

---

## Migration Path

If you have a process that was registered with `register/3` and want to convert it to singleton:

```erlang
%% Old: Could have multiple aliases
orka:register({global, service, translator}, Pid, Meta).
orka:register({global, service, old_translator}, Pid, Meta).

%% Unregister the old alias
orka:unregister({global, service, old_translator}).

%% Re-register as singleton
orka:unregister({global, service, translator}).
orka:register_single({global, service, translator}, Pid, Meta).
```

---

## Common Patterns

### Pattern 1: Verify Singleton Is Active

```erlang
ensure_singleton_alive(Key, M, F, A) ->
    case orka:lookup(Key) of
        {ok, {Key, Pid, Meta}} ->
            {ok, {Key, Pid, Meta}};
        not_found ->
            %% Not registered, start and register
            {ok, NewPid} = orka:register_with(Key, #{}, {M, F, A}),
            orka:register_single(Key, NewPid, #{}),
            orka:lookup(Key)
    end.
```

### Pattern 2: Singleton with Automatic Failover

```erlang
%% For true high availability, use non-singleton register/3
%% But for consistency, use a single "primary" with singleton
register_primary(PrimaryPid) ->
    orka:register_single({global, service, translator_primary}, PrimaryPid, Meta).

register_secondary(SecondaryPid) ->
    %% Secondary CAN'T use singleton, it's a backup
    orka:register({global, service, translator_backup}, SecondaryPid, Meta).

get_translator() ->
    case orka:lookup({global, service, translator_primary}) of
        {ok, {_, Pid, _}} -> {ok, Pid};
        not_found ->
            %% Primary down, use backup
            case orka:find_by_property(service, translator, status, <<"ready">>) of
                [{_, BackupPid, _}|_] -> {ok, BackupPid};
                [] -> {error, no_translators}
            end
    end.
```

### Pattern 3: Singleton Initialization Helper

```erlang
%% Ensure a singleton is initialized or return existing
init_singleton(Key, Metadata, {M, F, A}) ->
    case orka:lookup(Key) of
        {ok, Entry} ->
            {ok, Entry};
        not_found ->
            {ok, Pid} = orka:register_with(Key, Metadata, {M, F, A}),
            orka:register_single(Key, Pid, Metadata),
            orka:lookup(Key)
    end.
```

---

## Best Practices

1. **Document Intent**: Comment why a process is singleton, not just that it is
2. **Handle Constraint Errors**: Catch `already_registered_under_key` and handle gracefully
3. **Single Key Management**: Don't change the key; unregister and re-register if needed
4. **Combine with Tags**: Use tags to identify what the singleton manages
5. **Health Monitoring**: Use properties to track singleton health/status
6. **Avoid Conditional Singletons**: Don't mix `register/3` and `register_single/3` for the same logical process
7. **Test Enforcement**: Write tests that verify singleton constraints are enforced
