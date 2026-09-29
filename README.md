# org-retroclock

[![CI](https://github.com/Jotham-LEC/org-retroclock/actions/workflows/ci.yml/badge.svg)](https://github.com/Jotham-LEC/org-retroclock/actions/workflows/ci.yml)
[![License: GPL v3+](https://img.shields.io/badge/License-GPLv3%2B-blue.svg)](https://github.com/Jotham-LEC/org-retroclock/blob/main/LICENSE)

> Log the hour you already spent. Two commands that write a finished Org `CLOCK:`
> line — start, end and total — for work you did without clocking it.

Org clocks the present tense: clock in, work, clock out. Work you finished without
clocking has no command at all. `C-u C-u C-u M-x org-clock-in` only resumes the last
clock-out, and [org-clock-convenience](https://github.com/dfeich/org-clock-convenience)
corrects `CLOCK:` lines that already exist. org-retroclock writes the line that was
never there.

You can get there without it, and I did for a while. Clocking in starts a live clock:
it clocks out whatever is running, and you still have to fix the start time and clock
out at the right moment. Typing the line by hand works too, since `C-c C-c` on a
`CLOCK:` line fills in the total, but you open the drawer yourself, type two timestamps
in exactly Org's format, and put them where Org expects. Here I say how long it took,
and the line goes where Org would have put it.

## Install

Not on MELPA yet. With `use-package` and Emacs 30's `:vc`:

```elisp
(use-package org-retroclock
  :vc (:url "https://github.com/Jotham-LEC/org-retroclock" :rev :newest))
```

On Emacs 29, install it once with `package-vc-install`:

```elisp
(package-vc-install "https://github.com/Jotham-LEC/org-retroclock")
```

Or with [straight.el](https://github.com/radian-software/straight.el):

```elisp
(straight-use-package
 '(org-retroclock :type git :host github :repo "Jotham-LEC/org-retroclock"))
```

Or Doom, in `packages.el`:

```elisp
(package! org-retroclock
  :recipe (:host github :repo "Jotham-LEC/org-retroclock"))
```

Emacs 29.1 or newer. Nothing beyond Org, which you already have.

## Use

`M-x org-retroclock` logs against the Org entry at point. `M-x org-retroclock-recent`
asks first which task, using the same picker `org-clock-in` offers for recently clocked
tasks, so the entry need not be on screen or even in an open buffer. That picker reads
`org-clock-history`, which Org forgets when Emacs exits. To keep it across sessions:

```elisp
(setq org-clock-persist 'history)
(org-clock-persistence-insinuate)
```

Both then ask a duration — `90`, `90m`, `1h30m` or `1:30` — and log the span ending
now. Org on its own reads `m` as months, so `90m` would be seven and a half years; here
it means minutes. With a prefix argument they ask which end of the span to
pin instead, read that time through `org-read-date`, and measure the duration from
there: `s` for an hour you started at nine this morning, `e` for a meeting that ended
at six. A date without a year reads as the past one, so `25 14:00` is the 25th just
gone; a weekday does not, since Org reads `fri` as the coming Friday whatever it is
told, so type `-fri` for last Friday. Less than a minute, or a span that ends in the
future, is refused. More than a day asks first.

Nothing is bound out of the box, because where these belong depends on where your other
Org clock keys are:

```elisp
(keymap-set org-mode-map "C-c C-x h" #'org-retroclock)
(keymap-global-set "C-c o p" #'org-retroclock-recent)
```

In Doom, alongside the stock clock leader:

```elisp
(map! :leader :prefix ("n" . "notes")
      :desc "Retro clock (recent)" "p" #'org-retroclock-recent)
(map! :after org :map org-mode-map :localleader
      :desc "Retro clock (log past)" "c p" #'org-retroclock)
```

There is nothing to set. A task you clock retroactively joins `org-clock-history`, as
one you clock in does, so the pickers offer it afterwards.

## How it works

The entry goes exactly where a real one would. `org-clock-find-position` picks the spot
— creating the `:LOGBOOK:` drawer if `org-clock-into-drawer` says so — and the line is
written with `org-clock-string` and `org-time-stamp-format`, so `org-clock-sum`,
`org-clock-report` and the agenda's clock views read it like any other. No live clock is
started and no running clock is disturbed.

## Contributing

It is a small package and a personal one. Bug reports and pull requests are welcome.

```sh
make deps                # package-lint, into ./.deps
make compile lint test   # byte-compile clean, checkdoc, package-lint, ERT
```

CI runs the same three on Emacs 29 and 30, and melpazoid on top.

## License

GPL-3.0-or-later.
