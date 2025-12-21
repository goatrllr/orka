{application, orca, [
	{description, "Generic process registry using ETS and monitors"},
	{vsn, "0.1.0"},
	{registered, [orca_sup, orca]},
	{mod, {orca_app, []}},
	{applications, [
		kernel,
		stdlib
	]},
	{env, []},
	{modules, ['orca','orca_app','orca_sup']},
	{maintainers, []},
	{licenses, []},
	{links, []}
]}.
