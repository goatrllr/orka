-module(orca).
-behaviour(gen_server).

%% API
-export([start_link/0]).
-export([register/2, register/3]).
-export([register_batch/1]).
-export([register_batch_with/1]).
-export([register_with/3]).
-export([register_single/2, register_single/3]).
-export([unregister/1]).
-export([await/2, subscribe/1, unsubscribe/1]).
-export([lookup/1]).
-export([lookup_all/0]).
-export([add_tag/2, remove_tag/2]).
-export([update_metadata/2]).
-export([entries_by_type/1]).
-export([entries_by_tag/1]).
-export([count_by_type/1]).
-export([count_by_tag/1]).
-export([register_property/3]).
-export([find_by_property/2, find_by_property/3]).
-export([count_by_property/2]).
-export([property_stats/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include_lib("stdlib/include/ms_transform.hrl").
-compile({parse_transform, ms_transform}).

-define(REGISTRY_TABLE, orca_table).
-define(TAG_INDEX_TABLE, orca_tag_index).
-define(PROPERTY_INDEX_TABLE, orca_property_index).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Suggested Key & Metadata Format
% Key Structure: {Scope, Type, Name}
%   Scope: global | local
%   Type: user | service | resource | custom
%   Name: any term identifying the entity (e.g., user ID, service name, resource ID)
%
% %% Examples:
% {global, user, "alice@example.com"}           %% User process
% {global, service, translator}                  %% Named service
% {global, resource, {db, primary}}              %% Resource with sub-type
% {local, queue, job_processor_1}                %% Local to this node
%
% Benefits:
% Scope — global (cluster-wide) or local (node-only) for future syn integration
% Type — Categorize processes (user, service, resource, worker, etc.)
% Name — Flexible identifier (atom, string, tuple, number)

% Metadata Structure: #{field1 => value1, field2 => value2, ...}
% Simple metadata (backward compatible)
% Metadata = #{
%     tags => [high_priority, translator, online, authenticated, premium],      %% Categories for querying
%     properties => #{                                    %% Custom data - any Erlang term
%         version => "1.0.2",
%         max_connections => 100,
%         status => active,
%         config => #{timeout => 5000, retries => 3},     %% Nested maps
%         location => {37.7749, -122.4194},               %% Tuples for coordinates
%         features => [streaming, batch, webhooks]        %% Lists of atoms
%     },
%     created_at => erlang:system_time(millisecond),
%     owner => "supervisor_1"
% }

% Usage Examples

% User registration (self-register)
% orca:register({global, user, "mark@example.com"}, #{
%     tags => [user, online, authenticated, premium],
%     properties => #{
%         region => "us-west",
%         subscription_level => gold,
%         preferences => #{theme => dark, notifications => enabled}
%     }
% }).

% Service registration (supervisor registers)
% orca:register({global, service, translator}, ServicePid, #{
%     tags => [service, translator, critical, multilingual],
%     properties => #{
%         version => "2.1.0",
%         languages => [en, es, fr, de],
%         capacity => 150,
%         endpoints => ["api.translator.com", "backup.translator.com"]
%     }
% }).

% Resource tracking
% orca:register({global, resource, {db, primary}}, DbPid, #{
%     tags => [resource, database, critical, replicated],
%     properties => #{
%         pool_size => 50,
%         connected_clients => 12,
%         location => {37.7749, -122.4194},  %% Geo coordinates
%         config => #{max_connections => 1000, timeout => 30000}
%     }
% }).

% Worker pool registration
% orca:register({global, worker, image_processor_1}, WorkerPid, #{
%     tags => [worker, image_processing, gpu_enabled],
%     properties => #{
%         capabilities => [resize, filter, compress],
%         performance_score => 95,
%         last_health_check => erlang:system_time(second)
%     }
% }).



%%====================================================================
%% API
%%====================================================================
%% @doc Start the registry GenServer. Called by the supervisor.
start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Register a process with a key and optional metadata.
%% Key can be any Erlang term (e.g., {UserId, ServiceName} or {{user, "Mark"}, service}).
%% Pid defaults to the calling process.
register(Key, Metadata) ->
	register(Key, self(), Metadata).

%% @doc Register a process with a key, specific Pid, and metadata.
%% Supports supervisor registration of child processes.
register(Key, Pid, Metadata) when is_pid(Pid), is_map(Metadata) ->
	gen_server:call(?MODULE, {register, Key, Pid, Metadata});
register(_Key, _Pid, _Metadata) ->
	{error, badarg}.

%% @doc Start a process using {Module, Function, Arguments} and register it atomically.
%% 
%% This function:
%% 1. Starts the process using erlang:apply(M, F, A)
%% 2. Captures the resulting Pid
%% 3. Registers it with the provided Key and Metadata
%% 4. Returns {ok, Pid} on success
%% 5. Cleans up the process if registration fails
%%
%% Metadata structure:
%% #{
%%     tags => [atom1, atom2, ...],              %% Optional: list of tags
%%     properties => #{prop1 => val1, ...},      %% Optional: custom properties
%%     ... other fields ...                       %% Any other metadata
%% }
%%
%% Returns:
%% {ok, Pid} - Process started and registered successfully
%% {ok, {Key, Pid, Metadata}} - Key already registered; existing entry returned
%% {error, Reason} - MFA application failed or registration failed
%%
%% Examples:
%%
%% %% Start and register a translator service
%% orca:register_with(
%%     {global, service, translator},
%%     #{tags => [service, translator, online],
%%       properties => #{version => "2.1.0", capacity => 100}},
%%     {translator_server, start_link, []}
%% ).
%%
%% %% Start and register a user session
%% orca:register_with(
%%     {global, user, "alice@example.com"},
%%     #{tags => [user, online],
%%       properties => #{region => "us-west"}},
%%     {user_session, start_link, ["alice@example.com"]}
%% ).
%%
%% %% Start and register a database connection pool
%% orca:register_with(
%%     {global, resource, db_pool_primary},
%%     #{tags => [resource, database, pool],
%%       properties => #{max_connections => 100, active => 0}},
%%     {db_pool, start_link, [primary, [{max_size, 100}]]}
%% ).
%%
%% Use cases:
%% - Atomic process startup and registration (no race conditions)
%% - Supervisor dynamic child specifications
%% - Ensures process registration always succeeds if process starts
%% - Automatic cleanup: if registration fails, process is terminated
register_with(Key, Metadata, {M, F, A}) when is_map(Metadata) ->
	gen_server:call(?MODULE, {register_with, Key, Metadata, M, F, A});
register_with(_Key, _Metadata, _MFA) ->
	{error, badarg}.

%% @doc Register a process with singleton constraint (one key per Pid).
%% The process can only be registered under one key at a time.
%% If already registered, returns the existing entry.
%%
%% Metadata structure:
%% #{
%%     tags => [atom1, atom2, ...],              %% Optional: list of tags
%%     properties => #{prop1 => val1, ...},      %% Optional: custom properties
%%     ... other fields ...                       %% Any other metadata
%% }
%%
%% Returns:
%% {ok, {Key, Pid, Metadata}} - Registered successfully as singleton (or existing entry returned)
%%
%% Use cases:
%% - Unique service instances (only one translator service per node)
%% - Exclusive resource access (only one db connection manager)
%% - Configuration servers requiring single point of truth
%% - Distributed lock managers
%% - Event buses / message routers
%%
%% Examples:
%%
%% %% Register config server as singleton
%% orca:register_single(
%%     {global, service, config_server},
%%     #{tags => [service, config, critical],
%%       properties => #{reload_interval => 30000}}
%% ).
%%
%% %% Attempting to register same process under different key returns an error
%% orca:register_single(
%%     {global, service, app_config},
%%     ConfigPid,
%%     #{tags => [service, config]}
%% ).
%% %% Returns: {error, {already_registered_under_key, {global, service, config_server}}}
register_single(Key, Metadata) ->
	register_single(Key, self(), Metadata).

