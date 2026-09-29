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
;; entry need not be on screen, or even in a buffer you have open.  The
;; picker reads `org-clock-history', which Org forgets when Emacs exits
;; unless `org-clock-persist' is set.
;;
;; Both read a duration ("90", "90m", "1h30m" or "1:30") ending now.  A
;; trailing "m" means minutes, not Org's months.  With a prefix argument
;; they first ask which end of the span you want to pin, then read that
;; time and the duration, so an hour you spent this morning and a meeting
;; that ended at six are equally easy to say.  A span under a minute or
;; ending in the future is refused, and one over a day asks first.
;;
;; No keys are bound.  Bind the two commands wherever your Org keys live:
;;
;;     (keymap-set org-mode-map "C-c C-x h" #'org-retroclock)
;;     (keymap-global-set "C-c o p" #'org-retroclock-recent)

;;; Code:

(require 'org)
(require 'org-clock)

(defgroup org-retroclock nil
  "Log finished Org CLOCK entries retroactively."
  :group 'org-clock
  :link '(url-link :tag "Homepage" "https://github.com/Jotham-LEC/org-retroclock"))

(defcustom org-retroclock-push-history t
  "Whether a retroactive clock joins `org-clock-history'.
When non-nil a task clocked retroactively becomes a recent task like
any other, so it is offered by the pickers of `org-clock-in' and
`org-retroclock-recent' afterwards."
  :type 'boolean
  :package-version '(org-retroclock . "0.1.0"))

(defun org-retroclock--insert (start end)
  "Insert a finished CLOCK line spanning START to END on the entry at point.
START and END are Lisp timestamps."
  (save-excursion
    (org-back-to-heading t)
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
      ;; `org-clock-find-position' leaves point at the end of the line the
      ;; entry belongs after, which is how `org-clock-in' opens its own line.
      (insert-before-markers-and-inherit "\n")
      (backward-char 1)
      (insert-and-inherit org-clock-string " " ts "--" te " => "
                          (format "%2d:%02d" hours minutes))
      (org-indent-line)))
  (when org-retroclock-push-history
    (save-excursion
      (org-back-to-heading t)
      (org-clock-history-push))))

(defun org-retroclock--read-duration ()
  "Read a duration from the minibuffer and return it in whole minutes.
Org reads a bare \"m\" as months, so a number followed by \"m\" is
taken as minutes here: nobody logs a clock in months.  A span under a
minute is refused, because the CLOCK line would total 0:00, and a span
of more than a day has to be confirmed."
  (let* ((input (replace-regexp-in-string
                 "\\([0-9.]\\)m\\b" "\\1min"
                 (read-string "Duration (90, 90m, 1h30m or 1:30): ")
                 t))
         (minutes (org-duration-to-minutes input)))
    (when (< minutes 1)
      (user-error "Duration must be at least a minute"))
    (when (and (> minutes (* 24 60))
               (not (y-or-n-p (format "Log %s, more than a day? "
                                      (org-duration-from-minutes minutes)))))
      (user-error "Not logged"))
    ;; A CLOCK line has no seconds, so neither does the span.
    (round minutes)))

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
             (?s (let* ((start (org-read-date t t nil "Start time"))
                        (minutes (org-retroclock--read-duration)))
                   (cons start (time-add start (seconds-to-time (* minutes 60))))))
             (?e (let* ((end (org-read-date t t nil "End time"))
                        (minutes (org-retroclock--read-duration)))
                   (cons (time-subtract end (seconds-to-time (* minutes 60))) end)))))))
    (when (time-less-p (time-add (org-current-time) 60) (cdr span))
      (user-error "That span ends in the future, at %s"
                  (format-time-string (org-time-stamp-format t t) (cdr span))))
    span))

;;;###autoload
(defun org-retroclock (arg)
  "Log a finished CLOCK entry on the Org entry at point.
Without a prefix, read a duration and log the span ending now.  With
prefix ARG, pin a start or end time first and log the span from there."
  (interactive "P" org-mode)
  (barf-if-buffer-read-only)
  (pcase-let ((`(,start . ,end) (org-retroclock--read-times arg)))
    (org-with-wide-buffer
     (org-retroclock--insert start end))))

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
    (with-current-buffer (marker-buffer marker)
      (barf-if-buffer-read-only))
    (pcase-let ((`(,start . ,end) (org-retroclock--read-times arg)))
      (with-current-buffer (marker-buffer marker)
        (org-with-wide-buffer
         (goto-char marker)
         (org-retroclock--insert start end))))))

(provide 'org-retroclock)
;;; org-retroclock.el ends here
