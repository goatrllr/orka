# Orca Await/Subscribe Examples

This document provides practical examples of using `orca:await/2` and `orca:subscribe/1` for service startup coordination in multi-app systems.

## Overview

Orca provides two patterns for handling dependent services:

1. **`await/2`** - Blocking pattern for required dependencies
   - Waits for a key to be registered with a timeout
   - Returns immediately if already registered
   - Suitable for initialization sequences where dependencies are mandatory

2. **`subscribe/1`** - Non-blocking pattern for optional dependencies
   - Registers interest in a key without blocking
   - Receives message when key is registered
   - Suitable for graceful degradation and optional features

Note about `await/2` timeouts: `await/2` subscribes and sets a timer that will send a `{orca_await_timeout, Key}` message to the waiting process on expiry. The implementation calls `unsubscribe/1` and drains the timeout message to avoid stale notifications. There is a small race window where a registration and the timeout may arrive concurrently; callers should handle both `{orca_registered, ...}` and timeout responses, or prefer `subscribe/1` for non-blocking semantics when exact ordering matters.

## 1. Blocking Initialization Pattern

**Use Case**: A service requires another service to be available before it can start.

```erlang
-module(user_service).
-behavior(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_info/2, terminate/2]).

start_link() ->
    gen_server:start_link({local, user_service}, ?MODULE, [], []).

init([]) ->
    %% This service requires the database service to exist
    case orca:await({global, service, database}, 30000) of
        {ok, {_Key, DbPid, _Metadata}} ->
            %% Database is ready
            {ok, #state{
                db = DbPid,
                users = #{}
            }};
        {error, timeout} ->
            %% Database failed to start in time
            {stop, db_unavailable}
    end.

handle_call({get_user, UserId}, _From, State) ->
    %% Use State#state.db to query database
    {reply, {ok, user_data}, State}.
```

**Benefits**:
- Ensures mandatory dependencies are available before proceeding
- Clear startup failure semantics - service simply refuses to start
- Timeout prevents indefinite hangs

## 2. Multi-Service Startup Coordination

**Use Case**: A service depends on multiple other services that may start in any order.

```erlang
-module(order_service).
-behavior(gen_server).

start_link() ->
    gen_server:start_link({local, order_service}, ?MODULE, [], []).

init([]) ->
    %% Sequentially wait for required services
    case await_all_services() of
        {ok, Services} ->
            {ok, #state{services = Services}};
        {error, service, Reason} ->
            {stop, {required_service, Reason}}
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

**Benefits**:
- Clear dependency ordering
- Specific timeout for each service
- Easy to identify which service failed to start

## 3. Non-Blocking Optional Dependency Pattern

**Use Case**: A service can work with or without an optional feature, using it if available.

```erlang
-module(notification_service).
-behavior(gen_server).

start_link() ->
    gen_server:start_link({local, notification_service}, ?MODULE, [], []).

init([]) ->
    %% Subscribe to optional feature - don't block
    orca:subscribe({global, service, sms_provider}),
    orca:subscribe({global, service, push_service}),
    
    {ok, #state{
        sms_ready = false,
        push_ready = false,
        sms_pid = undefined,
        push_pid = undefined
    }}.

