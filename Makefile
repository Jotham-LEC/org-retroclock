EMACS ?= emacs
PACKAGE := org-retroclock
BATCH := $(EMACS) -Q --batch -L . -L test

.PHONY: all deps compile checkdoc package-lint lint test clean

all: compile lint test

# Only CI needs this; an Emacs you already configured has package-lint.
deps:
	$(BATCH) --eval '(progn (require (quote package)) (add-to-list (quote package-archives) (cons "melpa" "https://melpa.org/packages/") t) (package-initialize) (package-refresh-contents) (package-install (quote package-lint)))'

compile:
	$(BATCH) --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile $(PACKAGE).el test/$(PACKAGE)-test.el

# checkdoc reports through the warnings buffer and exits zero regardless, so
# read the buffer back and fail on anything in it.
checkdoc:
	$(BATCH) --eval '(progn (checkdoc-file "$(PACKAGE).el") (let ((warnings (get-buffer "*Warnings*"))) (when warnings (princ (with-current-buffer warnings (buffer-string))) (kill-emacs 1))))'

package-lint:
	$(BATCH) --eval '(progn (require (quote package)) (package-initialize) (require (quote package-lint)))' -f package-lint-batch-and-exit $(PACKAGE).el

lint: checkdoc package-lint

test:
	$(BATCH) -l test/$(PACKAGE)-test.el -f ert-run-tests-batch-and-exit

clean:
	rm -f *.elc test/*.elc
