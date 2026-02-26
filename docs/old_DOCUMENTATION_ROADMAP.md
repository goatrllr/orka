# Orka Documentation Roadmap

## New Documentation Structure

### Primary Documents

#### 1. [Readme-Core.md](Readme-Core.md) ⭐ **NEW**
**Purpose**: Stable Core API reference  
**Scope**: All 31 exported functions with examples  
**Audience**: Extension builders, production deployments  
**Updates**: Only adds new core functions (no breaking changes)

**Key Sections**:
- Architecture & Design Principles
- API Reference (31 functions organized by category)
- Data Structures (Entry, Key, Metadata)
- Test Coverage (61/61 passing)
- Extension Pattern & Principles
- Design for Extensions (what builders need)
- Usage Examples (basic, coordination, load balancing)
- FAQ for Extension Builders

#### 2. [README.md](README.md) 🔄 **UPDATED**
**Purpose**: Project overview and quick start  
**Scope**: Links to Core, highlights, comparison  
**Audience**: New users, project overview  
**Updates**: Can reference extensions, highlight features

**Updates Made**:
- Added link to Readme-Core.md in introduction
- Updated test coverage to 61/61 (from logs)
- Added new functions to API Overview:
  - `lookup_alive/1` — Liveness validation
  - `keys_by_type/1` — Lightweight type queries
  - `keys_by_tag/1` — Lightweight tag queries
  - `find_keys_by_property/2,3` — Property-based key queries
- Added "API Stability" design principle
- Updated test coverage details
- Added split-branch strategy explanation in footer

#### 3. [SPLIT_BRANCH_STRATEGY.md](SPLIT_BRANCH_STRATEGY.md) ⭐ **NEW**
**Purpose**: Architecture guide for Core + Extensions  
**Scope**: Split-branch design, extension patterns  
**Audience**: Extension builders, architecture decisions  
**Updates**: Design pattern (rarely changes)

**Key Sections**:
- Architecture diagram (Core → Extensions)
- Core Guarantees (stability, performance, policies)
- Extension Pattern (with working code example)
- How to Build Extensions (step by step)
- Test Coverage Strategy
- FAQ for Extension Builders
- Core Principles & Minimalism

### Supporting Documents (Existing)

#### [API.md](API.md)
**Purpose**: Complete, detailed API documentation  
**Status**: Updated with new function examples  
**Sections**: Same as Readme-Core but more detailed

#### [DOCMAP.md](DOCMAP.md)
**Purpose**: Navigation guide for all documentation  
**Status**: Existing (may reference new docs)

#### [docs/usage_patterns.md](docs/usage_patterns.md)
**Purpose**: 8 fundamental patterns  
**Status**: Existing patterns, may benefit from split-branch context

## New Functions Reference

### Function Groups

#### Liveness & Validation
- `lookup_alive/1` — Lookup with process liveness validation

#### Lightweight Key Queries
- `keys_by_type/1` — Get keys by type (vs entries)
- `keys_by_tag/1` — Get keys by tag (vs entries)
- `find_keys_by_property/2` — Get keys by property (vs entries)
- `find_keys_by_property/3` — Get keys by type + property (vs entries)

**Why Lightweight Versions?**
- Reduced memory footprint (keys only, not full entries)
- Better performance when full entry not needed
- Filtering before detailed operations
- Useful for extensions that add policies

## Documentation Flow

### For New Users
1. Start with [README.md](README.md) — quick overview
2. See [Readme-Core.md](Readme-Core.md) — API reference
3. Explore [docs/](docs/) — patterns and examples
4. Read [SPLIT_BRANCH_STRATEGY.md](SPLIT_BRANCH_STRATEGY.md) — architecture