%% @doc Register a process with singleton constraint and explicit Pid.
register_single(Key, Pid, Metadata) when is_pid(Pid), is_map(Metadata) ->
	gen_server:call(?MODULE, {register_single, Key, Pid, Metadata});
register_single(_Key, _Pid, _Metadata) ->
	{error, badarg}.

%% @doc Register multiple processes in a single atomic batch call.
%%
%% Reduces GenServer call overhead when registering many processes for a single context
%% (e.g., per-user services, per-job workers). All registrations succeed or all fail.
%%
%% Input: List of {Key, Pid, Metadata} tuples
%% Returns: {ok, [Entry]} where Entry = {Key, Pid, Metadata}
%%          {error, {RegistrationFailed, [FailedKeys], [SuccessfulKeys]}} on partial failure
%%
%% The error tuple contains:
%% - RegistrationFailed: The key that failed
%% - FailedKeys: All keys from this call that failed
%% - SuccessfulKeys: All keys from this call that succeeded (will be rolled back)
%%
%% Examples:
%%
%% %% Register 5 processes for a user (from supervisor)
%% UserId = user123,
%% {ok, [PortfolioEntry, TechnicalEntry, FundamentalEntry, OrdersEntry, RiskEntry]} =
%%     orca:register_batch([
%%         {{global, portfolio, UserId}, Pid1, #{tags => [portfolio, user], properties => #{strategy => momentum}}},
%%         {{global, technical, UserId}, Pid2, #{tags => [technical, user], properties => #{indicators => [rsi, macd]}}},
%%         {{global, fundamental, UserId}, Pid3, #{tags => [fundamental, user], properties => #{sectors => [tech, finance]}}},
%%         {{global, orders, UserId}, Pid4, #{tags => [orders, user], properties => #{queue_depth => 100}}},
%%         {{global, risk, UserId}, Pid5, #{tags => [risk, user], properties => #{max_position_size => 10000}}}
%%     ]).
register_batch(Registrations) ->
	case validate_batch_registrations(Registrations) of
		ok -> gen_server:call(?MODULE, {register_batch, Registrations});
		error -> {error, badarg}
	end.

%% @doc Start multiple processes using {Module, Function, Arguments} and register them atomically.
%%
%% Input: List of {Key, Metadata, {M, F, A}} tuples
%% Returns: {ok, [Entry]} where Entry = {Key, Pid, Metadata}
%%          {error, {Reason, [FailedKeys], [SuccessfulKeys]}} on partial failure
register_batch_with(Registrations) ->
	case validate_batch_with_registrations(Registrations) of
		ok -> gen_server:call(?MODULE, {register_batch_with, Registrations});
		error -> {error, badarg}
	end.

validate_batch_registrations(Registrations) when is_list(Registrations) ->
	case lists:all(fun
		({_Key, Pid, Metadata}) when is_pid(Pid), is_map(Metadata) ->
			true;
		(_) ->
			false
	end, Registrations) of
		true -> ok;
		false -> error
	end;
validate_batch_registrations(_Registrations) ->
	error.

validate_batch_with_registrations(Registrations) when is_list(Registrations) ->
	case lists:all(fun
		({_Key, Metadata, {M, F, A}}) when is_map(Metadata), is_atom(M), is_atom(F), is_list(A) ->
			true;
		(_) ->
			false
	end, Registrations) of
		true -> ok;
		false -> error
	end;
validate_batch_with_registrations(_Registrations) ->
	error.

%% @doc Unregister a process from the registry by key.
unregister(Key) ->
	gen_server:call(?MODULE, {unregister, Key}).

%% @doc Block and wait for a key to be registered with a timeout.
%% 
%% Waits for the specified key to be registered in the registry. If the key is already
%% registered, returns immediately with the entry. If the key is not registered, blocks
%% the caller until either:
%% - The key is registered (returns {ok, {Key, Pid, Metadata}})
%% - The timeout expires (returns {error, timeout})
%%
%% Timeout is in milliseconds. A timeout of 0 returns immediately with the current state.
%% A timeout of infinity waits indefinitely.
%%
%% Examples:
%%
%% %% Wait up to 30 seconds for database service to start
%% case orca:await({global, service, database}, 30000) of
%%     {ok, {_Key, DbPid, _Meta}} -> 
%%         io:format("Database ready: ~p~n", [DbPid]);
%%     {error, timeout} -> 
%%         io:format("Database startup timeout~n", [])
%% end.
%%
%% %% Multi-service startup coordination
%% init([]) ->
%%     case orca:await({global, service, database}, 30000) of
%%         {ok, {_K, DbPid, _Meta}} -> 
%%             {ok, #state{db = DbPid}};
%%         {error, timeout} -> 
%%             {stop, database_timeout}
%%     end.
await(Key, Timeout) ->
	%% Subscribe to the key
	gen_server:call(?MODULE, {subscribe_await, Key, self(), Timeout}),
	%% Wait for notification (either {orca_registered, Key, Entry} or timeout)
	receive
		{orca_registered, Key, Entry} -> {ok, Entry};
		{orca_await_timeout, Key} -> 
			gen_server:call(?MODULE, {unsubscribe, Key, self()}),	
			{error, timeout}
	after Timeout ->
			%% Timeout occurred, unsubscribe and return error
			gen_server:call(?MODULE, {unsubscribe, Key, self()}),
			%% Drain any pending timeout message from the subscription timer.
			receive
				{orca_await_timeout, Key} -> ok
			after 0 -> ok
			end,
			{error, timeout}
	end.

%% @doc Subscribe to notifications when a key is registered.
%% 
%% Non-blocking subscription. The caller will receive a message of the form:
%%   {orca_registered, Key, {Key, Pid, Metadata}}
%% when the key is registered (either immediately if already registered, or when 
%% it is subsequently registered).
%%
%% Useful for optional dependencies or handling services that may appear at any time
%% during the application lifecycle.
%%
%% Returns ok.
%%
%% Examples:
%%
%% %% Subscribe to optional feature
%% init([]) ->
%%     orca:subscribe({global, service, cache}),
%%     {ok, #state{cache_ready = false}}.
%%
%% %% Handle notification when cache appears
%% handle_info({orca_registered, _Key, {_K, CachePid, _Meta}}, State) ->
%%     {noreply, State#state{cache_ready = true, cache = CachePid}}.
%%
%% %% Multiple optional dependencies
%% init([]) ->
%%     orca:subscribe({global, service, cache}),
%%     orca:subscribe({global, service, metrics}),
%%     {ok, #state{services = #{}}}.
subscribe(Key) ->
	gen_server:call(?MODULE, {subscribe, Key, self()}).

%% @doc Unsubscribe from key registration notifications.
%%
%% Cancels a previous subscription made with subscribe/1. If not subscribed, no-op.
%% Returns ok.
%%
%% Examples:
%%
%% %% Unsubscribe when feature is no longer needed
%% handle_cast({disable_cache}, State) ->
%%     orca:unsubscribe({global, service, cache}),
%%     {noreply, State#state{cache_ready = false}}.
unsubscribe(Key) ->
	gen_server:call(?MODULE, {unsubscribe, Key, self()}).

%% @doc Lookup a single entry by key. Returns {ok, {Key, Pid, Metadata}} or not_found.
lookup(Key) ->
	case ets:lookup(?REGISTRY_TABLE, Key) of
		[Entry] -> {ok, Entry};
		[] -> not_found
	end.

%% @doc Return all entries in the registry.
lookup_all() ->
	ets:tab2list(?REGISTRY_TABLE).

%% @doc Add a tag to a registered process.
%% Returns ok if tag was added or already present, not_found if key not registered.
add_tag(Key, Tag) ->
	gen_server:call(?MODULE, {add_tag, Key, Tag}).

%% @doc Remove a tag from a registered process.
%% Returns ok if tag was removed, {error, tag_not_found} if not present, not_found if key not registered.
remove_tag(Key, Tag) ->
	gen_server:call(?MODULE, {remove_tag, Key, Tag}).

%% @doc Update metadata for a registered process (preserves existing tags).
%% Returns ok if updated, not_found if key not registered.
update_metadata(Key, NewMetadata) when is_map(NewMetadata) ->
	gen_server:call(?MODULE, {update_metadata, Key, NewMetadata});
update_metadata(_Key, _NewMetadata) ->
	{error, badarg}.

%% @doc Find all entries by type (second element of key tuple).
%% Key format: {Scope, Type, Name}
%% Returns a list of all entries matching the specified Type.
%% 
%% Examples:
%%
%% %% Register some services
%% orca:register({global, service, translator}, TranslatorPid, #{
%%     tags => [service, translator, online],
%%     properties => #{version => "2.1.0", languages => [en, es, fr]},
%%     created_at => 1703170800000,
%%     owner => "supervisor_1"
%% }).
%%
%% orca:register({global, service, storage}, StoragePid, #{
%%     tags => [service, storage, online],
%%     properties => #{version => "1.5.0", capacity => 1000},
%%     created_at => 1703170900000,
%%     owner => "supervisor_1"
%% }).
%%
%% %% Register a user
%% orca:register({global, user, "alice@example.com"}, AlicePid, #{
%%     tags => [user, online],
%%     properties => #{region => "us-west"},
%%     created_at => 1703171000000,
%%     owner => "alice"
%% }).
%%
%% %% Find all services
%% orca:entries_by_type(service).
%% Result: [
%%     {{global, service, translator}, <0.123.0>, #{
%%         tags => [service, translator, online],
%%         properties => #{version => "2.1.0", languages => [en, es, fr]},
%%         created_at => 1703170800000,
%%         owner => "supervisor_1"
%%     }},
%%     {{global, service, storage}, <0.124.0>, #{
%%         tags => [service, storage, online],
%%         properties => #{version => "1.5.0", capacity => 1000},
%%         created_at => 1703170900000,
%%         owner => "supervisor_1"
%%     }}
%% ]
%%
%% %% Find all users
%% orca:entries_by_type(user).
%% Result: [
%%     {{global, user, "alice@example.com"}, <0.125.0>, #{
%%         tags => [user, online],
%%         properties => #{region => "us-west"},
%%         created_at => 1703171000000,
%%         owner => "alice"
%%     }}
%% ]
entries_by_type(Type) ->
	ets:select(?REGISTRY_TABLE, ets:fun2ms(fun({Key, Pid, Meta}) when 
		is_tuple(Key) andalso size(Key) >= 2 andalso element(2, Key) =:= Type 
	-> {Key, Pid, Meta} end)).

%% @doc Find all entries with a specific tag in metadata.
%% Returns entries where metadata contains tags list with the specified tag.
%% Useful for querying processes by category or status.
%% 
%% Examples:
%%
%% %% Register services with various tags
%% orca:register({global, service, translator}, TranslatorPid, #{
%%     tags => [service, translator, critical, online],
%%     properties => #{version => "2.1.0"},
%%     created_at => 1703170800000,
%%     owner => "supervisor_1"
%% }).
%%
%% orca:register({global, service, cache}, CachePid, #{
%%     tags => [service, cache, online],
%%     properties => #{version => "1.0.0"},
%%     created_at => 1703170900000,
%%     owner => "supervisor_1"
%% }).
%%
%% orca:register({global, user, "bob@example.com"}, BobPid, #{
%%     tags => [user, online],
%%     properties => #{region => "us-east"},
%%     created_at => 1703171000000,
%%     owner => "bob"
%% }).
%%
%% orca:register({global, user, "charlie@example.com"}, CharliePid, #{
%%     tags => [user, offline],
%%     properties => #{region => "eu-west"},
%%     created_at => 1703171100000,
%%     owner => "charlie"
%% }).
%%
%% %% Find all online processes
%% orca:entries_by_tag(online).
%% Result: [
%%     {{global, service, translator}, <0.123.0>, #{
%%         tags => [service, translator, critical, online],
%%         properties => #{version => "2.1.0"},
%%         created_at => 1703170800000,
%%         owner => "supervisor_1"
%%     }},
%%     {{global, service, cache}, <0.124.0>, #{
%%         tags => [service, cache, online],
%%         properties => #{version => "1.0.0"},
%%         created_at => 1703170900000,
%%         owner => "supervisor_1"
%%     }},
%%     {{global, user, "bob@example.com"}, <0.125.0>, #{
%%         tags => [user, online],
%%         properties => #{region => "us-east"},
%%         created_at => 1703171000000,
%%         owner => "bob"
%%     }}
%% ]
%%
%% %% Find all critical processes
%% orca:entries_by_tag(critical).
%% Result: [
%%     {{global, service, translator}, <0.123.0>, #{
%%         tags => [service, translator, critical, online],
%%         properties => #{version => "2.1.0"},
%%         created_at => 1703170800000,
%%         owner => "supervisor_1"
%%     }}
%% ]
%%
%% %% Find all offline users
%% orca:entries_by_tag(offline).
%% Result: [
%%     {{global, user, "charlie@example.com"}, <0.126.0>, #{
%%         tags => [user, offline],
%%         properties => #{region => "eu-west"},
%%         created_at => 1703171100000,
%%         owner => "charlie"
%%     }}
%% ]
entries_by_tag(Tag) ->
	%% Get all keys with this tag from the index
	Keys = ets:match_object(?TAG_INDEX_TABLE, {{tag, Tag}, '$1'}),
	%% Look up full entries for each key
	lists:filtermap(fun({{tag, _}, Key}) ->
		case ets:lookup(?REGISTRY_TABLE, Key) of
			[Entry] -> {true, Entry};
			[] -> false  %% Key was deleted but tag index wasn't cleaned
		end
	end, Keys).

