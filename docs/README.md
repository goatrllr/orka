# Orka Documentation

<div align="center">

![Orka Logo](images/orka_logo.png)

</div>

Complete documentation for the Orka ETS-based process registry.

## Main Documentation

Start with the main [**API Documentation**](../API.md) in the project root for:
- Quick start guide
- Complete API reference
- Advanced features (await, subscribe, properties)
- 8 fundamental usage patterns
- Design principles and FAQs

## Detailed Guides

### 1. **[Usage Patterns](usage_patterns.md)**

Eight core patterns for service registration and startup:

- Pattern 1: Supervisor Registration
- Pattern 2: Atomic Process Startup (register_with)
- Pattern 3: Singleton Services
- Pattern 4: Batch Per-User Registration
- Pattern 5: Startup Coordination (await)
- Pattern 6: Optional Dependencies (subscribe)
- Pattern 7: Health Monitoring
- Pattern 8: Load Balancing with Properties

**When to read**: You want to see complete examples of each pattern in action.

### 2. **[Singleton Examples](singleton_examples.md)**

Deep-dive into singleton pattern with 7 real-world examples:

- Unique service instances (only one translator)
- Configuration servers
- Database connection pools
- Distributed locks
- Event buses / message routers
- Metrics collectors
- Resource managers with exclusive access

**When to read**: Building a service that must exist as a single instance.

### 3. **[Property Examples](property_examples.md)**

Using properties for rich queryable metadata with 6 use cases:

- Load balancing by capacity
- Geographic distribution
- Health and status monitoring
- Feature flag queries
- User session tracking
- Resource pool distribution

**When to read**: You need to search by custom attributes (region, capacity, version, etc.).

### 4. **[Await/Subscribe Examples](await_examples.md)**

Startup coordination deep-dive with 7 detailed examples:

- Blocking on critical dependencies
- Non-blocking optional dependencies
- Multi-service coordination
- Timeout handling
- Graceful degradation
- Optional enhancement features

**When to read**: Coordinating process startup across multiple services.

### 5. **[Comparison with Alternatives](comparison.md)**

How Orka compares to other process registries:

- **gproc**: Global process registry (built-in, older)
- **syn**: Distributed process groups (cluster-aware)
- **Orka**: ETS-based, high-performance, local-node

Including:
- Feature comparison table
- Performance characteristics
- When to use each
- Migration paths

**When to read**: Evaluating whether Orka is right for your use case.

## Quick Reference

### By Use Case

**Registering a service?**
→ [Usage Patterns](usage_patterns.md) Pattern 1 & 2

**Single-instance service?**
→ [Singleton Examples](singleton_examples.md)

**Waiting for startup?**
→ [Await/Subscribe Examples](await_examples.md) + [Usage Patterns](usage_patterns.md) Pattern 5 & 6

**Finding by attributes?**
→ [Property Examples](property_examples.md)

**Comparing to gproc/syn?**
→ [Comparison](comparison.md)

### By Feature

| Feature | Main Doc | Detailed Guide |
|---------|----------|-----------------|
| Basic registration | [API.md](../API.md) | [Usage Patterns](usage_patterns.md) |
| Singleton constraint | [API.md](../API.md) | [Singleton Examples](singleton_examples.md) |
| Tags/categories | [API.md](../API.md) | [Usage Patterns](usage_patterns.md) |
| Properties | [API.md](../API.md) | [Property Examples](property_examples.md) |
| Await/Subscribe | [API.md](../API.md) | [Await/Subscribe Examples](await_examples.md) |
| Batch registration | [API.md](../API.md) | [Usage Patterns](usage_patterns.md) Pattern 4 |
| Batch cleanup | [API.md](../API.md) | [Usage Patterns](usage_patterns.md) Pattern 8 |

## Testing

All examples and patterns have been tested:

- **71/71 tests passing** in Common Test suite
- Coverage includes: registration, lookups, tags, properties, singleton, await, subscribe, batch operations

See `test/orka_SUITE.erl` for test implementations.

## Performance Notes

- **Lookup**: ~1-2 microseconds (ETS public table)
- **Registration**: ~10-20 microseconds (gen_server + monitor)
- **Tag query**: O(n) where n = entries with tag (usually small)

Not suitable for per-message operations, but excellent for service discovery and startup coordination.

## Architecture Notes

Orka uses:
- **ETS public tables** for lock-free reads
- **gen_server** for atomic writes with monitors
- **Process monitors** for automatic cleanup
- **Tag and property indices** for efficient querying

See main [API.md](../API.md) "Design Principles" section for details.

---

**Last Updated**: December 2025 | **Version**: 1.0 | **Status**: Production Ready ✅
