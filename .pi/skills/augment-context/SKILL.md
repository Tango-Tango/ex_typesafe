---
name: augment-context
description: Use Augment's codebase-retrieval for context gathering
---

# Augment Context Engine

You have access to Augment's context engine via MCP tools. **Always prefer these over grep/find for understanding code.**

## Primary Tool: `mcp:auggie_codebase-retrieval`

Use `mcp:auggie_codebase-retrieval` (or the direct tool if available) to find code. It:
- Takes natural language queries
- Returns relevant code snippets from across the codebase
- Maintains a real-time index (always current)
- Works across all languages

**Good queries:**
- "Where is authentication handled?"
- "How does the background isolate communicate with the UI?"
- "What tests exist for the call manager?"
- "How are push notifications configured?"

**When to use:**
- Finding code you don't know the location of
- Understanding how components connect
- Gathering context before making changes
- Finding all usages of a pattern or concept

## Secondary Tool: `git-commit-retrieval`

Use for understanding code history:
- "How was feature X implemented?"
- "Why was this changed?"
- "How did we handle similar changes before?"

## Workflow

1. **Start with `mcp:auggie_codebase-retrieval`** to understand the landscape
2. Use `read` to examine specific files it returns
3. Use `grep`/`find` only for exact string matches or file patterns
4. Use `git-commit-retrieval` when history context helps

## Don't

- Don't grep blindly hoping to find things
- Don't read entire files when you need specific sections
- Don't skip context gathering before making changes

