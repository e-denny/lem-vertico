# lem-vertico

Vertico-style prompt and completion popup for Lem: one box with the count and
the prompt on its first line and the candidates below, plus where the prompt
sits, how wide it is, how the list is ordered, what Return and M-RET do, and
what floats to the top of the list.

Loading the system applies it. `lem-vertico:install` runs at load and

- pins the prompt to the bottom of the frame (`:bottom-display`),
- fills the frame width up to `*prompt-max-width*` and centers the prompt,
- grows the prompt window to hold the candidates, so the prompt line and the
  list share a single box (`layout-prompt-popup`),
- makes the candidate list borderless and puts it inside that box, on the rows
  below the prompt line, at the prompt's width,
- opens the candidate list automatically and lists it in order, best match
  first -- Down moves to the next candidate, as in Emacs,
- redefines `lem/prompt-window::compute-window-rectangle` to apply the width
  cap and the extra rows,
- shows `POSITION/TOTAL` at the start of the prompt line (`*show-count*`),
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
| `lem-vertico:*prompt-max-width*` | 120 | largest width of the prompt box and its candidates, in characters; `nil` for the whole frame |
| `lem-vertico:*completion-popup-max-rows*` | 10 | most candidate rows shown, below the prompt line inside the box |
| `lem-vertico:*show-count*` | `t` | show `POSITION/TOTAL` at the start of the prompt line |
| `lem-vertico:*history-ordering-p*` | `t` | list candidates found in the prompt's history first |
| `lem-vertico:*persisted-history-names*` | `("MH-EXECUTE-COMMAND")` | prompt histories saved between sessions, by name |
| `lem-vertico:*persisted-history-limit*` | 100 | most entries kept in a persisted prompt history |

## Keys

| key | command | effect |
|---|---|---|
| `Down` / `Tab` | `completion-next-line` | select the next candidate |
| `Up` / `S-Tab` | `completion-previous-line` | select the previous candidate |
| `Return` | `completion-select-and-execute` | insert the focused candidate and submit the prompt |
| `Return` on a `dir/` candidate | | inserts the directory, keeps the prompt open |
| `Return` when a file prompt's input is a directory (`~/Documents/`) | | submits the input, entering the directory |
| `Return` with no candidate focused | | submits the typed input |
| `M-Return` | `completion-submit-input` | submits the typed input exactly, whatever candidate is focused |

`M-Return` is vertico's `vertico-exit-input`: it is what you need to open a file
or switch to a buffer whose name is a prefix of an existing candidate, or to
answer a prompt with the empty string.

## Notes

**One box.** Emacs vertico lists the candidates inside the minibuffer window, so
the prompt line and the list share a box. Lem keeps the list in a separate
floating window, and every floating window is drawn with a box of its own -- in
the webview frontend a wrapper element with 10px of padding and a 1px outline,
which is also where the gap between the two boxes came from. So the prompt
window becomes the whole box: it grows to one prompt row plus one row per
candidate, and the candidate window is made borderless and laid on the rows
below the prompt line, at the prompt's width. Floating windows are painted in
creation order and the candidate window is created after the prompt, so it draws
over the prompt window's otherwise blank lower rows. The prompt is also wider
than its text -- the width cap and the centering are one change, because Lem
widens the popup to at least the prompt and re-aligns it to the prompt's x on
every redraw. A one-row popup would otherwise spill its 10px CSS padding onto
the prompt's own row, which is why an empty list hides the window instead of
shrinking it.

**The count.** Emacs vertico draws it left of the prompt as an overlay
`:before-string`. Lem has neither that nor `:align-to`, and a prompt buffer's
text *is* the prompt line, so the count is characters in the prompt buffer,
before the read-only prompt string. It cannot be inserted when it changes: the
completion captures the input start and every candidate range as *temporary*
points, which later edits do not shift, and the start point is reused by every
refresh of the list -- a variable-length prefix would leave them pointing into
the wrong place and Return would delete the wrong word. So the field is inserted
once, before the completion captures anything (`lem/prompt-window::
open-prompt-completion` is replaced for that), and every update rewrites it at
the same width: the count is padded to eight columns, wide enough for
`100/100`, the longest count the 100-item completion limit allows. The field is
taken out again when the completion ends, which is the one moment no point into
the prompt is alive. With no list on screen the count still says how many
candidates there are: `0/0` when nothing matches, `1/1` when the only match was
inserted directly. `*show-count*` turns the field off entirely; without the
`open-prompt-completion` replacement (i.e. on implementations other than SBCL,
where `LEM/PROMPT-WINDOW` cannot be unlocked) the count is not shown at all,
since keeping it in sync would not be safe.

**Ordering.** The list is Lem's own candidate order, best match first, not
reversed: the first candidate is the top row and Down moves to the next one.
`*scroll-recenter-p*` is bound to NIL around focus moves so the list scrolls one
candidate at a time instead of recentring on every keystroke.

**History.** Ordering happens in `lem/completion-mode::limitation-items`, i.e.
above the 100-item cut, so a recently used command that sorts past position 100
is still listed. History entries are matched against a candidate's `:label`, the
string insertion uses: M-x history holds command names, so it matches; file
history holds full paths, so with Lem's own file labels (last path segment)
nothing is boosted, as in Emacs. Lem keeps prompt histories in memory only, so
the histories named in `*persisted-history-names*` are created with a pathname
and written to `<lem-home>/history/prompts/<name>` on every submit. The setting
applies to histories created from now on; a history already in use in a running
editor keeps its in-memory copy until the next start.

Each patch captures the unpatched function once, so re-running `install` (or
reloading the system) replaces the wrapper rather than stacking another one.
