# Examples & Use Cases

> **Note**: This documentation covers the **Orka Core API** on the `main` branch. Orka uses a split-branch strategy where Core remains on `main` and extensions are on feature branches. All examples use Core only. Ensure you're on the correct branch. See [../README.md](../README.md) for branch information.

Practical patterns and real-world code examples for using Orka.

---

## Table of Contents

1. [Key Patterns](#key-patterns)
2. [Service Registration Patterns](#service-registration-patterns)
3. [Startup Coordination](#startup-coordination)
4. [Singleton Services](#singleton-services)
5. [Loaded-Based Distribution](#load-based-distribution)
6. [Health Monitoring](#health-monitoring)
7. [Complete Application Example](#complete-application-example)

---

## Key Patterns

### Pattern 1: Supervisor Registers Child

Service starts via supervisor, then supervisor registers it.

```erlang
%% translator_sup.erl
-module(translator_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    ChildSpec = {
        translator_server,
        {translator_server, start_link, []},
        permanent,
        5000,
        worker,
        [translator_server]
    },
    
    %% After child starts, register it
    {ok, {Pid}} = supervisor:start_child(?MODULE, ChildSpec),
    ok = orka:register(
        {global, service, translator},
        Pid,
        #{tags => [service, translator, critical]}
    ),
    
    {ok, {{one_for_one, 10, 60}, [ChildSpec]}}.
```

**Benefits**: Supervisor owns the process, registration is separate

---

### Pattern 2: Service Self-Registers

Service registers itself during init.

```erlang
%% translator_server.erl
-module(translator_server).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_info/2, terminate/2]).

start_link() ->
    gen_server:start_link({local, translator_server}, ?MODULE, [], []).

init([]) ->
    %% Self-register during init
    ok = orka:register(
        {global, service, translator},
        self(),
        #{
            tags => [service, translator, online, critical],
            properties => #{capacity => 100, version => "2.1.0"}
        }
    ),
    
    {ok, #state{}}. 

handle_call({translate, Text}, _From, State) ->
    Result = translate_text(Text),
    {reply, Result, State}.

terminate(_Reason, _State) ->
    %% Orka auto-cleanup on process crash
    ok.
```

**Benefits**: Service is autonomous, knows about registry

---

### Pattern 3: Batch Registration Per User

Register multiple services for a user atomically.

```erlang
%% user_workspace.erl
-module(user_workspace).

%% Start and register all user services
start_user_services(UserId) ->
    %% Simulate starting three services for the user
    {ok, PortfolioPid} = portfolio_server:start_link(UserId),
    {ok, OrdersPid} = orders_server:start_link(UserId),
    {ok, RiskPid} = risk_server:start_link(UserId),
    
    %% Register all atomically (all succeed or all fail)
    {ok, Entries} = orka:register_batch([
        {
            {global, portfolio, UserId},
            PortfolioPid,
            #{tags => [portfolio, UserId, user_service]}
        },
        {
            {global, orders, UserId},
            OrdersPid,
            #{tags => [orders, UserId, user_service]}
        },
        {
            {global, risk, UserId},
            RiskPid,
            #{tags => [risk, UserId, user_service]}
        }
    ]),
    
    {ok, Entries}.

%% Get all services for a user
get_user_services(UserId) ->
    orka:entries_by_tag(UserId).

%% Get specific service
get_portfolio(UserId) ->
    case orka:lookup({global, portfolio, UserId}) of
        {ok, {_K, PortfolioPid, _M}} -> {ok, PortfolioPid};
        not_found -> {error, not_found}
    end.

%% Cleanup all user services
shutdown_user(UserId) ->
    UserServices = orka:entries_by_tag(UserId),
    lists:foreach(fun({_K, Pid, _M}) ->
        Pid ! {shutdown, normal}
    end, UserServices).
```

**Benefits**: Atomic registration, easy cleanup via tags

---

### Pattern 4: Query by Capacity (Load Balancing)

Find workers with available capacity and distribute work.

```erlang
%% translator_pool.erl
-module(translator_pool).

-export([translate_with_load_balance/2, worker_available/1]).

%% Find least-loaded translator
translate_with_load_balance(Text, MinCapacity) ->
    case find_available_translator(MinCapacity) of
        {ok, {_K, TranslatorPid, _M}} ->
            call_translator(TranslatorPid, Text);
        not_found ->
            {error, no_translator_available}
    end.

%% Find translator with available capacity
find_available_translator(MinCapacity) ->
    %% Get all translators
    AllTranslators = orka:entries_by_type(service),
    
    %% Filter to translators with tag
    TranslatorEntries = lists:filter(fun(E) ->
        {_K, _P, Meta} = E,
        Tags = maps:get(tags, Meta, []),
        lists:member(translator, Tags)
    end, AllTranslators),
    
    %% Sort by capacity and pick highest available
    Sorted = lists:sort(fun({_K1, _P1, M1}, {_K2, _P2, M2}) ->
        Cap1 = maps:get(capacity, maps:get(properties, M1, #{}), 0),
        Cap2 = maps:get(capacity, maps:get(properties, M2, #{}), 0),
        Cap1 > Cap2
    end, TranslatorEntries),
    
    case Sorted of
        [{K, P, Meta}|_] ->
            CurrentLoad = maps:get(load, maps:get(properties, Meta, #{}), 0),
            Capacity = maps:get(capacity, maps:get(properties, Meta, #{}), 0),
            Available = Capacity - CurrentLoad,
            case Available >= MinCapacity of
                true -> {ok, {K, P, Meta}};
                false -> not_found
            end;
        [] -> not_found
    end.

%% Check if worker is available
worker_available(WorkerId) ->
    case orka:lookup_alive({global, worker, WorkerId}) of
        {ok, {_K, Pid, _M}} -> {ok, Pid};
        not_found -> {error, not_found}
    end.

call_translator(Pid, Text) ->
    try
        gen_server:call(Pid, {translate, Text}, 5000)
    catch
        _:_ -> {error, translator_error}
    end.
```

**Benefits**: Dynamic load balancing without manual worker management

---

## Service Registration Patterns

### Registering Global Services

Services available across the node.

```erlang
%% Global service pattern
register_global_service(ServiceName, Metadata) ->
    Key = {global, service, ServiceName},
    orka:register(Key, self(), Metadata).

%% Lookup global service
get_global_service(ServiceName) ->
    Key = {global, service, ServiceName},
    case orka:lookup(Key) of
        {ok, {_K, Pid, _M}} -> {ok, Pid};
        not_found -> {error, not_found}
    end.

%% Example usage
-module(auth_service).
-behaviour(gen_server).

init([]) ->
    ok = register_global_service(
        auth,
        #{tags => [service, auth, online]}
    ),
    {ok, #state{}}.
```

---

### Per-Type Services

Register services by type for categorization.

```erlang
%% Services organized by type
register_database(Name, Host, Port) ->
    Key = {global, database, Name},
    orka:register(
        Key,
        self(),
        #{
            tags => [database, online],
            properties => #{
                host => Host,
                port => Port,
                type => sql
            }
        }
    ).

%% Get all databases
get_all_databases() ->
    orka:entries_by_type(database).

%% Get databases in specific region
get_databases_by_property(Host) ->
    Databases = orka:entries_by_type(database),
    lists:filter(fun({_K, _P, Meta}) ->
        DbHost = maps:get(host, maps:get(properties, Meta, #{}), none),
        DbHost =:= Host
    end, Databases).
```

---

## Startup Coordination

### Blocking on Critical Dependencies

Wait for required services before proceeding.

```erlang
%% app_sup.erl - Application supervisor
-module(app_sup).
-behaviour(supervisor).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    %% Start critical services first
    ServiceSpec = {
        service_pool,
        {service_pool, start_link, []},
        permanent,
        5000,
        supervisor,
        [service_pool]
    },
    
    {ok, {{one_for_one, 10, 60}, [ServiceSpec]}}.

%% app_start.erl - Startup coordinator
-module(app_start).

%% Wait for all required services
ensure_ready() ->
    try
        % Wait for database (30 second timeout)
        {ok, {_K, DbPid, _M}} = 
            orka:await({global, service, database}, 30000),
        io:format("Database ready: ~p~n", [DbPid]),
        
        %% Wait for cache (30 second timeout)
        {ok, {_K, CachePid, _M}} =
            orka:await({global, service, cache}, 30000),
        io:format("Cache ready: ~p~n", [CachePid]),
        
        ok
    catch
        error:timeout ->
            io:format("Startup timeout - critical service not available~n"),
            init:stop()
    end.
```

---

### Non-Blocking Optional Dependencies

Service works with or without optional features.

```erlang
%% notification_service.erl
-module(notification_service).
-behaviour(gen_server).

init([]) ->
    %% Subscribe to optional SMS provider (don't block)
    {ok, _Ref} = orka:subscribe({global, service, sms_provider}),
    
    {ok, #state{sms_available = false}}.

%% Receive notification when SMS provider registers
handle_info({orka_registered, {global, service, sms_provider}, {_K, SmsPid, _M}}, State) ->
    io:format("SMS provider available: ~p~n", [SmsPid]),
    {noreply, State#state{sms_available = true, sms_pid = SmsPid}};

handle_info({orka_registered, _, _}, State) ->
    {noreply, State}.

%% Send notification (uses SMS if available, falls back to email)
handle_call({notify, Phone, Message}, _From, State) ->
    Result = case State#state.sms_available of
        true ->
            send_sms(State#state.sms_pid, Phone, Message);
        false ->
            send_email_fallback(Phone, Message)
    end,
    {reply, Result, State}.
```

---

### Multi-Service Coordination

Coordinate multiple dependent services.

```erlang
%% order_service.erl
-module(order_service).
-behaviour(gen_server).

init([]) ->
    %% Wait for all required services
    await_all_services(),
    {ok, #state{}}.

await_all_services() ->
    Services = [
        {global, service, database},
        {global, service, inventory},
        {global, service, payment},
        {global, service, shipping}
    ],
    
    lists:foreach(fun(Key) ->
        case orka:await(Key, 30000) of
            {ok, {_K, Pid, _M}} ->
                io:format("Service ~p ready: ~p~n", [Key, Pid]);
            timeout ->
                error({service_timeout, Key})
        end
    end, Services),
    
    ok.
```

---

## Singleton Services

Ensure only one instance of a critical service.

```erlang
%% database_connection_manager.erl
-module(database_connection_manager).
-behaviour(gen_server).

start_link() ->
    gen_server:start_link(?MODULE, [], []).

init([]) ->
    %% Register as singleton - fails if another instance exists
    case orka:register_single(
        {global, service, db_manager},
        #{tags => [service, database, critical]}
    ) of
        {ok, {_K, _P, _M}} ->
            io:format("Database manager started~n"),
            {ok, #state{connections = []}};
        {error, {already_registered_under_key, ExistingKey}} ->
            io:format("Database manager already running under ~p~n", [ExistingKey]),
            ignore;  %% Don't start this instance
        {error, Reason} ->
            {stop, Reason}
    end.

handle_call({get_connection, DbName}, _From, State) ->
    %% Manage connections
    {reply, {ok, connection}, State}.
```

---

## Load-Based Distribution

### Capacity-Based Load Balancing

Distribute work based on worker capacity.

```erlang
%% work_distributor.erl
-module(work_distributor).

%% Find worker with minimum load
find_best_worker(MinCapacity) ->
    Workers = orka:entries_by_type(worker),
    
    case lists:sort(fun compare_worker_load/2, Workers) of
        [] ->
            {error, no_workers};
        [{K, P, M}|_] ->
            CurrentLoad = maps:get(current_load, 
                maps:get(properties, M, #{}), 0),
            MaxCapacity = maps:get(capacity,
                maps:get(properties, M, #{}), 0),
            
            Available = MaxCapacity - CurrentLoad,
            case Available >= MinCapacity of
                true -> {ok, {K, P, M}};
                false -> {error, insufficient_capacity}
            end
    end.

%% Compare workers by available capacity
compare_worker_load({_K1, _P1, M1}, {_K2, _P2, M2}) ->
    Props1 = maps:get(properties, M1, #{}),
    Props2 = maps:get(properties, M2, #{}),
    
    Load1 = maps:get(current_load, Props1, 0),
    Cap1 = maps:get(capacity, Props1, 0),
    Available1 = Cap1 - Load1,
    
    Load2 = maps:get(current_load, Props2, 0),
    Cap2 = maps:get(capacity, Props2, 0),
    Available2 = Cap2 - Load2,
    
    Available1 > Available2.

%% Distribute work
distribute_work(Items) ->
    lists:map(fun(Item) ->
        case find_best_worker(1) of
            {ok, {_K, WorkerPid, _M}} ->
                WorkerPid ! {process_item, Item},
                {ok, WorkerPid};
            {error, Reason} ->
                {error, Reason}
        end
    end, Items).
```

---

## Health Monitoring

### View System Health Status

Monitor registry and service health.

```erlang
%% health_monitor.erl
-module(health_monitor).

%% Get overall health status
system_health() ->
    TotalServices = orka:count(),
    OnlineCount = orka:count_by_tag(online),
    CriticalCount = orka:count_by_tag(critical),
    
    Health = case TotalServices of
        0 -> down;
        _ when OnlineCount < CriticalCount -> degraded;
        _ -> healthy
    end,
    
    #{
        total_services => TotalServices,
        online => OnlineCount,
        critical => CriticalCount,
        health => Health,
        uptime_ratio => OnlineCount / TotalServices
    }.

%% Monitor service health by type
health_by_type(Type) ->
    Entries = orka:entries_by_type(Type),
    
    Healthy = lists:filter(fun({_K, Pid, _M}) ->
        is_process_alive(Pid)
    end, Entries),
    
    #{
        type => Type,
        total => length(Entries),
        healthy => length(Healthy),
        ratio => length(Healthy) / max(1, length(Entries))
    }.

%% Find unhealthy services
unhealthy_services() ->
    AllEntries = orka:entries(),
    
    lists:filter(fun({_K, Pid, Meta}) ->
        IsAlive = is_process_alive(Pid),
        Tags = maps:get(tags, Meta, []),
        HasOnlineTag = lists:member(online, Tags),
        
        %% Unhealthy = marked as online but not alive
        HasOnlineTag andalso (not IsAlive)
    end, AllEntries).

%% Capacity report
capacity_report() ->
    AllEntries = orka:entries_by_type(worker),
    
    lists:map(fun({_K, _P, Meta}) ->
        Props = maps:get(properties, Meta, #{}),
        Capacity = maps:get(capacity, Props, 0),
        CurrentLoad = maps:get(current_load, Props, 0),
        
        #{
            capacity => Capacity,
            load => CurrentLoad,
            available => Capacity - CurrentLoad,
            utilization => CurrentLoad / max(1, Capacity)
        }
    end, AllEntries).
```

---

## Complete Application Example

### Trading Platform

Multi-service application with user portfolios, orders, risk management.

```erlang
%% trading_app.erl - Application module
-module(trading_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    %% Start the main supervisor
    {ok, _} = application:ensure_all_started(orka),
    trading_sup:start_link().

stop(_State) ->
    ok.

%% trading_sup.erl - Main supervisor
-module(trading_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    %% Start core services
    Services = [
        {database_server, {database_server, start_link, []},
         permanent, 5000, worker, [database_server]},
        {risk_engine, {risk_engine, start_link, []},
         permanent, 5000, worker, [risk_engine]},
        {order_handler, {order_handler, start_link, []},
         permanent, 5000, worker, [order_handler]}
    ],
    
    {ok, {{one_for_one, 10, 60}, Services}}.

%% user_workspace_sup.erl - Per-user supervisor
-module(user_workspace_sup).
-behaviour(supervisor_bridge).

start_link(UserId) ->
    supervisor_bridge:start_link(?MODULE, [UserId]).

init([UserId]) ->
    %% Start user-specific services
    io:format("Starting services for user: ~p~n", [UserId]),
    
    Processes = [
        {portfolio_server, {portfolio_server, start_link, [UserId]}, temporary},
        {order_server, {order_server, start_link, [UserId]}, temporary},
        {risk_monitor, {risk_monitor, start_link, [UserId]}, temporary}
    ],
    
    %% Start all processes
    StartedPids = [{Module, startproce(startModule, StartArgs)} ||
        {_, {Module, StartFunc, StartArgs}, _} <- Processes],
    
    %% Register all atomically
    Entries = [{
        {global, Type, UserId},
        Pid,
        #{tags => [Type, UserId, user_service]}
    } || {Type, Pid} <- StartedPids],
    
    {ok, _} = orka:register_batch(Entries),
    
    %% Keep supervisor running
    {ok, {{one_for_one, 10, 60}, [P || {_, P} <- StartedPids]}}.

%% Example service: portfolio_server
-module(portfolio_server).
-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3]).

start_link(UserId) ->
    gen_server:start_link(?MODULE, [UserId], []).

init([UserId]) ->
    %% Register in orka
    ok = orka:register(
        {global, portfolio, UserId},
        self(),
        #{tags => [portfolio, UserId, user_service]}
    ),
    {ok, #state{user_id = UserId, holdings = #{}}}.

handle_call({get_positions}, _From, State) ->
    {reply, {ok, State#state.holdings}, State}.

%% Client usage
get_user_portfolio(UserId) ->
    case orka:lookup({global, portfolio, UserId}) of
        {ok, {_K, PortfolioPid, _M}} ->
            gen_server:call(PortfolioPid, {get_positions});
        not_found ->
            {error, user_not_found}
    end.
```

**Key Patterns**:
- Global services (database, risk engine)
- Per-user service groups (registry)
- Atomic user workspace startup
- Lookup by user ID
- Cleanup on user logout

---

## See Also

- [../README.md](../README.md) — Project overview
- [API_Documentation.md](API_Documentation.md) — Complete API reference
- [Developer_Reference.md](Developer_Reference.md) — Design and architecture
- [usage_patterns.md](usage_patterns.md) — 8 fundamental patterns
