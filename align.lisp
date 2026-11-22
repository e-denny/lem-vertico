(in-package :lem-vertico)

;;; Keep the selected candidate on the popup's bottom row.
;;;
;;; Popup menus move the focus with WINDOW-SEE, which honours the global
;;; *scroll-recenter-p* (t) and therefore calls WINDOW-RECENTER: the focused
;;; line is put in the *middle* of the popup. When the focus is the last
;;; candidate there is nothing left to draw below it, so the rows under it are
;;; cleared and you get blank rows at the bottom -- exactly the "6 candidates
;;; and 4 blank rows in a 10-row popup" case. ALIGN-POPUP-SELECTION undoes that
;;; by scrolling the view until the focused row is the window's last row;
;;; MOVE-FOCUS is advised (with *scroll-recenter-p* bound to NIL) so it runs on
;;; every focus move. MOVE-FOCUS lives in the locked LEM/POPUP-MENU package,
;;; hence the unlock (SBCL-only; other implementations ignore that block).

(defun align-popup-selection (popup-menu)
  "Scroll POPUP-MENU's window so the focused row is the bottom row."
  (when popup-menu
    (let* ((window (lem/popup-menu::popup-menu-window popup-menu))
           (buffer (lem/popup-menu::popup-menu-buffer popup-menu))
           (focus (lem/popup-menu::focus-point popup-menu))
           (row (lem:window-cursor-y window))
           ;; WINDOW-HEIGHT counts the count modeline; the last *text* row is
           ;; one above it when the popup has one.
           (last-row (1- (lem-core::window-height-without-modeline window))))
      (when (and focus
                 (< row last-row)
                 (= (lem:line-number-at-point focus)
                    (lem:buffer-nlines buffer)))
        (lem:window-scroll window (- row last-row))))))

(defvar *original-move-focus* nil
  "The unadvised LEM/POPUP-MENU::MOVE-FOCUS, captured the first time this file
is loaded so that reloading init.lisp replaces the advice instead of stacking
another copy on top of it.")