%% @doc Count processes by type.
%% 
%% Returns the number of entries with the specified Type in the key.
%% Key format: {Scope, Type, Name}
%% 
%% Examples:
%%
%% %% Register multiple services and users (see entries_by_type/1 for setup)
%%
%% %% Count total services
%% orca:count_by_type(service).
%% Result: 2
%%
%% %% Count total users
%% orca:count_by_type(user).
%% Result: 1
%%
%% %% Count non-existent type
%% orca:count_by_type(resource).
%% Result: 0
%%
%% Use cases:
%% - Monitor how many active service instances are running
%% - Track connected user count
%% - Health check: verify minimum number of critical services registered
%%
%% Example health check:
%% check_translator_service_health() ->
%%     MinInstances = 2,
%%     case orca:count_by_type(service) >= MinInstances of
%%         true -> healthy;
%%         false -> alert_admin()
%%     end.
count_by_type(Type) ->
	ets:select_count(?REGISTRY_TABLE, ets:fun2ms(fun({Key, _Pid, _Meta}) when 
		is_tuple(Key) andalso size(Key) >= 2 andalso element(2, Key) =:= Type 
	-> true end)).

%% @doc Count processes with a specific tag.
%% 
%% Returns the number of entries that have the specified tag in their metadata.
%% 
%% Examples:
%%
%% %% Count online processes (see entries_by_tag/1 for setup)
%% orca:count_by_tag(online).
%% Result: 3
%%
%% %% Count offline processes
%% orca:count_by_tag(offline).
%% Result: 1
%%
%% %% Count critical processes
%% orca:count_by_tag(critical).
%% Result: 1
%%
%% %% Count processes with a tag that doesn't exist in registry
%% orca:count_by_tag(maintenance).
%% Result: 0
%%
%% Use cases:
%% - Monitor online/offline user count for dashboards
%% - Alert when critical service count drops below threshold
%% - Track processes in specific states (active, maintenance, degraded)
%% - Load balancing: count available instances of a service type
%%
%% Example dashboard query:
%% get_system_stats() ->
%%     #{
%%         total_users => orca:count_by_tag(user),
%%         online_users => orca:count_by_tag(online),
%%         offline_users => orca:count_by_tag(offline),
%%         critical_services => orca:count_by_tag(critical),
%%         total_services => orca:count_by_type(service)
%%     }.
%%
%% Example alert trigger:
%% check_service_availability() ->
%%     AvailableInstances = orca:count_by_tag(online),
%%     case AvailableInstances < 2 of
%%         true -> alert_ops_team("Low service availability!");
%%         false -> ok
%%     end.

