---
name: format
description: Format Swift with the repo SwiftFormat config. Use after editing .swift files, before verify, or when CI format job fails.
---

# Format

```bash
./Scripts/format.sh
```

Config is `.swiftformat`. Do not add SwiftLint, Prettier for Swift, or a second formatter.

Claude Code already formats a Swift file on Write/Edit via `.claude/hooks/format-swift.sh`. Still run the script before claiming done so untouched files are consistent.

```bash
swiftformat Packages Apps Tools Tests --config .swiftformat --lint
```
