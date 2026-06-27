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

## Slicing Debug Logs

When debugging slicing path generation, ordering, seam placement, wall generation, extrusion roles, or preview/G-code mismatches, use the structured slicing debug log system before relying on screenshots or visual guesses.

For Optimize seam / `seam_optimization` issues, the implementation writes structured logs to:

- `debug_logs/slicing/optimize_seam_latest.log` under the BambuStudio data directory

Required debugging workflow:

- Confirm whether the relevant option is enabled and whether the code path was entered.
- Record layer id, print Z, region index, perimeter count, external wall count, inner wall candidate count, mapping decisions, shared-wall splits, and final emission order.
- Use the log to identify whether a problem is caused by option propagation, missing candidates, wrong inner/external mapping, assignment conflicts, group ordering, or later G-code/preview processing.
- If the existing log fields are insufficient, extend the structured log format instead of adding temporary one-off `printf` statements.
- Keep debug logging low-intrusion and gated by the feature or an explicit debug condition; do not flood normal slicing logs for unrelated users.

## Packaging Workflow

After feature changes, provide a runnable macOS app for testing.

- For first builds, dependency/CMake changes, architecture changes, or release-like verification, use the full packaging path:
  `./BuildMac.sh -s -x -a arm64 -c Release -t 14.0`
- For ordinary C++/resource/profile edits after a full build already exists, prefer the fast packaging path:
  `tools/dev/fast_package_mac.sh -a arm64 -c Release`
- If the fast packaging path fails because the build directory is missing or CMake configuration changed, fall back to the full packaging path and record the reason in `DEBUGGING_KNOWLEDGE_BASE.md`.
