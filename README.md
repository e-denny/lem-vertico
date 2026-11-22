# lem-vertico

Vertico-style prompt and candidate popup for Lem: where the prompt sits, how
wide it is, how the candidate list is sized and ordered, and what Return does.

Loading the system applies it. `lem-vertico:install` runs at load and

- pins the prompt to the bottom of the frame (`:bottom-display`),
- fills the frame width up to `*prompt-max-width*` and centers the prompt,
- opens the candidate list automatically and reverses it so the best match sits
  next to the prompt line,
- redefines `lem/prompt-window::compute-window-rectangle` to apply the width cap,
- caps the popup at `*completion-popup-max-rows*` rows with the focused row on
  the bottom row (`fit-completion-popup`, `align-popup-selection`),
- binds `Return` in the completion keymap to `completion-select-and-execute`,
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
| `lem-vertico:*completion-popup-max-rows*` | 10 | most candidate rows shown |

## Keys

| key | command | effect |
|---|---|---|
| `Return` | `completion-select-and-execute` | insert the focused candidate and submit the prompt |
| `Return` on a `dir/` candidate | | inserts the directory, keeps the prompt open |
| `Return` with no candidate focused | | submits the typed input |

## Notes

The width cap and the centering are the same change: Lem widens the popup to at
least the prompt and re-aligns it to the prompt's x on every redraw, so capping
only the popup would be undone. A one-row popup would otherwise spill its 10px
CSS padding onto the prompt's own row, which is why an empty list hides the
window instead of shrinking it.

Each patch captures the unpatched function once, so re-running `install` (or
reloading the system) replaces the wrapper rather than stacking another one.
