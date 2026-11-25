(in-package :lem-vertico)

;;; Starting and ending a prompt completion around the count field.
;;;
;;; OPEN-PROMPT-COMPLETION is replaced with its own body -- see
;;; src/ext/prompt-window.lisp -- for one reason: the count field has to be in
;;; the prompt buffer *before* the function captures the input start as a
;;; temporary point, because that point (and every candidate range derived from
;;; it, on every later refresh) is not shifted by later edits.  Everything after
;;; that point capture is Lem's own code, unchanged.
;;;
;;; COMPLETION-END is wrapped instead of replaced: it ends a completion, after
;;; which no point into the prompt is alive any more, so that is the moment the
;;; count field can be taken out again and the prompt window shrunk to its one
;;; line.  (The field is deliberately not removed anywhere earlier; see
;;; count.lisp.)

(defun popup-menu-of-context ()
  (let ((context lem/completion-mode::*completion-context*))
    (and context (lem/completion-mode::context-popup-menu context))))

(defun open-prompt-completion ()
  "Lem's OPEN-PROMPT-COMPLETION, with the count field put in first."
  (alexandria:when-let (completion-fn
                        (lem/prompt-window::prompt-window-completion-function
                         (lem/prompt-window:current-prompt-window)))
    (let ((prompt (lem/prompt-window:current-prompt-window)))
      ;; Finish a completion that is still running: ending it removes the count
      ;; field, and nothing may capture a point across that change.
      (lem/completion-mode:completion-end)
      (ensure-prompt-count-field)
      (with-point ((start (lem/prompt-window::current-prompt-start-point)))
        (lem/completion-mode:run-completion
         (lambda (point)
           (with-point ((start start)
                        (end point))
             (let ((items (funcall completion-fn
                                   (lem:points-to-string
                                    start
                                    (lem:buffer-end-point (lem:point-buffer end))))))
               (loop :for item :in items
                     :when (typecase item
                             (string
                              (lem/completion-mode:make-completion-item
                               :label item :start start :end end))
                             (lem/completion-mode:completion-item
                              item))
                     :collect :it))))
         :style (prompt-completion-style)
         :then (lambda ()
                 (lem/prompt-window::update-prompt-window
                  (lem/prompt-window:current-prompt-window)))))
      ;; A single candidate is inserted without a list, and no candidate at all
      ;; leaves the completion alive with nothing on screen: both need a count
      ;; that says so instead of a blank field.
      (unless (popup-menu-of-context)
        (refresh-prompt-count prompt)))))

(defvar *original-completion-end* nil
  "LEM/COMPLETION-MODE::COMPLETION-END before this file patched it.")

(defun install-completion-end ()
  "Take the count field out of the prompt whenever a completion ends."
  #+sbcl
  (sb-ext:without-package-locks
    (progn
      (setf *original-completion-end*
            (or *original-completion-end*
                (symbol-function 'lem/completion-mode::completion-end)))
      (setf (symbol-function 'lem/completion-mode::completion-end)
            (lambda ()
              (prog1 (funcall *original-completion-end*)
                (finish-prompt-count))))))
  (values))


;;; No common prefix inserted when the list opens.
;;;
;;; START-COMPLETION calls NARROWING-DOWN on the items it was given, which
;;; inserts their common prefix into the prompt (src/ext/completion-mode.lisp:
;;; 262, 321).  That is meant for a completion the user asked for with TAB, but
;;; *automatic-tab-completion* runs OPEN-PROMPT-COMPLETION as soon as the prompt
;;; appears, so a buffer prompt whose candidates are all star buffers opens with
;;; a "*" already typed -- and the added character then filters the list to the
;;; star buffers, hiding the very default the prompt offered.  Emacs vertico
;;; never inserts a common prefix; TAB (COMPLETION-INSERT-CANDIDATE) inserts a
;;; whole candidate instead.
;;;
;;; Only the call START-COMPLETION makes is inhibited, not NARROWING-DOWN at
;;; large: COMPLETION-NARROWING-DOWN-OR-NEXT-LINE still uses it when something
;;; asks for that behaviour, and the dynamic variable is unbound again by the
;;; time START-COMPLETION returns.

(defvar *inhibit-initial-narrowing* nil
  "True while START-COMPLETION runs: do not insert the common prefix.")

(defvar *original-start-completion* nil
  "LEM/COMPLETION-MODE::START-COMPLETION before this file patched it.")

(defvar *original-narrowing-down* nil
  "LEM/COMPLETION-MODE::NARROWING-DOWN before this file patched it.")

(defun install-no-initial-narrowing ()
  "Open a completion with its candidates and without inserting a common prefix."
  #+sbcl
  (sb-ext:without-package-locks
    (progn
      (setf *original-narrowing-down*
            (or *original-narrowing-down*
                (symbol-function 'lem/completion-mode::narrowing-down)))
      (setf (symbol-function 'lem/completion-mode::narrowing-down)
            (lambda (context last-items)
              (unless *inhibit-initial-narrowing*
                (funcall *original-narrowing-down* context last-items))))
      (setf *original-start-completion*
            (or *original-start-completion*
                (symbol-function 'lem/completion-mode::start-completion)))
      (setf (symbol-function 'lem/completion-mode::start-completion)
            (lambda (context items style)
              (let ((*inhibit-initial-narrowing* t))
                (funcall *original-start-completion* context items style))))))
  (values))
