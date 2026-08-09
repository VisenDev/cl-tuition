;;; test-textinput.lisp
;;;
;;; SPDX-License-Identifier: MIT
;;;
;;; Copyright (C) 2025  Anthony Green <green@moxielogic.com>
;;;
;;;; Tests for the textinput component (src/components/textinput.lisp)

(in-package #:tuition-tests)

(def-suite textinput-tests
  :description "Tests for the textinput component."
  :in tuition-tests)

(in-suite textinput-tests)

(defun ti-strip-ansi (s)
  "Remove ANSI escape sequences from S for content assertions."
  (with-output-to-string (o)
    (let ((i 0) (n (length s)))
      (loop while (< i n) do
        (if (char= (char s i) #\Escape)
            (loop while (and (< i n) (not (char= (char s i) #\m))) do (incf i))
            (write-char (char s i) o))
        (incf i)))))

(test textinput-placeholder-truncates-with-ellipsis
  "A placeholder wider than WIDTH is truncated with an ellipsis."
  (let ((ti (tui.textinput:make-textinput :width 10 :prompt ""
                                          :placeholder "Enter your name here")))
    (is (string= "Enter you…"
                 (ti-strip-ansi (tui.textinput:textinput-view ti))))))

(test textinput-placeholder-pads-to-width
  "A placeholder shorter than WIDTH is padded with trailing spaces."
  (let ((ti (tui.textinput:make-textinput :width 6 :prompt ""
                                          :placeholder "hi")))
    (is (string= "hi    "
                 (ti-strip-ansi (tui.textinput:textinput-view ti))))))

(test textinput-placeholder-exact-width-no-ellipsis
  "A placeholder exactly WIDTH wide is shown verbatim (no ellipsis)."
  (let ((ti (tui.textinput:make-textinput :width 5 :prompt ""
                                          :placeholder "hello")))
    (is (string= "hello"
                 (ti-strip-ansi (tui.textinput:textinput-view ti))))))

(test textinput-value-hides-placeholder
  "Once a value is entered, the placeholder is not shown."
  (let ((ti (tui.textinput:make-textinput :width 20 :prompt ""
                                          :placeholder "type here")))
    (tui.textinput:textinput-set-value ti "abc")
    (tui.textinput:textinput-blur ti)
    (is (string= "abc" (ti-strip-ansi (tui.textinput:textinput-view ti))))))
