(in-package :lem-vertico)

;;; The candidate count ("3/25"), at the start of the prompt line.
;;;
;;; Emacs vertico draws the count left of the prompt, on the minibuffer line, as
;;; an overlay's :before-string.  Lem has neither :before-string nor :align-to,
;;; and the prompt window's text *is* the prompt line ("Command: " is buffer
;;; text marked read-only and :field), so the only place a count can be drawn
;;; left of the prompt is in the prompt buffer, before the prompt string.
;;;
;;; That text cannot simply be inserted when the count changes.  Completion
;;; captures the input start -- and, for every candidate, the range that
;;; selecting it replaces -- as *temporary* points (src/buffer/internal/
;;; point.lisp): temporary points are not shifted by later edits, and the
;;; completion's start point is reused by every refresh of the candidate list.
;;; Inserting or deleting a variable-length prefix mid-completion would leave
;;; those points pointing into the wrong place, and Return would delete the
;;; wrong region instead of the word being completed.
;;;
;;; So the field is inserted once, before the completion captures anything
;;; (OPEN-PROMPT-COMPLETION is replaced for that, see prompt.lisp), and every
;;; update rewrites it at the *same* width: the count is padded to
;;; +COUNT-FIELD-WIDTH+ columns, wide enough for "100/100", the longest count
;;; Lem's 100-item completion limit can produce.  The padding also keeps the
;;; prompt from sliding sideways as the numbers change.

(defvar *show-count* t
  "When non-NIL, the candidate count is shown at the start of the prompt line.
Takes effect the next time a completion starts.")

(defconstant +count-field-width+ 8
  "Width of the count field in characters, including its trailing space.
Three digits of position and three of total (\"100/100\") plus a space is the
widest count the 100-item completion limit allows; padding to a fixed width is
what makes the field safe to rewrite in place.")

(defvar *count-field-enabled* #+sbcl t #-sbcl nil
  "True when the count field may be kept in the prompt buffer.
The field is only safe to keep when OPEN-PROMPT-COMPLETION is replaced, which
needs an unlocked LEM/PROMPT-WINDOW; without it the completion would hold stale
points into the prompt and selecting a candidate would delete the wrong text.")

(define-attribute vertico-count-attribute
  (t :foreground :base04))

(defun popup-menu-count (popup-menu)
  "Return POPUP-MENU's focused candidate number (1-based) and its number of rows.
The number is the candidate's position in the list the producer returned, which
is also its row on screen now that the list is listed in order (top = best
match) instead of reversed.  The number is NIL when there is no focus."
  (when popup-menu
    (let* ((buffer (lem/popup-menu::popup-menu-buffer popup-menu))
           (first-row (lem/popup-menu::buffer-start-line buffer))
           (rows (1+ (- (lem:buffer-nlines buffer) first-row)))
           (focus (lem/popup-menu::focus-point popup-menu))
           (row (and focus (lem:line-number-at-point focus))))
      (values (when (and row (<= first-row row))
                (1+ (- row first-row)))
              rows))))

(defun completion-count-string (popup-menu)
  "The \"POSITION/TOTAL\" text describing POPUP-MENU, or NIL."
  (multiple-value-bind (row rows)
      (popup-menu-count popup-menu)
    (when (and rows (plusp rows))
      (format nil "~A/~D" (or row "-") rows))))

(defun pad-count (text)
  "TEXT padded to +COUNT-FIELD-WIDTH+ columns.
The field width is constant so that rewriting it never moves the prompt string,
which is what keeps the completion's temporary points valid (see above)."
  (cond ((zerop (length text))
         (make-string +count-field-width+ :initial-element #\space))
        ((< (length text) (1- +count-field-width+))
         (concatenate 'string
                      text
                      (make-string (- +count-field-width+ 1 (length text))
                                   :initial-element #\space)
                      " "))
        (t
         (concatenate 'string text " "))))

(defun prompt-count-text (prompt)
  "The count field currently shown at the start of PROMPT's line, or NIL."
  (lem:window-parameter prompt :vertico-count))

(defun set-prompt-count (prompt text)
  "Show TEXT at the start of PROMPT's line, left of the prompt string.
TEXT is NIL to remove the field.  The field is read-only, like the prompt
string, and the input starts after both of them
\(PROMPT-WINDOW-START-CHARPOS)."
  (let ((current (prompt-count-text prompt)))
    (unless (equal current text)
      (let ((buffer (lem:window-buffer prompt))
            ;; The field we are replacing is read-only text of our own, and it is
            ;; not part of the prompt's undo history: an undo that took it away
            ;; would leave the field bookkeeping (and the input start) wrong.
            (lem:*inhibit-read-only* t)
            (lem:*inhibit-modification-hooks* t))
        (lem/buffer/internal:with-inhibit-undo ()
          (when current
            (with-point ((start (lem:buffer-start-point buffer))
                         (end (lem:buffer-start-point buffer)))
              (lem:character-offset end (length current))
              (lem:delete-between-points start end)))
          (when text
            (with-point ((start (lem:buffer-start-point buffer)))
              (lem:insert-string start text
                                 :attribute 'vertico-count-attribute
                                 :read-only t))))
        (setf (lem/prompt-window::prompt-window-start-charpos prompt)
              (+ (length (lem/prompt-window::prompt-buffer-prompt-string buffer))
                 (length (or text "")))
              (lem:window-parameter prompt :vertico-count) text)
        t))))

(defun refresh-prompt-count
    (&optional (prompt (lem/prompt-window:current-prompt-window)) popup-menu)
  "Rewrite PROMPT's count field for the running completion.
POPUP-MENU defaults to the completion's own list.  With no list on screen the
count still says how many candidates there are -- \"0/0\" when nothing matches,
\"1/1\" when the only match was inserted directly -- which is what Lem leaves
behind on those paths."
  (when (and prompt *show-count* *count-field-enabled*)
    (let* ((context lem/completion-mode::*completion-context*)
           (popup (or popup-menu
                       (and context (lem/completion-mode::context-popup-menu context))))
           (count (cond (popup (or (completion-count-string popup) "-/-"))
                        (context (let ((items (lem/completion-mode::context-last-items context)))
                                   (if items
                                       (format nil "1/~D" (length items))
                                       "0/0")))
                        (t nil))))
      (set-prompt-count prompt (and count (pad-count count))))))

(defun ensure-prompt-count-field ()
  "Give the active prompt its (blank) count field, unless it has one.
Called before a completion starts: see the note at the top of this file for why
the field has to be there before the completion captures its points."
  (let ((prompt (lem/prompt-window:current-prompt-window)))
    (when (and prompt *show-count* *count-field-enabled*
               (null (prompt-count-text prompt)))
      (set-prompt-count prompt (pad-count "")))))

(defun finish-prompt-count ()
  "Drop the count field and the candidate rows, a completion having ended."
  (let ((prompt (lem/prompt-window:current-prompt-window)))
    (when prompt
      (set-prompt-count prompt nil)
      ;; The prompt window was grown to hold the list; it is one line again.
      (ignore-errors
        (lem-core::update-floating-prompt-window (lem:current-frame))))))
