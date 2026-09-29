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

;; `org-clock-out' totals the two stamps as written, so the seconds they
;; drop have to be dropped from the total too.
(ert-deftest org-retroclock-insert-totals-the-stamps-as-org-does ()
  (org-retroclock-test--with-entry
    (org-retroclock--insert (time-add org-retroclock-test--start 30)
                            org-retroclock-test--end)
    (should (equal (org-retroclock-test--clock-line)
                   "CLOCK: [2026-09-24 Thu 09:00]--[2026-09-24 Thu 10:30] =>  1:30")))
  (org-retroclock-test--with-entry
    (org-retroclock--insert org-retroclock-test--start
                            (time-subtract org-retroclock-test--end 30))
    (should (equal (org-retroclock-test--clock-line)
                   "CLOCK: [2026-09-24 Thu 09:00]--[2026-09-24 Thu 10:29] =>  1:29"))))

(ert-deftest org-retroclock-reads-a-fraction-to-the-nearest-minute ()
  (should (= (org-retroclock-test--read-duration "1.33h" 'never) 80))
  (should (= (org-retroclock-test--read-duration "1:30:40" 'never) 91)))

(ert-deftest org-retroclock-insert-obeys-org-clock-into-drawer ()
  (org-retroclock-test--with-entry
    (let ((org-clock-into-drawer nil))
      (org-retroclock--insert org-retroclock-test--start org-retroclock-test--end))
    (should-not (string-match-p ":LOGBOOK:" (buffer-string))))
  (org-retroclock-test--with-entry
    (let ((org-clock-into-drawer "CLOCKING"))
      (org-retroclock--insert org-retroclock-test--start org-retroclock-test--end))
    (should (string-match-p ":CLOCKING:" (buffer-string)))))

(ert-deftest org-retroclock-insert-goes-newest-first-in-an-existing-logbook ()
  (org-retroclock-test--with-entry
    (goto-char (point-max))
    (insert ":LOGBOOK:\nCLOCK: [2026-09-01 Tue 08:00]--[2026-09-01 Tue 09:00] =>  1:00\n:END:\n")
    (goto-char (point-min))
    (org-retroclock--insert org-retroclock-test--start org-retroclock-test--end)
    (should (string-match-p (concat "^:LOGBOOK:\n"
                                    "CLOCK: \\[2026-09-24[^\n]*\n"
                                    "CLOCK: \\[2026-09-01")
                            (buffer-string)))
    (goto-char (point-min))
    (should (equal (org-clock-sum-current-item) 150))))

(ert-deftest org-retroclock-insert-lands-after-a-properties-drawer ()
  (org-retroclock-test--with-entry
    (goto-char (point-max))
    (insert "SCHEDULED: <2026-09-24 Thu>\n:PROPERTIES:\n:ID: x\n:END:\nbody\n")
    (goto-char (point-min))
    (org-retroclock--insert org-retroclock-test--start org-retroclock-test--end)
    (should (string-match-p ":PROPERTIES:\n:ID: x\n:END:\n:LOGBOOK:\nCLOCK:" (buffer-string)))
    (goto-char (point-min))
    (should (equal (org-clock-sum-current-item) 90))))

(ert-deftest org-retroclock-insert-clocks-the-entry-not-its-children ()
  (org-retroclock-test--with-entry
    (goto-char (point-max))
    (insert "** Child\n")
    (goto-char (point-min))
    (org-retroclock--insert org-retroclock-test--start org-retroclock-test--end)
    (goto-char (point-min))
    (re-search-forward "^\\*\\* Child")
    (should (equal (org-clock-sum-current-item) 0))))

(ert-deftest org-retroclock-insert-handles-a-span-past-a-day ()
  (org-retroclock-test--with-entry
    (org-retroclock--insert org-retroclock-test--start
                            (time-add org-retroclock-test--start (* 30 3600)))
    (should (equal (org-retroclock-test--clock-line)
                   "CLOCK: [2026-09-24 Thu 09:00]--[2026-09-25 Fri 15:00] => 30:00"))
    (goto-char (point-min))
    (should (equal (org-clock-sum-current-item) 1800))))

(ert-deftest org-retroclock-insert-refuses-to-work-before-the-first-heading ()
  (let ((system-time-locale "C"))
    (with-temp-buffer
      (org-mode)
      (insert "Preamble, no heading yet.\n")
      (goto-char (point-min))
      (should-error (org-retroclock--insert org-retroclock-test--start
                                            org-retroclock-test--end)
                    :type 'user-error))))

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

(ert-deftest org-retroclock-ignores-narrowing-to-the-heading-line ()
  (org-retroclock-test--with-entry
    (goto-char (point-max))
    (insert ":LOGBOOK:\nCLOCK: [2026-09-01 Tue 08:00]--[2026-09-01 Tue 09:00] =>  1:00\n:END:\n")
    (goto-char (point-min))
    (narrow-to-region (point) (line-end-position))
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "90")))
      (org-retroclock nil))
    (should (= (point-max) (line-end-position)))
    (widen)
    (should (= (how-many ":LOGBOOK:" (point-min) (point-max)) 1))
    (goto-char (point-min))
    (should (equal (org-clock-sum-current-item) 150))))

(ert-deftest org-retroclock-ignores-narrowing-to-the-body ()
  (org-retroclock-test--with-entry
    (goto-char (point-max))
    (insert "body line\n")
    (goto-char (point-min))
    (forward-line 1)
    (narrow-to-region (point) (point-max))
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "90")))
      (org-retroclock nil))
    (widen)
    (should (string-match-p "\\`\\* Write the tests\n:LOGBOOK:\nCLOCK: " (buffer-string)))))

