(defsystem "lem-vertico"
  :description "Vertico-style prompt and completion popup for Lem."
  :author "Lem contributors"
  :license "MIT"
  :depends-on ("lem/core" "alexandria")
  :serial t
  :components ((:file "package")
               (:file "popup")
               (:file "align")
               (:file "select")
               (:file "install")))
