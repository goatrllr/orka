# Orka Property System Examples

The Orka process registry supports arbitrary properties that can be registered and queried across multiple processes. Properties enable flexible, searchable metadata without modifying the core registry structure. Unlike tags which are boolean markers, properties store actual values that can be compared and analyzed.

## Key Concepts

- **Properties**: Arbitrary values (numbers, strings, atoms, maps, etc.) associated with registered processes
- **Property Names**: Atom identifiers for the property (e.g., `capacity`, `region`, `status`)
- **Property Values**: Any Erlang term (e.g., `100`, `"us-west"`, `ok`, `{lat, 40.7128}`)
- **Multiple Instances**: Multiple processes can register the same property value for load distribution and failover

## API Overview

```erlang
%% Register a property value for a process
orka:register_property(Key, Pid, #{property => Name, value => Value}).

%% Find all entries with a specific property value
orka:find_by_property(PropertyName, PropertyValue).

%% Find entries with a property value filtered by type
orka:find_by_property(Type, PropertyName, PropertyValue).

%% Count entries with a specific property value
orka:count_by_property(PropertyName, PropertyValue).

%% Get distribution of values for a property
orka:property_stats(Type, PropertyName).
```

Note: property lookups match values by exact Erlang term equality. For example, lists, maps, and tuples must match exactly the stored term to be found. Use `find_by_property(Type, PropertyName, Value)` when you need to restrict the search to a specific key `Type` (the second element of the `{Scope, Type, Name}` key tuple). If you need more flexible matching (partial matches, ranges, or fuzzy comparisons), perform client-side filtering after retrieving candidates from the index.

---

## Use Case 1: Load Balancing with Capacity

Distribute work across multiple translator instances based on their current capacity. Services can register their available capacity as a property and clients can query for instances with sufficient capacity.

### Setup

```erlang
%% Register translator instances with capacity
TranslatorPid1 = start_translator_service(1),
TranslatorPid2 = start_translator_service(2),
TranslatorPid3 = start_translator_service(3),

orka:register({global, service, translator_1}, TranslatorPid1, 
    #{tags => [service, online, translator]}),
orka:register_property({global, service, translator_1}, TranslatorPid1, 
    #{property => capacity, value => 100}).

orka:register({global, service, translator_2}, TranslatorPid2, 
    #{tags => [service, online, translator]}),
orka:register_property({global, service, translator_2}, TranslatorPid2, 
    #{property => capacity, value => 150}).

orka:register({global, service, translator_3}, TranslatorPid3, 
    #{tags => [service, online, translator]}),
orka:register_property({global, service, translator_3}, TranslatorPid3, 
    #{property => capacity, value => 80}).
```

### Queries

```erlang
%% Find instances with capacity 150
orka:find_by_property(service, capacity, 150).
%% Result: [{{global, service, translator_2}, <0.234.0>, {...}}]

%% Get capacity distribution
orka:property_stats(service, capacity).
%% Result: #{100 => 1, 150 => 1, 80 => 1}

%% Count instances with specific capacity
orka:count_by_property(capacity, 100).
%% Result: 1
```

### Client Pattern

```erlang
%% Client chooses translator with sufficient capacity
select_translator(RequiredCapacity) ->
    % In a real system, you'd iterate through capacities
    % For simplicity, we find exact matches:
    case orka:find_by_property(service, capacity, RequiredCapacity) of
        [_|_] = Instances ->
            %% Pick randomly from available instances
            Element = rand:uniform(length(Instances)),
            {Key, Pid, _Metadata} = lists:nth(Element, Instances),
            {ok, Pid};
        [] ->
            {error, no_available_capacity}
    end.
```

---

## Use Case 2: Geographic Distribution

Route database connections to the nearest region. Database replicas register their geographic location as a property, enabling location-aware routing.

### Setup

```erlang
%% Register database replicas in different regions
DbPidWest1 = connect_db_replica("us-west-1"),
DbPidWest2 = connect_db_replica("us-west-2"),
DbPidEast = connect_db_replica("us-east-1"),
DbPidEurope = connect_db_replica("eu-central-1"),

orka:register({global, resource, db_west_1}, DbPidWest1,
    #{tags => [database, replica]}),
orka:register_property({global, resource, db_west_1}, DbPidWest1,
    #{property => region, value => "us-west"}).

orka:register({global, resource, db_west_2}, DbPidWest2,
    #{tags => [database, replica]}),
orka:register_property({global, resource, db_west_2}, DbPidWest2,
    #{property => region, value => "us-west"}).

orka:register({global, resource, db_east}, DbPidEast,
    #{tags => [database, replica]}),
orka:register_property({global, resource, db_east}, DbPidEast,
    #{property => region, value => "us-east"}).

orka:register({global, resource, db_europe}, DbPidEurope,
    #{tags => [database, replica]}),
orka:register_property({global, resource, db_europe}, DbPidEurope,
    #{property => region, value => "eu-central"}).
```

