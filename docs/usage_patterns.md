# Orca Usage Patterns

This document describes the fundamental patterns for using the orca registry in service-oriented architectures.

## Core Philosophy

Orca is a **focused process registry**. Services handle their own startup and dependency injection; orca handles the "where is this process?" question.

- ✓ Orca does: Register, lookup, query, cleanup, await
- ✓ Services do: Startup sequences, lazy-loading, resource injection
- ✓ Result: Composable, testable, minimal coupling

## Pattern 1: Service Starts Itself, Then Registers

**Use when**: Your supervisor or startup module starts the service and wants to register it.

```erlang
%% In supervisor or startup module
start_service() ->
    {ok, Pid} = service_module:start_link(),
    orca:register({global, service, my_service}, Pid, #{
        tags => [service, critical],
        properties => #{version => "1.0"}
    }),
    {ok, Pid}.
```

**Benefits**:
- Simple and explicit
- Service doesn't know about orca
- Easy to test in isolation
- Supervisor controls registration lifecycle

**Example: Database service**:
```erlang
-module(db_supervisor).

start_db() ->
    {ok, DbPid} = db_server:start_link(),
    orca:register({global, service, database}, DbPid, #{
        tags => [service, database, critical],
        properties => #{max_connections => 100, pool_type => primary}
    }),
    {ok, DbPid}.
```

## Pattern 2: Service Registers Itself (Self-Registration)

**Use when**: The service knows it needs to be discoverable and registers during init.

```erlang
%% In service init
init([]) ->
    orca:register({global, service, my_service}, self(), #{
        tags => [service, online],
        properties => #{capacity => 100}
    }),
    {ok, #state{}}.
```

**Benefits**:
- Service is autonomous
- Registration happens automatically on startup
- Service controls its own metadata
- No external startup wrapper needed

**Example: Cache service**:
```erlang
-module(cache_server).
-behavior(gen_server).

start_link() ->
    gen_server:start_link({local, cache_server}, ?MODULE, [], []).

init([]) ->
    orca:register({global, service, cache}, self(), #{
        tags => [service, cache, optional],
        properties => #{
            max_size => 10000,
            ttl_seconds => 3600,
            eviction_policy => lru
        }
    }),
    {ok, #state{data = #{}}}.
```

**Example: Metrics service**:
```erlang
-module(metrics_server).

init([]) ->
    orca:register({global, service, metrics}, self(), #{
        tags => [service, metrics, monitoring],
        properties => #{sample_interval => 5000}
    }),
    {ok, #state{counters = #{}}}.
```

## Pattern 3: Per-User/Per-Session Service with Supervisor

**Use when**: You need dynamic services per user, session, or resource.

```erlang
%% Supervisor creates user-scoped service
start_user_session(UserId) ->
    orca:register_with(
        {global, user, UserId},
        #{
            tags => [user, online, session],
            properties => #{region => "us-west"}
        },
        {user_session, start_link, [UserId]}
    ).
```

**Benefits**:
- Atomic startup + registration (no race conditions)
- Each user/session gets its own process
- Automatic cleanup when process dies
- Easy to query "all users" or "users in region X"

**Example: User session manager**:
```erlang
-module(session_manager).

%% Called by web framework
create_session(UserId) ->
    case orca:register_with(
        {global, user, UserId},
        #{
            tags => [user, session, online],
            properties => #{
                created_at => erlang:system_time(millisecond),
                region => get_user_region(UserId)
            }
        },
        {user_session, start_link, [UserId]}
    ) of
        {ok, Pid} -> {ok, Pid};
        {error, Reason} -> {error, Reason}
    end.

%% Look up a user's session
get_session(UserId) ->
    case orca:lookup({global, user, UserId}) of
        {ok, {_Key, Pid, _Meta}} -> {ok, Pid};
        not_found -> {error, session_not_found}
    end.

%% Find all users in a region
users_in_region(Region) ->
    orca:find_by_property(user, region, Region).
```

