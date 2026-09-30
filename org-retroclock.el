;;; org-retroclock.el --- Log finished Org CLOCK entries retroactively -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jotham Lim Ee Chen

;; Author: Jotham Lim Ee Chen <jotham@cothink.ing>
;; Assisted-by: Claude:claude-opus-5
;; URL: https://github.com/Jotham-LEC/org-retroclock
;; Version: 0.1.2
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
;; that ended at six are equally easy to say.  Type a range for that
;; time, such as "9:00-10:30" or "-1 2pm-3:30pm", and it is the whole
;; span, with no duration asked.  Org reads both ends of a range on one
;; day, so "22:00-01:00" ends before it starts and is refused; to cross
;; midnight, pin the end and type a duration.  A date without a year is
;; read as the past one, and "-fri" is last Friday.  A span under a minute
;; or ending in the future is refused, and one over a day asks first.
;; Org's timestamps carry no time zone, so a span whose stamps would come
;; out backwards across the autumn clock change is refused too.
;;
;; No keys are bound.  Bind the two commands wherever your Org keys live:
;;
;;     (keymap-set org-mode-map "C-c C-x h" #'org-retroclock)
;;     (keymap-global-set "C-c o p" #'org-retroclock-recent)

;;; Code:

(require 'org)
(require 'org-clock)

(defun org-retroclock--stamps (start end)
  "Return the list (TS TE SECONDS) of a CLOCK line from START to END.
TS and TE are the line's two stamps and SECONDS its total.  The total
is worked out from the stamps, as `org-clock-out' works out its own, so
that it agrees with what the line says.  A stamp carries no time zone,
so across the autumn clock change SECONDS can be zero or negative."
  (let* ((stamp (org-time-stamp-format t t))
         (ts (format-time-string stamp start))
         (te (format-time-string stamp end)))
    (list ts te (org-time-convert-to-integer
                 (time-subtract (org-time-string-to-time te)
                                (org-time-string-to-time ts))))))

(defun org-retroclock--insert (start end)
  "Insert a finished CLOCK line spanning START to END on the entry at point.
START and END are Lisp timestamps.  Return the line's span and total."
  (save-excursion
    (org-back-to-heading t)
    ;; A task clocked after the fact is a recent task all the same, as
    ;; `org-clock-in' makes it.
    (org-clock-history-push)
    (org-clock-find-position nil)
    (pcase-let* ((`(,ts ,te ,seconds) (org-retroclock--stamps start end))
                 (hours (floor seconds 3600))
                 (minutes (floor (mod seconds 3600) 60)))
      ;; `org-clock-find-position' leaves point at the start of the line the
      ;; new one goes above.  Open a line there, as `org-clock-in' does.
      (insert-before-markers-and-inherit "\n")
      (backward-char 1)
      (insert-and-inherit org-clock-string " " ts "--" te " => "
                          (format "%2d:%02d" hours minutes))
      (org-indent-line)
      ;; A running clock shows in the mode line the total of its entry's
      ;; subtree, which has just grown if the line went on that entry or
      ;; below it.  With no clock running, the marker has no buffer.
      (when (eq (marker-buffer org-clock-hd-marker)
                (org-base-buffer (current-buffer)))
        (org-back-to-heading t)
        (while (and (> (point) org-clock-hd-marker)
                    (org-up-heading-safe)))
        (when (= (point) org-clock-hd-marker)
          (setq org-clock-total-time
                (org-clock-sum-current-item (org-clock-get-sum-start)))
          (org-clock-update-mode-line)))
      (format "%s--%s => %d:%02d" ts te hours minutes))))

(defun org-retroclock--read-duration ()
  "Read a duration from the minibuffer and return it in whole minutes.
Org reads a bare \"m\" as months, so a number followed by \"m\" is
taken as minutes here: nobody logs a clock in months.  A span under a
minute is refused, because the CLOCK line would total 0:00, and a span
of more than a day has to be confirmed."
  (let* ((typed (string-trim (read-string "Duration (90, 90m, 1h30m or 1:30): ")))
         ;; Org's units are lower case, and `org-duration-p' matches
         ;; "2H" through `case-fold-search' that `org-duration-to-minutes'
         ;; then cannot convert.
         (input (replace-regexp-in-string
                 "\\([0-9.]\\) *m\\b" "\\1min" (downcase typed) t))
         (minutes
          ;; `org-duration-p' leaves out the bare number, which
          ;; `org-duration-to-minutes' reads as minutes.
          (if (or (org-duration-p input)
                  (string-match-p "\\`[0-9]+\\(?:\\.[0-9]*\\)?\\'" input))
              (org-duration-to-minutes input)
            (user-error "Not a duration: %S" typed))))
    (when (< minutes 1)
      (user-error "Duration must be at least a minute"))
    (org-retroclock--confirm-long minutes)
    ;; A CLOCK line has no seconds, so neither does the span.
    (round minutes)))

(defun org-retroclock--confirm-long (minutes)
  "Ask before logging MINUTES when that is more than a day.
Signal a `user-error' when the answer is no."
  (when (and (> minutes (* 24 60))
             (not (y-or-n-p (format "Log %s, more than a day? "
                                    (org-duration-from-minutes minutes)))))
    (user-error "Not logged")))

(defvar org-time-was-given)
(defvar org-end-time-was-given)

(defun org-retroclock--read-date (prompt)
  "Read a date and a time, or a range of times, with PROMPT.
Return the cons (START . END).  END is nil for a single time, and for a
range such as \"9:00-10:30\" or \"2pm-3:30pm\" it is the range's end,
on the day the range starts, as Org reads it: \"22:00-01:00\" ends
before it starts.  Org's \"22:00+3\" ends the next day.

A date without a year is taken as past.  Org reads a bare weekday
forwards however it is told, so the prompt also mentions \"-fri\",
which Org reads as last Friday."
  ;; Org reads a range only for a caller that binds
  ;; `org-end-time-was-given', and otherwise drops the typed time
  ;; altogether and uses the current one.
  (let* ((org-read-date-prefer-future nil)
         (org-time-was-given nil)
         (org-end-time-was-given nil)
         (start (org-read-date t t nil (concat prompt " (or a range such as 9:00-10:30; \
-fri for last Friday)")))
         (end org-end-time-was-given))
    (cond
     ((not end) (list start))
     ;; Org takes a range from "9am-10:30" but not the start, and uses
     ;; the current time instead.
     ((not org-time-was-given)
      (user-error "Org read no start time in that range; write both times alike, \
as 9:00-10:30 or 9am-10:30am"))
     ;; Org writes the end as it would in a timestamp, where "22:00+3"
     ;; ends at "25:00".
     ((string-match "\\`\\([0-9]+\\):\\([0-5][0-9]\\)\\'" end)
      (let ((day (decode-time start)))
        (cons start
              (encode-time (list 0 (string-to-number (match-string 2 end))
                                 (string-to-number (match-string 1 end))
                                 (decoded-time-day day) (decoded-time-month day)
                                 (decoded-time-year day) nil -1 nil)))))
     (t (user-error "Cannot read the end of that range: %s" end)))))

(defun org-retroclock--read-times (anchored)
  "Return the cons (START . END) of a span read from the minibuffer.
When ANCHORED is nil the span is a duration ending now, rounded down
by `org-clock-rounding-minutes' as `org-clock-in' would.  Otherwise ask
which end to pin, read that time, and read the duration from there;
a range typed for that time is the whole span, and no duration is
asked.  A span that ends more than a minute from now is refused: this
logs work already done.  So is one whose CLOCK line would total no time
or less, as a range that ends before it starts would, and as the stamps
of a span across the autumn clock change can."
  (let* ((range nil)
         (span
          (if (not anchored)
              (let* ((minutes (org-retroclock--read-duration))
                     (end (org-current-time org-clock-rounding-minutes t)))
                (cons (time-subtract end (seconds-to-time (* minutes 60))) end))
            (let* ((anchor (read-char-choice "Anchor: [s]tart time  [e]nd time: "
                                             '(?s ?e)))
                   (typed (org-retroclock--read-date
                           (if (eq anchor ?s) "Start time" "End time"))))
              (cond
               ((cdr typed) (setq range t) typed)
               ((eq anchor ?s)
                (let ((minutes (org-retroclock--read-duration)))
                  (cons (car typed) (time-add (car typed) (seconds-to-time (* minutes 60))))))
               (t
                (let ((minutes (org-retroclock--read-duration)))
                  (cons (time-subtract (car typed) (seconds-to-time (* minutes 60)))
                        (car typed)))))))))
    (when (time-less-p (time-add (current-time) 60) (cdr span))
      (user-error "That span ends in the future, at %s; for last Friday type -fri"
                  (format-time-string (org-time-stamp-format t t) (cdr span))))
    (pcase-let ((`(,ts ,te ,seconds) (org-retroclock--stamps (car span) (cdr span))))
      (cond
       ;; Org reads both ends of a range on the day it starts.
       ((not (time-less-p (car span) (cdr span)))
        (user-error "That range ends at %s, not after it starts: Org reads both \
times on one day; to cross midnight, pin the end and type a duration" te))
       ;; Org's stamps carry no time zone, so when the clocks go back an
       ;; hour a span can end at an earlier stamp than it starts, and
       ;; `org-clock-out' would total it as negative.
       ((<= seconds 0)
        (user-error "The clocks go back in between, so %s--%s would total %d \
minutes: Org's timestamps carry no time zone"
                    ts te (/ seconds 60)))))
    (when range
      (org-retroclock--confirm-long
       (/ (float-time (time-subtract (cdr span) (car span))) 60)))
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
prefix ARG, pin a start or end time first and log the span from there,
or type a range such as \"9:00-10:30\" for that time and log it."
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
  ;; Org's picker lists only the tasks whose buffers are open, but still
  ;; comes up, empty, when none is.
  (unless (delq nil (mapcar #'marker-buffer
                            (append (list org-clock-default-task
                                          org-clock-interrupted-task
                                          org-clock-marker)
                                    org-clock-history)))
    (user-error "No recent task in an open buffer"))
  (let ((marker (org-clock-select-task "Retro-clock which recent task? ")))
    (unless (and (markerp marker) (marker-buffer marker))
      (user-error "No task selected"))
    (org-retroclock--log marker arg)))

(provide 'org-retroclock)
;;; org-retroclock.el ends here
