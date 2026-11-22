(defsystem "lem-vertico"
  :description "Vertico-style prompt and completion popup for Lem."
  :author "Lem contributors"
  :license "MIT"
  :depends-on ("lem/core" "alexandria")
  :serial t
  :components ((:file "package")
               (:file "count")
               (:file "popup")
               (:file "prompt")
               (:file "history")
               (:file "select")
               (:file "install")))