**Example: Job worker per task**:
```erlang
-module(job_coordinator).

%% Start a worker for a job
start_job_worker(JobId, Config) ->
    orca:register_with(
        {global, job, JobId},
        #{
            tags => [job, worker, processing],
            properties => #{
                config => Config,
                started_at => erlang:system_time(millisecond),
                status => running
            }
        },
        {job_worker, start_link, [JobId, Config]}
    ).

%% Get a job's worker
get_job(JobId) ->
    case orca:lookup({global, job, JobId}) of
        {ok, {_Key, Pid, Meta}} -> {ok, Pid, Meta};
        not_found -> {error, job_not_found}
    end.

%% Find all active jobs
active_jobs() ->
    orca:find_by_property(job, status, running).
```

## Pattern 4: Singleton Service (Only One Instance)

**Use when**: You need to ensure exactly one instance exists (database connection pool, config server, lock manager, etc.).

```erlang
%% Register as singleton to prevent duplicates
start_singleton_service() ->
    orca:register_with(
        {global, service, database},
        #{tags => [service, database, critical]},
        {db_service, start_link, []}
    ).
```

Or with explicit singleton constraint:

```erlang
init([]) ->
    %% This will fail if Pid is already registered under a different key
    case orca:register_single({global, service, config_server}, self(), #{
        tags => [service, config, critical],
        properties => #{reload_interval => 30000}
    }) of
        {ok, _Entry} ->
            {ok, #state{}};
        {error, {already_registered_under_key, OtherKey}} ->
            {stop, {already_running_as, OtherKey}}
    end.
```

**Benefits**:
- Guarantees only one instance per key
- Automatic prevention of duplicate services
- Clear error if someone tries to register twice
- Perfect for critical system services

**Example: Lock manager**:
```erlang
-module(lock_manager).

init([]) ->
    case orca:register_single(
        {global, service, lock_manager},
        self(),
        #{
            tags => [service, locks, critical],
            properties => #{max_locks => 10000}
        }
    ) of
        {ok, _} ->
            {ok, #state{locks = #{}}};
        {error, {already_registered_under_key, _}} ->
            {stop, lock_manager_already_running}
    end.
```

**Example: Configuration server**:
```erlang
-module(config_server).

init([]) ->
    case orca:register_single(
        {global, service, config_server},
        self(),
        #{
            tags => [service, config, critical],
            properties => #{
                reload_interval => 30000,
                config_path => "/etc/app.config"
            }
        }
    ) of
        {ok, _} ->
            load_config(),
            {ok, #state{config = load_config()}};
        {error, {already_registered_under_key, _}} ->
            {stop, config_server_already_running}
    end.
```

## Pattern 5: Blocking Wait for Required Dependency

**Use when**: Your service **cannot** start without another service being available.

```erlang
%% Service waits for required dependency
init([]) ->
    case orca:await({global, service, database}, 30000) of
        {ok, {_K, DbPid, _Meta}} ->
            {ok, #state{db = DbPid}};
        {error, timeout} ->
            {stop, database_unavailable}
    end.
```

**Benefits**:
- Clear startup failure semantics
- Prevents partial initialization
- Automatic timeout prevents hanging
- Service never starts in broken state

**Example: API handler requiring database**:
```erlang
-module(api_handler).
-behavior(gen_server).

init([]) ->
    case orca:await({global, service, database}, 30000) of
        {ok, {_K, DbPid, _Meta}} ->
            {ok, #state{db = DbPid, requests = 0}};
        {error, timeout} ->
            io:format("Database not available, refusing to start~n", []),
            {stop, db_unavailable}
    end.

handle_call({query, Sql}, _From, State) ->
    %% Safe to use State#state.db - we know it exists
    Result = db_server:query(State#state.db, Sql),
    {reply, Result, State}.
```

