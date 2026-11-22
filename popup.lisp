(in-package :lem-vertico)

;;; The completion box: one box, the prompt line first, the candidates below.
;;;
;;; Emacs vertico lists the candidates inside the minibuffer window, so the
;;; prompt line and the list share a single box.  Lem keeps the list in a
;;; separate floating window, and every floating window is drawn with a box of
;;; its own -- in the webview frontend a wrapper element with 10px of padding
;;; and a 1px outline.  Two boxes with a gap between them is what that looks
;;; like, and the count used to sit in the list's modeline, i.e. in the gap.
;;;
;;; So the prompt window becomes the whole box: it grows to one prompt row plus
;;; one row per candidate, and the candidate window is made borderless and put
;;; on the rows below the prompt line, inside that box.  Floating windows are
;;; painted in creation order and the candidate window is created after the
;;; prompt, so it draws over the prompt window's otherwise blank lower rows.
;;; Both windows share the prompt's left edge and width, which keeps the
;;; candidate text aligned with the prompt text and the right edge straight.
;;;
;;; The candidates are listed in order, best match first: the completion's own
;;; order, not reversed.  Down moves to the next candidate, as in Emacs.

(defvar *completion-popup-max-rows* 10
  "Upper bound on the number of candidate rows shown by the completion popup.")

