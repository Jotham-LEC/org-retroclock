;;; org-retroclock.el --- Log finished Org CLOCK entries retroactively -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jotham Lim Ee Chen

;; Author: Jotham Lim Ee Chen <jotham@cothink.ing>
;; Assisted-by: Claude:claude-opus-5
;; URL: https://github.com/Jotham-LEC/org-retroclock
;; Version: 0.1.1
;; Package-Requires: ((emacs "29.1"))
;; Keywords: outlines, calendar, convenience
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or (at
;; your option) any later version.
;;
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Org clocks the present tense.  You clock in, you work, you clock out.
;; Work you finished without clocking has no command at all: three prefix
;; arguments to `org-clock-in' only resume the last clock-out, and packages
;; such as org-clock-convenience correct CLOCK lines that already exist.
;;
;; org-retroclock writes the line that was never there.  Say how long the
;; work took and it inserts a finished CLOCK entry -- start, end and total
;; -- where Org would have logged it, without starting a live clock.
;;
;; `org-retroclock' acts on the entry at point.  `org-retroclock-recent'
;; offers the picker `org-clock-in' uses for recently clocked tasks, so the
;; entry need not be on screen.  The picker reads `org-clock-history',
;; which holds a task only while its buffer is open, and which Org forgets
;; when Emacs exits unless `org-clock-persist' is set.
;;
;; Both read a duration ("90", "90m", "1h30m" or "1:30") ending now.  A
;; trailing "m" means minutes, not Org's months.  With a prefix argument
;; they first ask which end of the span you want to pin, then read that
;; time and the duration, so an hour you spent this morning and a meeting
;; that ended at six are equally easy to say.  A date without a year is
;; read as the past one, and "-fri" is last Friday.  A span under a minute
;; or ending in the future is refused, and one over a day asks first.
;;
;; No keys are bound.  Bind the two commands wherever your Org keys live:
;;
;;     (keymap-set org-mode-map "C-c C-x h" #'org-retroclock)
;;     (keymap-global-set "C-c o p" #'org-retroclock-recent)

;;; Code:

(require 'org)
(require 'org-clock)

(defun org-retroclock--insert (start end)
  "Insert a finished CLOCK line spanning START to END on the entry at point.
START and END are Lisp timestamps.  Return the line's span and total."
  (save-excursion
    (org-back-to-heading t)
    ;; A task clocked after the fact is a recent task all the same, as
    ;; `org-clock-in' makes it.
    (org-clock-history-push)
    (org-clock-find-position nil)
    (let* ((stamp (org-time-stamp-format t t))
           (ts (format-time-string stamp start))
           (te (format-time-string stamp end))
           ;; The total is worked out from the stamps, as `org-clock-out'
           ;; works out its own, so that it agrees with what the line says.
           (seconds (org-time-convert-to-integer
                     (time-subtract (org-time-string-to-time te)
                                    (org-time-string-to-time ts))))
           (hours (floor seconds 3600))
           (minutes (floor (mod seconds 3600) 60)))
      ;; `org-clock-find-position' leaves point at the start of the line the
      ;; new one goes above.  Open a line there, as `org-clock-in' does.
      (insert-before-markers-and-inherit "\n")
      (backward-char 1)
      (insert-and-inherit org-clock-string " " ts "--" te " => "
                          (format "%2d:%02d" hours minutes))
      (org-indent-line)
      ;; A running clock on this entry shows the entry's total in the
      ;; mode line, which has just grown.  With no clock running, the
      ;; marker has no buffer.
      (org-back-to-heading t)
      (when (and (eq (marker-buffer org-clock-hd-marker)
                     (org-base-buffer (current-buffer)))
                 (= org-clock-hd-marker (point)))
        (setq org-clock-total-time
              (org-clock-sum-current-item (org-clock-get-sum-start)))
        (org-clock-update-mode-line))
      (format "%s--%s => %d:%02d" ts te hours minutes))))

(defun org-retroclock--read-duration ()
  "Read a duration from the minibuffer and return it in whole minutes.
Org reads a bare \"m\" as months, so a number followed by \"m\" is
taken as minutes here: nobody logs a clock in months.  A span under a
minute is refused, because the CLOCK line would total 0:00, and a span
of more than a day has to be confirmed."
  (let* ((input (let ((case-fold-search t))
                  (replace-regexp-in-string
                   "\\([0-9.]\\) *m\\b" "\\1min"
                   (string-trim (read-string "Duration (90, 90m, 1h30m or 1:30): "))
                   t)))
         (minutes
          ;; `org-duration-p' leaves out the bare number, which
          ;; `org-duration-to-minutes' reads as minutes.
          (if (or (org-duration-p input)
                  (string-match-p "\\`[0-9]+\\(?:\\.[0-9]*\\)?\\'" input))
              (org-duration-to-minutes input)
            (user-error "Not a duration: %S" input))))
    (when (< minutes 1)
      (user-error "Duration must be at least a minute"))
    (when (and (> minutes (* 24 60))
               (not (y-or-n-p (format "Log %s, more than a day? "
                                      (org-duration-from-minutes minutes)))))
      (user-error "Not logged"))
    ;; A CLOCK line has no seconds, so neither does the span.
    (round minutes)))

