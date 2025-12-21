# Documentation Map

This is your quick navigation guide to all Orca documentation.

## Start Here

1. **[README.md](README.md)** (5 min) — Project overview, features, quick examples
2. **[API.md](API.md)** (15-20 min) — Complete API reference with core examples

## Deep Dives by Feature

| I Want To... | Read | Time |
|--------------|------|------|
| See example patterns | [docs/usage_patterns.md](docs/usage_patterns.md) | 10 min |
| Build singleton service | [docs/singleton_examples.md](docs/singleton_examples.md) | 10 min |
| Query by attributes | [docs/property_examples.md](docs/property_examples.md) | 10 min |
| Coordinate startup | [docs/await_examples.md](docs/await_examples.md) | 10 min |
| Compare alternatives | [docs/comparison.md](docs/comparison.md) | 5 min |

## By Use Case

### "I'm building a web service"
1. [README.md](README.md#quick-start) — Overview
2. [API.md](API.md#core-api) — Learn core functions
3. [docs/usage_patterns.md](docs/usage_patterns.md) Pattern 1 — Supervisor registration
4. [docs/comparison.md](docs/comparison.md) — Check against gproc

### "I need to wait for services at startup"
1. [API.md](API.md#startup-coordination-await--subscribe) — Overview
2. [docs/await_examples.md](docs/await_examples.md) — Detailed examples
3. [docs/usage_patterns.md](docs/usage_patterns.md) Pattern 5 & 6

### "I'm building a trading/financial app"
1. [README.md](README.md#trading-application) — Example workspace
2. [docs/usage_patterns.md](docs/usage_patterns.md) Pattern 4 — Batch registration
3. [docs/property_examples.md](docs/property_examples.md) Pattern 2 — Load balancing

### "I need a single-instance service"
1. [API.md](API.md#register_singlekey-metadata---ok--entry) — Function overview
2. [docs/singleton_examples.md](docs/singleton_examples.md) — 7 detailed examples

### "I need to monitor system health"
1. [API.md](API.md#core-api) — count_by_tag, count_by_type
2. [docs/usage_patterns.md](docs/usage_patterns.md) Pattern 7 — Health monitoring
3. [docs/property_examples.md](docs/property_examples.md) Pattern 4 — Property stats

### "I have a multi-node system"
1. [docs/comparison.md](docs/comparison.md) — Evaluate options
2. [docs/extensions/orca_syn.md](docs/extensions/orca_syn.md) — Hybrid architecture (design)

### "I need to group processes"
1. [docs/usage_patterns.md](docs/usage_patterns.md) Pattern 1-3 — Basic grouping
2. [docs/extensions/groups_examples.md](docs/extensions/groups_examples.md) — Process groups (design)

## Documentation Files

### Core Documentation (Production)

- **README.md** (13K)  
  Project overview, features, quick start, examples, FAQ

- **API.md** (23K)  
  Complete API reference, all functions, usage patterns, design principles

- **docs/README.md** (4.5K)  
  Navigation guide for detailed docs

### Feature Deep-Dives (Production)

- **docs/usage_patterns.md** (19K)  
  8 fundamental patterns covering all main features

- **docs/singleton_examples.md** (15K)  
  7 examples of singleton pattern with 7 use cases

- **docs/property_examples.md** (18K)  
  6 detailed property examples with load balancing, monitoring, etc.

- **docs/await_examples.md** (12K)  
  7 startup coordination examples from blocking to non-blocking

- **docs/comparison.md** (3.8K)  
  Feature comparison: Orca vs gproc vs syn

### Extension Ideas (Not Implemented)

- **docs/extensions/README.md** (NEW)  
  Overview of extension ideas and when to use them

- **docs/extensions/orca_syn.md** (20K)  
  Hybrid Orca + Syn architecture for distributed systems (design only)

- **docs/extensions/groups_examples.md** (13K)  
  3 approaches to process groups (design only)

- **docs/extensions/partial_match_options.md** (13K)  
  Query patterns for multi-process lookups (design only)

### Other

- **plans.md** (12K)  
  Internal planning document (can be deleted)

## Navigation Quick Links

```
README.md (START HERE)
  ↓
API.md (COMPLETE REFERENCE)
  ↓ (Based on what you need)
  ├─→ docs/usage_patterns.md (see all patterns)
  ├─→ docs/singleton_examples.md (single-instance)
  ├─→ docs/property_examples.md (attributes)
  ├─→ docs/await_examples.md (startup)
  ├─→ docs/comparison.md (alternatives)
  └─→ docs/extensions/ (future ideas)
```

## File Organization

```
orca/
├── README.md                    ← START HERE
├── API.md                       ← API REFERENCE
├── DOCMAP.md                    ← YOU ARE HERE
├── plans.md                     ← internal planning (can delete)
│
└── docs/
    ├── README.md                ← Docs navigation guide
    ├── usage_patterns.md        ← 8 patterns
    ├── singleton_examples.md    ← Single-instance services
    ├── property_examples.md     ← Rich metadata queries
    ├── await_examples.md        ← Startup coordination
    ├── comparison.md            ← vs gproc/syn
    │
    └── extensions/              ← NOT YET IMPLEMENTED
        ├── README.md            ← Extension overview
        ├── orca_syn.md          ← Multi-node pattern
        ├── groups_examples.md   ← Process groups
        └── partial_match_options.md  ← Query patterns
```

## Recommended Reading Order

**New to Orca?**

1. README.md (project overview)
2. API.md sections: Quick Start, Core API
3. Pick a use case from table above

**Building a feature?**

1. Find your use case in the table above
2. Read relevant section in API.md
3. Study the examples in docs/
4. Check comparison.md if evaluating tools

**Contributing/Maintaining?**

1. API.md - entire document
2. test/orca_SUITE.erl - understand test structure
3. docs/ - learn patterns for code review
4. docs/extensions/ - understand extension philosophy

**Evaluating Orca?**

1. README.md - features and use cases
2. docs/comparison.md - how it compares
3. API.md Quick Start - verify it meets needs
4. Test suite (make ct) - verify stability

## Print-Friendly Guides

To create a single-document guide:

```bash
# Print all docs to one file (Unix/Linux)
cat README.md API.md docs/usage_patterns.md > orca_guide.md

# Generate PDF (requires pandoc)
pandoc -o orca_guide.pdf README.md API.md docs/*.md
```

## Search Tips

- **Looking for example?** → Check docs/usage_patterns.md
- **Can't find a function?** → Check API.md Core API section
- **Need pattern idea?** → Check docs/usage_patterns.md
- **Comparing tools?** → Check docs/comparison.md
- **Getting started?** → Start with README.md

## Questions?

- **API question?** → API.md
- **Pattern question?** → docs/usage_patterns.md
- **Feature evaluation?** → docs/comparison.md
- **Can't find something?** → Check the file index above

---

**Total Documentation**: ~140KB | **Files**: 10 core + 3 extensions | **Examples**: 30+ | **Patterns**: 8 + 3 extension ideas

Last updated: December 2025
