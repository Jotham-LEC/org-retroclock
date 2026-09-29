# Changelog

All notable changes to org-retroclock are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.2] — 2026-09-29

### Fixed
- The `=>` total is worked out from the two timestamps as written, as `org-clock-out`
  does, so it always agrees with them; `1.33h` wrote `09:10--10:30 => 1:19`. A
  duration is rounded to whole minutes.
- A span ending now is no longer refused as ending in the future when
  `org-time-stamp-rounding-minutes` rounds the clock back.
- A date without a year is read as the past one: `25` typed on the 29th is the 25th
  just gone, not next month's. Org reads a weekday such as `fri` forwards regardless,
  so the date prompt and the refusal of a future span point to `-fri`, last Friday.
- A buffer not in Org mode, and a point before the first heading, are refused before
  any prompt. Outside Org mode an empty `:LOGBOOK:` drawer used to be left behind.
- `90 m`, with a space, and `90M` whatever `case-fold-search` says, are minutes.
  Input that is not a duration is refused with a clear message instead of an error
  from inside Org.
- Logging on the task being clocked updates its total in the mode line.

### Added
- Both commands echo the line they wrote and the entry it went on.

### Removed
- `org-retroclock-push-history`. A retroactive clock always joins `org-clock-history`,
  as `org-clock-in` always adds the task it clocks. A leftover `setq` of the option
  does nothing and can be deleted.

### Changed
- `make check` runs byte-compilation with all warnings as errors (tests included),
  checkdoc, package-lint, relint, a format check and the tests; CI runs it on Emacs
  29.1, 30.1, 31.1 and a snapshot.
- The README and commentary no longer claim a picked task need not be in an open
  buffer: `org-clock-history` drops a task along with its buffer.

## [0.1.1] — 2026-09-28

### Fixed
- A number followed by `m` is read as minutes. Org reads `m` as months, so `90m`
  logged 3,888,000 minutes and `1h30m` 1,296,060.
- A span of more than a day has to be confirmed.
- A duration under a minute is refused instead of writing a `0:00` line.
- A span that ends more than a minute in the future is refused.
- A read-only buffer is refused before any prompt, not after the last one.
- `org-retroclock` widens first, so a narrowed buffer no longer gets a second
  `:LOGBOOK:` drawer or a line below the body text.
- A span ending now is rounded by `org-clock-rounding-minutes`, never into the future,
  as `org-clock-in` rounds its own.

### Changed
- `org-retroclock` is marked as an `org-mode` command, so `M-x` hides it elsewhere.
- The suggested binding is `C-c C-x h`; `C-c C-x C-p` is `org-previous-link`.
- `LICENSE` is the verbatim GPL-3 text, so GitHub detects it.

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

[Unreleased]: https://github.com/Jotham-LEC/org-retroclock/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/Jotham-LEC/org-retroclock/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/Jotham-LEC/org-retroclock/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Jotham-LEC/org-retroclock/releases/tag/v0.1.0
