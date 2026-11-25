(in-package :lem-vertico)

;;; History-first ordering, a first-row default, and a persisted history for M-x.
;;;
;;; Vertico's default sort function (vertico-sort-history-length-alpha, from
;;; vertico-sort.el) lists what was used last first; that is what makes M-x
;;; usable with hundreds of commands and an empty input.  Lem sorts candidates
;;; by match quality only and ignores the prompt's own history.
;;;
;;; Reordering in LIMITATION-ITEMS rather than in a producer wrapper has two
;;; advantages: it sits above the *LIMIT-NUMBER-OF-ITEMS* cut, so a recently
;;; used command outside the first 100 matches can still surface, and it works
;;; whichever producer lem-orderless or lem-marginalia have installed.
;;;
;;; A history entry is matched against the candidate's :label, the string that
;;; insertion uses.  M-x history holds command names, so it matches.  File
;;; history holds full paths, so with lem's own file labels (the last path
;;; segment) nothing is boosted -- which is what Emacs does too, since
;;; file-name-history holds full names while its candidates are relative.
;;;
;;; Lem keeps prompt histories in memory only: PROMPT-WINDOW::GET-HISTORY builds
;;; (MAKE-HISTORY) with no pathname, and only the file and project histories are
;;; given one.  History-first ordering is worth little across restarts, so the
;;; histories named in *PERSISTED-HISTORY-NAMES* are now created with a pathname
;;; and written on every ADD-HISTORY.