**Example: Multi-service startup coordination**:
```erlang
-module(order_service).

init([]) ->
    case await_all_services() of
        {ok, Services} ->
            {ok, #state{services = Services}};
        {error, service, ServiceName} ->
            {stop, {service_unavailable, ServiceName}}
    end.

await_all_services() ->
    case orca:await({global, service, database}, 30000) of
        {ok, {_, DbPid, _}} ->
            case orca:await({global, service, cache}, 20000) of
                {ok, {_, CachePid, _}} ->
                    case orca:await({global, service, queue}, 15000) of
                        {ok, {_, QueuePid, _}} ->
                            {ok, #{
                                db => DbPid,
                                cache => CachePid,
                                queue => QueuePid
                            }};
                        {error, timeout} ->
                            {error, queue, timeout}
                    end;
                {error, timeout} ->
                    {error, cache, timeout}
            end;
        {error, timeout} ->
            {error, database, timeout}
    end.
```

## Pattern 6: Non-Blocking Subscription to Optional Dependency

**Use when**: Your service can work with or without another service, using it if available.

```erlang
init([]) ->
    %% Subscribe to optional feature - don't block
    orca:subscribe({global, service, cache}),
    {ok, #state{cache = undefined}}.

handle_info({orca_registered, {global, service, cache}, {_K, Pid, _Meta}}, State) ->
    io:format("Cache is now available~n", []),
    {noreply, State#state{cache = Pid}}.
```

**Benefits**:
- Service starts immediately
- Graceful degradation without optional services
- Feature becomes available as it appears
- No startup timeouts

**Example: Notification service with optional SMS provider**:
```erlang
-module(notification_service).
-behavior(gen_server).

init([]) ->
    %% Subscribe to optional features
    orca:subscribe({global, service, sms_provider}),
    orca:subscribe({global, service, push_service}),
    
    %% Start immediately without waiting
    {ok, #state{
        sms_ready = false,
        push_ready = false,
        sms_pid = undefined,
        push_pid = undefined
    }}.

handle_info({orca_registered, {global, service, sms_provider}, {_, Pid, _Meta}}, State) ->
    io:format("SMS provider available~n", []),
    {noreply, State#state{sms_ready = true, sms_pid = Pid}};

handle_info({orca_registered, {global, service, push_service}, {_, Pid, _Meta}}, State) ->
    io:format("Push service available~n", []),
    {noreply, State#state{push_ready = true, push_pid = Pid}};

handle_info(_Info, State) ->
    {noreply, State}.

handle_call({notify, Message}, _From, State) ->
    %% Send via available channels
    case State#state.sms_ready of
        true -> send_sms(State#state.sms_pid, Message);
        false -> ok
    end,
    case State#state.push_ready of
        true -> send_push(State#state.push_pid, Message);
        false -> ok
    end,
    {reply, ok, State}.
```

**Example: Analytics with optional export service**:
```erlang
-module(analytics_server).

init([]) ->
    orca:subscribe({global, service, analytics_exporter}),
    {ok, #state{
        exporter_ready = false,
        exporter_pid = undefined,
        events = []
    }}.

handle_info({orca_registered, {global, service, analytics_exporter}, {_, Pid, _Meta}}, State) ->
    %% Exporter appeared, send buffered events
    send_buffered_events(State#state.events, Pid),
    {noreply, State#state{exporter_ready = true, exporter_pid = Pid, events = []}}.

handle_call({log_event, Event}, _From, State) ->
    case State#state.exporter_ready of
        true ->
            send_event(State#state.exporter_pid, Event);
        false ->
            %% Buffer event until exporter is available
            ok
    end,
    {reply, ok, State}.
```

## Pattern 7: Service Pre-Registration During Startup

**Use when**: A startup coordinator needs to register a "starting" state before initialization completes.

```erlang
%% In service module
pre_register(ServiceName) ->
    orca:register({global, service, ServiceName}, self(), #{
        tags => [service, starting],
        properties => #{status => initializing}
    }).

%% Later, when ready, mark as complete
mark_ready() ->
    orca:remove_tag({global, service, my_service}, starting),
    orca:add_tag({global, service, my_service}, ready).
```

