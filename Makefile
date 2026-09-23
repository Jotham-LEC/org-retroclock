EMACS ?= emacs
PACKAGE := org-retroclock

# Dependencies live in the checkout so that a local run and a CI run see the
# same versions, and neither touches the Emacs you actually use.
INIT := --eval '(progn (require (quote package)) (setq package-user-dir (expand-file-name ".deps")) (add-to-list (quote package-archives) (cons "melpa" "https://melpa.org/packages/") t) (package-initialize))'
BATCH := $(EMACS) -Q --batch $(INIT) -L . -L test

.PHONY: all deps compile checkdoc package-lint lint test clean

all: deps compile lint test

deps:
	$(BATCH) --eval '(progn (package-refresh-contents) (package-install (quote package-lint)))'

compile:
	$(BATCH) --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile $(PACKAGE).el test/$(PACKAGE)-test.el

# checkdoc reports through the warnings buffer and exits zero regardless, so
# read the buffer back and fail on anything in it.
checkdoc:
	$(BATCH) --eval '(progn (checkdoc-file "$(PACKAGE).el") (let ((warnings (get-buffer "*Warnings*"))) (when warnings (princ (with-current-buffer warnings (buffer-string))) (kill-emacs 1))))'

package-lint:
	$(BATCH) --eval '(require (quote package-lint))' -f package-lint-batch-and-exit $(PACKAGE).el

lint: checkdoc package-lint

test:
	$(BATCH) -l test/$(PACKAGE)-test.el -f ert-run-tests-batch-and-exit

clean:
	rm -f *.elc test/*.elc
