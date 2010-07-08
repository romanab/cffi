;; Defining C structures.
;; Liam Healy 2009-04-07 22:42:15EDT interface.lisp
;; Time-stamp: <2010-07-08 09:25:23EDT cstruct.lisp>
;; $Id: $

(in-package :fsbv)

(export '(defcstruct defined-type-p))

;;; These macros are designed to make the interface to functions that
;;; get and/or return structs as transparent as possible, mimicking
;;; the CFFI definitions.

;;; Potential efficiency improvement: when a filed has count > 1,
;;; define a pointer to the first element, and reference from that,
;;; instead of recomputing the pointer each element.

(defun lookup-type (symbol)
  (or `(libffi-type-pointer ,symbol)
      (error "Element type ~a is not known to libffi." symbol)))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defvar *libffi-struct-defs* nil))

(defun defined-type-p (name)
  "This structure has been defined for call-by-value."
  (member name *libffi-struct-defs*))

(defun field-count (field &optional (default 1))
  (getf field :count default))

(defun name-from-name-and-options (name-and-options)
  (if (listp name-and-options)
      (first name-and-options)
      name-and-options))

(defun option-from-name-and-options (name-and-options option default)
  (if (listp name-and-options)
      (getf (rest name-and-options) option default)
      default))

(defun iterate-foreign-structure (fields form)
  "Iterate over the foreign structure, generating forms
   with form-function, a function of field, fn and gn.
   The argument fn is the count within the field, and
   gn is the overall count from 0."
  (loop for field in fields with gn = 0
     append
     (loop for fn from 0 below (field-count field)
	append
	(prog1
	    (funcall form field fn gn)
	  (incf gn)))))

(defun structure-slot-form (field structure-name fn)
  "A form for getting or setting the foreign slot value.
   The variables 'object and 'index are captured."
  (let ((form
	 `(cffi:foreign-slot-value
	   (cffi:mem-aref object ',structure-name index)
	   ',structure-name ',(first field))))
    (if (field-count field nil)		; aggregate slot
	`(object ,form ,(second field) ,fn)
	;; simple slot
	form)))

(defmacro defcstruct (name-and-options &body fields)
  "A macro to define the struct to CFFI and to libffi simultaneously.
   Syntax is exactly that of cffi:defcstruct."
  (let ((total-number-of-elements (apply '+ (mapcar 'field-count fields)))
	(name (name-from-name-and-options name-and-options)))
    (pushnew name *libffi-struct-defs*)
    `(progn
       (cffi:defcstruct
	   ,(name-from-name-and-options name-and-options)
	 ,@fields)
       (eval-when (:compile-toplevel :load-toplevel :execute)
	 (pushnew ',name *libffi-struct-defs*))
       (setf (libffi-type-pointer ,name)
	     (let ((ptr (cffi:foreign-alloc 'ffi-type))
		   (elements (cffi:foreign-alloc
			      :pointer
			      :count
			      ,(1+ total-number-of-elements))))
	       (setf
		;; The elements
		,@(iterate-foreign-structure
		   fields
		   (lambda (field fn gn)
		     (declare (ignore fn))
		     (list
		      `(cffi:mem-aref elements :pointer ,gn)
		      (lookup-type (second field)))))
		(cffi:mem-aref elements :pointer ,total-number-of-elements)
		(cffi:null-pointer)
		;; The ffi-type
		(cffi:foreign-slot-value ptr 'ffi-type 'size) 0
		(cffi:foreign-slot-value ptr 'ffi-type 'alignment) 0
		(cffi:foreign-slot-value ptr 'ffi-type 'type) +type-struct+
		(cffi:foreign-slot-value ptr 'ffi-type 'elements) elements)
	       ptr)
	     (get ',name 'foreign-object-components)
	     (lambda (object &optional (index 0))
	       (,(option-from-name-and-options name-and-options :constructor 'list)
		 ,@(iterate-foreign-structure
		    fields
		    (lambda (field fn gn)
		      (declare (ignore gn))
		      `(,(structure-slot-form field name fn))))))
	     (get ',name 'setf-foreign-object-components)
	     (lambda (value object &optional (index 0))
	       (setf
		,@(iterate-foreign-structure
		   fields
		   (lambda (field fn gn)
		     `(,(structure-slot-form field name fn)
			,(let ((decon
				(option-from-name-and-options
				 name-and-options :deconstructor 'elt)))
			      (if (listp decon)
				  `(,(nth gn decon) value)
				  `(,decon value ,gn)))))))))
       ',name)))
