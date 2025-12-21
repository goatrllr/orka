-module(orca_registry).
-behaviour(gen_server).

%% API
-export([start_link/0]).
-export([register/2, register/3]).
-export([unregister/1]).
-export([lookup/1]).
-export([lookup_all/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(REGISTRY_TABLE, orca_registry_table).

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
register(Key, Pid, Metadata) when is_pid(Pid) ->
	gen_server:call(?MODULE, {register, Key, Pid, Metadata}).

%% @doc Unregister a process from the registry by key.
unregister(Key) ->
	gen_server:call(?MODULE, {unregister, Key}).

%% @doc Lookup a single entry by key. Returns {ok, {Key, Pid, Metadata}} or not_found.
lookup(Key) ->
	case ets:lookup(?REGISTRY_TABLE, Key) of
		[Entry] -> {ok, Entry};
		[] -> not_found
	end.

%% @doc Return all entries in the registry.
lookup_all() ->
	ets:tab2list(?REGISTRY_TABLE).

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
	%% Store for tracking monitored pids -> keys mapping
	{ok, maps:new()}.

%% @doc Handle registration requests
handle_call({register, Key, Pid, Metadata}, _From, PidKeyMap) ->
	%% If this key was previously registered to a different pid, unmonitor the old one
	OldPidKeyMap = case ets:lookup(?REGISTRY_TABLE, Key) of
		[{Key, OldPid, _}] ->
			%% Check if this is the only key for this pid
			NewMap = maps:update_with(OldPid, 
				fun(Keys) -> lists:delete(Key, Keys) end, 
				[], 
				PidKeyMap),
			%% If no more keys for this pid, demonitor
			case maps:get(OldPid, NewMap, []) of
				[] -> maps:remove(OldPid, NewMap);
				_ -> NewMap
			end;
		[] ->
			PidKeyMap
	end,
	
	%% Insert new entry into ETS
	ets:insert(?REGISTRY_TABLE, {Key, Pid, Metadata}),
	
	%% Monitor the new pid (or update existing monitor)
	monitor(process, Pid),
	
	%% Track pid -> keys mapping
	NewPidKeyMap = maps:update_with(Pid, 
		fun(Keys) -> [Key | lists:delete(Key, Keys)] end, 
		[Key], 
		OldPidKeyMap),
	
	{reply, ok, NewPidKeyMap};

%% @doc Handle unregistration requests
handle_call({unregister, Key}, _From, PidKeyMap) ->
	Result = case ets:lookup(?REGISTRY_TABLE, Key) of
		[{Key, Pid, _}] ->
			%% Remove from ETS
			ets:delete(?REGISTRY_TABLE, Key),
			
			%% Update pid->keys mapping
			NewMap = maps:update_with(Pid, 
				fun(Keys) -> lists:delete(Key, Keys) end, 
				[], 
				PidKeyMap),
			
			%% If no more keys for this pid, demonitor
			NewPidKeyMap = case maps:get(Pid, NewMap, []) of
				[] -> maps:remove(Pid, NewMap);
				_ -> NewMap
			end,
			
			{ok, NewPidKeyMap};
		[] ->
			{not_found, PidKeyMap}
	end,
	
	case Result of
		{ok, UpdatedMap} -> {reply, ok, UpdatedMap};
		{not_found, _} -> {reply, not_found, PidKeyMap}
	end.

%% @doc Handle process 'DOWN' messages from monitors
handle_info({'DOWN', _Ref, process, Pid, _Reason}, PidKeyMap) ->
	%% Get all keys associated with this pid
	case maps:get(Pid, PidKeyMap, []) of
		[] ->
			%% No keys tracked for this pid (shouldn't happen, but be safe)
			{noreply, PidKeyMap};
		Keys ->
			%% Remove all entries for this pid from ETS
			lists:foreach(fun(Key) -> ets:delete(?REGISTRY_TABLE, Key) end, Keys),
			%% Remove pid from tracking map
			NewPidKeyMap = maps:remove(Pid, PidKeyMap),
			{noreply, NewPidKeyMap}
	end;

%% Ignore any other info messages
handle_info(_Info, PidKeyMap) ->
	{noreply, PidKeyMap}.

%% @doc Handle async messages (not used currently)
handle_cast(_Msg, PidKeyMap) ->
	{noreply, PidKeyMap}.

%% @doc Cleanup on termination
terminate(_Reason, _PidKeyMap) ->
	%% Note: We leave the ETS table intact so registrations survive code reloads
	%% To clear registrations, the entire application would need to restart
	ok.

%% @doc Code change callback
code_change(_OldVsn, PidKeyMap, _Extra) ->
	{ok, PidKeyMap}.
