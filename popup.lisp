(in-package :lem-vertico)

;;; Completion popup size.
;;;
;;; lem-if:display-popup-menu defaults to 20 visible items
;;; (src/ext/popup-menu.lisp:114) and completion-mode never passes
;;; :max-display-items, so the popup can be raised well past the space under the
;;; prompt. These :around methods only act when the caller did not choose a
;;; limit itself -- i.e. for completion popups -- and they also force the window
;;; height to equal the number of candidate lines, so the focused entry (the
;;; last one, because *completion-reverse* is on) always sits on the popup's
;;; bottom row instead of leaving blank rows underneath.

(defvar *completion-popup-max-rows* 10
  "Upper bound on the number of candidate rows shown by the completion popup.")

(defvar *prompt-max-width* 120
  "Largest width, in characters, of the prompt and its completion popup.
NIL leaves the prompt as wide as the frame.")

;;; *COMPLETION-POPUP-MAX-ROWS* counts candidate rows; the count modeline (see
;;; count.lisp) is an extra row on top of them, so the window is never so short
;;; that the count would replace a candidate.

(defun completion-popup-height (popup-menu)
  (let ((lines (lem:buffer-nlines (lem/popup-menu::popup-menu-buffer popup-menu))))
    (+ (popup-modeline-rows popup-menu)
       (max 1 (min *completion-popup-max-rows* lines)))))

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
;;; src/ext/prompt-window.lisp:186, with MIN-WIDTH capped at the new maximum.
;;; Heights are untouched.

(defun prompt-rectangle (buffer &key gravity source-window child-completion-window)
  "Rectangle for a prompt buffer, width-capped at *PROMPT-MAX-WIDTH*."
  (destructuring-bind (width height)
      (lem/popup-window::compute-buffer-size buffer)
    (when child-completion-window
      (destructuring-bind (child-width child-height)
          (lem/popup-window::compute-buffer-size
           (lem:window-buffer child-completion-window))
        (declare (ignore child-height))
        (setf width (max width child-width))))
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
       :height (alexandria:clamp height
                                 lem/prompt-window::+min-height+
                                 (- (lem:display-height) 2))))))



(defun fit-completion-popup (popup-menu)
  (when popup-menu
    (let* ((window (lem/popup-menu::popup-menu-window popup-menu))
           (height (completion-popup-height popup-menu))
           ;; The popup can be as wide as its longest row; keep it inside the
           ;; prompt's column so it cannot grow past the configured maximum.
           (width (max 1 (min (or *prompt-max-width* (lem:display-width))
                              (lem:window-width window)))))
      (unless (and (= height (lem:window-height window))
                   (= width (lem:window-width window)))
        (lem/popup-window::update-popup-window
         :source-window (lem/popup-window::popup-window-source-window window)
         :width width
         :height height
         :destination-window window)))
    (align-popup-selection popup-menu)))

(defmethod lem-if:display-popup-menu :around ((implementation lem:implementation)
                                              items &rest args)
  (let ((popup-menu (apply #'call-next-method implementation items args)))
    (when (null (getf args :max-display-items))
      (enable-count-modeline popup-menu)
      (fit-completion-popup popup-menu))
    popup-menu))

(defmethod lem-if:popup-menu-update :around ((implementation lem:implementation)
                                             popup-menu items &rest args)
  (prog1 (apply #'call-next-method implementation popup-menu items args)
    (when (null (getf args :max-display-items))
      (enable-count-modeline popup-menu)
      (fit-completion-popup popup-menu))))
