(in-package :lem-vertico)

;;; Installation.
;;;
;;; Loading this system applies the settings, key bindings and patches.  Each
;;; patch captures the unpatched function once, so re-running INSTALL (or
;;; reloading the system) replaces the wrapper instead of stacking another one.

(defun install ()
  "Apply the vertico settings, key bindings and function patches."

  ;; Prompt at the bottom of the frame (default :top-display).
  (setf lem-core::*default-prompt-gravity* :bottom-display)

  ;; Prompt as wide as the display instead of 2/3 (default nil).
  (setf lem/prompt-window::*fill-width* t)

  ;; Candidate list directly above the prompt, not to its right
  ;; (default :horizontally-adjacent-window).
  (setf lem/prompt-window::*prompt-completion-window-gravity*
        :horizontally-above-window)

  ;; Open the candidate list as soon as the prompt appears, so TAB is not needed
  ;; to see it (default nil). This is the switch that *prompt-after-activate-hook*
  ;; tricks are usually used for; prefer it.
  (setf lem:*automatic-tab-completion* t)

  ;; Reverse the list so the best match sits next to the prompt line and
  ;; navigation starts from there (default nil).
  (setf lem/completion-mode::*completion-reverse* t)

  #+sbcl
  (sb-ext:without-package-locks
    (setf (symbol-function 'lem/prompt-window::compute-window-rectangle)
          #'prompt-rectangle))

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
                (let ((lem-core::*scroll-recenter-p* nil))
                  (funcall *original-move-focus* popup-menu function))
                (align-popup-selection popup-menu))))))

  (define-key lem/completion-mode::*completion-mode-keymap*
    "Return" 'completion-select-and-execute)

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
                         (hide-completion-popup context))))))
              (when lem/completion-mode::*completion-reverse*
                (ignore-errors
                  (lem/completion-mode::completion-end-of-buffer)))))))

  ;; History-first candidate order, and a persisted M-x history.
  (install-history-ordering)
  (install-history-persistence)

  (values))

(install)