**Benefits**:
- Signals to dependents that service is starting
- Services can subscribe and wait for "ready" tag
- Clear visibility into startup progress

**Example: Startup coordinator waiting for all services**:
```erlang
-module(app_startup).

startup() ->
    Services = [translator, cache, database],
    %% Wait for all services to be ready
    lists:map(fun(Service) ->
        Key = {global, service, Service},
        case orca:await(Key, 30000) of
            {ok, {_K, Pid, Meta}} ->
                Tags = maps:get(tags, Meta, []),
                case lists:member(ready, Tags) of
                    true -> {ok, Service, Pid};
                    false -> {error, {service_not_ready, Service}}
                end;
            {error, timeout} ->
                {error, {service_timeout, Service}}
        end
    end, Services).
```

## Decision Tree: Which Pattern?

```
Does service know about orca?
├─ No → Pattern 1: Supervisor registers service
└─ Yes → Service has self-registration
         ├─ Service is singleton?
         │  ├─ Yes → Pattern 4: register_single
         │  └─ No  → Pattern 2: register(self(), ...)
         │
         └─ Service is per-user/resource?
            └─ Yes → Pattern 3: register_with (supervisor)

Does your service need another service to start?
├─ Yes, required → Pattern 5: await with timeout
├─ No, optional → Pattern 6: subscribe
└─ Pre-register → Pattern 7: register "starting" state
```

## Quick Reference

| Pattern | Startup | Singleton | Dynamic | Blocking | Use Case |
|---------|---------|-----------|---------|----------|----------|
| 1 | Supervisor | No | No | No | Services discovered by supervisor |
| 2 | Self | Optional | No | No | Self-aware services |
| 3 | Supervisor | No | **Yes** | No | User sessions, job workers |
| 4 | Self | **Yes** | No | No | Database pools, lock managers |
| 5 | Self | No | No | **Yes** | Required dependencies |
| 6 | Self | No | No | No | Optional features |
| 7 | Self | No | No | No | Multi-stage startup |

## Pattern 8: Batch Registration for Multi-Process Workloads

**Use when**: You're registering multiple processes for a single context (e.g., per-user services, per-job workers) and want to minimize GenServer calls.

```erlang
%% Register 5 processes for a user in a single call (explicit Pids)
UserId = user123,
{ok, Entries} = orca:register_batch([
    {{global, portfolio, UserId}, PortfolioPid, #{tags => [portfolio, user], properties => #{strategy => momentum}}},
    {{global, technical, UserId}, TechnicalPid, #{tags => [technical, user], properties => #{indicators => [rsi, macd]}}},
    {{global, fundamental, UserId}, FundamentalPid, #{tags => [fundamental, user], properties => #{sectors => [tech, finance]}}},
    {{global, orders, UserId}, OrdersPid, #{tags => [orders, user], properties => #{queue_depth => 100}}},
    {{global, risk, UserId}, RiskPid, #{tags => [risk, user], properties => #{max_position_size => 10000}}}
]).

%% Or start and register in a single call
{ok, Entries} = orca:register_batch_with([
    {{global, portfolio, UserId}, #{tags => [portfolio, user]}, {portfolio_service, start_link, [UserId]}},
    {{global, technical, UserId}, #{tags => [technical, user]}, {technical_service, start_link, [UserId]}},
    {{global, fundamental, UserId}, #{tags => [fundamental, user]}, {fundamental_service, start_link, [UserId]}},
    {{global, orders, UserId}, #{tags => [orders, user]}, {order_service, start_link, [UserId]}},
    {{global, risk, UserId}, #{tags => [risk, user]}, {risk_service, start_link, [UserId]}}
]).
```

**Benefits**:
- Single GenServer call instead of 5 (significant reduction for trading/multi-process apps)
- Atomic: all succeed or all fail
- Cleaner syntax than sequential register calls
- Perfect for per-user workspaces with fixed service sets

