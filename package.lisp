(defpackage :lem-vertico
  (:use :cl :lem)
  (:documentation "Vertico-style prompt and completion popup for Lem.")
  (:export #:*prompt-max-width*
           #:*completion-popup-max-rows*
           #:*show-count*
           #:*history-ordering-p*
           #:*persisted-history-names*
           #:*persisted-history-limit*
           #:completion-select-and-execute
           #:completion-submit-input
           #:history-order-items
           #:install))
(in-package :lem-vertico)
