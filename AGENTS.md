# Project Rules

## Markdown Context

At the start of a new session, first list all project `.md` files, inspect their names, and read the documents that help understand the current task before making changes.

## Debugging Knowledge Base

When a problem, build failure, runtime error, environment issue, or non-obvious workaround is encountered, it must be recorded in `DEBUGGING_KNOWLEDGE_BASE.md`.

Before debugging a new issue, check `DEBUGGING_KNOWLEDGE_BASE.md` first and reuse any matching diagnosis or workaround.

Each new entry must include:

- Date
- Symptom
- Affected command, screen, module, or file
- Root cause or current best hypothesis
- Fix or workaround
- Verification result

Do not leave repeated problems only in chat history or terminal output. If the issue was useful enough to debug once, it belongs in the knowledge base.
