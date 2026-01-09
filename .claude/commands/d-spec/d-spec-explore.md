---
description: Explore target codebase or repo for patterns and examples
argument-hint: [source] "[feature/goal]"
---
Explore the source code at `$1` to understand how it implements `$2`.  
Adapt findings for our project.

**Steps**:
1. **Analyze** `$1` for:  
   * Key patterns/APIs related to `$2`.  
   * Configs (auth, dependencies), error handling, and optimizations.  
2. **Extract** reusable snippets/modules.  
3. **Adapt** for our use case (modify for clarity, security, or compatibility).  

**Deliverables**:  
* Summary of `$2` implementation in `$1`.  
* Boilerplate code (with inline comments for adjustments).  
* Caveats or integration steps.
