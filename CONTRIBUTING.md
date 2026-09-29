# Contributing

- `make deps` once, then `make check` must be green: byte-compilation with every
  warning an error (tests included), checkdoc, package-lint, relint, the format
  check and the ERT suite.
- Every fix comes with a regression test, and that test is shown to fail without
  the fix.
- Tests stub only OS and process boundaries (the clock, the minibuffer), never
  the behaviour under test.
- Tests are byte-compiled like the package, so they meet the same warnings.
- Formatting is `make format`: indentation as `emacs -Q` makes it, spaces, no
  trailing whitespace.
