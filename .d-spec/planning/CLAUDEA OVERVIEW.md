# ClaudEA Overview
ClaudEA is a collection of prompts, skills, commands, scripts, workflows, and the like that turn Claude Code into a full-fledged executive assistant capable of managing notes, tasks, projects, calendar, and email/text communications using CLI apps/packages + text/.md files in any markdown-compatible editor or vault.

## Core Vision: Managing a Team of AI Agents
ClaudEA enables you to **manage by exception** rather than do all the work yourself. Spin up multiple specialized Claude sub-agents to handle knowledge work and coding tasks autonomously. You step in only for edge cases requiring human judgment. Each agent has the context, instruction, and intent needed to actually augment or fully automate your work.

## Problems ClaudEA Solves
- **Fragmented tools/systems**: Eliminates context loss from switching between disconnected apps
- **Information/task overload**: Provides intelligent triage and organization of overwhelming volume
- **Reactive workflows**: Replaces reactive task management with proactive, anticipatory assistance
- **GUI dependency**: Enables pure CLI/text-based workflow without constant context switching

## Design Principles
**Text-File Native Architecture**: Everything stored as plain text/markdown + local SQL database. No proprietary formats, no vendor lock-in.

**CLI-First Interface**: Terminal-based, scriptable, automation-friendly. No GUI required.

**Editor Agnostic**: Works with any markdown-compatible text editor or notes app (Obsidian, VS Code, Vim, Typora, Logseq, etc.). Your choice of interface, not ours.

**Full Control & Transparency**: You own the data. You can inspect, modify, and understand everything. No black boxes.

## Interoperability
The user interfaces with ClaudEA via the Claude Code CLI application in their markdown vault/workspace. The capabilities, prompts, scripts, etc. that provide context, intent, decision tree context, and instruction to the Claude Code agent are intentionally interoperable with other CLI coding agents, AI agents in general, and any markdown/text editor.

## Scope: Ideas, Not Implementation
Everything in the 'claudea ideas' folder captures high-level vision and concepts - a place to explore possibilities before moving to development. This is where features (prompts, skills, plugins, scripts, agents) are imagined, not built.
