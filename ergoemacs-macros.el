;;; ergoemacs-macros.el --- Macros for ergoemacs-mode -*- lexical-binding: t -*-

;; Copyright © 2013, 2014  Free Software Foundation, Inc.

;; Maintainer: Matthew L. Fidler
;; Keywords: convenience

;; ErgoEmacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published
;; by the Free Software Foundation, either version 3 of the License,
;; or (at your option) any later version.

;; ErgoEmacs is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with ErgoEmacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; 

;; Todo:

;; 

;;; Code:

;; These should only be called when byte compiled
(require 'custom)

(declare-function ergoemacs-warn "ergoemacs-lib")

;;;###autoload
(defmacro ergoemacs-keymapp (keymap)
  "Error free check of keymap by `keymapp'"
  `(ignore-errors (keymapp ,keymap)))

(defmacro ergoemacs-gethash (key table &optional dflt)
  "Safe `gethash'.
Will only use `gethash' when `table' is a hash table"
  `(and ,table (hash-table-p ,table) (gethash ,key ,table ,dflt)))

;;;###autoload
(defmacro ergoemacs-sv (symbol &optional default)
  "Error free `symbol-value'.
If SYMBOL is void, return nil"
  `(if ,default
       (ignore-errors (default-value ,symbol))
     (ignore-errors (symbol-value ,symbol))))

;; This shouldn't be called at run-time; This fixes the byte-compile warning.
(fset 'ergoemacs-theme-component--parse
      #'(lambda(keys-and-body &optional skip-first)
          "Parse KEYS-AND-BODY, optionally skipping the name and
documentation with SKIP-FIRST.

Uses `ergoemacs-theme-component--parse-keys-and-body' and
  `ergoemacs-theme-component--parse-remaining'."
          (ergoemacs-theme-component--parse-keys-and-body
           keys-and-body
           'ergoemacs-theme-component--parse-remaining
           skip-first)))

(fset 'ergoemacs-theme-component--parse-key-str
      #'(lambda (str)
          "Wraps C-i, C-m and C-[ in <>."
          (cond
           ((not (stringp str)) str)
           ((string-match-p "^\\(?:M-\\|S-\\)*C-\\(?:M-\\|S-\\)*[im[]$" str) (concat "<" str ">"))
           (t str))))

(fset 'ergoemacs-theme-component--parse-key
      #'(lambda  (item)
          "Changes `kbd' and `read-kbd-macro' on C-i, C-m, and C-[ to allow calling on GUI."
          (cond
           ((not (consp item)) item)
           ((eq (nth 0 item) 'kbd)
            (list 'kbd (ergoemacs-theme-component--parse-key-str (nth 1 item))))
           ((eq (nth 0 item) 'read-kbd-macro)
            (list 'read-kbd-macro (ergoemacs-theme-component--parse-key-str (nth 1 item)) (nth 2 item)))
           (t item))))

(fset 'ergoemacs-theme-component--parse-fun
      #'(lambda (fun)
          "Determine how FUN should be used with `ergoemacs-component-struct--define-key'."
          (let (tmp)
            (or (and (ergoemacs-keymapp (ergoemacs-sv fun)) `(quote ,fun))
                (ignore-errors
                  (and (consp fun)
                       (stringp (nth 0 fun))
                       (symbolp (nth 1 fun))
                       (eq (nth 1 fun) :emacs)
                       (setq tmp (lookup-key global-map (read-kbd-macro (nth 0 fun))))
                       (commandp tmp)
                       `(quote ,tmp)))
                (ignore-errors
                  (and (consp fun)
                       (eq 'quote (nth 0 fun))
                       (consp (nth 1 fun))
                       (stringp (nth 0 (nth 1 fun)))
                       (symbolp (nth 1 (nth 1 fun)))
                       (eq (nth 1 (nth 1 fun)) :emacs)
                       (setq tmp (lookup-key global-map (read-kbd-macro (nth 0 (nth 1 fun)))))
                       (commandp tmp)
                       `(quote ,tmp)))
                (ignore-errors
                  (and (consp fun)
                       (stringp (nth 0 fun))
                       (symbolp (nth 1 fun))
                       `(quote ,fun)))
                fun))))

;;;###autoload
(defun ergoemacs-theme-component--parse-remaining (remaining)
  "Parse the REMAINING list, and convert:

- `define-key' is converted to
  `ergoemacs-component-struct--define-key' and keymaps are quoted.

- `global-set-key' is converted to
  `ergoemacs-component-struct--define-key' with keymap equal to
  `global-map'.

- `bind-key' is converted to
  `ergoemacs-component-struct--define-key'.

- `global-unset-key' is converted to
  `ergoemacs-component-struct--define-key' with keymap equal to
  `global-map' and function definition is nil.

- `global-reset-key' is converted
  `ergoemacs-component-struct--define-key'

- `setq' and `set' is converted to
  `ergoemacs-component-struct--set'

- `add-hook' and `remove-hook' is converted to
  `ergoemacs-component-struct--set'

- Mode initialization like (delete-selection-mode 1)
  or (delete-selection) is converted to
  `ergoemacs-component-struct--set'

- Allows :version statement expansion to
  `ergoemacs-component-struct--new-version'

- Adds with-hook syntax or (when -hook) or (when -mode) using
  `ergoemacs-component-struct--with-hook'

Since `ergoemacs-mode' tries to distinguish return, escape, and
tab from their ASCII equivalents In the GUI, the following Emacs
keyboard codes are converted to keys that `ergoemacs-mode' can
distinguish from the ASCII equivalents:

- C-i (TAB) is changed to <C-i>

- C-m (RET) is changed to <C-m>

- C-[ (ESC)  is changed to <C-]>"
  (let* ((last-was-version nil)
         (remaining
          (mapcar
           (lambda(elt)
             (cond
              (last-was-version
               (setq last-was-version nil)
               (if (stringp elt)
                   `(ergoemacs-component-struct--new-version ,elt)
                 `(ergoemacs-component-struct--new-version ,(symbol-name elt))))
              ((ignore-errors (eq elt ':version))
               (setq last-was-version t)
               nil)
              ((ignore-errors (eq (nth 0 elt) 'global-reset-key))
               `(ergoemacs-component-struct--define-key 'global-map ,(ergoemacs-theme-component--parse-key (nth 1 elt)) nil))
              ((ignore-errors (eq (nth 0 elt) 'global-unset-key))
               `(ergoemacs-component-struct--define-key 'global-map ,(ergoemacs-theme-component--parse-key (nth 1 elt)) nil))
              ((ignore-errors (eq (nth 0 elt) 'set))
               ;; Currently doesn't support (setq a b c d ), but it should.
               `(ergoemacs-component-struct--set ,(nth 1 elt) '(lambda() ,(nth 2 elt))))
              ((ignore-errors (eq (nth 0 elt) 'add-hook))
               `(ergoemacs-component-struct--set ,(nth 1 elt) ,(nth 2 elt)
                                                 (list t ,(nth 3 elt) ,(nth 4 elt))))
              ((ignore-errors (eq (nth 0 elt) 'remove-hook))
               `(ergoemacs-component-struct--set ,(nth 1 elt) ,(nth 2 elt)
                                                 (list nil nil ,(nth 3 elt))))
              ((ignore-errors (memq (nth 0 elt) '(setq setq-default)))
               ;; in the theme component `setq' is equivalent to
               ;; `seq-default' since the component uses `set' and `set-default'
               (let ((tmp-elt elt)
                     (ret '()))
                 (pop tmp-elt)
                 (while (and (= 0 (mod (length tmp-elt) 2)) (< 0 (length tmp-elt)))
                   (push `(ergoemacs-component-struct--set (quote ,(pop tmp-elt)) '(lambda() ,(pop tmp-elt))) ret))
                 (push 'progn ret)
                 ret))
              ((ignore-errors (string-match "-mode$" (symbol-name (nth 0 elt))))
               `(ergoemacs-component-struct--set (quote ,(nth 0 elt)) '(lambda() ,(nth 1 elt))))
              ((ignore-errors (eq (nth 0 elt) 'global-set-key))
               `(ergoemacs-component-struct--define-key 'global-map ,(ergoemacs-theme-component--parse-key (nth 1 elt))
                                                        ,(ergoemacs-theme-component--parse-fun (nth 2 elt))))
              
              ;; (bind-key "C-c x" 'my-ctrl-c-x-command)
              ((ignore-errors (and (eq (nth 0 elt) 'bind-key)
                                   (= (length elt) 3)))
               `(ergoemacs-component-struct--define-key 'global-map (kbd ,(ergoemacs-theme-component--parse-key-str (nth 1 elt)))
                                                        ,(ergoemacs-theme-component--parse-fun (nth 2 elt))))

              ;; (bind-key "C-c x" 'my-ctrl-c-x-command some-other-map)
              ((ignore-errors (and (eq (nth 0 elt) 'bind-key)
                                   (= (length elt) 4)))
               `(ergoemacs-component-struct--define-key (quote ,(nth 3 elt)) (kbd ,(ergoemacs-theme-component--parse-key-str (nth 1 elt)))
                                                        ,(ergoemacs-theme-component--parse-fun (nth 2 elt))))
              
              ((ignore-errors (eq (nth 0 elt) 'define-key))
               (if (equal (nth 1 elt) '(current-global-map))
                   `(ergoemacs-component-struct--define-key 'global-map ,(ergoemacs-theme-component--parse-key (nth 2 elt))
                                                            ,(ergoemacs-theme-component--parse-fun (nth 3 elt)))
                 `(ergoemacs-component-struct--define-key (quote ,(nth 1 elt)) ,(ergoemacs-theme-component--parse-key (nth 2 elt))
                                                          ,(ergoemacs-theme-component--parse-fun (nth 3 elt)))))
              ((or (ignore-errors (eq (nth 0 elt) 'with-hook))
                   (and (ignore-errors (eq (nth 0 elt) 'when))
                        (ignore-errors (string-match "\\(-hook\\|-mode\\|^mark-active\\)$" (symbol-name (nth 1 elt))))))
               (let ((tmp (ergoemacs-theme-component--parse (cdr (cdr elt)) t)))
                 `(ergoemacs-component-struct--with-hook
                   ',(nth 1 elt) ',(nth 0 tmp)
                   '(lambda () ,@(nth 1 tmp)))))
              ((ignore-errors (memq (nth 0 elt) '(dolist when unless if)))
               `(,(car elt) ,(car (cdr elt)) ,@(macroexpand-all (ergoemacs-theme-component--parse-remaining (cdr (cdr elt))))))
              ((ignore-errors (memq (nth 0 elt) '(ergoemacs-advice defadvice)))
               (macroexpand-all elt))
              (t `(ergoemacs-component-struct--deferred ',elt))))
           remaining)))
    remaining))

(defvar ergoemacs-theme-component-properties
  '(:bind
    :bind-keymap
    :bind*
    :bind-keymap*
    :commands
    :interpreter
    :defer
    :demand
    :package-name
    :ergoemacs-require
    :no-load
    :no-require
    :just-first-keys
    :variable-modifiers
    :variable-prefixes
    :layout)
  "List of ergoemacs-theme-component properties.")

(defvar ergoemacs-theme-components--modified-plist nil
  "Modified plist.")

(fset 'ergoemacs-theme-component--parse-keys-and-body
      #'(lambda (keys-and-body &optional parse-function  skip-first)
          "Split KEYS-AND-BODY into keyword-and-value pairs and the remaining body.

KEYS-AND-BODY should have the form of a property list, with the
exception that only keywords are permitted as keys and that the
tail -- the body -- is a list of forms that does not start with a
keyword.

Returns a two-element list containing the keys-and-values plist
and the body.

This has been stolen directly from ert by Christian Ohler <ohler@gnu.org>

Afterward it was modified for use with `ergoemacs-mode' to use
additional parsing routines defined by PARSE-FUNCTION."
          (let ((extracted-key-accu '())
                plist
                (remaining keys-and-body))
            ;; Allow
            ;; (component name)
            (unless (or (keywordp (cl-first remaining)) skip-first)
              (if (condition-case nil
                      (stringp (cl-first remaining))
                    (error nil))
                  (push (cons ':name (pop remaining)) extracted-key-accu)
                (push (cons ':name  (symbol-name (pop remaining))) extracted-key-accu))
              (when (memq (type-of (cl-first remaining)) '(symbol cons))
                (setq remaining (cdr remaining)))
              (when (stringp (cl-first remaining))
                (push (cons ':description (pop remaining)) extracted-key-accu)))
            (while (and (consp remaining) (keywordp (cl-first remaining)))
              (let ((keyword (pop remaining)))
                (unless (consp remaining)
                  (error "Value expected after keyword %S in %S"
                         keyword keys-and-body))
                (when (assoc keyword extracted-key-accu)
                  (ergoemacs-warn "Keyword %S appears more than once in %S" keyword
                                  keys-and-body))
                (push (cons keyword (pop remaining)) extracted-key-accu)))
            (setq extracted-key-accu (nreverse extracted-key-accu))
            (setq plist (cl-loop for (key . value) in extracted-key-accu
                              collect key
                              collect value))
            (when parse-function
              (setq remaining
                    (funcall parse-function remaining)))
            (list plist remaining))))

;;;###autoload
(defmacro ergoemacs-save-buffer-state (&rest body)
  "Eval BODY,
then restore the buffer state under the assumption that no significant
modification has been made in BODY.  A change is considered
significant if it affects the buffer text in any way that isn't
completely restored again.  Changes in text properties like `face' or
`syntax-table' are considered insignificant.  This macro allows text
properties to be changed, even in a read-only buffer.

This macro should be placed around all calculations which set
\"insignificant\" text properties in a buffer, even when the buffer is
known to be writeable.  That way, these text properties remain set
even if the user undoes the command which set them.

This macro should ALWAYS be placed around \"temporary\" internal buffer
changes \(like adding a newline to calculate a text-property then
deleting it again\), so that the user never sees them on his
`buffer-undo-list'.  

However, any user-visible changes to the buffer \(like auto-newlines\)
must not be within a `ergoemacs-save-buffer-state', since the user then
wouldn't be able to undo them.

The return value is the value of the last form in BODY.

This was stole/modified from `c-save-buffer-state'"
  `(let* ((modified (buffer-modified-p)) (buffer-undo-list t)
          (inhibit-read-only t) (inhibit-point-motion-hooks t)
          before-change-functions after-change-functions
          deactivate-mark
          buffer-file-name buffer-file-truename ; Prevent primitives checking
                                        ; for file modification
          )
     (unwind-protect
         (progn ,@body)
       (and (not modified)
            (buffer-modified-p)
            (set-buffer-modified-p nil)))))

(defvar ergoemacs--map-properties-list
  '(
    :composed-list
    :composed-p
    :deferred-maps
    :empty-p
    :installed-p
    :key-hash
    :key-lessp
    :key-struct
    :keys
    :label
    :lookup
    :movement-p
    :original
    :original-user
    :override-map-p
    :override-maps
    :revert-original
    :sequence
    :set-map-p
    :use-local-unbind-list-p
    :user
    :where-is
    :map-list
    )
  "Partial list of `ergoemacs' supported properties.

These proprerties are aliaes for ergoemacs-map-properties--
functions.")

;;;###autoload
(defmacro ergoemacs (&rest args)
  "Get/Set keymaps and `ergoemacs-mode' properties

When arg1 can be a property.  The following properties are supported:
- :layout - returns the current (or specified by PROPERTY) keyboard layout.
- :map-list,  :composed-p, :composed-list, :key-hash :empty-p calls ergoemacs-map-properties-- equivalent functions.

"
  (let ((arg1 (nth 0 args))
        (arg2 (nth 1 args))
        (arg3 (nth 2 args))
        (arg4 (nth 3 args)))
    (cond
     ((and arg1 (symbolp arg1) (eq arg1 :reset-prefix))
      `(prefix-command-preserve-state))
     ((and arg1 (symbolp arg1) (eq arg1 :set-selection))
      `(gui-set-selection ,@(cdr args)))
     ((and arg1 (symbolp arg1) (eq arg1 :set-selection))
      `(gui-set-selection ,@(cdr args)))
     ((and arg1 (symbolp arg1) (eq arg1 :custom-p) (symbolp arg2))
      (if (fboundp 'custom-variable-p)
          `(custom-variable-p ,arg2)
        `(user-variable-p ,arg2)))
     ((and arg1 (symbolp arg1) (eq arg1 :apply-key) arg2 arg3)
      `(ergoemacs-translate--apply-key ,@(cdr args)))
     ((and arg1 (symbolp arg1) (eq arg1 :spinner) arg2)
      `(ergoemacs-command-loop--spinner-display ,@(cdr args)))
     ((and arg1 (symbolp arg1) (eq arg1 :define-key) arg2 arg3)
      `(ergoemacs-translate--define-key ,arg2 ,arg3 ,arg4))
     ((and arg1 (symbolp arg1) (eq arg1 :ignore-global-changes-p) (not arg2) (not arg3))
      `(ergoemacs-map-properties--ignore-global-changes-p))
     ((and arg1 (symbolp arg1) (eq arg1 :user-before) (not arg2) (not arg3))
      `(ergoemacs-map-properties--before-ergoemacs))
     ((and arg1 (symbolp arg1) (eq arg1 :user-after) (not arg2) (not arg3))
      `(ergoemacs-map-properties--before-ergoemacs t))
     ((and arg1 (symbolp arg1) (eq arg1 :combine) arg2 arg3)
      `(ergoemacs-command-loop--combine ,arg2 ,arg3))
     ((and arg1 (symbolp arg1) (eq arg1 :modifier-desc)
           arg2)
      `(mapconcat #'ergoemacs-key-description--modifier ,arg2 ""))
     ((and arg1 (symbolp arg1)
           (memq arg1 ergoemacs--map-properties-list))
      `(,(intern (format "ergoemacs-map-properties--%s" (substring (symbol-name arg1) 1))) ,@(cdr args)))

     ((and arg1 (symbolp arg1)
           (eq arg1 :global-map))
      `(ergoemacs-map-properties--original (or ergoemacs-saved-global-map global-map)))
     ((and arg1 (symbolp arg1)
           (eq arg1 :revert-global-map))
      `(ergoemacs-map-properties--original (or ergoemacs-saved-global-map global-map) :setcdr))
     ((and arg1 (symbolp arg1)
           (eq arg1 :layout))
      `(ergoemacs-layouts--current ,arg2))
     ((and arg1 arg2 (not arg3)
           (symbolp arg2)
           (string= ":" (substring (symbol-name arg2) 0 1)))
      ;; Get a arg2
      (cond
       ((eq arg2 :full)
        `(ignore-errors (char-table-p (nth 1 (ergoemacs-map-properties--keymap-value ,arg1)))))
       ((eq arg2 :indirect)
        (macroexpand-all `(ergoemacs-keymapp (symbol-function ,arg1))))
       ((memq arg2 '(:map-key :key))
        ;; FIXME Expire any ids that are no longer linked??
        `(ignore-errors (plist-get (ergoemacs-map-properties--map-fixed-plist ,arg1) :map-key)))
       ((memq arg2 ergoemacs--map-properties-list)
        `(,(intern (format "ergoemacs-map-properties--%s" (substring (symbol-name arg2) 1))) ,arg1))
       (t
        `(ergoemacs-map-properties--get ,arg1 ,arg2))))
     ((and arg1 arg2 arg3
           (symbolp arg2)
	   (memq arg2 ergoemacs--map-properties-list))
      ;; Assign a property.
      `(,(intern (format "ergoemacs-map-properties--%s" (substring (symbol-name arg2) 1))) ,arg1 ,@(cdr (cdr args))))
     ((and arg1 arg2 arg3
           (symbolp arg2)
           (string= ":" (substring (symbol-name arg2) 0 1)))
      ;; Assign a property.
      `(ergoemacs-map-properties--put ,arg1 ,arg2 ,arg3))
     ((and (not arg3) (eq arg1 'emulation-mode-map-alists))
      `(ergoemacs-map--emulation-mode-map-alists ,arg2))
     ((and (not arg3) (eq arg1 'minor-mode-overriding-map-alist))
      `(ergoemacs-map--minor-mode-overriding-map-alist ,arg2))
     ((and (not arg3) (eq arg1 'minor-mode-map-alist))
      `(ergoemacs-map--minor-mode-map-alist ,arg2))
     (t
      `(ergoemacs-map-- ,arg1)))))

;;;###autoload
(defmacro ergoemacs-advice (function args &rest body-and-plist)
  "Defines an `ergoemacs-mode' advice.

The structure is (ergoemacs-advice function args tags body-and-plist)

When the tag :type equals :replace, the advice replaces the function.

When :type is :replace that replaces a function (like `define-key')"
  (declare (doc-string 2)
           (indent 2))
  (let ((kb (make-symbol "kb")))
    (setq kb (ergoemacs-theme-component--parse-keys-and-body `(nil nil ,@body-and-plist)))
    (cond
     ((eq (plist-get (nth 0 kb) :type) :around)
      ;; FIXME: use `nadvice' for emacs 24.4+
      (macroexpand-all `(progn
                          (defadvice ,function (around ,(intern (format "ergoemacs-advice--%s" (symbol-name function))) ,args activate)
                            ,(plist-get (nth 0 kb) :description)
                            ,@(nth 1 kb)))))
     ((eq (plist-get (nth 0 kb) :type) :after)
      ;; FIXME: use `nadvice' for emacs 24.4+
      (macroexpand-all
       `(progn
          (defadvice ,function (after ,(intern (format "ergoemacs-advice--after-%s" (symbol-name function))) ,args activate)
            ,(plist-get (nth 0 kb) :description)
            ,@(nth 1 kb)))))
     ((eq (plist-get (nth 0 kb) :type) :before)
      ;; FIXME: use `nadvice' for emacs 24.4+
      (macroexpand-all `(progn
                          (defadvice ,function (before ,(intern (format "ergoemacs-advice--%s" (symbol-name function))) ,args activate)
                            ,(plist-get (nth 0 kb) :description)
                            ,@(nth 1 kb)))))
     ((eq (plist-get (nth 0 kb) :type) :replace)
      (macroexpand-all `(progn
                          (defalias ',(intern (format "ergoemacs-advice--real-%s" (symbol-name function)))
                            (symbol-function ',function) (concat ,(format "ARGS=%s\n\n" args) (documentation ',function)
                                                                 ,(format "\n\n`ergoemacs-mode' preserved the real `%s' in this function."
                                                                          (symbol-name function))))
                          (defun ,(intern (format "ergoemacs-advice--%s--" function)) ,args
                            ,(format "%s\n\n%s\n\n`ergoemacs-mode' replacement function for `%s'.\nOriginal function is preserved in `ergoemacs-advice--real-%s'"
                                     (documentation function)
                                     (plist-get (nth 0 kb) :description) (symbol-name function) (symbol-name function))
                            ,@(nth 1 kb))
                          ;; Hack to make sure the documentation is in the function...
                          (defalias ',(intern (format "ergoemacs-advice--%s" function)) ',(intern (format "ergoemacs-advice--%s--" function))
                            ,(format "ARGS=%s\n\n%s\n\n%s\n\n`ergoemacs-mode' replacement function for `%s'.\nOriginal function is preserved in `ergoemacs-advice--real-%s'"
                                     args (documentation function) (plist-get (nth 0 kb) :description) (symbol-name function) (symbol-name function)))
                          ,(if (plist-get (nth 0 kb) :always)
                               `(push ',function ergoemacs-advice--permanent-replace-functions)
                             `(push ',function ergoemacs-advice--temp-replace-functions))))))))

(defmacro ergoemacs-cache (item &rest body)
  "Either read ITEM's cache or evaluate BODY, cache ITEM and return value."
  (declare (indent 1))
  (or (and (symbolp item)
           (macroexpand-all
            `(progn
               (or (ergoemacs-map--cache-- ',item)
                   (ergoemacs-map--cache--
                    ',item (progn ,@body))))))
      (macroexpand-all
       `(let ((--hash-key ,item))
          (or (ergoemacs-map--cache-- --hash-key)
              (ergoemacs-map--cache-- --hash-key (progn ,@body)))))))

(defmacro ergoemacs-cache-p (item)
  "Does ITEM cache exist?"
  (or (and (symbolp item)
           (macroexpand-all
            `(ergoemacs-map-cache--exists-p ',item)))
      (macroexpand-all
       `(let ((--hash-key ,item))
          (ergoemacs-map-cache--exists-p --hash-key)))))

(defmacro ergoemacs-timing (key &rest body)
  "Save the timing using KEY for BODY."
  (declare (indent 1))
  (if (listp key)
      `(ergoemacs-timing-- ,key (lambda() ,@body))
    `(ergoemacs-timing-- ',key (lambda() ,@body))))

(defmacro ergoemacs-no-specials (&rest body)
  "Revert some `ergoemacs-mode' functions to their C defintions in BODY."
  `(cl-letf (((symbol-function 'read-key-sequence) #'ergoemacs--real-read-key-sequence)
	     ((symbol-function 'describe-key) #'ergoemacs--real-describe-key))
     ,@body))

(defmacro ergoemacs-autoloadp (object)
  "Non-nil if OBJECT is an autoload."
  (cond
   ((fboundp #'autoloadp) `(autoloadp ,object))
   (t `(eq 'autoload (car-safe ,object)))))

(defmacro ergoemacs-buffer-narrowed-p ()
  "Return non-nil if the current buffer is narrowed."
  (cond
   ((fboundp #'buffer-narrowed-p) `(buffer-narrowed-p))
   (t `(/= (- (point-max) (point-min)) (buffer-size)))))

(provide 'ergoemacs-macros)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ergoemacs-macros.el ends here
;; Local Variables:
;; coding: utf-8-emacs
;; End:
