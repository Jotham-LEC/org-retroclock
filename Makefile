EMACS ?= emacs
PACKAGE := org-retroclock
TESTS := test/$(PACKAGE)-test.el

# Dependencies live in the checkout so that a local run and a CI run see the
# same versions, and neither touches the Emacs you actually use.
INIT := --eval '(progn (require (quote package)) (setq package-user-dir (expand-file-name ".deps") package-quickstart-file (expand-file-name ".deps/package-quickstart.el")) (add-to-list (quote package-archives) (cons "melpa" "https://melpa.org/packages/") t) (package-initialize))'
# Prefer newer sources, so a stale .elc from `make compile' isn't tested.
BATCH := $(EMACS) -Q --batch --eval '(setq load-prefer-newer t)' $(INIT) -L . -L test

.PHONY: all check deps compile checkdoc package-lint relint lint format format-check test clean

all: check

check: compile lint format-check test

deps:
	$(BATCH) --eval '(progn (package-refresh-contents) (package-install (quote package-lint)) (package-install (quote relint)))'

compile:
	$(BATCH) --eval '(setq byte-compile-warnings (quote all) byte-compile-error-on-warn t)' -f batch-byte-compile $(PACKAGE).el $(TESTS)

# checkdoc reports through the warnings buffer and exits zero regardless, so
# read the buffer back and fail on anything in it.  Emacs 31 turned the verb
# check off by default and 29 and 30 leave it on, so ask for it either way and
# a local run says what CI will.
checkdoc:
	$(BATCH) --eval '(progn (require (quote checkdoc)) (setq checkdoc-verb-check-experimental-flag t) (checkdoc-file "$(PACKAGE).el") (let ((warnings (get-buffer "*Warnings*"))) (when warnings (princ (with-current-buffer warnings (buffer-string))) (kill-emacs 1))))'

package-lint:
	$(BATCH) --eval '(require (quote package-lint))' -f package-lint-batch-and-exit $(PACKAGE).el

relint:
	$(BATCH) --eval '(require (quote relint))' -f relint-batch $(PACKAGE).el

lint: checkdoc package-lint relint

# Indentation is whatever emacs -Q makes of it, so every editor agrees.
format:
	$(BATCH) -l test/format.el $(PACKAGE).el $(TESTS)

format-check:
	$(BATCH) -l test/format.el --check $(PACKAGE).el $(TESTS)

test:
	$(BATCH) -l $(TESTS) -f ert-run-tests-batch-and-exit

clean:
	rm -f *.elc test/*.elc