### Queries

```erlang
%% Find all replicas in a region
orka:find_by_property(resource, region, "us-west").
%% Result: [
%%     {{global, resource, db_west_1}, <0.245.0>, {...}},
%%     {{global, resource, db_west_2}, <0.246.0>, {...}}
%% ]

%% Count replicas per region
orka:property_stats(resource, region).
%% Result: #{"us-west" => 2, "us-east" => 1, "eu-central" => 1}

%% Count replicas in east
orka:count_by_property(region, "us-east").
%% Result: 1
```

### Routing Pattern

```erlang
%% Route to nearest region
get_local_db_connection(UserRegion) ->
    case orka:find_by_property(resource, region, UserRegion) of
        [_|_] = LocalReplicas ->
            %% Pick randomly from local region
            Idx = rand:uniform(length(LocalReplicas)),
            {{_Key, _Pid, _Metadata} = Entry, _} = 
                {lists:nth(Idx, LocalReplicas), ok},
            {ok, Entry};
        [] ->
            %% Fallback to any available replica
            case orka:find_by_property(resource, region, '_') of
                [] -> {error, no_replicas};
                [_|_] = AllReplicas ->
                    Idx = rand:uniform(length(AllReplicas)),
                    {ok, lists:nth(Idx, AllReplicas)}
            end
    end.
```

---

## Use Case 3: Health Monitoring

Track process health status and enable operational dashboards to monitor system state at a glance.

### Setup

```erlang
%% Register worker processes with health status
WorkerPid1 = spawn_worker(1),
WorkerPid2 = spawn_worker(2),
WorkerPid3 = spawn_worker(3),

orka:register({global, worker, w1}, WorkerPid1,
    #{tags => [worker, online]}),
orka:register_property({global, worker, w1}, WorkerPid1,
    #{property => health, value => ok}).

orka:register({global, worker, w2}, WorkerPid2,
    #{tags => [worker, online]}),
orka:register_property({global, worker, w2}, WorkerPid2,
    #{property => health, value => ok}).

orka:register({global, worker, w3}, WorkerPid3,
    #{tags => [worker, online]}),
orka:register_property({global, worker, w3}, WorkerPid3,
    #{property => health, value => warning}).

%% Later: update health status
%% When w1 becomes unhealthy, remove and re-register
orka:unregister({global, worker, w1}),
orka:register({global, worker, w1}, WorkerPid1,
    #{tags => [worker, unhealthy]}),
orka:register_property({global, worker, w1}, WorkerPid1,
    #{property => health, value => degraded}).
```

### Queries

```erlang
%% Get health distribution
orka:property_stats(worker, health).
%% Result: #{ok => 1, warning => 1, degraded => 1}

%% Count healthy workers
orka:count_by_property(health, ok).
%% Result: 1

%% Find all degraded workers
orka:find_by_property(worker, health, degraded).
%% Result: [{{global, worker, w1}, <0.251.0>, {...}}]
```

### Monitoring Pattern

```erlang
%% Dashboard query: health summary
get_health_summary() ->
    Stats = orka:property_stats(worker, health),
    TotalWorkers = orka:count_by_tag(worker),
    HealthyWorkers = maps:get(ok, Stats, 0),
    WarningWorkers = maps:get(warning, Stats, 0),
    DegradedWorkers = maps:get(degraded, Stats, 0),
    
    #{
        total => TotalWorkers,
        healthy => HealthyWorkers,
        warning => WarningWorkers,
        degraded => DegradedWorkers,
        health_percentage => (HealthyWorkers / TotalWorkers) * 100
    }.
```

---

## Use Case 4: Feature Flags and API Versions

Different service instances support different feature sets or API versions. Clients can query which instances support specific features.

### Setup

