-record(orka_state, {
    local_store  :: {module(), term()},
    global_store :: {module(), term()},
    pid_singleton = #{} :: map(),
    pid_keys      = #{} :: map(),
    subscribers   = #{} :: map(),
    monitor_map   = #{} :: map()
}).
