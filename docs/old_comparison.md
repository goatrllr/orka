# Orka vs. Gproc vs. Syn

Comparison of local process registry implementations.

## Feature Comparison

| Feature | Orka | Gproc | Syn |
|---------|------|-------|-----|
| Process Registration | ✓ | ✓ | ✓ |
| Flexible Keys (any term) | ✓ | ✓ | ✓ |
| Multiple Aliases/Process | ✓ | ✓ | ✓ |
| Tag-based Queries | ✓ | ✗ | ✓ |
| Non-unique Properties | ✓ | ✗ | ✗ |
| Property Statistics | ✓ | ✗ | ✗ |
| Singleton Pattern | ✓ | ✗ | ✗ |
| Atomic Start-Register | ✓ (register_with) | ✗ | ✗ |
| ETS for Lock-free Reads | ✓ | ✓ | ✗ (gen_server only) |
| Process Monitoring | ✓ | ✓ | ✓ |
| Counter API | ✗ | ✓ | ✗ |
| Named Values | ✗ | ✓ | ✗ |

## Key Strengths & Weaknesses

### Orka Strengths

- **Properties System** — Gproc has nothing like this. Store arbitrary values and query them efficiently (e.g., all instances with `capacity => 100`)
- **Singleton Pattern** — Neither gproc nor syn have this built-in. Prevents accidental duplicates
- **Atomic Startup** — `register_with/3` is cleaner than start → register separately
- **Property Stats** — `property_stats/2` gives distribution analysis (e.g., instances per capacity level)
- **Cleaner API** — Smaller, focused surface area (no counters, named values, etc.)

### Gproc Strengths

- **Counters** — Built-in counter objects (not in orka or syn)
- **Named Values** — Global shared values with atomic updates
- **Mature** — Battle-tested in production for years
- **Flexible Metadata** — Can store arbitrary data per registration

### Syn Strengths

- **Distributed First** — Designed for clustering from the ground up
- **Event Notifications** — Built-in event system for registration changes
- **Scalable** — Better for very large numbers of registrations
- **Cleaner Code** — Simpler internal architecture than gproc

## Architecture Comparison

### Orka

**Pros:**
- Lock-free reads via ETS match specs
- Efficient property-based queries
- Good for high-read workloads

**Cons:**
- Single writer bottleneck (acceptable for local registry)

### Gproc

**Pros:**
- Flexible, supports many use cases
- Battle-tested, mature

**Cons:**
- More complex, heavier weight
- Higher overhead for complex features

### Syn

**Pros:**
- Simple design
- Distributed-friendly
- Built-in clustering support

**Cons:**
- Read bottleneck (gen_server process calls)
- Not ideal for high-read scenarios

## Use Case Fit

| Use Case | Orka | Gproc | Syn |
|----------|------|-------|-----|
| Service Discovery | ✓✓ | ✓✓ | ✓✓ |
| Load Balancing (by property) | ✓✓ | ✓ | ✓ |
| Singleton Services | ✓✓ | ✗ | ✗ |
| Health/Status Tracking | ✓✓ | ✓ | ✓ |
| Global Counters | ✗ | ✓✓ | ✗ |
| Named Shared State | ✗ | ✓✓ | ✗ |
| Distributed Clustering | ✗ | ✓ | ✓✓ |

## Performance Characteristics

**Orka:** Lock-free reads via ETS, excellent for high-read workloads (<10K lookups/sec)

**Gproc:** Good reads via ETS, more overhead for complex features

**Syn:** Read bottleneck (gen_server process calls), better for low-read scenarios

## When to Use Each

### Use Orka When

- Building microservice architectures with local service discovery
- Need efficient property-based queries (load balancing by capacity, region, etc.)
- Want singleton pattern enforcement
- Prefer simplicity and composability over feature richness

### Use Gproc When

- Need counters or global named values
- Want a mature, battle-tested system
- Building systems that mix different registry patterns

### Use Syn When

- Clustering across multiple nodes is required
- Building distributed systems from the start
- Event notifications on registration changes matter

## Assessment

Orka is optimized for modern microservice architectures where you want:

✓ Fast local service discovery  
✓ Property-driven routing  
✓ Composable with service-specific logic  
✓ Foundation for distributed via syn  

### Distinctive Advantages

- **Simpler than Gproc** — Focused scope, easier to understand
- **More capable than Syn locally** — Better read performance, richer query API
- **Better for property-driven architectures** — Load balancing by capacity, region, etc.
- **Designed for composition** — Services build on top with their own logic

### Limitations

- Not a drop-in gproc replacement — Missing counters, named values
- Not distributed — That's intentional (use syn for multi-node scenarios)