count_by_tag(Tag) ->
	%% Count entries with this tag using the index
	length(ets:match_object(?TAG_INDEX_TABLE, {{tag, Tag}, '_'})).

%% @doc Register a property value for a process.
%% Properties are arbitrary values associated with registered processes.
%% Multiple processes can share the same property value (unlike tags).
%% 
%% Parameters:
%%   Key - the registry key of the process
%%   Pid - the process ID
%%   Property - map with keys: property (atom), value (any term)
%%
%% Returns ok, not_found if key not registered, or {error, Reason}.
%%
%% Examples:
%%
%% %% Register load balancer instances with capacity
%% orca:register_property({global, service, translator_1}, TranslatorPid1, 
%%     #{property => capacity, value => 100}).
%% orca:register_property({global, service, translator_2}, TranslatorPid2, 
%%     #{property => capacity, value => 150}).
%%
%% %% Register database replicas by region
%% orca:register_property({global, resource, db_1}, DbPid1, 
%%     #{property => region, value => "us-west"}).
%% orca:register_property({global, resource, db_2}, DbPid2, 
%%     #{property => region, value => "us-east"}).
%%
%% %% Register services with complex configuration
%% orca:register_property({global, service, api_gateway}, ApiPid,
%%     #{property => config, value => #{timeout => 5000, retries => 3}}).
%% orca:register_property({global, service, worker_pool}, PoolPid,
%%     #{property => capabilities, value => [image_resize, compression, filtering]}).
register_property(Key, Pid, #{property := PropName, value := PropValue}) when is_pid(Pid) ->
	gen_server:call(?MODULE, {register_property, Key, Pid, PropName, PropValue});
register_property(_Key, _Pid, _Property) ->
	{error, badarg}.

%% @doc Find all entries with a specific property value.
%% Returns entries where the property matches the given value.
%%
%% Parameters:
%%   PropertyName - atom, name of the property
%%   PropertyValue - value to match
%%
%% Returns list of {Key, Pid, Metadata} tuples.
%%
%% Examples:
%%
%% %% Find all services in us-west region
%% orca:find_by_property(region, "us-west").
%% Result: [
%%     {{global, resource, db_2}, <0.145.0>, #{region => "us-west", ...}},
%%     {{global, service, translator}, <0.123.0>, #{region => "us-west", ...}}
%% ]
%%
%% %% Find all translators with capacity over 100
%% orca:find_by_property(capacity, 150).
%% Result: [{{global, service, translator_2}, <0.124.0>, #{capacity => 150, ...}}]
%%
%% %% Find services with specific capabilities
%% orca:find_by_property(capabilities, [image_resize, compression]).
%% Result: [{{global, service, worker_pool}, <0.200.0>, #{capabilities => [image_resize, compression], ...}}]
%%
%% %% Find services with specific config
%% orca:find_by_property(config, #{timeout => 5000, retries => 3}).
%% Result: [{{global, service, api_gateway}, <0.150.0>, #{config => #{timeout => 5000, retries => 3}, ...}}]
find_by_property(PropertyName, PropertyValue) ->
	Keys = ets:match_object(?PROPERTY_INDEX_TABLE, {{property, PropertyName, PropertyValue}, '$1'}),
	lists:filtermap(fun({{property, _, _}, Key}) ->
		case ets:lookup(?REGISTRY_TABLE, Key) of
			[Entry] -> {true, Entry};
			[] -> false
		end
	end, Keys).

%% @doc Find entries with a specific property value, filtered by type.
%% Combines property and type filtering for more specific queries.
%% Filters by the second element of key tuple (e.g., Type is second element for {global, service, cache_1}).
%%
%% Parameters:
%%   Type - second element of key tuple (e.g., service, resource)
%%   PropertyName - atom, name of the property
%%   PropertyValue - value to match
%%
%% Returns list of {Key, Pid, Metadata} tuples matching both type and property.
find_by_property(Type, PropertyName, PropertyValue) ->
	Keys = ets:match_object(?PROPERTY_INDEX_TABLE, {{property, PropertyName, PropertyValue}, '$1'}),
	lists:filtermap(fun({{property, _, _}, Key}) ->
		case ets:lookup(?REGISTRY_TABLE, Key) of
				[{RegKey, _, _} = Entry] ->
					case is_tuple(RegKey) andalso size(RegKey) >= 2 andalso element(2, RegKey) =:= Type of
					true -> {true, Entry};
					false -> false
				end;
			[] -> false
		end
	end, Keys).

%% @doc Count entries with a specific property value.
%% Returns integer count of matching entries.
%%
%% Examples:
%%
%% %% Count services in production region
%% orca:count_by_property(region, "production").
%% Result: 3
%%
%% %% Count translators with specific capacity
%% orca:count_by_property(capacity, 100).
%% Result: 2
count_by_property(PropertyName, PropertyValue) ->
	length(ets:match_object(?PROPERTY_INDEX_TABLE, {{property, PropertyName, PropertyValue}, '_'})).

%% @doc Get statistics about a property across all processes.
%% Returns a map with counts for each unique value of the property.
%%
%% Parameters:
%%   Type - second element of key tuple (e.g., service, resource)
%%   PropertyName - atom, name of the property
%%
%% Returns map like #{value1 => count1, value2 => count2, ...}
%%
%% Examples:
%%
%% %% Get distribution of regions for all services
%% orca:property_stats(service, region).
%% Result: #{"us-west" => 3, "us-east" => 2, "eu-central" => 1}
%%
%% %% Get distribution of capacities for all resources
%% orca:property_stats(resource, capacity).
%% Result: #{100 => 2, 150 => 3, 200 => 1}
%%
%% %% Get distribution of supported languages across services
%% orca:property_stats(service, languages).
%% Result: {[en, es, fr] => 2, [en, de] => 1, [en, es, fr, de] => 1}
%%
%% %% Get distribution of subscription levels for users
%% orca:property_stats(user, subscription_level).
%% Result: #{gold => 5, silver => 3, bronze => 2}
property_stats(Type, PropertyName) ->
	%% Get all property index entries for this property name
	Entries = ets:match_object(?PROPERTY_INDEX_TABLE, {{property, PropertyName, '$1'}, '$2'}),
	%% Count by value
	lists:foldl(fun({{property, _, Value}, Key}, Acc) ->
		case ets:lookup(?REGISTRY_TABLE, Key) of
            [{RegKey, _Pid, _Meta}] when is_tuple(RegKey), size(RegKey) >= 2, element(2, RegKey) =:= Type ->
				maps:update_with(Value, fun(Count) -> Count + 1 end, 1, Acc);
			_ -> Acc
		end
	end, #{}, Entries).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
	%% Create a public ETS table for lock-free reads
	%% Table is named so it persists across code reloads (as long as the controller doesn't crash)
	ets:new(?REGISTRY_TABLE, [
		set,           %% type: unique keys
		public,        %% allow read access from any process
		named_table    %% allow access by name
	]),
	%% Create tag index table: {{tag, Tag}, Key} for efficient tag queries
	ets:new(?TAG_INDEX_TABLE, [
		bag,           %% multiple entries per tag
		public,        %% allow read access from any process
		named_table    %% allow access by name
	]),
	%% Create property index table: {{property, Name, Value}, Key} for efficient property queries
	ets:new(?PROPERTY_INDEX_TABLE, [
		bag,           %% multiple keys can have same property value
		public,        %% allow read access from any process
		named_table    %% allow access by name
	]),
	%% Store for tracking monitored pids -> keys mapping, subscribers, and monitor refs
	%% State is tuple: {PidSingletonMap, PidKeyMap, SubscribersMap, MonitorMap}
	%% PidSingletonMap: #{Pid => Key} for singleton constraint tracking
	%% PidKeyMap: #{Pid => [Keys]} for multi-key tracking
	%% SubscribersMap: #{Key => [Pid | {Pid, TimerRef}]} for await/subscribe notifications
	%% MonitorMap: #{Pid => MonitorRef}
	{ok, {maps:new(), maps:new(), maps:new(), maps:new()}}.

%% @doc Handle registration requests
handle_call(Msg, From, {PidSingleton, PidKeyMap, Subscribers}) ->
	%% Upgrade legacy state without MonitorMap
	handle_call(Msg, From, {PidSingleton, PidKeyMap, Subscribers, maps:new()});
handle_call({register, Key, Pid, Metadata}, _From, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}) ->
	case maps:get(Pid, PidSingleton, undefined) of
		undefined ->
			case ets:lookup(?REGISTRY_TABLE, Key) of
				%% Key not registered yet, proceed with registration
				[] ->
					do_register(Key, Pid, Metadata, {PidSingleton, PidKeyMap, Subscribers, MonitorMap});
				%% If this key was previously registered, check if the process is alive
				[{Key, ExistingPid, _ExistingMetadata} = Entry] ->
					case is_process_alive(ExistingPid) of
						true ->
							%% Process is alive, return the existing registration
							{reply, {ok, Entry}, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}};
						false ->
							%% Process is dead but entry still in ETS, clean it up and re-register
							NewState = remove_dead_pid_entries(ExistingPid, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}),
							do_register(Key, Pid, Metadata, NewState)
					end
			end;
		ExistingKey when ExistingKey =:= Key ->
			case ets:lookup(?REGISTRY_TABLE, Key) of
				[Entry] -> {reply, {ok, Entry}, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}};
				[] -> do_register(Key, Pid, Metadata, {PidSingleton, PidKeyMap, Subscribers, MonitorMap})
			end;
		ExistingKey ->
			{reply, {error, {already_registered_under_key, ExistingKey}}, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}}
	end;

%% @doc Handle batch registration - all or nothing
handle_call({register_batch, Registrations}, _From, State) ->
	register_batch_entries(Registrations, State, State, [], [], []);

%% @doc Handle batch register_with requests
handle_call({register_batch_with, Registrations}, _From, State) ->
	register_batch_with_entries(Registrations, State, State, [], [], [], []);

%% @doc Handle unregistration requests
handle_call({unregister, Key}, _From, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}) ->
	Result = case ets:lookup(?REGISTRY_TABLE, Key) of
		[{Key, Pid, _}] ->
			%% Remove from ETS
			ets:delete(?REGISTRY_TABLE, Key),
			
			%% Remove all tags for this key from tag index
			ets:match_delete(?TAG_INDEX_TABLE, {'_', Key}),
			
			%% Remove all properties for this key from property index
			ets:match_delete(?PROPERTY_INDEX_TABLE, {'_', Key}),
			
			%% Update pid->keys mapping
			NewKeyMap = maps:update_with(Pid, 
				fun(Keys) -> lists:delete(Key, Keys) end, 
				[], 
				PidKeyMap),
			
			%% Remove from singleton map only if this is the singleton key
			NewSingleton = case maps:get(Pid, PidSingleton, undefined) of
				Key -> maps:remove(Pid, PidSingleton);
				_ -> PidSingleton
			end,
			
			%% If no more keys for this pid, demonitor
			FinalMap = case maps:get(Pid, NewKeyMap, []) of
				[] -> maps:remove(Pid, NewKeyMap);
				_ -> NewKeyMap
			end,
			FinalMonitors = case maps:is_key(Pid, FinalMap) of
				true -> MonitorMap;
				false -> maybe_demonitor_pid(Pid, MonitorMap)
			end,
			
			{ok, {NewSingleton, FinalMap, Subscribers, FinalMonitors}};
		[] ->
			{not_found, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}}
	end,
	
	case Result of
		{ok, UpdatedState} -> {reply, ok, UpdatedState};
		{not_found, _} -> {reply, not_found, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}}
	end;

%% @doc Handle adding a tag
handle_call({add_tag, Key, Tag}, _From, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}) ->
	case ets:lookup(?REGISTRY_TABLE, Key) of
		[{Key, Pid, Metadata}] ->
			Tags = maps:get(tags, Metadata, []),
			case lists:member(Tag, Tags) of
				true ->
					%% Tag already exists
					% {reply, {error, tag_already_exists}, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}};
					{reply, ok, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}};
				false ->
					%% Add tag to metadata
					NewTags = [Tag | Tags],
					NewMetadata = maps:put(tags, NewTags, Metadata),
					ets:insert(?REGISTRY_TABLE, {Key, Pid, NewMetadata}),
					
					%% Add to tag index
					ets:insert(?TAG_INDEX_TABLE, {{tag, Tag}, Key}),
					
					{reply, ok, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}}
		end;
		[] ->
			{reply, not_found, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}}
	end;%% @doc Handle removing a tag
handle_call({remove_tag, Key, Tag}, _From, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}) ->
	case ets:lookup(?REGISTRY_TABLE, Key) of
		[{Key, Pid, Metadata}] ->
			Tags = maps:get(tags, Metadata, []),
			case lists:member(Tag, Tags) of
				false ->
					%% Tag doesn't exist
					{reply, {error, tag_not_found}, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}};
				true ->
					%% Remove tag from metadata
					NewTags = lists:delete(Tag, Tags),
					NewMetadata = maps:put(tags, NewTags, Metadata),
					ets:insert(?REGISTRY_TABLE, {Key, Pid, NewMetadata}),
					
					%% Remove from tag index
					ets:delete_object(?TAG_INDEX_TABLE, {{tag, Tag}, Key}),
					
					{reply, ok, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}}
		end;
		[] ->
			{reply, not_found, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}}
	end;%% @doc Handle updating metadata (preserves tags)
handle_call({update_metadata, Key, NewMetadata}, _From, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}) ->
	case ets:lookup(?REGISTRY_TABLE, Key) of
		[{Key, Pid, OldMetadata}] ->
			%% Preserve existing tags
			Tags = maps:get(tags, OldMetadata, []),
			UpdatedMetadata = normalize_tags(maps:put(tags, Tags, NewMetadata)),
			ets:insert(?REGISTRY_TABLE, {Key, Pid, UpdatedMetadata}),
			update_property_index(Key, UpdatedMetadata),
			{reply, ok, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}};
		[] ->
			{reply, not_found, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}}
	end;

