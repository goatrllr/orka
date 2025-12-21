Orca vs. Gproc vs. Syn (Local Registry Only)
Feature Comparison
Feature	Orca	Gproc	Syn
Process Registration	✓	✓	✓
Flexible Keys (any term)	✓	✓	✓
Multiple Aliases/Process	✓	✓	✓
Tag-based Queries	✓	✗	✓
Non-unique Properties	✓	✗	✗
Property Statistics	✓	✗	✗
Singleton Pattern	✓	✗	✗
Atomic Start-Register	✓ (register_with)	✗	✗
ETS for Lock-free Reads	✓	✓	✗ (uses gen_server only)
Process Monitoring	✓	✓	✓
Counter API	✗	✓	✗
Named Values	✗	✓	✗
Key Differences
Orca Strengths:

Properties System — Gproc has nothing like this. You can store arbitrary values and query them efficiently (e.g., all instances with capacity => 100)
Singleton Pattern — Neither gproc nor syn have this built-in. Useful for preventing accidental duplicates
Atomic Startup — register_with/3 is cleaner than start → register separately
Property Stats — property_stats/2 gives you distribution analysis (e.g., how many instances at each capacity level)
Cleaner API — Smaller, focused surface area (no counters, named values, etc.)
Gproc Strengths:

Counters — Built-in counter objects (not in orca or syn)
Named Values — Global shared values with atomic updates
Mature — Battle-tested in production for years
More Flexible Metadata — Can store arbitrary data per registration
Syn Strengths:

Distributed First — Designed for clustering from the ground up
Event Notifications — Built-in event system for registration changes
Scalable — Better for very large numbers of registrations
Cleaner Code — Simpler internal architecture than gproc
Architecture Comparison
Orca:

Pro: Lock-free reads, efficient queries via ETS match specs
Con: Single writer bottleneck (but acceptable for local registry)
Gproc:

Pro: Flexible, supports many use cases
Con: More complex, heavier weight
Syn:

Pro: Simple, distributed-friendly
Con: Every read is a process call (bottleneck at scale)
Use Case Fit
Use Case	Orca	Gproc	Syn
Service Discovery	✓✓	✓✓	✓✓
Load Balancing (by property)	✓✓	✓	✓
Singleton Services	✓✓	✗	✗
Health/Status Tracking	✓✓	✓	✓
Global Counters	✗	✓✓	✗
Named Shared State	✗	✓✓	✗
Distributed Clustering	✗	✓	✓✓
Performance (Local Registry)
Orca: Lock-free reads via ETS, good for high-read workloads
Gproc: Good reads via ETS, more overhead for complex features
Syn: Read bottleneck (gen_server process calls), better for low-read scenarios
My Assessment
Orca is:

✓ Simpler than Gproc — Focused scope, easier to understand
✓ More capable than Syn (locally) — Better read performance, richer query API
✓ Better for property-driven architectures — Load balancing by capacity, region, etc.
✓ Designed for composition — Services build on top with their own logic
✗ Not a drop-in gproc replacement — Missing counters, named values
✗ Not distributed — That's intentional (using syn for that)
When to use Orca:

Building microservice architectures with local service discovery
Need efficient property-based queries (load balancing by capacity, region, etc.)
Want singleton pattern enforcement
Prefer simplicity and composability over feature richness
When to use Gproc:

Need counters or global named values
Want a mature, battle-tested system
Building systems that mix different registry patterns
When to use Syn:

Clustering across multiple nodes is required
Building distributed systems from the start
Event notifications on registration changes matter
Bottom Line: Orca fills a specific niche between "minimal registry" and "feature-complete gproc." It's optimized for modern microservice architectures where you want:

Fast local service discovery ✓
Property-driven routing ✓
Composable with service-specific logic ✓
Preparation for distributed via syn ✓