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
;;; Two cases deliberately keep the plain insert-only behaviour: a directory
;;; candidate, where Emacs also stays in the minibuffer and lists the
;;; directory instead of exiting, and any buffer outside a prompt -- an
;;; lsp-mode completion list, say -- where there is nothing to submit.  With no
;;; candidate focused (an empty list, see the CONTINUE-COMPLETION patch below)
;;; Return submits what was typed.

(defun prompt-window-active-p ()
  (and (lem/prompt-window:current-prompt-window) t))

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
          (t
           (lem/completion-mode::completion-select)
           (unless directory-p
             (when (prompt-window-active-p)
               (lem/prompt-window::prompt-execute)))))))


;;; Keep the completion context alive when nothing matches.
;;;
;;; CONTINUE-COMPLETION calls COMPLETION-END as soon as the candidate list comes
;;; back empty (src/ext/completion-mode.lisp:328-330): the popup quits,
;;; completion-mode turns off and *COMPLETION-CONTEXT* is cleared.  The prompt
;;; then remembers nothing about the completion, so one character too many ends
;;; it for good -- deleting that character ran DELETE-PREVIOUS-CHAR as the plain
;;; prompt command, which never refreshes.
;;;
;;; The replacement keeps the context and the mode, and hides the popup instead
;;; of shrinking it to nothing: a one-row box spills its 10px CSS padding onto
;;; the row below (the frontend pads the wrapper by borderOffsetY), which is the
;;; prompt's own row, so an empty popup would cover the "Command:" line.  The
;;; next keystroke refreshes through COMPLETION-REFRESH and the popup reappears
;;; where it was; its style -- the :horizontally-above-window gravity set above
;;; -- is remembered for the reopen so the position does not change.  Return in
;;; that state submits the typed input, as COMPLETION-SELECT-AND-EXECUTE does
;;; when no candidate is focused: what vertico does with an empty list.

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
The completion stays alive with no candidates on screen."
  (let ((popup (lem/completion-mode::context-popup-menu context)))
    (when popup
      ;; POPUP-WINDOW-STYLE is specialized on the window, not on the menu.
      (setf *completion-popup-style*
            (lem/popup-window::popup-window-style
             (lem/popup-menu::popup-menu-window popup)))
      (lem:popup-menu-quit popup)
      (setf (lem/completion-mode::context-popup-menu context) nil))))

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
                     (when *completion-popup-style*
                       (list :style *completion-popup-style*)))))))
