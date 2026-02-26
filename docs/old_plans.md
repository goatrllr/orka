## What additional features or refinements would you like to add? Some possibilities:

Property updates - update_property/3 to modify values without re-registration
Metadata updates - Better ways to update metadata without losing tags/properties
Batch operations - Register multiple processes or properties at once
Query builders - Higher-level query helpers (range queries, boolean combinations)
Persistence - Snapshot/restore functionality for crash recovery
Metrics/monitoring - Built-in stats on registry size, operation counts
Documentation refactoring - Consolidate all examples and patterns
Performance benchmarks - Compare against gproc or other registries
Distributed support prep - Design for syn integration



will this singleton pattern allows resource injection pattern, so that i can request the db service by name and if it's not registered it will start be registered, or if already registered, return the "entry" (the starting of a non-started service to be handled elsewhere)

Yes, absolutely! This is a perfect use case for the singleton pattern. You can implement a lazy initialization with resource injection pattern. Let me show you how:

```erlang
%% Resource injection pattern with singleton
get_or_start_db_service(ServiceName) ->
    Key = {global, service, ServiceName},
    case orka:lookup(Key) of
        {ok, Entry} ->
            %% Already registered, return it
            {ok, Entry};
        not_found ->
            %% Not registered, start it and register as singleton
            case start_db_service(ServiceName) of
                {ok, Pid} ->
                    case orka:register_single(Key, Pid, #{
                        tags => [service, database, critical],
                        properties => #{service_name => ServiceName}
                    }) of
                        {ok, Entry} -> {ok, Entry};
                        {error, {already_registered_under_key, _}} ->
                            %% Race condition: another process registered it first
                            orka:lookup(Key)
                    end;
                {error, Reason} ->
                    {error, {start_failed, Reason}}
            end
    end.

%% Usage
case get_or_start_db_service(primary_db) of
    {ok, {Key, Pid, Metadata}} ->
        %% Service is now registered and running
        db_query(Pid, "SELECT * FROM users");
    {error, Reason} ->
        handle_error(Reason)
end.
```
This gives you several advantages:

1. Lazy Initialization

Services only start when first requested
No startup overhead for unused services
Perfect for microservices architectures
2. Singleton Safety

Once started, only ONE instance exists
Re-requesting the same service returns the existing one
Race condition safe (handled by the already_registered_under_key case)
3. Entry-Based Routing

The Entry = {Key, Pid, Metadata} contains everything you need
You get the canonical key, the running Pid, and metadata
Can be passed to other modules/functions
4. Graceful Degradation

If service startup fails, error is returned
If race condition occurs, the winner's registration is used
No orphaned processes

for lazy initialization with get-or-start, that logic belongs in the service module itself, not orka:
```erlang
%% In db_service module
-module(db_service).

%% Get existing or start new
get_connection(ServiceName) ->
    Key = {global, service, ServiceName},
    case orka:lookup(Key) of
        {ok, {_K, Pid, _Meta}} ->
            {ok, Pid};
        not_found ->
            %% Start and register atomically
            case orka:register_with(Key, #{tags => [database, service]}, 
                                   {?MODULE, start_link, [ServiceName]}) of
                {ok, Pid} -> {ok, Pid};
                {error, Reason} -> {error, Reason}
            end
    end.
```

For singleton pattern, the service would just use register_single instead:
```erlang
get_connection(ServiceName) ->
    Key = {global, service, ServiceName},
    case orka:lookup(Key) of
        {ok, {_K, Pid, _Meta}} -> {ok, Pid};
        not_found ->
            case orka:register_with(Key, #{tags => [database, service]},
                                   {?MODULE, start_link, [ServiceName]}) of
                {ok, Pid} ->
                    %% Register as singleton after successful start
                    orka:register_single(Key, Pid, #{tags => [database, service]}),
                    {ok, Pid};
                {error, Reason} -> {error, Reason}
            end
    end.
```