(defvar *prompt-max-width* 120
  "Largest width, in characters, of the prompt box and its candidates.
NIL leaves the prompt as wide as the frame.")

(defclass completion-popup-gravity (lem/popup-window::gravity)
  ()
  (:documentation "Puts a popup on the row below its source window's first row,
at the source window's width: the candidate list inside the prompt's box."))

(defvar *popup-gravity* (make-instance 'completion-popup-gravity))

(defmethod lem/popup-window::compute-popup-window-rectangle
    ((gravity completion-popup-gravity)
     &key source-window width height &allow-other-keys)
  (let ((height (max 1 height)))
    (list (lem:window-x source-window)
          ;; Clamped for the first frame only: the prompt is still one row until
          ;; LAYOUT-PROMPT-POPUP has grown it, which leaves no room below it.
          (max 0 (min (1+ (lem:window-y source-window))
                      (- (lem:display-height) height)))
          (max width (lem:window-width source-window))
          height)))

(defun prompt-completion-style ()
  "Style for the candidate list drawn inside the prompt's box.
Borderless on purpose: the prompt window's box surrounds the list as well."
  (lem/popup-window::make-style :gravity *popup-gravity*
                                :use-border nil
                                :offset-x 0
                                :offset-y 0
                                :cursor-invisible t))

;;; Prompt width.
;;;
;;; The M-x prompt fills the frame (*FILL-WIDTH* t) and the completion popup is
;;; never narrower than the prompt -- compute-popup-window-rectangle widens it to
;;; the source window -- so on a maximised frame the candidate list runs from
;;; edge to edge for rows that are barely 100 columns of text.  This redefinition
;;; of COMPUTE-WINDOW-RECTANGLE clamps the prompt to *PROMPT-MAX-WIDTH* and lets
;;; the existing :bottom-display gravity center it; the popup follows, because
;;; it is at least as wide as the prompt and is positioned at the prompt's x.
;;;
;;; The original is duplicated here rather than wrapped because the clamp happens
;;; in the middle of it: the same buffer-size and child-window logic as
;;; src/ext/prompt-window.lisp:186, with MIN-WIDTH capped at the new maximum and
;;; the child's rows added to the height, since the list lives inside the box.

(defun prompt-rectangle (buffer &key gravity source-window child-completion-window)
  "Rectangle for a prompt buffer, width-capped at *PROMPT-MAX-WIDTH*.
A completion list is drawn inside the prompt's box, on the rows below the prompt
line, so the prompt window is that many rows taller than its buffer."
  (destructuring-bind (width height)
      (lem/popup-window::compute-buffer-size buffer)
    (let ((child-rows 0))
      (when child-completion-window
        (destructuring-bind (child-width child-height)
            (lem/popup-window::compute-buffer-size
             (lem:window-buffer child-completion-window))
          (declare (ignore child-height))
          (setf width (max width child-width)
                child-rows (lem:window-height child-completion-window))))
      (let* ((display-width (lem:display-width))
             (max-width (max 1 (if *prompt-max-width*
                                   (min *prompt-max-width* (- display-width 2))
                                   (- display-width 2))))
             (min-width (min max-width
                             (if lem/prompt-window::*fill-width*
                                 (1- display-width)
                                 (round (* display-width 2/3))))))
        (lem/popup-window::compute-popup-window-rectangle
         (lem/popup-window::ensure-gravity gravity)
         :source-window source-window
         :width (alexandria:clamp (1+ width) min-width max-width)
         :height (alexandria:clamp (+ height child-rows)
                                   lem/prompt-window::+min-height+
                                   (- (lem:display-height) 2)))))))

(defun completion-popup-rows (popup-menu)
  "Rows of candidates POPUP-MENU shows: its lines, capped at *COMPLETION-POPUP-MAX-ROWS*."
  (max 1 (min *completion-popup-max-rows*
              (lem:buffer-nlines (lem/popup-menu::popup-menu-buffer popup-menu))
              (- (lem:display-height) 4))))

(defun prompt-completion-popup-p (popup-menu)
  "True when POPUP-MENU is the candidate list of a prompt."
  (when popup-menu
    (let ((source (lem/popup-window::popup-window-source-window
                   (lem/popup-menu::popup-menu-window popup-menu))))
      (and source
           (eq source (lem/prompt-window:current-prompt-window))))))

(defun layout-prompt-popup (popup-menu)
  "Put POPUP-MENU's candidates inside the prompt's box, below the prompt line."
  (let ((window (lem/popup-menu::popup-menu-window popup-menu))
        (prompt (lem/prompt-window:current-prompt-window))
        (rows (completion-popup-rows popup-menu)))
    (when (and window prompt)
      ;; The prompt grows to hold the candidates and PROMPT-RECTANGLE reads the
      ;; candidate window's height, so size that first.
      (lem:window-set-size window (max 3 (lem:window-width window)) rows)
      ;; The completion context does not know its popup yet when the popup is
      ;; created, so LEM's UPDATE-PROMPT-WINDOW (which looks it up there) is not
      ;; enough: recompute the prompt's rectangle with this window as the child.
      (destructuring-bind (x y width height)
          (lem/prompt-window::compute-window-rectangle
           (lem:window-buffer prompt)
           :gravity (lem/prompt-window::prompt-gravity prompt)
           :source-window (lem/prompt-window::prompt-window-caller-of-prompt-window prompt)
           :child-completion-window window)
        (lem:window-set-pos prompt x y)
        (lem:window-set-size prompt width height)
        ;; With the prompt in its final place, the list goes on the row below
        ;; the prompt line, at the prompt's width.
        (lem:window-set-pos window x (1+ y))
        (lem:window-set-size window width rows))
      ;; Narrowing the list leaves the focused row where it was, but an update
      ;; puts the focus back on the first candidate, above the view.
      (let ((lem-core::*scroll-recenter-p* nil))
        (ignore-errors (lem:window-see window)))
      (refresh-prompt-count prompt popup-menu))))

(defun fit-detached-popup (popup-menu)
  "Size an ordinary completion popup: candidate rows only, in its own box."
  (let ((window (lem/popup-menu::popup-menu-window popup-menu)))
    (lem/popup-window::update-popup-window
     :source-window (lem/popup-window::popup-window-source-window window)
     :width (lem/popup-window::popup-window-base-width window)
     :height (completion-popup-rows popup-menu)
     :destination-window window)))

(defun fit-completion-popup (popup-menu)
  "Size POPUP-MENU to its candidates, and to the prompt's box when it is one."
  (when popup-menu
    (if (prompt-completion-popup-p popup-menu)
        (layout-prompt-popup popup-menu)
        (fit-detached-popup popup-menu))))

(defmethod lem-if:display-popup-menu :around ((implementation lem:implementation)
                                              items &rest args)
  (let ((popup-menu (apply #'call-next-method implementation items args)))
    ;; Only completions are fitted; a context menu or a list opened with
    ;; :max-display-items keeps the size its caller asked for.
    (when (null (getf args :max-display-items))
      (fit-completion-popup popup-menu))
    popup-menu))

(defmethod lem-if:popup-menu-update :around ((implementation lem:implementation)
                                             popup-menu items &rest args)
  (prog1 (apply #'call-next-method implementation popup-menu items args)
    (when (null (getf args :max-display-items))
      (fit-completion-popup popup-menu))))
