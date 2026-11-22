(in-package :lem-vertico)

;;; Return selects and submits in one keystroke.
;;;
;;; `Return` in *completion-mode-keymap* is COMPLETION-SELECT
;;; (src/ext/completion-mode.lisp:115): it inserts the focused candidate into
;;; the prompt and closes the popup.  Submitting is a second Return, because
;;; PROMPT-EXECUTE is bound to `Return` in the prompt's own keymap
;;; (src/ext/prompt-window.lisp:79).  Vertico submits on the first Return, so
;;; this binds Return to a command that inserts and then submits.
;;;
;;; Three cases deliberately do not follow that path:
;;;
;;; - a directory candidate, where Emacs also stays in the minibuffer and lists
;;;   the directory instead of exiting;
;;; - a typed directory in a file prompt ("~/Documents/"), where submitting the
;;;   input is the only sensible meaning -- vertico-preselect 'directory.  The
;;;   focused candidate there is the first entry *inside* the directory, so
;;;   inserting it would open that entry rather than the directory;
;;; - any buffer outside a prompt -- an lsp-mode completion list, say -- where
;;;   there is nothing to submit.
;;;
;;; With no candidate focused (an empty list, see the CONTINUE-COMPLETION patch
;;; below) Return submits what was typed, and M-RETURN
;;; (COMPLETION-SUBMIT-INPUT) submits the typed input whatever is focused.

(defun prompt-window-active-p ()
  (and (lem/prompt-window:current-prompt-window) t))

(defun prompt-input-string ()
  "The text typed into the active prompt, without the prompt string."
  (ignore-errors (lem/prompt-window::get-input-string)))