(defun org-retroclock--read-date (prompt)
  "Read a date and time with PROMPT, taking a date without a year as past.
Org reads a bare weekday forwards however it is told, so the prompt
also mentions \"-fri\", which Org reads as last Friday."
  (let ((org-read-date-prefer-future nil))
    (org-read-date t t nil (concat prompt " (-fri for last Friday)"))))

(defun org-retroclock--read-times (anchored)
  "Return the cons (START . END) of a span read from the minibuffer.
When ANCHORED is nil the span is a duration ending now, rounded down
by `org-clock-rounding-minutes' as `org-clock-in' would.  Otherwise ask
which end to pin, read that time, and read the duration from there.
A span that ends more than a minute from now is refused: this logs work
already done."
  (let ((span
         (if (not anchored)
             (let* ((minutes (org-retroclock--read-duration))
                    (end (org-current-time org-clock-rounding-minutes t)))
               (cons (time-subtract end (seconds-to-time (* minutes 60))) end))
           (pcase (read-char-choice "Anchor: [s]tart time  [e]nd time: " '(?s ?e))
             (?s (let* ((start (org-retroclock--read-date "Start time"))
                        (minutes (org-retroclock--read-duration)))
                   (cons start (time-add start (seconds-to-time (* minutes 60))))))
             (?e (let* ((end (org-retroclock--read-date "End time"))
                        (minutes (org-retroclock--read-duration)))
                   (cons (time-subtract end (seconds-to-time (* minutes 60))) end)))))))
    (when (time-less-p (time-add (current-time) 60) (cdr span))
      (user-error "That span ends in the future, at %s; for last Friday type -fri"
                  (format-time-string (org-time-stamp-format t t) (cdr span))))
    span))

;; Both commands come through here, so that everything that can refuse
;; the entry does so before the first prompt.
(defun org-retroclock--log (marker arg)
  "Read a span and log it as a finished CLOCK entry on the entry at MARKER.
ARG is the prefix argument, as for `org-retroclock'.  A buffer that is
not in Org mode or is read-only, or a MARKER before the first heading,
is refused before anything is asked."
  (with-current-buffer (marker-buffer marker)
    (unless (derived-mode-p 'org-mode)
      (user-error "Not an Org buffer: %s" (buffer-name)))
    (barf-if-buffer-read-only)
    (org-with-wide-buffer
     (goto-char marker)
     (when (org-before-first-heading-p)
       (user-error "Not on an Org entry")))
    (pcase-let ((`(,start . ,end) (org-retroclock--read-times arg)))
      (org-with-wide-buffer
       (goto-char marker)
       (message "Logged %s on %s" (org-retroclock--insert start end)
                (org-get-heading t t t t))))))

;;;###autoload
(defun org-retroclock (arg)
  "Log a finished CLOCK entry on the Org entry at point.
Without a prefix, read a duration and log the span ending now.  With
prefix ARG, pin a start or end time first and log the span from there."
  (interactive "P" org-mode)
  (org-retroclock--log (point-marker) arg))

;;;###autoload
(defun org-retroclock-recent (arg)
  "Pick a recently clocked task and log a finished CLOCK entry on it.
The span is read as for `org-retroclock', including the meaning of
prefix ARG.  This is that command's global counterpart: it reaches any
task Org remembers clocking, rather than the entry at point."
  (interactive "P")
  (org-clock-load)
  (let ((marker (org-clock-select-task "Retro-clock which recent task? ")))
    (unless (and (markerp marker) (marker-buffer marker))
      (user-error "No task selected"))
    (org-retroclock--log marker arg)))

(provide 'org-retroclock)
;;; org-retroclock.el ends here