handle_call({register_property, Key, Pid, PropName, PropValue}, _From, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}) ->
	case ets:lookup(?REGISTRY_TABLE, Key) of
		[{Key, RegisteredPid, Metadata}] when RegisteredPid =:= Pid ->
			%% Key exists and Pid matches, update metadata and index
			Props0 = maps:get(properties, Metadata, #{}),
			NewProps = maps:put(PropName, PropValue, Props0),
			UpdatedMetadata = maps:put(properties, NewProps, Metadata),
			ets:insert(?REGISTRY_TABLE, {Key, Pid, UpdatedMetadata}),
			update_property_index(Key, UpdatedMetadata),
			{reply, ok, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}};
		[] ->
			%% Key not found
			{reply, not_found, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}};
		[{Key, _OtherPid, _Metadata}] ->
			%% Key exists but Pid doesn't match
			{reply, {error, pid_mismatch}, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}}
	end;

handle_call({register_with, Key, Metadata, M, F, A}, _From, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}) ->
	case ets:lookup(?REGISTRY_TABLE, Key) of
		[{Key, ExistingPid, _ExistingMetadata} = Entry] ->
			case is_process_alive(ExistingPid) of
				true ->
					{reply, {ok, Entry}, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}};
				false ->
					NewState = remove_dead_pid_entries(ExistingPid, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}),
					register_with_start(Key, Metadata, M, F, A, NewState)
			end;
		[] ->
			register_with_start(Key, Metadata, M, F, A, {PidSingleton, PidKeyMap, Subscribers, MonitorMap})
	end;