Counter Service Using Properties
```erlang
%% counter_service.erl
-module(counter_service).
-export([start_link/0]).
-export([get/1, increment/1, decrement/1, set/2]).

start_link() ->
    Pid = spawn_link(fun init/0),
    {ok, Pid}.

init() ->
    %% Register this counter service
    Key = {global, service, counter},
    orka:register_single(Key, self(), #{
        tags => [service, counter, system],
        properties => #{}
    }),
    loop(#{}).

loop(Counters) ->
    receive
        {get, Name, From} ->
            Value = maps:get(Name, Counters, 0),
            From ! {ok, Value},
            loop(Counters);
        
        {increment, Name, From} ->
            NewValue = maps:get(Name, Counters, 0) + 1,
            UpdatedCounters = maps:put(Name, NewValue, Counters),
            %% Register property with new value
            orka:register_property({global, counter, Name}, self(), #{
                property => Name,
                value => NewValue
            }),
            From ! {ok, NewValue},
            loop(UpdatedCounters);
        
        {decrement, Name, From} ->
            NewValue = max(0, maps:get(Name, Counters, 0) - 1),
            UpdatedCounters = maps:put(Name, NewValue, Counters),
            orka:register_property({global, counter, Name}, self(), #{
                property => Name,
                value => NewValue
            }),
            From ! {ok, NewValue},
            loop(UpdatedCounters);
        
        {set, Name, NewValue, From} ->
            UpdatedCounters = maps:put(Name, NewValue, Counters),
            orka:register_property({global, counter, Name}, self(), #{
                property => Name,
                value => NewValue
            }),
            From ! {ok, NewValue},
            loop(UpdatedCounters)
    end.

%% Client API
get(CounterName) ->
    call({get, CounterName}).

increment(CounterName) ->
    call({increment, CounterName}).

decrement(CounterName) ->
    call({decrement, CounterName}).

set(CounterName, Value) ->
    call({set, CounterName, Value}).

call(Request) ->
    case orka:lookup({global, service, counter}) of
        {ok, {_Key, CounterPid, _Meta}} ->
            CounterPid ! {Request, self()},
            receive
                {ok, Result} -> {ok, Result}
            after 5000 -> {error, timeout}
            end;
        not_found ->
            {error, counter_service_not_found}
    end.
```
Usage Examples
```erlang
%% Start the counter service
{ok, _CounterPid} = counter_service:start_link().

%% Increment a counter
counter_service:increment(request_count).
%% Result: {ok, 1}

counter_service:increment(request_count).
%% Result: {ok, 2}

%% Set a counter
counter_service:set(active_users, 10).
%% Result: {ok, 10}

%% Get current value
counter_service:get(request_count).
%% Result: {ok, 2}

%% Query via orka (eventually consistent view)
orka:find_by_property(counter, request_count, 2).
%% Result: [{{global, counter, request_count}, <0.123.0>, {...}}]

%% Get all counter values
orka:property_stats(request_count, counter).
%% Result: #{2 => 1}
```
Pros of Property-Based Counters
✓ Queryable — Can find/filter by counter value via orca
✓ Distributed-ready — Properties will work with syn when you add clustering
✓ Observable — Operational visibility via property_stats/2
✓ Simple — No external dependencies, all in-process
✓ Low memory — Store counters in properties index for fast lookup
✓ Good for dashboards — Query counter distribution across processes

Cons / Limitations
✗ Not atomic for reads — Each get requires process call, property in ETS may be stale
✗ Not high-frequency — Each increment = register_property call (ETS write, index update)
✗ No batch operations — Can't increment multiple counters atomically
✗ Ordering — No guarantees on order of concurrent increments
✗ No persistence — Counters lost on service restart

When This Approach Works Well
```erlang
%% Low-frequency metrics (good fit)
counter_service:increment(daily_active_users).     % Once per user session
counter_service:increment(api_errors_today).       % Few per minute
counter_service:set(system_load_percent, 45).      % Once per second

%% High-frequency metrics (poor fit)
counter_service:increment(http_requests).          % Thousands per second ✗
counter_service:increment(bytes_processed).        % Continuous ✗
```
Better Alternative for High-Frequency
For very high-frequency counters, keep them in-process and periodically register via properties:
```erlang
%% In your service process
loop(State = #{counter => Counter}) ->
    receive
        {increment, Name} ->
            NewCounter = Counter + 1,
            NewState = State#{counter => NewCounter},
            
            %% Register property periodically (e.g., every 1000 increments)
            case NewCounter rem 1000 of
                0 ->
                    orka:register_property({global, service, my_service}, self(), #{
                        property => request_count,
                        value => NewCounter
                    });
                _ ->
                    ok
            end,
            loop(NewState);
        ...
    end.
```
Summary
Yes, property-based counters work well for:

System metrics that change slowly (< 100/second)
Operational dashboards and monitoring
Counts you want to query/filter alongside other orka data
Anything that doesn't need microsecond accuracy
Use gproc-style counters instead for:

High-frequency metrics (> 1000/second)
Atomic increment/decrement operations
Metrics that must survive process restarts
Global cluster-wide counters
The property-based approach is elegant for moderate-frequency metrics because it gives you searchability and observability while keeping orka focused on process registration.


Services can implement their own pre-registration patterns if needed:
```erlang
%% In a service module that wants pre-registration
-module(my_service).

%% Pre-register a placeholder (process 1 managing startup)
pre_register(ServiceName) ->
    orka:register({global, service, ServiceName}, self(), #{
        tags => [service, starting],
        properties => #{status => initializing}
    }).

%% Later, when ready, update metadata
mark_ready() ->
    orka:add_tag({global, service, my_service}, ready),
    orka:remove_tag({global, service, my_service}, starting).
```

Or use a startup coordinator:
```erlang
%% Startup process waits for all services
startup_coordinator() ->
    Services = [translator, cache, database],
    Pids = lists:map(fun(Service) ->
        case orka:await({global, service, Service}, 30000) of
            {ok, {_K, Pid, _Meta}} -> Pid;
            {error, timeout} -> throw({service_timeout, Service})
        end
    end, Services),
    {ok, Pids}.