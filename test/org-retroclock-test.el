;;; org-retroclock-test.el --- Tests for org-retroclock -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with `make test'.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'org-retroclock)

(defconst org-retroclock-test--start
  (encode-time '(0 0 9 24 9 2026 nil -1 nil))
  "Thursday 24 September 2026, 09:00 local time.")

(defconst org-retroclock-test--end
  (encode-time '(0 30 10 24 9 2026 nil -1 nil))
  "Ninety minutes after `org-retroclock-test--start'.")

(defmacro org-retroclock-test--with-entry (&rest body)
  "Run BODY at the heading of a one-entry Org buffer."
  (declare (indent 0))
  `(let ((system-time-locale "C")
         (org-clock-history nil))
     (with-temp-buffer
       (org-mode)
       (insert "* Write the tests\n")
       (goto-char (point-min))
       ,@body)))

(defun org-retroclock-test--clock-line ()
  "Return the buffer's CLOCK line, without indentation."
  (goto-char (point-min))
  (when (re-search-forward (concat "^[ \t]*" (regexp-quote org-clock-string) ".*$") nil t)
    (string-trim (match-string 0))))

(ert-deftest org-retroclock-insert-writes-a-closed-clock-line ()
  (org-retroclock-test--with-entry
    (org-retroclock--insert org-retroclock-test--start org-retroclock-test--end)
    (should (equal (org-retroclock-test--clock-line)
                   "CLOCK: [2026-09-24 Thu 09:00]--[2026-09-24 Thu 10:30] =>  1:30"))))

(ert-deftest org-retroclock-insert-lands-inside-the-entry ()
  (org-retroclock-test--with-entry
    (org-retroclock--insert org-retroclock-test--start org-retroclock-test--end)
    (goto-char (point-min))
    (re-search-forward (regexp-quote org-clock-string))
    (should (equal (org-get-heading t t t t) "Write the tests"))
    ;; Org's own reader has to agree that this is a clock line on this entry.
    (should (equal (org-clock-sum-current-item) 90))))

(ert-deftest org-retroclock-insert-pads-hours-past-ten ()
  (org-retroclock-test--with-entry
    (org-retroclock--insert org-retroclock-test--start
                            (time-add org-retroclock-test--start (* 11 3600)))
    (should (string-suffix-p "=> 11:00" (org-retroclock-test--clock-line)))))

(ert-deftest org-retroclock-push-history-is-customisable ()
  (org-retroclock-test--with-entry
    (let ((org-retroclock-push-history nil))
      (org-retroclock--insert org-retroclock-test--start org-retroclock-test--end))
    (should (null org-clock-history))
    (org-retroclock--insert org-retroclock-test--start org-retroclock-test--end)
    (should (= (length org-clock-history) 1))))

(ert-deftest org-retroclock-read-times-without-anchor-ends-now ()
  (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "1:30")))
    (pcase-let ((`(,start . ,end) (org-retroclock--read-times nil)))
      (should (= (round (float-time (time-subtract end start))) 5400))
      (should (< (abs (float-time (time-subtract (current-time) end))) 5)))))

(ert-deftest org-retroclock-read-times-anchors-on-a-start ()
  (cl-letf (((symbol-function 'read-char-choice) (lambda (&rest _) ?s))
            ((symbol-function 'org-read-date)
             (lambda (&rest _) org-retroclock-test--start))
            ((symbol-function 'read-string) (lambda (&rest _) "90")))
    (pcase-let ((`(,start . ,end) (org-retroclock--read-times t)))
      (should (time-equal-p start org-retroclock-test--start))
      (should (time-equal-p end org-retroclock-test--end)))))

(ert-deftest org-retroclock-read-times-anchors-on-an-end ()
  (cl-letf (((symbol-function 'read-char-choice) (lambda (&rest _) ?e))
            ((symbol-function 'org-read-date)
             (lambda (&rest _) org-retroclock-test--end))
            ((symbol-function 'read-string) (lambda (&rest _) "90")))
    (pcase-let ((`(,start . ,end) (org-retroclock--read-times t)))
      (should (time-equal-p start org-retroclock-test--start))
      (should (time-equal-p end org-retroclock-test--end)))))

(ert-deftest org-retroclock-rejects-a-non-positive-duration ()
  (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "0")))
    (should-error (org-retroclock--read-times nil) :type 'user-error)))

(provide 'org-retroclock-test)
;;; org-retroclock-test.el ends here
