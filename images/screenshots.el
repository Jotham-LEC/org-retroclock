;;; screenshots.el --- Make the README's images -*- lexical-binding: t; -*-

;;; Commentary:

;; From the top of the repository, in a graphical session:
;;
;;     emacs -Q -l images/screenshots.el
;;
;; It stages each scene in a fresh Org buffer, types into it as you would,
;; has Emacs write its own frame to PNG (Emacs built with Cairo), and puts
;; images/demo.gif and images/range.png together with ImageMagick's
;; `magick'.  Emacs exits when it is done.  The frame shows on screen while
;; it works; to keep it off the screen, run it under a headless Wayland
;; compositor, such as
;;
;;     WLR_BACKENDS=headless sway
;;
;; with WAYLAND_DISPLAY set to that compositor's socket.

;;; Code:

(require 'cl-lib)

(defconst screenshots-dir
  (file-name-directory (or load-file-name buffer-file-name))
  "The images directory, where the images are written.")

(add-to-list 'load-path (expand-file-name ".." screenshots-dir))
(require 'org-retroclock)

(setq inhibit-startup-screen t
      ring-bell-function #'ignore
      frame-resize-pixelwise t
      org-startup-folded nil
      org-clock-persist nil)
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)
(blink-cursor-mode -1)
(load-theme 'modus-operandi t)
(set-face-attribute 'default nil :family "DejaVu Sans Mono" :height 140)

(defun screenshots-export (name)
  "Write the selected frame to NAME.png in a temporary directory.
Return the file name."
  (redisplay t)
  (sit-for 0.3)
  (redisplay t)
  (let ((file (expand-file-name (concat name ".png") screenshots-tmp))
        (coding-system-for-write 'binary))
    (with-temp-file file
      (set-buffer-multibyte nil)
      (insert (x-export-frames nil 'png)))
    file))

(defvar screenshots-tmp (make-temp-file "org-retroclock-shots-" t)
  "Where the frames are written before they are put together.")

(defun screenshots-magick (&rest args)
  "Run `magick' with ARGS, signalling if it fails."
  (unless (zerop (apply #'call-process "magick" nil nil nil args))
    (error "Magick failed: %S" args)))

(defun screenshots-framed (file)
  "Return FILE with a thin grey border, as a new file beside it."
  (let ((framed (concat (file-name-sans-extension file) "-framed.png")))
    (screenshots-magick file "-bordercolor" "#c8c8c8" "-border" "1" framed)
    framed))

(defun screenshots-type (keys)
  "Queue KEYS, a `kbd' string, as if typed."
  (setq unread-command-events
        (append unread-command-events (listify-key-sequence (kbd keys)))))

(defvar screenshots-steps nil
  "Steps still to run, each (DELAY . FUNCTION).")

(defun screenshots-run (&rest steps)
  "Run STEPS, each (DELAY . FUNCTION), DELAY seconds after the last.
They run from timers, so that a step can look at a prompt an earlier
step left waiting."
  (setq screenshots-steps steps)
  (screenshots--next))

(defun screenshots--next ()
  "Run the next of `screenshots-steps' after its delay."
  (when screenshots-steps
    (pcase-let ((`(,delay . ,fn) (pop screenshots-steps)))
      (run-at-time delay nil
                   (lambda ()
                     (condition-case err
                         (funcall fn)
                       (error (message "Screenshot step failed: %S" err)
                              (kill-emacs 2)))
                     (screenshots--next))))))

(defun screenshots-heading ()
  "Put point on the heading the scenes log on."
  (with-current-buffer "work.org"
    (goto-char (point-min))
    (re-search-forward "^\\* TODO Write")
    (beginning-of-line)))

(set-frame-size nil 100 21)
(switch-to-buffer (get-buffer-create "work.org"))
(org-mode)
(insert "#+title: Work\n\n"
        "* DONE Fix the flaky clock test\n"
        ":LOGBOOK:\n"
        "CLOCK: [2026-10-06 Tue 14:10]--[2026-10-06 Tue 15:05] =>  0:55\n"
        ":END:\n"
        "* TODO Write the quarterly report\n"
        "* TODO Review the release notes\n")
(set-buffer-modified-p nil)
(org-fold-show-all '(headings drawers))
(screenshots-heading)

(let (demo)
  (screenshots-run
   (cons 1 (lambda () (screenshots-type "M-x org-retroclock RET")))
   (cons 1 (lambda () (push (screenshots-export "demo-1") demo)))
   (cons 0.2 (lambda () (screenshots-type "1h30m")))
   (cons 1 (lambda () (push (screenshots-export "demo-2") demo)))
   (cons 0.2 (lambda () (screenshots-type "RET")))
   (cons 1.5 (lambda ()
               (org-fold-show-all '(headings drawers))
               (screenshots-heading)
               (push (screenshots-export "demo-3") demo)
               (message nil)))
   ;; The date prompt is long, and wraps in a narrower frame.
   (cons 0.5 (lambda ()
               (set-frame-size nil 142 21)
               (screenshots-heading)
               (screenshots-type "C-u M-x org-retroclock RET e -1 SPC 14:00-15:30")))
   (cons 2 (lambda ()
             (screenshots-magick (screenshots-framed (screenshots-export "range"))
                                 "-strip" (expand-file-name "range.png" screenshots-dir))))
   (cons 0.2 (lambda () (screenshots-type "C-g C-g")))
   (cons 0.5 (lambda ()
               (pcase-let ((`(,one ,two ,three)
                            (mapcar #'screenshots-framed (reverse demo))))
                 (screenshots-magick "-delay" "120" one "-delay" "160" two
                                     "-delay" "450" three "-loop" "0"
                                     "-layers" "Optimize"
                                     (expand-file-name "demo.gif" screenshots-dir)))
               (delete-directory screenshots-tmp t)
               (kill-emacs 0)))))

;;; screenshots.el ends here
