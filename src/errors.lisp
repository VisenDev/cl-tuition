;;; errors.lisp
;;;
;;; SPDX-License-Identifier: MIT
;;;
;;; Copyright (C) 2025  Anthony Green <green@moxielogic.com>
;;;
;;;; Condition types and error handling hooks

(in-package #:tuition)

(define-condition tuition-error (error)
  ()
  (:documentation "Base condition for Tuition errors."))

(define-condition terminal-error (tuition-error)
  ((reason :initarg :reason :reader terminal-error-reason))
  (:report (lambda (c s)
             (format s "Terminal error: ~A" (terminal-error-reason c)))))

(define-condition terminal-operation-error (terminal-error)
  ((operation :initarg :operation :reader terminal-error-operation))
  (:report (lambda (c s)
             (format s "Terminal ~A failed: ~A"
                     (terminal-error-operation c)
                     (terminal-error-reason c)))))

(define-condition input-error (tuition-error)
  ((reason :initarg :reason :reader input-error-reason))
  (:report (lambda (c s)
             (format s "Input error: ~A" (input-error-reason c)))))

(defun %env-truthy-p (name)
  "True when environment variable NAME is set to a truthy value."
  (let ((v (uiop:getenv name)))
    (and v (member (string-downcase (string-trim " " v))
                   '("1" "true" "yes" "on" "t")
                   :test #'string=))))

(defparameter *panic-log-enabled*
  (%env-truthy-p "TUITION_DEBUG")
  "When true, HANDLE-ERROR writes a tuition-panic-<timestamp>.log trace file in
addition to reporting to *ERROR-OUTPUT*.  Seeded from the TUITION_DEBUG
environment variable at load time; may be set at runtime.")

(defun %backtrace-string (condition)
  "Return a best-effort backtrace string for CONDITION.  Never signals."
  (with-output-to-string (s)
    (ignore-errors
      (uiop:print-backtrace :stream s :condition condition))))

(defun %write-panic-log (where condition backtrace)
  "Write a panic trace file and return its pathname, or NIL on failure."
  (ignore-errors
    (let ((path (format nil "tuition-panic-~D.log" (get-universal-time))))
      (with-open-file (f path :direction :output
                              :if-exists :supersede
                              :if-does-not-exist :create)
        (format f "Caught error at ~A:~%~%~A~%~%~A~%" where condition backtrace))
      path)))

(defparameter *error-handler*
  (lambda (where condition)
    (let ((backtrace (%backtrace-string condition)))
      (ignore-errors
        (format *error-output* "~&Tuition caught error at ~A:~%~A~%~A~%"
                where condition backtrace))
      (when *panic-log-enabled*
        (let ((path (%write-panic-log where condition backtrace)))
          (when path
            (ignore-errors
              (format *error-output* "Trace written to ~A~%" path)))))))
  "Function of (WHERE CONDITION) called when internal errors are caught.
WHERE is a keyword indicating origin, e.g., :event-loop, :input-loop, :terminal.
The default reports the condition and a backtrace to *ERROR-OUTPUT* and, when
*PANIC-LOG-ENABLED* (or the TUITION_DEBUG env var) is set, writes a
tuition-panic-<timestamp>.log trace file.  Users may bind or set this to
customize error reporting.")

(defun handle-error (where condition)
  "Invoke the configured error handler for a caught CONDITION at WHERE."
  (funcall *error-handler* where condition))
