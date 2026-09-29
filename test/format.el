;;; format.el --- Format Emacs Lisp the way emacs -Q does -*- lexical-binding: t; -*-

;;; Commentary:

;; emacs -Q --batch -L . -l test/format.el [--check] FILE...
;;
;; Loads each FILE first, so that its `(declare (indent N))' forms apply,
;; then indents it in `emacs-lisp-mode', untabifies it and deletes
;; trailing whitespace.  Without --check each FILE is rewritten.  With
;; it, nothing is written: a diff of what would change is printed, and
;; Emacs exits 1 if anything would.

;;; Code:

(let* ((check (member "--check" command-line-args-left))
       (files (remove "--check" command-line-args-left))
       (changed nil))
  (setq command-line-args-left nil)
  (dolist (file files)
    (load (expand-file-name file) nil t))
  (dolist (file files)
    (with-temp-buffer
      (insert-file-contents file)
      (emacs-lisp-mode)
      (let ((before (buffer-string))
            (inhibit-message t))
        (indent-region (point-min) (point-max))
        (untabify (point-min) (point-max))
        (delete-trailing-whitespace)
        (unless (equal before (buffer-string))
          (push file changed)
          (if (not check)
              (write-region nil nil file nil 'silent)
            (let ((tmp (make-temp-file "format-")))
              (unwind-protect
                  (progn
                    (write-region nil nil tmp nil 'silent)
                    (princ (shell-command-to-string
                            (format "diff -u --label %s --label %s %s %s"
                                    (shell-quote-argument file)
                                    (shell-quote-argument (concat file " (formatted)"))
                                    (shell-quote-argument file)
                                    (shell-quote-argument tmp)))))
                (delete-file tmp))))))))
  (when changed
    (message "%s: %s" (if check "Not formatted" "Formatted")
             (mapconcat #'identity (nreverse changed) " "))
    (when check
      (kill-emacs 1))))

;;; format.el ends here
