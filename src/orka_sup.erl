-module(orka_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
	supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
	Procs = [
		#{
			id => orka,
			start => {orka, start_link, []},
			restart => permanent,
			shutdown => 5000,
			type => worker,
			modules => [orka]
		}
	],
	{ok, {{one_for_one, 1, 5}, Procs}}.