(defun directory-name-p (input)
  "True when INPUT names a directory, i.e. is non-empty and ends with a slash."
  (and input
       (plusp (length input))
       (char= (char input (1- (length input))) #\/)))

(defun directory-input-p ()
  "True when the typed input names a directory.
In a file prompt that is exactly the case where the candidates are the
entries of an existing directory; when the directory does not exist the list
is empty and Return already submits the input."
  (directory-name-p (prompt-input-string)))

;;; Tab inserts the candidate; Down and Up move the selection.
;;;
;;; Emacs vertico binds TAB to vertico-insert and leaves moving to Down/Up, so
;;; this replaces Lem's own TAB (COMPLETION-NARROWING-DOWN-OR-NEXT-LINE, which
;;; inserts the common prefix of all candidates and otherwise moves down).  In
;;; a file prompt a directory candidate's label ends in a slash, so inserting
;;; it and refreshing the list descends into that directory: one TAB lists the
;;; subdirectory.  Any other candidate (a file, an M-x command, a buffer) is
;;; simply inserted into the prompt, which is the whole name only if the label
;;; is the whole name -- file items carry the range of the last path component
;;; (src/ext/prompt-window.lisp:435), command items the token at point.
;;;
;;; COMPLETION-INSERT leaves the completion in place, so the refresh below is
;;; what recomputes the list for the new input.  Outside a prompt the key does
;;; what Lem bound it to: a completion list in a buffer is not a prompt and has
;;; nothing to descend into.

(define-command completion-insert-candidate () ()
  "Insert the focused candidate into the prompt and list what it leads to."
  (let* ((context lem/completion-mode::*completion-context*)
         (popup (and context (lem/completion-mode::context-popup-menu context)))
         (item (and popup (lem/popup-menu:get-focus-item popup))))
    (cond ((and item (prompt-window-active-p))
           (lem/completion-mode::completion-insert (lem:current-point) item)
           (lem/completion-mode:completion-refresh))
          (t
           (lem/completion-mode::completion-narrowing-down-or-next-line)))))

(defun prompt-history-name (prompt)
  "The name of PROMPT's history, e.g. \"PROMPT-FOR-FILE\", or NIL.
Looked up by identity in the prompt window's history table, so the answer does
not depend on how the history symbol was interned."
  (let ((history (ignore-errors
                  (lem/prompt-window::prompt-window-history prompt)))
        (name nil))
    (when history
      (maphash (lambda (key value)
                 (when (eq value history)
                   (setf name (string key))))
               lem/prompt-window::*history-table*)
      name)))

(defun file-prompt-p (prompt)
  "True when PROMPT completes file names (C-x C-f, C-x C-w, ...)."
  (member (prompt-history-name prompt)
          '("PROMPT-FOR-FILE" "PROMPT-FOR-DIRECTORY")
          :test #'string=))

(define-command completion-select-and-execute () ()
  "Insert the focused candidate and submit the prompt."
  (let* ((context lem/completion-mode::*completion-context*)
         (popup (and context (lem/completion-mode::context-popup-menu context)))
         (item (and popup (lem/popup-menu:get-focus-item popup)))
         (label (and item (lem/completion-mode:completion-item-label item)))
         (directory-p (and label
                           (plusp (length label))
                           (char= (char label (1- (length label))) #\/))))
    (cond ((null item)
           (when (prompt-window-active-p)
             (lem/prompt-window::prompt-execute)))
          ((and (prompt-window-active-p)
                (directory-input-p)
                (file-prompt-p (lem/prompt-window:current-prompt-window)))
           (lem/prompt-window::prompt-execute))
          (t
           (lem/completion-mode::completion-select)
           (unless directory-p
             (when (prompt-window-active-p)
               (lem/prompt-window::prompt-execute)))))))

(define-command completion-submit-input () ()
  "Submit the prompt input exactly as typed, ignoring the focused candidate.
The vertico-exit-input case: needed to create a new file or buffer whose name
is a prefix of an existing candidate, or to search for the empty string."
  (cond ((prompt-window-active-p)
         (lem/prompt-window::prompt-execute))
        (lem/completion-mode::*completion-context*
         (lem/completion-mode::completion-select))
        (t nil)))


;;; Keep the completion context alive when nothing matches.
;;;
;;; CONTINUE-COMPLETION calls COMPLETION-END as soon as the candidate list comes
;;; back empty (src/ext/completion-mode.lisp:328-330): the popup quits,
;;; completion-mode turns off and *COMPLETION-CONTEXT* is cleared.  The prompt
;;; then remembers nothing about the completion, so one character too many ends
;;; it for good -- deleting that character ran DELETE-PREVIOUS-CHAR as the plain
;;; prompt command, which never refreshes.
;;;
;;; The completion context, the mode and the popup are kept as Lem leaves them;
;;; only the window is hidden, because a one-row box spills its 10px CSS padding
;;; onto the row below (the frontend pads the wrapper by borderOffsetY), which is
;;; the prompt's own row, so an empty popup would cover the "Command:" line.  The
;;; next keystroke refreshes through COMPLETION-REFRESH and the popup reappears
;;; where it was; the style -- the borderless list-inside-the-prompt style from
;;; popup.lisp -- is remembered for the reopen, so the box does not change shape.
;;; Return in that state submits the typed input, as COMPLETION-SELECT-AND-EXECUTE
;;; does when no candidate is focused: what vertico does with an empty list.  The
;;; count field stays, reading "0/0".

(defvar *original-continue-completion* nil
  "The unpatched CONTINUE-COMPLETION, captured the first time this file is
loaded so that reloading init.lisp replaces the patch instead of stacking
another wrapper on top of it.")

(defvar *completion-popup-style* nil
  "Style of the completion popup that was hidden because nothing matched.
DISPLAY-POPUP-MENU takes a keyword list or a style object; the popup is reopened
with this one so it keeps the gravity it was created with.")

(defun hide-completion-popup (context)
  "Delete CONTEXT's popup window, remembering its style, keep the context.
The completion stays alive with no candidates on screen; the prompt goes back to
its one line and the count reads \"0/0\"."
  (let ((popup (lem/completion-mode::context-popup-menu context)))
    (when popup
      ;; POPUP-WINDOW-STYLE is specialized on the window, not on the menu.
      (setf *completion-popup-style*
            (lem/popup-window::popup-window-style
             (lem/popup-menu::popup-menu-window popup)))
      (lem:popup-menu-quit popup)
      (setf (lem/completion-mode::context-popup-menu context) nil)))
  (refresh-prompt-count)
  (ignore-errors (lem-core::update-floating-prompt-window (lem:current-frame))))

(defun refresh-completion-popup (context items)
  "Show ITEMS in CONTEXT's popup, reopening it with its style when hidden."
  (let ((popup (lem/completion-mode::context-popup-menu context)))
    (if popup
        (lem:popup-menu-update popup items
                               :print-spec (lem/completion-mode::make-print-spec items))
        (setf (lem/completion-mode::context-popup-menu context)
              (apply #'lem:display-popup-menu
                     items
                     :action-callback
                     (lambda (item)
                       (lem/completion-mode::completion-insert
                        (lem:current-point) item)
                       (lem/completion-mode:completion-end))
                     :print-spec (lem/completion-mode::make-print-spec items)
                     (list :style (or *completion-popup-style*
                                      (prompt-completion-style))))))))