handle_call({register_single, Key, Pid, Metadata}, _From, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}) ->
	%% Check if this Pid is already registered as singleton
	case maps:get(Pid, PidSingleton, undefined) of
		undefined ->
			%% Pid not registered as singleton, check if registered at all
			case maps:get(Pid, PidKeyMap, []) of
				[] ->
					%% Pid not registered, proceed with registration
					case do_register(Key, Pid, Metadata, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}) of
						{reply, Reply, {UpdatedSingleton, UpdatedKeyMap, UpdatedSubs, UpdatedMonitors}} ->
							case Reply of
								{ok, Entry} ->
									%% Add to singleton map
									NewSingleton = maps:put(Pid, Key, UpdatedSingleton),
									{reply, {ok, Entry}, {NewSingleton, UpdatedKeyMap, UpdatedSubs, UpdatedMonitors}};
								_ ->
									{reply, Reply, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}}
							end
					end;
				_ExistingKeys ->
					%% Pid already has non-singleton registrations
					{reply, {error, {already_registered, _ExistingKeys}}, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}}
			end;
		ExistingKey ->
			%% Pid already registered as singleton
			case ExistingKey =:= Key of
				true ->
					case ets:lookup(?REGISTRY_TABLE, ExistingKey) of
						[Entry] ->
							{reply, {ok, Entry}, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}};
						[] ->
							%% Stale singleton entry, allow re-registration under requested key
							do_register(Key, Pid, Metadata, {PidSingleton, PidKeyMap, Subscribers, MonitorMap})
					end;
				false ->
					{reply, {error, {already_registered_under_key, ExistingKey}}, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}}
			end
	end;

%% @doc Handle subscribe-await requests - non-blocking subscription with timeout tracking
handle_call({subscribe_await, Key, CallerPid, Timeout}, _From, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}) ->
	case ets:lookup(?REGISTRY_TABLE, Key) of
		[Entry] ->
			%% Key already registered, send notification immediately
			CallerPid ! {orca_registered, Key, Entry},
			{reply, ok, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}};
		[] ->
			%% Key not registered, add to subscribers map with optional timer
			SubscribersList = maps:get(Key, Subscribers, []),
			SubEntry = case Timeout of
				infinity -> 
					CallerPid;
				Ms when Ms > 0 ->
					TimerRef = erlang:send_after(Ms, CallerPid, {orca_await_timeout, Key}),
					{CallerPid, TimerRef};
				0 ->
					%% Timeout of 0 means immediate timeout - send timeout message
					CallerPid ! {orca_await_timeout, Key},
					CallerPid
			end,
			NewSubscribers = maps:put(Key, [SubEntry | SubscribersList], Subscribers),
			{reply, ok, {PidSingleton, PidKeyMap, NewSubscribers, MonitorMap}}
	end;

%% @doc Handle subscribe requests - non-blocking subscription to key registration
handle_call({subscribe, Key, CallerPid}, _From, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}) ->
	case ets:lookup(?REGISTRY_TABLE, Key) of
		[Entry] ->
			%% Key already registered, send notification immediately
			CallerPid ! {orca_registered, Key, Entry},
			{reply, ok, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}};
		[] ->
			%% Key not registered, add to subscribers map
			SubscribersList = maps:get(Key, Subscribers, []),
			NewSubscribers = maps:put(Key, [CallerPid | SubscribersList], Subscribers),
			{reply, ok, {PidSingleton, PidKeyMap, NewSubscribers, MonitorMap}}
	end;

%% @doc Handle unsubscribe requests - cancel subscription to key registration
handle_call({unsubscribe, Key, CallerPid}, _From, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}) ->
	case maps:get(Key, Subscribers, []) of
		[] ->
			%% No subscribers for this key
			{reply, ok, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}};
		SubscribersList ->
			%% Remove CallerPid from subscribers (handle both plain Pid and {Pid, TimerRef} formats)
			NewList = lists:filter(fun
				(Pid) when is_pid(Pid) -> Pid =/= CallerPid;
				({Pid, _}) -> Pid =/= CallerPid
			end, SubscribersList),
			
			%% Cancel any associated timers
			lists:foreach(fun
				({Pid, TimerRef}) when Pid =:= CallerPid ->
					catch erlang:cancel_timer(TimerRef);
				(_) ->
					ok
			end, SubscribersList),
			
			%% Update subscribers map
			NewSubscribers = case NewList of
				[] -> maps:remove(Key, Subscribers);
				_ -> maps:put(Key, NewList, Subscribers)
			end,
			{reply, ok, {PidSingleton, PidKeyMap, NewSubscribers, MonitorMap}}
	end.

%% @doc Handle process 'DOWN' messages from monitors
handle_info(Info, {PidSingleton, PidKeyMap, Subscribers}) ->
	%% Upgrade legacy state without MonitorMap
	handle_info(Info, {PidSingleton, PidKeyMap, Subscribers, maps:new()});
handle_info({'DOWN', _Ref, process, Pid, _Reason}, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}) ->
	%% Get all keys associated with this pid
	NewState = remove_dead_pid_entries(Pid, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}),
	{noreply, NewState};

