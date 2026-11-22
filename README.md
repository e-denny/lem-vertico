# lem-vertico

Vertico-style prompt and candidate popup for Lem: where the prompt sits, how
wide it is, how the candidate list is sized and ordered, what Return and M-RET
do, the candidate count, and what floats to the top of the list.

Loading the system applies it. `lem-vertico:install` runs at load and

- pins the prompt to the bottom of the frame (`:bottom-display`),
- fills the frame width up to `*prompt-max-width*` and centers the prompt,
- opens the candidate list automatically and reverses it so the best match sits
  next to the prompt line,
- redefines `lem/prompt-window::compute-window-rectangle` to apply the width cap,
- caps the popup at `*completion-popup-max-rows*` candidate rows with the
  focused row on the bottom row (`fit-completion-popup`, `align-popup-selection`),
- shows `POSITION/TOTAL` in the popup window's modeline (`*show-count*`),
- binds `Return` in the completion keymap to `completion-select-and-execute`,
- binds `M-Return` to `completion-submit-input`,
- lists candidates that appear in the prompt's history first
  (`*history-ordering-p*`) and keeps the M-x history across sessions
  (`*persisted-history-names*`),
- patches `lem/completion-mode::continue-completion` so an empty candidate list
  hides the popup instead of ending the completion.

## Loading

```lisp
(pushnew (merge-pathnames "extensions/vertico/" (lem-home)) asdf:*central-registry* :test #'equal)
(asdf:load-system "lem-vertico")
```

Loading the system applies it; there is nothing else to call.

## Knobs

| variable | default | meaning |
|---|---|---|
| `lem-vertico:*prompt-max-width*` | 120 | largest width of the prompt and its popup, in characters; `nil` for the whole frame |
| `lem-vertico:*completion-popup-max-rows*` | 10 | most candidate rows shown (the count modeline is an extra row) |
| `lem-vertico:*show-count*` | `t` | show `POSITION/TOTAL` in the popup modeline |
| `lem-vertico:*history-ordering-p*` | `t` | list candidates found in the prompt's history first |
| `lem-vertico:*persisted-history-names*` | `("MH-EXECUTE-COMMAND")` | prompt histories saved between sessions, by name |
| `lem-vertico:*persisted-history-limit*` | 100 | most entries kept in a persisted prompt history |

## Keys

| key | command | effect |
|---|---|---|
| `Return` | `completion-select-and-execute` | insert the focused candidate and submit the prompt |
| `Return` on a `dir/` candidate | | inserts the directory, keeps the prompt open |
| `Return` when a file prompt's input is a directory (`~/Documents/`) | | submits the input, entering the directory |
| `Return` with no candidate focused | | submits the typed input |
| `M-Return` | `completion-submit-input` | submits the typed input exactly, whatever candidate is focused |

`M-Return` is vertico's `vertico-exit-input`: it is what you need to open a file
or switch to a buffer whose name is a prefix of an existing candidate, or to
answer a prompt with the empty string.

## Notes

The width cap and the centering are the same change: Lem widens the popup to at
least the prompt and re-aligns it to the prompt's x on every redraw, so capping
only the popup would be undone. A one-row popup would otherwise spill its 10px
CSS padding onto the prompt's own row, which is why an empty list hides the
window instead of shrinking it.

The candidate count is a modeline, not a prompt-line decoration. Emacs vertico
writes it onto the minibuffer line with an overlay `:before-string`; Lem has no
overlays and no `:align-to`, and a prompt buffer's text is the input, so text
next to the prompt cannot be drawn without becoming editable. A header line in
the popup buffer does not work either: the focused row is pinned to the popup's
bottom row, so a list taller than the window scrolls the header out of view
exactly when a count is worth reading. The popup window's modeline is always
drawn, and is what Lem's own typeout window does for its status line. The number
is the candidate's position in the produced list (best match = 1), not its
screen row, so the reversed display reads the same way as Emacs. The total is
capped at Lem's 100-item completion limit.

History ordering happens in `lem/completion-mode::limitation-items`, i.e. above
the 100-item cut, so a recently used command that sorts past position 100 is
still listed. History entries are matched against a candidate's `:label`, the
string insertion uses: M-x history holds command names, so it matches; file
history holds full paths, so with Lem's own file labels (last path segment)
nothing is boosted, as in Emacs. Lem keeps prompt histories in memory only, so
the histories named in `*persisted-history-names*` are created with a pathname
and written to `<lem-home>/history/prompts/<name>` on every submit. The setting
applies to histories created from now on; a history already in use in a running
editor keeps its in-memory copy until the next start.

Each patch captures the unpatched function once, so re-running `install` (or
reloading the system) replaces the wrapper rather than stacking another one.