(defvar *history-ordering-p* t
  "When non-NIL, candidates found in the prompt's history are listed after the
default (if the prompt has one) and before the rest, most recent first.")

(defvar *persisted-history-names* '("MH-EXECUTE-COMMAND")
  "Prompt histories, by name, that are saved between sessions.
Names, not symbols, so this does not depend on which package interned the
history symbol: M-x's is read as LEM-CORE::MH-EXECUTE-COMMAND.")

(defvar *persisted-history-limit* 100
  "Most entries kept in a persisted prompt history.")

(defun persisted-history-name-p (name)
  "True when NAME is one of *PERSISTED-HISTORY-NAMES*."
  (and name (member (string name) *persisted-history-names* :test #'string=) t))

(defun persisted-history-pathname (name)
  "File that history NAME is saved in, next to lem's other histories."
  (merge-pathnames (format nil "history/prompts/~(~a~)" name) (lem:lem-home)))

(defun prompt-history-entries (&optional (prompt (lem/prompt-window:current-prompt-window)))
  "The labels of PROMPT's history, most recently used first."
  (let ((history (and prompt
                      (ignore-errors
                        (lem/prompt-window::prompt-window-history prompt)))))
    (when history
      (reverse (lem/common/history:history-data-list history)))))

(defun history-position-table (prompt)
  "Label -> position hash for PROMPT's history, most recently used = 0."
  (let ((table (make-hash-table :test #'equal)))
    (loop :for entry :in (prompt-history-entries prompt)
          :for position :from 0
          :do (unless (nth-value 1 (gethash entry table))
                (setf (gethash entry table) position)))
    table))

(defun history-order-items (items
                            &optional (prompt (lem/prompt-window:current-prompt-window)))
  "ITEMS with the prompt's default first, then its history, most recent first.
The rest keep the producer's order."
  (prefer-default-candidate
   (if (or (null *history-ordering-p*) (null prompt))
       items
       (let ((positions (history-position-table prompt)))
         (if (zerop (hash-table-count positions))
             items
             (let ((ranked '())
                   (rest '()))
               (dolist (item items)
                 (multiple-value-bind (position found)
                     (gethash (lem/completion-mode:completion-item-label item)
                              positions)
                   (if found
                       (push (cons position item) ranked)
                       (push item rest))))
               (if (null ranked)
                   items
                   (append (mapcar #'cdr
                                   (stable-sort (nreverse ranked) #'< :key #'car))
                           (nreverse rest)))))))))

;;; The prompt's default comes first.
;;;
;;; C-x b passes PROMPT-FOR-BUFFER a default: OTHER-BUFFER, the most recent
;;; buffer that is not on screen.  That is the buffer Return should choose, and
;;; the one the prompt names in parentheses.  History-first ordering would
;;; instead put the buffer just used -- the one still in the history -- on top,
;;; so C-x b twice in a row highlighted the buffer it had just selected while
;;; the prompt offered a different default.  Moving the default in front of the
;;; history makes the first candidate and the focused row agree with the prompt.
;;;
;;; PROMPT-FOR-BUFFER is patched only to record its :default argument in
;;; *DEFAULT-CANDIDATE* for the duration of the prompt.  The binding is
;;; dynamic, and PROMPT-FOR-BUFFER does not return until the prompt has ended, so
;;; the value is there whenever the prompt's completion calls LIMITATION-ITEMS.
;;; Buffer prompts are the only ones that pass a default, so M-x, file prompts
;;; and the rest are unaffected.

(defvar *default-candidate* nil
  "Label that the running prompt offers as its default, or NIL.")

(defvar *original-prompt-for-buffer* nil
  "LEM:PROMPT-FOR-BUFFER before this file patched it.")

(defun default-candidate-name (default)
  "DEFAULT as the label a candidate would carry, or NIL."
  (cond ((null default) nil)
        ((stringp default) default)
        (t (or (ignore-errors (lem:buffer-name default))
               (princ-to-string default)))))

(defun prefer-default-candidate (items)
  "ITEMS with *DEFAULT-CANDIDATE*'s item first, the rest in order."
  (if *default-candidate*
      (let ((item (find *default-candidate* items
                        :test #'string=
                        :key #'lem/completion-mode:completion-item-label)))
        (if item
            (cons item (remove item items :test #'eq))
            items))
      items))

(defun save-prompt-history (history)
  "Write HISTORY to disk; SAVE-FILE is already a no-op without a pathname."
  (when history
    (ignore-errors (lem/common/history:save-file history))))

(defvar *original-limitation-items* nil
  "LEM/COMPLETION-MODE::LIMITATION-ITEMS before this file patched it.")

(defvar *original-get-history* nil
  "LEM/PROMPT-WINDOW::GET-HISTORY before this file patched it.")

(defvar *original-add-history* nil
  "LEM/COMMON/HISTORY:ADD-HISTORY before this file patched it.")

(defun install-default-candidate ()
  "Record the default of a running PROMPT-FOR-BUFFER, to list it first."
  #+sbcl
  (sb-ext:without-package-locks
    (progn
      (setf *original-prompt-for-buffer*
            (or *original-prompt-for-buffer*
                (symbol-function 'lem:prompt-for-buffer)))
      (setf (symbol-function 'lem:prompt-for-buffer)
            (lambda (prompt &rest args)
              (let ((*default-candidate*
                      (default-candidate-name (getf args :default))))
                (apply *original-prompt-for-buffer* prompt args))))))
  (values))

(defun install-history-ordering ()
  "List candidates that appear in the prompt's history first."
  #+sbcl
  (sb-ext:without-package-locks
    (setf *original-limitation-items*
          (or *original-limitation-items*
              (symbol-function 'lem/completion-mode::limitation-items)))
    (setf (symbol-function 'lem/completion-mode::limitation-items)
          (lambda (items)
            (funcall *original-limitation-items* (history-order-items items)))))
  (values))

(defun install-history-persistence ()
  "Create the configured prompt histories with a pathname and save them.
PERSISTED-HISTORY-NAMES applies to histories created from now on; an already
used history keeps its in-memory copy until the editor restarts."
  #+sbcl
  (sb-ext:without-package-locks
    (progn
      (setf *original-get-history*
            (or *original-get-history*
                (symbol-function 'lem/prompt-window::get-history)))
      (setf (symbol-function 'lem/prompt-window::get-history)
            (lambda (name)
              (or (gethash name lem/prompt-window::*history-table*)
                  (setf (gethash name lem/prompt-window::*history-table*)
                        (if (persisted-history-name-p name)
                            (lem/common/history:make-history
                             :pathname (persisted-history-pathname name)
                             :limit *persisted-history-limit*)
                            (funcall *original-get-history* name))))))

      ;; ADD-HISTORY is the one place every prompt submit goes through, and it
      ;; is a plain function (not a command), so patching it is safe.  Histories
      ;; without a pathname -- everything except the ones above, the file
      ;; history and the listener's -- make SAVE-FILE a no-op.
      (setf *original-add-history*
            (or *original-add-history*
                (symbol-function 'lem/common/history:add-history)))
      (setf (symbol-function 'lem/common/history:add-history)
            (lambda (history input &rest args)
              (prog1 (apply *original-add-history* history input args)
                (save-prompt-history history))))))
  (values))