%% Ignore any other info messages
handle_info(_Info, State) ->
	{noreply, State}.

%% @doc Handle async messages (not used currently)
handle_cast(Msg, {PidSingleton, PidKeyMap, Subscribers}) ->
	%% Upgrade legacy state without MonitorMap
	handle_cast(Msg, {PidSingleton, PidKeyMap, Subscribers, maps:new()});
handle_cast(_Msg, State) ->
	{noreply, State}.

%% @doc Cleanup on termination
terminate(_Reason, _State) ->
	%% Note: We leave the ETS table intact so registrations survive code reloads
	%% To clear registrations, the entire application would need to restart
	ok.

%% @doc Code change callback
code_change(_OldVsn, State, _Extra) ->
	{ok, State}.


%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Internal Functions
%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% @doc Perform the actual registration (fast path)
do_register(Key, Pid, Metadata, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}) ->
    %% Monitor the pid only if it's new to the registry
	{NewMonitorMap, _} = maybe_monitor_pid(Pid, PidKeyMap, MonitorMap),

    %% Insert new entry into ETS
	NormalizedMetadata = normalize_tags(Metadata),
    Entry = {Key, Pid, NormalizedMetadata},
    ets:insert(?REGISTRY_TABLE, Entry),
    
    %% Clear existing tags for this key from tag index
    ets:match_delete(?TAG_INDEX_TABLE, {'_', Key}),
    
    %% Add tags to tag index
    Tags = maps:get(tags, NormalizedMetadata, []),
    lists:foreach(fun(Tag) ->
        ets:insert(?TAG_INDEX_TABLE, {{tag, Tag}, Key})
    end, Tags),
	update_property_index(Key, NormalizedMetadata),
        
    %% Track pid -> keys mapping
    NewPidKeyMap = maps:update_with(Pid, 
        fun(Keys) -> [Key | lists:delete(Key, Keys)] end, 
        [Key], 
        PidKeyMap),
    
    %% Notify any subscribers waiting for this key
    NewSubscribers = notify_subscribers(Key, Entry, Subscribers),
    
    {reply, {ok, Entry}, {PidSingleton, NewPidKeyMap, NewSubscribers, NewMonitorMap}}.

register_with_start(Key, Metadata, M, F, A, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}) ->
	%% Try to start the process
	try erlang:apply(M, F, A) of
		{ok, Pid} ->
			%% Process started successfully, now register it
			case do_register(Key, Pid, Metadata, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}) of
				{reply, {ok, {_, Pid, _}}, UpdatedState} ->
					{reply, {ok, Pid}, UpdatedState};
				{reply, {error, Reason}, _} ->
					%% Registration failed, terminate the process
					exit(Pid, kill),
					{reply, {error, {registration_failed, Reason}}, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}};
				Error ->
					%% Unexpected error, terminate the process
					exit(Pid, kill),
					{reply, {error, Error}, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}}
			end;
		Pid when is_pid(Pid) ->
			%% Process started and returned Pid directly (not in {ok, Pid} tuple)
			case do_register(Key, Pid, Metadata, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}) of
				{reply, {ok, {_, Pid, _}}, UpdatedState} ->
					{reply, {ok, Pid}, UpdatedState};
				{reply, {error, Reason}, _} ->
					%% Registration failed, terminate the process
					exit(Pid, kill),
					{reply, {error, {registration_failed, Reason}}, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}};
				Error ->
					%% Unexpected error, terminate the process
					exit(Pid, kill),
					{reply, {error, Error}, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}}
			end;
		Other ->
			%% MFA returned something unexpected
			{reply, {error, {invalid_return, Other}}, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}}
	catch
		Error:Reason ->
			{reply, {error, {Error, Reason}}, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}}
	end.

%% Synchronous version of do_register for batch operations (doesn't return reply tuple)
do_register_sync(Key, Pid, Metadata, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}) ->
    %% Check if already monitoring this pid
	{NewMonitorMap, _} = maybe_monitor_pid(Pid, PidKeyMap, MonitorMap),

    %% Insert new entry into ETS
	NormalizedMetadata = normalize_tags(Metadata),
    Entry = {Key, Pid, NormalizedMetadata},
    ets:insert(?REGISTRY_TABLE, Entry),
    
    %% Clear existing tags for this key from tag index
    ets:match_delete(?TAG_INDEX_TABLE, {'_', Key}),
    
    %% Add tags to tag index
    Tags = maps:get(tags, NormalizedMetadata, []),
    lists:foreach(fun(Tag) ->
        ets:insert(?TAG_INDEX_TABLE, {{tag, Tag}, Key})
    end, Tags),
	update_property_index(Key, NormalizedMetadata),
        
    %% Track pid -> keys mapping
    NewPidKeyMap = maps:update_with(Pid, 
        fun(Keys) -> [Key | lists:delete(Key, Keys)] end, 
        [Key], 
        PidKeyMap),
    
    %% Notify any subscribers waiting for this key
    NewSubscribers = notify_subscribers(Key, Entry, Subscribers),
    
    {ok, Entry, {PidSingleton, NewPidKeyMap, NewSubscribers, NewMonitorMap}}.

normalize_tags(Metadata) ->
	case maps:get(tags, Metadata, undefined) of
		undefined ->
			Metadata;
		Tags when is_list(Tags) ->
			maps:put(tags, lists:usort(Tags), Metadata);
		_ ->
			Metadata
	end.

maybe_monitor_pid(Pid, PidKeyMap, MonitorMap) ->
	case maps:get(Pid, PidKeyMap, []) of
		[] ->
			Ref = monitor(process, Pid),
			{maps:put(Pid, Ref, MonitorMap), Ref};
		_ ->
			{MonitorMap, undefined}
	end.

maybe_demonitor_pid(Pid, MonitorMap) ->
	case maps:take(Pid, MonitorMap) of
		{Ref, NewMap} ->
			catch erlang:demonitor(Ref, [flush]),
			NewMap;
		error ->
			MonitorMap
	end.

cleanup_new_monitors(MonitorMap, PrevMonitorMap) ->
	lists:foreach(fun({Pid, Ref}) ->
		case maps:is_key(Pid, PrevMonitorMap) of
			true -> ok;
			false -> catch erlang:demonitor(Ref, [flush])
		end
	end, maps:to_list(MonitorMap)).

update_property_index(Key, Metadata) ->
	ets:match_delete(?PROPERTY_INDEX_TABLE, {'_', Key}),
	case maps:get(properties, Metadata, #{}) of
		Props when is_map(Props) ->
			maps:foreach(fun(PropName, PropValue) ->
				ets:insert(?PROPERTY_INDEX_TABLE, {{property, PropName, PropValue}, Key})
			end, Props);
		_ ->
			ok
	end.

remove_dead_pid_entries(Pid, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}) ->
	%% Get all keys associated with this pid
	case maps:get(Pid, PidKeyMap, []) of
		[] ->
			%% No keys tracked for this pid
			{PidSingleton, PidKeyMap, Subscribers, MonitorMap};
		Keys ->
			%% Remove all entries for this pid from ETS
			lists:foreach(fun(Key) -> 
				ets:delete(?REGISTRY_TABLE, Key),
				%% Also remove all tags for this key from tag index
				ets:match_delete(?TAG_INDEX_TABLE, {'_', Key}),
				%% Also remove all properties for this key from property index
				ets:match_delete(?PROPERTY_INDEX_TABLE, {'_', Key})
			end, Keys),
			%% Remove pid from singleton map
			NewSingleton = maps:remove(Pid, PidSingleton),
			%% Remove pid from tracking map
			NewPidKeyMap = maps:remove(Pid, PidKeyMap),
			NewMonitorMap = maybe_demonitor_pid(Pid, MonitorMap),
			{NewSingleton, NewPidKeyMap, Subscribers, NewMonitorMap}
	end.