### For Extension Builders
1. Read [SPLIT_BRANCH_STRATEGY.md](SPLIT_BRANCH_STRATEGY.md) — design pattern
2. Reference [Readme-Core.md](Readme-Core.md) — available core functions
3. Check [API.md](API.md) — detailed examples
4. See extension examples in [Readme-Core.md](Readme-Core.md#design-for-extensions)

### For Core Contributors
1. Understand [SPLIT_BRANCH_STRATEGY.md](SPLIT_BRANCH_STRATEGY.md) — guarantees
2. Review [Readme-Core.md](Readme-Core.md#core-principles) — design principles
3. Check test coverage in logs (61/61 passing)
4. Update docs when adding core functions (rarely)

## Test Coverage Reference

**From logs** (not run during documentation creation):
- ✅ 61/61 Core tests passing
- `orka_SUITE.erl` — Main test suite (coverage breakdown in Readme-Core.md)
- Test categories: registration, lookup, tags, properties, coordination, cleanup

## Key Design Decisions

### Split-Branch Strategy
**Rationale**: 
- Core API stability across versions
- Extensions can add features without modification
- Multiple extensions can coexist
- Clean architecture with no tangled dependencies

**Guarantee**: 
- Core functions never break
- New functions added for universal use only
- Extensions are optional, not required

### New Lightweight Functions
**Rationale**:
- Developers often need only keys, not full entries
- Reduces memory and processing overhead
- Common pattern in filtering, load balancing

**Added in Core**:
- `keys_by_type/1` — Type-based key enumeration
- `keys_by_tag/1` — Tag-based key enumeration
- `find_keys_by_property/2,3` — Property-based key queries

### Liveness Validation
**Rationale**:
- Common pattern: lookup + check if alive
- Auto-cleanup of dead entries reduces stale data
- Better user experience with async cleanup

**Added in Core**:
- `lookup_alive/1` — Lookup with liveness check

## File Locations

```
/workspace/projects/orka/
├── Readme-Core.md                    # ⭐ NEW: Core API reference
├── README.md                         # 🔄 UPDATED: Project overview  
├── SPLIT_BRANCH_STRATEGY.md          # ⭐ NEW: Architecture guide
├── API.md                            # Complete API reference
├── DOCMAP.md                         # Documentation navigation
├── src/
│   └── orka.erl                      # Main module (719 lines code)
├── test/
│   └── orka_SUITE.erl                # Core tests (61/61 passing)
└── docs/
    ├── usage_patterns.md
    ├── singleton_examples.md
    ├── property_examples.md
    ├── await_examples.md
    ├── comparison.md
    └── extensions/
        ├── orka_syn.md
        ├── groups_examples.md
        └── message_systems.md
```

## Documentation Maintenance

### When to Update Readme-Core.md
- Adding new core functions (rare, only if universally useful)
- Fixing errors or clarifying existing content
- Adding new examples
- **NOT**: Removing functions, changing signatures, policy changes

### When to Update README.md
- Highlighting new features
- Linking to new documentation
- Updating examples
- Reflecting new use cases

### When to Update SPLIT_BRANCH_STRATEGY.md
- Clarifying extension pattern
- Adding extension examples
- Updating FAQ based on common questions
- Refining core guarantees (rare)

## Testing & Validation

**Core Test Status**: 61/61 passing ✅
- Sourced from: Test logs (not run during documentation session)
- Last run: 2026-01-14
- Coverage: Registration, lookup, tags, properties, coordination, cleanup

**Documentation Validation**:
- ✅ All 31 functions documented in Readme-Core.md
- ✅ New functions (lookup_alive, keys_by_*, find_keys_by_property) included
- ✅ README.md updated with links and new functions
- ✅ Split-branch strategy explained in detail
- ✅ Examples for extension builders provided

## Next Steps

### Immediate (Documentation Complete)
- ✅ Readme-Core.md created (517 lines)
- ✅ README.md updated (467 lines)
- ✅ SPLIT_BRANCH_STRATEGY.md created (214 lines)

### Future (Optional Extensions)
- Service discovery extension (with custom policies)
- Process groups extension (named collections)
- Distributed registry extension (multi-node)
- Metrics/observability extension (telemetry)

All built on stable Core without modification.

---

**Documentation Version**: 1.0 | **Core Functions**: 31 | **Tests**: 61/61 | **Status**: Complete ✅
