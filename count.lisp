(in-package :lem-vertico)

;;; The candidate count ("3/25"), in the completion popup's modeline.
;;;
;;; Emacs vertico writes the count onto the minibuffer line, left of the prompt,
;;; through an overlay's :before-string.  None of that has an equivalent here:
;;; Lem has no overlays and no :align-to text property, and a prompt buffer's
;;; text *is* the input, so text inserted before the input start point would be
;;; editable, would be visited by C-a, and would shift the prompt string.
;;;
;;; A header line inside the popup buffer is the next idea, and it does not work
;;; here: ALIGN-POPUP-SELECTION pins the focused row to the popup's bottom row,
;;; so as soon as the candidate list is taller than the window the view scrolls
;;; and a header line sits outside the visible area -- exactly when a count is
;;; worth reading.
;;;
;;; That leaves the popup window's modeline, which is always drawn and always
;;; visible, and is the mechanism Lem's own typeout window uses for its status
;;; line (a per-window WINDOW-MODELINE-FORMAT).  It costs one row, drawn below
;;; the candidates, i.e. between the list and the prompt line; the count is
;;; right aligned there.

(defvar *show-count* t
  "When non-NIL, the completion popup shows \"POSITION/TOTAL\" in its modeline.
Takes effect the next time a completion popup is opened.")

(defun completion-popup-p (popup-menu)
  "True when POPUP-MENU is the popup of the running completion."
  (let ((context lem/completion-mode::*completion-context*))
    (and context
         (eq popup-menu (lem/completion-mode::context-popup-menu context)))))

(defun popup-menu-count (popup-menu)
  "Return POPUP-MENU's candidate number (1-based) and its number of rows.
The number is the candidate's position in the list the producer returned, not
its screen row: with *COMPLETION-REVERSE* the display is upside down, so the
best match is the bottom row and has to read 1/N, as it does in Emacs.  The
number is NIL when there is no focus or it is not on a candidate."
  (when popup-menu
    (let* ((buffer (lem/popup-menu::popup-menu-buffer popup-menu))
           (first-row (lem/popup-menu::buffer-start-line buffer))
           (rows (1+ (- (lem:buffer-nlines buffer) first-row)))
           (focus (lem/popup-menu::focus-point popup-menu))
           (row (and focus (lem:line-number-at-point focus))))
      (when (and row (<= first-row row))
        (setf row (1+ (- row first-row))))
      (values (cond ((null row) nil)
                    ((and lem/completion-mode::*completion-reverse*
                          (completion-popup-p popup-menu))
                     (1+ (- rows row)))
                    (t row))
              rows))))

(defun completion-count-modeline (window)
  "Modeline element: the focused candidate's position and the total, right aligned."
  (multiple-value-bind (row rows)
      (popup-menu-count (lem:window-parameter window :popup-menu))
    (values (if (and rows (plusp rows))
                (format nil "~a/~d" (or row "-") rows)
                "")
            nil
            :right)))

(defun popup-modeline-rows (popup-menu)
  "The number of modeline rows POPUP-MENU's window has, 0 or 1."
  (let ((window (and popup-menu (lem/popup-menu::popup-menu-window popup-menu))))
    (if (and window (lem:window-use-modeline-p window)) 1 0)))

(defun enable-count-modeline (popup-menu)
  "Give POPUP-MENU's window a modeline that shows the candidate count.
The window remembers its menu so the count can be recomputed on redraw; the
modeline is redrawn on every redraw-display, i.e. after every command, so
navigation updates it without any extra invalidation."
  (when (and *show-count* popup-menu)
    (let ((window (lem/popup-menu::popup-menu-window popup-menu)))
      (when window
        (setf (lem:window-parameter window :popup-menu) popup-menu)
        ;; USE-MODELINE-P has a reader only, and popups are constructed with
        ;; NIL (src/ext/popup-window.lisp, MAKE-POPUP-WINDOW).
        (setf (slot-value window 'lem-core::use-modeline-p) t)
        (setf (lem-core::window-modeline-format window)
              '(completion-count-modeline))
        t))))