%% @doc Notify all subscribers waiting for a key that has been registered
notify_subscribers(Key, Entry, Subscribers) ->
	case maps:get(Key, Subscribers, []) of
		[] ->
			%% No subscribers for this key
			Subscribers;
		SubList ->
			%% Send notification to all subscribers and cancel timers
			lists:foreach(fun
				(Pid) when is_pid(Pid) ->
					Pid ! {orca_registered, Key, Entry};
				({Pid, TimerRef}) ->
					catch erlang:cancel_timer(TimerRef),
					Pid ! {orca_registered, Key, Entry}
			end, SubList),
			%% Remove this key from subscribers map
			maps:remove(Key, Subscribers)
	end.

%% @doc Helper for batch registration
register_batch_entries([], State, _PrevState, Entries, _NewEntries, _FailedKeys) ->
	%% All succeeded
	{reply, {ok, lists:reverse(Entries)}, State};

register_batch_entries([Reg | Rest], {PidSingleton, PidKeyMap, Subscribers, MonitorMap} = State, PrevState, Entries, NewEntries, FailedKeys) ->
	%% Parse registration tuple - {Key, Pid, Metadata}
	{Key, Pid, Metadata} = Reg,
	
	%% Try to register this entry
	case ets:lookup(?REGISTRY_TABLE, Key) of
		[] ->
			case maps:get(Pid, PidSingleton, undefined) of
				undefined ->
					%% Key not registered, register it
					case do_register_sync(Key, Pid, Metadata, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}) of
						{ok, Entry, NewState} ->
							register_batch_entries(Rest, NewState, PrevState, [Entry | Entries], [Entry | NewEntries], FailedKeys);
						{error, Reason} ->
							%% Rollback: unregister all successful ones
							rollback_batch(NewEntries, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}, PrevState),
							AllFailed = [Key | FailedKeys],
							{reply, {error, {Reason, AllFailed, Entries}}, PrevState}
					end;
				ExistingKey when ExistingKey =:= Key ->
					case do_register_sync(Key, Pid, Metadata, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}) of
						{ok, Entry, NewState} ->
							register_batch_entries(Rest, NewState, PrevState, [Entry | Entries], [Entry | NewEntries], FailedKeys);
						{error, Reason} ->
							rollback_batch(NewEntries, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}, PrevState),
							AllFailed = [Key | FailedKeys],
							{reply, {error, {Reason, AllFailed, Entries}}, PrevState}
					end;
				ExistingKey ->
					AllFailed = [Key | FailedKeys],
					rollback_batch(NewEntries, {PidSingleton, PidKeyMap, Subscribers, MonitorMap}, PrevState),
					{reply, {error, {{already_registered_under_key, ExistingKey}, AllFailed, Entries}}, PrevState}
			end;
		[{Key, ExistingPid, _} = Entry] ->
			%% Key already exists, check if process is alive
			case is_process_alive(ExistingPid) of
				true ->
					%% Process is alive - return existing entry and continue
					register_batch_entries(Rest, State, PrevState, [Entry | Entries], NewEntries, FailedKeys);
				false ->
					%% Process is dead, clean up and re-register
					NewState = remove_dead_pid_entries(ExistingPid, State),
					case do_register_sync(Key, Pid, Metadata, NewState) of
						{ok, Entry, NewState2} ->
							register_batch_entries(Rest, NewState2, PrevState, [Entry | Entries], [Entry | NewEntries], FailedKeys);
						{error, Reason} ->
							rollback_batch(NewEntries, State, PrevState),
							AllFailed = [Key | FailedKeys],
							{reply, {error, {Reason, AllFailed, Entries}}, PrevState}
					end
			end
	end.

%% Rollback registered entries
rollback_batch(Entries, {_, _, _, MonitorMap}, {_, _, _, PrevMonitorMap}) ->
	cleanup_new_monitors(MonitorMap, PrevMonitorMap),
	lists:foreach(fun({Key, _Pid, _Meta}) ->
		ets:delete(?REGISTRY_TABLE, Key),
		ets:match_delete(?TAG_INDEX_TABLE, {'_', Key}),
		ets:match_delete(?PROPERTY_INDEX_TABLE, {'_', Key})
	end, Entries).

register_batch_with_entries([], State, _PrevState, Entries, _NewEntries, _StartedPids, _FailedKeys) ->
	{reply, {ok, lists:reverse(Entries)}, State};

register_batch_with_entries([Reg | Rest], State, PrevState, Entries, NewEntries, StartedPids, FailedKeys) ->
	{Key, Metadata, {M, F, A}} = Reg,
	case ets:lookup(?REGISTRY_TABLE, Key) of
		[{Key, ExistingPid, _} = Entry] ->
			case is_process_alive(ExistingPid) of
				true ->
					register_batch_with_entries(Rest, State, PrevState, [Entry | Entries], NewEntries, StartedPids, FailedKeys);
				false ->
					NewState = remove_dead_pid_entries(ExistingPid, State),
					start_and_register_batch(Key, Metadata, {M, F, A}, NewState, PrevState, Rest, Entries, NewEntries, StartedPids, FailedKeys)
			end;
		[] ->
			start_and_register_batch(Key, Metadata, {M, F, A}, State, PrevState, Rest, Entries, NewEntries, StartedPids, FailedKeys)
	end.

start_and_register_batch(Key, Metadata, {M, F, A}, State, PrevState, Rest, Entries, NewEntries, StartedPids, FailedKeys) ->
	try erlang:apply(M, F, A) of
		{ok, Pid} ->
			handle_started_batch(Key, Pid, Metadata, State, PrevState, Rest, Entries, NewEntries, [Pid | StartedPids], FailedKeys);
		Pid when is_pid(Pid) ->
			handle_started_batch(Key, Pid, Metadata, State, PrevState, Rest, Entries, NewEntries, [Pid | StartedPids], FailedKeys);
		Other ->
			rollback_batch(NewEntries, State, PrevState),
			kill_started_pids(StartedPids),
			AllFailed = [Key | FailedKeys],
			{reply, {error, {invalid_return, Other, AllFailed, Entries}}, PrevState}
	catch
		Error:Reason ->
			rollback_batch(NewEntries, State, PrevState),
			kill_started_pids(StartedPids),
			AllFailed = [Key | FailedKeys],
			{reply, {error, {{Error, Reason}, AllFailed, Entries}}, PrevState}
	end.

handle_started_batch(Key, Pid, Metadata, State, PrevState, Rest, Entries, NewEntries, StartedPids, FailedKeys) ->
	case do_register_sync(Key, Pid, Metadata, State) of
		{ok, Entry, NewState} ->
			register_batch_with_entries(Rest, NewState, PrevState, [Entry | Entries], [Entry | NewEntries], StartedPids, FailedKeys);
		{error, Reason} ->
			rollback_batch(NewEntries, State, PrevState),
			kill_started_pids(StartedPids),
			AllFailed = [Key | FailedKeys],
			{reply, {error, {Reason, AllFailed, Entries}}, PrevState}
	end.

kill_started_pids(Pids) ->
	lists:foreach(fun(Pid) ->
		catch exit(Pid, kill)
	end, Pids).