handle_info({orca_registered, {global, service, sms_provider}, {_, SmsPid, _Meta}}, State) ->
    io:format("SMS provider is now available~n", []),
    {noreply, State#state{sms_ready = true, sms_pid = SmsPid}};

handle_info({orca_registered, {global, service, push_service}, {_, PushPid, _Meta}}, State) ->
    io:format("Push service is now available~n", []),
    {noreply, State#state{push_ready = true, push_pid = PushPid}};

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

**Benefits**:
- Service starts immediately without waiting
- Gracefully handles missing optional dependencies
- Features become available as they appear

## 4. Cascading Service Dependencies

**Use Case**: Services that depend on other dependent services.

```erlang
%% Service A: Depends on database
-module(database_adapter).
init([]) ->
    case orca:await({global, service, database}, 30000) of
        {ok, {_, Pid, _}} -> {ok, #state{db = Pid}};
        {error, timeout} -> {stop, db_unavailable}
    end,
    %% Register ourselves so dependent services can find us
    orca:register({global, service, database_adapter}, self(), #{
        tags => [service, adapter, database]
    }),
    {ok, State}.

%% Service B: Depends on database adapter
-module(data_service).
init([]) ->
    %% Wait for database_adapter (which internally depends on database)
    case orca:await({global, service, database_adapter}, 30000) of
        {ok, {_, AdapterPid, _}} ->
            {ok, #state{adapter = AdapterPid}};
        {error, timeout} ->
            {stop, adapter_unavailable}
    end,
    orca:register({global, service, data_service}, self(), #{
        tags => [service, data]
    }),
    {ok, State}.

%% Service C: Depends on data service
-module(api_handler).
init([]) ->
    case orca:await({global, service, data_service}, 30000) of
        {ok, {_, DataPid, _}} ->
            {ok, #state{data_service = DataPid}};
        {error, timeout} ->
            {stop, data_service_unavailable}
    end,
    {ok, State}.
```

**Benefits**:
- Each service is independent and reusable
- Clear dependency chain is visible in code
- Partial startup works (e.g., if you manually start Service B, it fails cleanly)

## 5. Graceful Degradation with Timeout Fallback

**Use Case**: A service can work in degraded mode if optional services are slow to start.

```erlang
-module(report_service).
-behavior(gen_server).

start_link() ->
    gen_server:start_link({local, report_service}, ?MODULE, [], []).

init([]) ->
    %% Try to wait for analytics service, but don't block the whole app
    case orca:await({global, service, analytics}, 5000) of
        {ok, {_, AnalyticsPid, _}} ->
            io:format("Starting with analytics enabled~n", []),
            {ok, #state{analytics = AnalyticsPid, mode = full}};
        {error, timeout} ->
            io:format("Analytics unavailable, starting in degraded mode~n", []),
            %% Still subscribe for when it becomes available
            orca:subscribe({global, service, analytics}),
            {ok, #state{analytics = undefined, mode = degraded}}
    end.

handle_info({orca_registered, {global, service, analytics}, {_, Pid, _Meta}}, State) ->
    io:format("Analytics is now available, upgrading from degraded mode~n", []),
    {noreply, State#state{analytics = Pid, mode = full}};

handle_info(_Info, State) ->
    {noreply, State}.

handle_call({generate_report, ReportId}, _From, State) ->
    Report = case State#state.mode of
        full ->
            %% Generate rich report with analytics
            generate_full_report(ReportId, State#state.analytics);
        degraded ->
            %% Generate basic report without analytics
            generate_basic_report(ReportId)
    end,
    {reply, Report, State}.
```

**Benefits**:
- Application starts even if optional services are slow
- Graceful upgrade when services become available
- No hard dependency on startup timing

## 6. Process Pool with Await

**Use Case**: Waiting for a pool of worker processes to be available.

```erlang
-module(worker_pool).

%% Supervisor ensures N worker processes are started
%% Each registers itself with a unique key
start_workers(N) ->
    [
        spawn(fun() ->
            WorkerId = {global, worker, Index},
            orca:register(WorkerId, self(), #{
                tags => [worker, pool],
                worker_index => Index
            })
        end)
        || Index <- lists:seq(1, N)
    ].

%% Consumer waits for specific worker
get_worker(WorkerId, Timeout) ->
    case orca:await(WorkerId, Timeout) of
        {ok, {_, WorkerPid, _Meta}} ->
            {ok, WorkerPid};
        {error, timeout} ->
            {error, worker_unavailable}
    end.

%% Find any available worker
find_available_worker(Timeout) ->
    case orca:await({global, worker, '_'}, Timeout) of
        {ok, {_, WorkerPid, _Meta}} ->
            {ok, WorkerPid};
        {error, timeout} ->
            {error, no_workers_available}
    end.
```

## 7. Unsubscribe for Cleanup

**Use Case**: Managing subscriptions with proper cleanup.

```erlang
-module(feature_manager).

-export([enable_feature/1, disable_feature/1, handle_feature/1]).

enable_feature(FeatureId) ->
    Key = {global, feature, FeatureId},
    orca:subscribe(Key),
    {ok, subscribed}.

disable_feature(FeatureId) ->
    Key = {global, feature, FeatureId},
    orca:unsubscribe(Key),
    {ok, unsubscribed}.

handle_feature({global, feature, FeatureId}) ->
    {orca_registered, {global, feature, FeatureId}, {_, FeaturePid, _Meta}} =
        receive_message(),
    io:format("Feature ~w is now available: ~p~n", [FeatureId, FeaturePid]).
```

**Benefits**:
- Clean resource management
- Prevents memory leaks from stale subscriptions
- Can re-subscribe to same feature multiple times

## Best Practices

### 1. Choose the Right Pattern

- **Use `await/2`** for mandatory dependencies that block initialization
- **Use `subscribe/1`** for optional dependencies that enhance functionality
- **Use both** when you have required base services and optional add-ons

### 2. Set Reasonable Timeouts

```erlang
%% Local service (same node): 1-5 seconds
await({global, service, local_db}, 5000)

%% Network service (different node): 10-30 seconds
await({global, service, remote_api}, 30000)

%% Optional feature: Short timeout to fail fast
await({global, service, analytics}, 2000)
```

### 3. Handle Errors Explicitly

```erlang
%% Don't do this:
{ok, {_, Pid, _}} = orca:await(Key, Timeout),

%% Do this:
case orca:await(Key, Timeout) of
    {ok, {_, Pid, _}} -> start_with(Pid);
    {error, timeout} -> handle_timeout();
    {error, Reason} -> handle_error(Reason)
end.
```

### 4. Register Services Early

Services should register themselves as soon as they're minimally functional:

```erlang
init([]) ->
    %% Do minimal initialization
    {ok, State} = initialize_basic_state(),
    
    %% Register immediately
    orca:register({global, service, my_service}, self()),
    
    %% Do expensive initialization afterward
    {ok, State2} = initialize_expensive_stuff(State),
    
    {ok, State2}.
```

### 5. Use Meaningful Keys

```erlang
%% Good: Scope, type, name
{global, service, database}
{global, service, user_api}
{local, worker, pool_1}

%% Bad: Unclear purpose
{global, proc_123}
{local, thing}
```

## Summary

| Pattern | Use When | Blocks? | Timeout |
|---------|----------|---------|---------|
| `await/2` | Mandatory dependency | Yes | Configurable |
| `subscribe/1` | Optional dependency | No | N/A |
| Both | Mixed requirements | Selective | Both |

Choose the pattern that matches your service architecture and handle errors appropriately for robust multi-app systems.
