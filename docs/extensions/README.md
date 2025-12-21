# Orca Extensions: Future Ideas & Patterns

This directory contains documentation for planned extensions and patterns not yet implemented in the core Orca registry.

These are **ideas and designs** for future development, not production features. They demonstrate how Orca can be extended to handle advanced scenarios.

## Extension Ideas

### 1. **[Orca + Syn Integration (orca_syn.md)](orca_syn.md)**

**Status**: Design only (not implemented)

Hybrid architecture combining:
- **Orca** (local, fast, strong consistency)
- **Syn** (distributed, eventual consistency)

**Covers**:
- Local-first with remote fallback pattern
- Eventually consistent discovery
- Hybrid queries by consistency level
- Multi-node trading platform example
- Syn vs Orca comparison
- Migration path to distributed

**Use case**: Multi-node deployments where you need both local performance and cluster-wide service discovery.

---

### 2. **[Process Groups Patterns (groups_examples.md)](groups_examples.md)**

**Status**: Design only (not implemented)

Three approaches to managing process groups with Orca:
- **Approach 1**: Tag-based groups (simplest)
- **Approach 2**: Property-based groups (richer queries)
- **Approach 3**: Hybrid with group registry (syn replacement)

**Covers**:
- Chat room example with broadcast
- Syn replacement patterns
- Topic subscriptions
- Scalability considerations
- Comparison table

**Use case**: Grouping processes by logical categories (room members, team members, subscribers).

---

### 3. **[Query Patterns: Partial Matching (partial_match_options.md)](partial_match_options.md)**

**Status**: Design only (not implemented)

Four approaches to querying multi-process per-user lookups:
- Metadata storage (gets stale)
- Tag-based lookup (recommended)
- Partial key matching (possible but not needed)
- Hybrid approach

**Covers**:
- Trading app example: 5 services per user
- Performance implications
- Consistency guarantees
- Recommendation: Use tag-based instead

**Use case**: Finding all processes associated with a user or context.

---

### 4. **[Message Systems: Kafka & RabbitMQ Clones (message_systems.md)](message_systems.md)**

**Status**: Extension reference architecture (design only)

Complete architecture for building Kafka and RabbitMQ clones using Orca as the process registry foundation, with four required extensions:
- **orca_router** — Caching for high-throughput routing
- **orca_pubsub** — Efficient multi-recipient broadcasting
- **orca_batch** — Bulk operations for batch processing
- **orca_sharded** — Distributed registry reducing contention

**Covers**:
- Kafka clone: topics, partitions, producers, consumers, consumer groups
- RabbitMQ clone: exchanges, queues, bindings, publishers, consumers
- Complete working examples for both architectures
- Performance comparisons with/without extensions
- When to use each extension
- Integration patterns

**Use case**: Building high-throughput distributed message systems using Orca as the service discovery foundation.

---

## Why These Are Not Implemented

These extensions are documented because they represent:

1. **Good design patterns** - Worth understanding even if not building them
2. **Future roadmap** - Ideas for when needs arise
3. **Architecture examples** - How to extend Orca systematically
4. **Evaluation material** - Compare against built-in alternatives (syn, etc.)

Core Orca includes everything needed for the **vast majority** of single-node use cases. These extensions address advanced scenarios.

---

## When to Use Extensions

### Orca + Syn (orca_syn.md)

**When you need**:
- Multi-node process discovery
- Local performance within a node
- Global visibility across cluster
- Some eventual consistency acceptable

**Instead of**: gproc, pure syn, manual service discovery

---

### Process Groups (groups_examples.md)

**When you need**:
- Logical process grouping (chat rooms, teams, subscribers)
- Broadcast to all members
- Dynamic membership
- Rich query capabilities

**Instead of**: Hardcoding PIDs, manual membership tracking, syn for local groups

---

### Partial Key Matching (partial_match_options.md)

**When you need**:
- Find all processes for a user/context
- Multi-process per user/entity
- Efficient bulk operations

**Instead of**: Metadata storage, prefix trees, manual tracking

**Recommendation**: Use **tag-based lookup** documented here - simpler, always current, automatic cleanup.

---

## Extension Module Philosophy

If/when building these extensions, follow the pattern:

```erlang
%% Core orca module
-module(orca).
%% Handles: registration, lookup, tags, properties, await, subscribe

%% Extension modules build on orca
-module(orca_grp).      %% Process groups wrapper
-module(orca_syn_bridge).  %% Syn integration layer
-module(orca_counter).   %% Distributed counters (future)
```

**Principles**:
1. Keep core Orca focused on registration + lookup
2. Build extensions as separate modules using Orca as foundation
3. Extensions add convenience or advanced patterns
4. Core library stays minimal and fast

---

## Evaluation Process

To decide if an extension should be built:

1. **Is it in this directory?** → Design exists, pattern understood
2. **Can Orca core + simple code solve it?** → Build that first (see [docs/](../))
3. **Is it used in >1 project?** → Consider building the extension
4. **Does it need strict semantics?** → Design carefully before implementing
5. **Can users build it themselves?** → Document as pattern, provide examples

---

## Current Status

| Extension | Status | Use Now? |
|-----------|--------|----------|
| Orca + Syn | Design | Use syn directly, or read pattern for architecture ideas |
| Process Groups | Design | Use Orca tags + custom code, or read pattern examples |
| Partial Matching | Design | Use tag-based lookup (recommended), see docs |
| Message Systems | Design | Read for architecture ideas, build custom extensions as needed |

---

**Last Updated**: December 2025 | **Note**: These are ideas and patterns, not production features
