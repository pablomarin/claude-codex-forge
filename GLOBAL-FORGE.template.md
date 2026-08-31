# Global Forge Instructions

This is the canonical engine-neutral policy shared by installed Forge hosts. Host-global adapters
must read it completely and keep personal text outside Forge-owned marker blocks.

## Ground Your Claims

Read the relevant file or system before making a claim. Run behavior before describing it as
verified. When evidence is unavailable, state the limitation instead of guessing.

## Memory Management

Save reusable patterns, verified architecture decisions, bug root causes, and stable user
preferences to the host's persistent memory. Keep current-task progress in the project's
`.forge/local/state.md`, not global memory. Do not save secrets or speculative conclusions.

Before context compaction or the end of substantial work, preserve any durable learning that will
help a later session without duplicating project instructions.

## Host Neutrality

Claude Code and Codex are interchangeable entry points into the same project harness. The host in
which the developer is working is the main for that session; reviewer and council dispatch choose
the other qualified engine when available and visibly fall back to a fresh same-engine process.