```erlang
%% Register API instances with supported features
ApiPidV1 = start_api_server(v1),
ApiPidV2 = start_api_server(v2),
ApiPidV3 = start_api_server(v3),

%% v1 API supports basic operations
orka:register({global, service, api_v1}, ApiPidV1,
    #{tags => [service, api, online]}),
orka:register_property({global, service, api_v1}, ApiPidV1,
    #{property => api_version, value => "1.0.0"}).

%% v2 API adds streaming support
orka:register({global, service, api_v2}, ApiPidV2,
    #{tags => [service, api, online]}),
orka:register_property({global, service, api_v2}, ApiPidV2,
    #{property => api_version, value => "2.0.0"}).
orka:register_property({global, service, api_v2}, ApiPidV2,
    #{property => feature, value => streaming}).

%% v3 API adds advanced features
orka:register({global, service, api_v3}, ApiPidV3,
    #{tags => [service, api, online]}),
orka:register_property({global, service, api_v3}, ApiPidV3,
    #{property => api_version, value => "3.0.0"}).
orka:register_property({global, service, api_v3}, ApiPidV3,
    #{property => feature, value => streaming}).
orka:register_property({global, service, api_v3}, ApiPidV3,
    #{property => feature, value => batch_operations}).
orka:register_property({global, service, api_v3}, ApiPidV3,
    #{property => feature, value => webhooks}).
```

### Queries

```erlang
%% Find all API versions
orka:property_stats(service, api_version).
%% Result: #{"1.0.0" => 1, "2.0.0" => 1, "3.0.0" => 1}

%% Find instances supporting streaming
orka:find_by_property(service, feature, streaming).
%% Result: [
%%     {{global, service, api_v2}, <0.260.0>, {...}},
%%     {{global, service, api_v3}, <0.261.0>, {...}}
%% ]

%% Find instances supporting webhooks
orka:find_by_property(service, feature, webhooks).
%% Result: [{{global, service, api_v3}, <0.261.0>, {...}}]
```

### Feature Discovery Pattern

```erlang
%% Client discovers available features
get_capability(Feature) ->
    case orka:find_by_property(service, feature, Feature) of
        [_|_] = Instances ->
            {ok, Instances};
        [] ->
            {error, feature_not_available}
    end.

%% Route request to appropriate version
route_request(RequiredFeatures) ->
    AvailableInstances = orka:find_by_property(service, api_version, '_'),
    FilteredInstances = lists:filter(fun({_Key, _Pid, _Meta}) ->
        % Check if this instance supports all required features
        lists:all(fun(Feature) ->
            % Would need to track features per instance
            % This is a simplified example
            Feature =/= unsupported
        end, RequiredFeatures)
    end, AvailableInstances),
    
    case FilteredInstances of
        [_|_] -> 
            Idx = rand:uniform(length(FilteredInstances)),
            {ok, lists:nth(Idx, FilteredInstances)};
        [] ->
            {error, no_instance_with_features}
    end.
```

---

## Use Case 5: User Sessions and Device Tracking

Track multiple concurrent sessions per user with device type information for routing login requests to appropriate handlers.

### Setup

```erlang
%% User "alice@example.com" has three concurrent sessions
AliceWeb = spawn_session_handler(alice, web),
AliceMobile = spawn_session_handler(alice, mobile),
AliceDesktop = spawn_session_handler(alice, desktop),

orka:register({user, "alice@example.com", session_1}, AliceWeb,
    #{tags => [session, user, alice, online]}),
orka:register_property({user, "alice@example.com", session_1}, AliceWeb,
    #{property => device_type, value => web}).

orka:register({user, "alice@example.com", session_2}, AliceMobile,
    #{tags => [session, user, alice, online]}),
orka:register_property({user, "alice@example.com", session_2}, AliceMobile,
    #{property => device_type, value => mobile}).

orka:register({user, "alice@example.com", session_3}, AliceDesktop,
    #{tags => [session, user, alice, online]}),
orka:register_property({user, "alice@example.com", session_3}, AliceDesktop,
    #{property => device_type, value => desktop}).

%% User "bob@example.com" has one session
BobMobile = spawn_session_handler(bob, mobile),
orka:register({user, "bob@example.com", session_1}, BobMobile,
    #{tags => [session, user, bob, online]}),
orka:register_property({user, "bob@example.com", session_1}, BobMobile,
    #{property => device_type, value => mobile}).
```

### Queries

```erlang
%% Find all web sessions (send web-specific notifications)
orka:find_by_property(device_type, web).
%% Result: [{{user, "alice@example.com", session_1}, <0.280.0>, {...}}]

%% Find all mobile sessions (send mobile-optimized notifications)
orka:find_by_property(device_type, mobile).
%% Result: [
%%     {{user, "alice@example.com", session_2}, <0.281.0>, {...}},
%%     {{user, "bob@example.com", session_1}, <0.282.0>, {...}}
%% ]

%% Get device distribution across all sessions
orka:property_stats(session, device_type).
%% Result: #{web => 1, mobile => 2, desktop => 1}
```

### Notification Pattern