**Example: Trading App with Per-User Services**:
```erlang
%% Supervisor starts all services for a user
-module(user_services_sup).
-behavior(supervisor).

start_link(UserId) ->
    supervisor:start_link({local, {user_sup, UserId}}, ?MODULE, [UserId]).

init([UserId]) ->
    SupFlags = #{strategy => one_for_one, intensity => 5, period => 60},
    
    ChildSpecs = [
        {portfolio, {portfolio_service, start_link, [UserId]}, permanent, 5000, worker, []},
        {technical, {technical_service, start_link, [UserId]}, permanent, 5000, worker, []},
        {fundamental, {fundamental_service, start_link, [UserId]}, permanent, 5000, worker, []},
        {orders, {order_service, start_link, [UserId]}, permanent, 5000, worker, []},
        {risk, {risk_service, start_link, [UserId]}, permanent, 5000, worker, []}
    ],
    
    {ok, {SupFlags, ChildSpecs}}.

%% Each service self-registers
-module(portfolio_service).
-behavior(gen_server).

init([UserId]) ->
    orca:register({global, portfolio, UserId}, self(), #{
        tags => [portfolio, user],
        properties => #{strategy => momentum, created_at => erlang:system_time(millisecond)}
    }),
    {ok, #state{user_id = UserId}}.
```

**Batch API Signature**:
```erlang
-spec register_batch([{Key, Pid, Metadata}]) ->
    {ok, [Entry]} | {error, {FirstFailure, FailedKeys, SuccessfulEntries}}.

-spec register_batch_with([{Key, Metadata, {M, F, A}}]) ->
    {ok, [Entry]} | {error, {FirstFailure, FailedKeys, SuccessfulEntries}}.
```

- Returns all entries on success
- Returns detailed error on failure with list of failed keys
- **Key behavior**: If a key is already registered with a live process, the existing entry is returned and processing continues (doesn't fail the batch)
- **Rollback semantics**: Only newly registered entries are rolled back on failure; pre-existing entries remain
- On failure in `register_batch_with`: newly started processes are terminated, but previously running processes continue

**When to Use**:
- ✓ Per-user services (trading apps, workspace managers)
- ✓ Per-job workers (batch processing, task queues)
- ✓ Service clusters that always start together
- ✗ Don't use for optional/conditional registrations
- ✗ Don't use if services start at different times

**When NOT to Use**:
- If services start asynchronously over time, use individual `register/3` calls
- If some services are optional, use `subscribe` instead
- If you need different error handling per service, handle individually

**Cleanup**:

When unregistering all services for a user/context, use `batch_unregister/1`:

```erlang
%% Clean up all services for a user when workspace closes
UserId = user123,
Keys = [
    {global, portfolio, UserId},
    {global, technical, UserId},
    {global, fundamental, UserId},
    {global, orders, UserId},
    {global, risk, UserId}
],
{ok, {RemovedKeys, NotFoundKeys}} = orca:batch_unregister(Keys).

%% RemovedKeys = [all keys that were removed]
%% NotFoundKeys = [any keys that weren't registered]
```

Benefits over sequential unregister:
- Single GenServer call instead of 5
- Atomic operation on multiple keys
- Clear reporting of what succeeded/failed

## Best Practices

1. **Register early**: Don't wait for expensive initialization
2. **Clear keys**: Use `{Scope, Type, Name}` format consistently
3. **Rich metadata**: Include tags and properties for querying
4. **Handle timeouts**: Always expect `{error, timeout}` from `await/2`
5. **Keep services independent**: Don't hardcode knowledge of other services
6. **Use subscribe for optional features**: Don't block on nice-to-haves
7. **Let services control their metadata**: Don't modify other services' registrations
8. **Use batch for fixed multi-process sets**: Reduces GenServer overhead for per-user/per-job workloads
