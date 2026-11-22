(defpackage :lem-vertico
  (:use :cl :lem)
  (:documentation "Vertico-style prompt and completion popup for Lem.")
  (:export #:*prompt-max-width*
           #:*completion-popup-max-rows*
           #:completion-select-and-execute
           #:install))
(in-package :lem-vertico)
