# Changelog

All notable changes to org-retroclock are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] — 2026-09-24

First release, extracted from the author's Doom Emacs configuration where it had been
in daily use.

### Added
- **`org-retroclock`** logs a finished `CLOCK:` entry on the Org entry at point, and
  **`org-retroclock-recent`** does the same for a task chosen from
  `org-clock-select-task`, the picker `org-clock-in` already uses. Both read a duration
  ending now, or with a prefix argument a span pinned to a start or an end time.
- **`org-retroclock-push-history`** (default `t`) decides whether a retroactive clock
  joins `org-clock-history` and so turns up in those pickers later.

[Unreleased]: https://github.com/Jotham-LEC/org-retroclock/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Jotham-LEC/org-retroclock/releases/tag/v0.1.0
