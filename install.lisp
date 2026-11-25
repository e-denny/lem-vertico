(in-package :lem-vertico)

;;; Installation.
;;;
;;; Loading this system applies the settings, key bindings and patches.  Each
;;; patch captures the unpatched function once, so re-running INSTALL (or
;;; reloading the system) replaces the wrapper instead of stacking another one.

(defvar *original-move-focus* nil
  "The unadvised LEM/POPUP-MENU::MOVE-FOCUS, captured the first time this file
is loaded so that reloading init.lisp replaces the advice instead of stacking
another copy on top of it.")

(defun install ()
  "Apply the vertico settings, key bindings and function patches."

  ;; Prompt at the bottom of the frame (default :top-display).
  (setf lem-core::*default-prompt-gravity* :bottom-display)

  ;; Prompt as wide as the display instead of 2/3 (default nil).
  (setf lem/prompt-window::*fill-width* t)

  ;; Open the candidate list as soon as the prompt appears, so TAB is not needed
  ;; to see it (default nil). This is the switch that *prompt-after-activate-hook*
  ;; tricks are usually used for; prefer it.
  (setf lem:*automatic-tab-completion* t)

  ;; List the candidates in order, best match first, instead of reversing them.
  ;; The list sits below the prompt line now, so the first candidate is the top
  ;; row and Down moves to the next one (default nil; the earlier revision of
  ;; this extension set it to T for a list drawn above the prompt).
  (setf lem/completion-mode::*completion-reverse* nil)

  #+sbcl
  (sb-ext:without-package-locks
    (setf (symbol-function 'lem/prompt-window::compute-window-rectangle)
          #'prompt-rectangle))

  ;; The count field in the prompt line is only safe with OPEN-PROMPT-COMPLETION
  ;; replaced (see prompt.lisp); COUNT checks this before touching the buffer.
  #+sbcl
  (sb-ext:without-package-locks
    (setf (symbol-function 'lem/prompt-window::open-prompt-completion)
          #'open-prompt-completion))

  #+sbcl
  (sb-ext:without-package-locks
    (progn
      (setf *original-move-focus*
            (or *original-move-focus*
                (symbol-function 'lem/popup-menu::move-focus)))
      (setf (symbol-function 'lem/popup-menu::move-focus)
            (lambda (popup-menu function)
              ;; POPUP-MENU is NIL while a completion has no matching candidates:
              ;; its popup is hidden, and TAB/Up/Down must not walk into it.
              (when popup-menu
                ;; No recentring: the list scrolls one row at a time, and the
                ;; popup is exactly as tall as its candidates anyway.
                (let ((lem-core::*scroll-recenter-p* nil))
                  (funcall *original-move-focus* popup-menu function))
                (refresh-prompt-count))))))

  (install-completion-end)
  (install-no-initial-narrowing)

  ;; C-x C-b opens the completion list instead of Lem's column list: the same
  ;; box as C-x b, with the count and the first candidate focused.  A column
  ;; list has no prompt line to put a count on, and which buffer is selected is
  ;; easier to see in the completion list.  The column list stays available as
  ;; M-x LIST-BUFFERS; see LIST-POPUP-GRAVITY in popup.lisp for its placement.
  (define-key *global-keymap* "C-x C-b" 'select-buffer)

  (define-key lem/completion-mode::*completion-mode-keymap*
    "Return" 'completion-select-and-execute)

  ;; vertico-insert: TAB inserts the focused candidate, descending into a
  ;; directory in a file prompt; Down/Up move the selection.
  (define-key lem/completion-mode::*completion-mode-keymap*
    "Tab" 'completion-insert-candidate)

  ;; vertico-exit-input: submit the typed input even when a candidate is focused.
  (define-key lem/completion-mode::*completion-mode-keymap*
    "M-Return" 'completion-submit-input)

  #+sbcl
  (sb-ext:without-package-locks
    (progn
      (setf *original-continue-completion*
            (or *original-continue-completion*
                (symbol-function 'lem/completion-mode::continue-completion)))
      (setf (symbol-function 'lem/completion-mode::continue-completion)
            (lambda (context)
              (lem/completion-mode::compute-completion-items
               context
               (lambda (items)
                 (let ((context lem/completion-mode::*completion-context*))
                   (when context
                     (if items
                         (progn
                           (refresh-completion-popup context items)
                           (lem/completion-mode::call-focus-action))
                         (hide-completion-popup context))))))))))

  ;; History-first candidate order, the prompt's default first, and a persisted
  ;; M-x history.
  (install-default-candidate)
  (install-history-ordering)
  (install-history-persistence)

  (values))

(install)