```erlang
%% Send device-specific notifications
send_notification_to_devices(UserId, Devices, Message) ->
    lists:foreach(fun(DeviceType) ->
        case orka:find_by_property(device_type, DeviceType) of
            [_|_] = Sessions ->
                lists:foreach(fun({{_User, _UserId, _SessionId}, SessionPid, _Meta}) ->
                    SessionPid ! {notification, DeviceType, Message}
                end, Sessions);
            [] ->
                ok
        end
    end, Devices).

%% Example: send notification to mobile devices only
notify_mobile_users(Message) ->
    send_notification_to_devices(any_user, [mobile], Message).
```

---

## Use Case 6: Resource Pool Management

Track connection counts and resource utilization per pool for intelligent connection routing and pool management.

### Setup

```erlang
%% Database connection pool management
Pool1Pid = start_connection_pool(pool_1, 100),
Pool2Pid = start_connection_pool(pool_2, 150),
Pool3Pid = start_connection_pool(pool_3, 75),

orka:register({global, pool, db_pool_1}, Pool1Pid,
    #{tags => [resource, connection_pool, database]}),
orka:register_property({global, pool, db_pool_1}, Pool1Pid,
    #{property => max_connections, value => 100}).
orka:register_property({global, pool, db_pool_1}, Pool1Pid,
    #{property => active_connections, value => 45}).

orka:register({global, pool, db_pool_2}, Pool2Pid,
    #{tags => [resource, connection_pool, database]}),
orka:register_property({global, pool, db_pool_2}, Pool2Pid,
    #{property => max_connections, value => 150}).
orka:register_property({global, pool, db_pool_2}, Pool2Pid,
    #{property => active_connections, value => 148}).

orka:register({global, pool, db_pool_3}, Pool3Pid,
    #{tags => [resource, connection_pool, database]}),
orka:register_property({global, pool, db_pool_3}, Pool3Pid,
    #{property => max_connections, value => 75}).
orka:register_property({global, pool, db_pool_3}, Pool3Pid,
    #{property => active_connections, value => 12}).
```

### Queries

```erlang
%% Find pools with specific active connection count
orka:find_by_property(pool, active_connections, 45).
%% Result: [{{global, pool, db_pool_1}, <0.310.0>, {...}}]

%% Get distribution of max connections across pools
orka:property_stats(pool, max_connections).
%% Result: #{100 => 1, 150 => 1, 75 => 1}

%% Find pools with specific capacity
orka:find_by_property(pool, max_connections, 150).
%% Result: [{{global, pool, db_pool_2}, <0.311.0>, {...}}]

%% Count pools
orka:count_by_property(max_connections, 100).
%% Result: 1
```

### Connection Routing Pattern

```erlang
%% Get least loaded pool
get_least_loaded_pool() ->
    Pools = orka:lookup_all(),
    FilteredPools = [P || P <- Pools, 
        is_pool_entry(P)],
    
    LeastLoaded = lists:min_by(fun({_Key, _Pid, Meta}) ->
        maps:get(active_connections, Meta, 0)
    end, FilteredPools),
    
    {ok, LeastLoaded}.

%% Check pool availability
get_available_pools(MinCapacity) ->
    Pools = orka:lookup_all(),
    lists:filter(fun({_Key, _Pid, Meta}) ->
        MaxConn = maps:get(max_connections, Meta, 0),
        Active = maps:get(active_connections, Meta, 0),
        Available = MaxConn - Active,
        Available >= MinCapacity
    end, Pools).

%% Check if entry is a pool
is_pool_entry({Key, _Pid, _Meta}) ->
    is_tuple(Key) andalso size(Key) >= 2 andalso element(1, Key) =:= global.
```

---

## Best Practices

1. **Atomicity**: Properties should be registered immediately after process registration to maintain consistency
2. **Cleanup**: Properties are automatically cleaned up when the process crashes or is unregistered
3. **Type Safety**: Use consistent atom names for property names (e.g., always `capacity`, not `cap` or `cap_limit`)
4. **Documentation**: Document what property values are valid for each property name
5. **Performance**: Use `find_by_property/2` for broad queries; use `find_by_property/3` when filtering by type
6. **Monitoring**: Use `property_stats/2` for operational dashboards and health checks
7. **Updates**: When properties change, consider unregistering and re-registering or implement property update API

## Future Enhancements

- **Property Updates**: Add `update_property/3` to modify property values without re-registration
- **Multi-Value Properties**: Support multiple values per property per process
- **Indexed Queries**: Range queries (e.g., capacity >= 100)
- **Distributed Properties**: Extend to syn-based distributed registry for cluster-wide property queries