(defun org-retroclock-test--read-duration (input &optional confirm)
  "Return what `org-retroclock--read-duration' makes of INPUT.
CONFIRM is the answer to any `y-or-n-p', which fails the test if it is
asked and CONFIRM is the symbol `never'."
  (cl-letf (((symbol-function 'read-string) (lambda (&rest _) input))
            ((symbol-function 'y-or-n-p)
             (lambda (&rest _)
               (when (eq confirm 'never)
                 (ert-fail "y-or-n-p was not expected"))
               confirm)))
    (org-retroclock--read-duration)))

(ert-deftest org-retroclock-reads-m-as-minutes-not-months ()
  (should (= (org-retroclock-test--read-duration "90m" 'never) 90))
  (should (= (org-retroclock-test--read-duration "1h30m" 'never) 90))
  (should (= (org-retroclock-test--read-duration "1.5h" 'never) 90))
  (should (= (org-retroclock-test--read-duration "90min" 'never) 90))
  (should (= (org-retroclock-test--read-duration "1:30" 'never) 90))
  (should (= (org-retroclock-test--read-duration "90" 'never) 90)))

(ert-deftest org-retroclock-asks-before-logging-more-than-a-day ()
  (should (= (org-retroclock-test--read-duration "24h" 'never) 1440))
  (should (= (org-retroclock-test--read-duration "30h" t) 1800))
  (should-error (org-retroclock-test--read-duration "30h" nil) :type 'user-error))

(ert-deftest org-retroclock-prompt-names-the-accepted-forms ()
  (let (prompt)
    (cl-letf (((symbol-function 'read-string)
               (lambda (p &rest _) (setq prompt p) "90")))
      (org-retroclock--read-times nil))
    (should (string-prefix-p "Duration (90, 90m, 1h30m or 1:30)" prompt))))

(ert-deftest org-retroclock-refuses-less-than-a-minute ()
  (should-error (org-retroclock-test--read-duration "0:00:30" 'never) :type 'user-error)
  (should-error (org-retroclock-test--read-duration "0.5" 'never) :type 'user-error)
  (should (= (org-retroclock-test--read-duration "1" 'never) 1)))

(defun org-retroclock-test--read-anchored (anchor time duration)
  "Return `org-retroclock--read-times' for ANCHOR (?s or ?e) at TIME.
DURATION is the string typed at the duration prompt."
  (cl-letf (((symbol-function 'read-char-choice) (lambda (&rest _) anchor))
            ((symbol-function 'org-read-date) (lambda (&rest _) time))
            ((symbol-function 'read-string) (lambda (&rest _) duration)))
    (org-retroclock--read-times t)))

(ert-deftest org-retroclock-refuses-an-end-in-the-future ()
  (should-error (org-retroclock-test--read-anchored
                 ?e (time-add (current-time) 3600) "30")
                :type 'user-error)
  (should-error (org-retroclock-test--read-anchored
                 ?s (time-subtract (current-time) 1800) "90")
                :type 'user-error))

(ert-deftest org-retroclock-allows-an-end-within-a-minute-of-now ()
  (should (org-retroclock-test--read-anchored
           ?e (time-add (current-time) 30) "30"))
  (should (org-retroclock-test--read-anchored
           ?s (time-subtract (current-time) 5400) "90")))

;; `org-current-time' rounds by `org-time-stamp-rounding-minutes', which
;; can put "now" minutes in the past and refuse the present as the future.
(ert-deftest org-retroclock-does-not-round-now-when-refusing-the-future ()
  (let ((org-clock-rounding-minutes 0)
        (org-time-stamp-rounding-minutes '(15 5))
        (now (encode-time '(0 37 10 24 9 2026 nil -1 nil))))
    (cl-letf (((symbol-function 'current-time) (lambda () now))
              ((symbol-function 'read-string) (lambda (&rest _) "30")))
      (should (time-equal-p (cdr (org-retroclock--read-times nil)) now)))))

(defmacro org-retroclock-test--no-prompts (&rest body)
  "Run BODY, failing the test if it reads a duration or an anchor."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'read-string)
              (lambda (&rest _) (ert-fail "read-string was called")))
             ((symbol-function 'read-char-choice)
              (lambda (&rest _) (ert-fail "read-char-choice was called"))))
     ,@body))

(defmacro org-retroclock-test--picking (marker &rest body)
  "Run BODY with `org-clock-select-task' returning MARKER."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'org-clock-load) #'ignore)
             ((symbol-function 'org-clock-select-task)
              (lambda (&rest _) ,marker)))
     ,@body))

(ert-deftest org-retroclock-refuses-a-read-only-buffer-before-prompting ()
  (org-retroclock-test--with-entry
    (setq buffer-read-only t)
    (org-retroclock-test--no-prompts
      (should-error (org-retroclock nil) :type 'buffer-read-only))))

(ert-deftest org-retroclock-recent-refuses-a-read-only-task-before-prompting ()
  (org-retroclock-test--with-entry
    (setq buffer-read-only t)
    (let ((marker (point-marker)))
      (with-temp-buffer
        (org-retroclock-test--picking marker
          (org-retroclock-test--no-prompts
            (should-error (org-retroclock-recent nil) :type 'buffer-read-only)))))))

(ert-deftest org-retroclock-recent-logs-on-the-picked-task ()
  (org-retroclock-test--with-entry
    (insert "* Other\n* Picked\n")
    (goto-char (point-min))
    (re-search-forward "^\\* Picked")
    (let ((marker (copy-marker (line-beginning-position))))
      (goto-char (point-min))
      (narrow-to-region (point) (line-end-position))
      (with-temp-buffer
        (org-retroclock-test--picking marker
          (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "90m")))
            (org-retroclock-recent nil))))
      (widen)
      (goto-char marker)
      (should (equal (org-clock-sum-current-item) 90))
      (goto-char (point-min))
      (should (equal (org-clock-sum-current-item) 0)))))

(ert-deftest org-retroclock-rounds-now-into-the-past ()
  (let ((org-clock-rounding-minutes 5)
        (now (encode-time '(0 33 10 24 9 2026 nil -1 nil))))
    (cl-letf (((symbol-function 'current-time) (lambda () now))
              ((symbol-function 'read-string) (lambda (&rest _) "90")))
      (pcase-let ((`(,start . ,end) (org-retroclock--read-times nil)))
        (should (time-equal-p start org-retroclock-test--start))
        (should (time-equal-p end org-retroclock-test--end))))))

(provide 'org-retroclock-test)
;;; org-retroclock-test.el ends here
