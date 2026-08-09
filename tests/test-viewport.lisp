;;; test-viewport.lisp
;;;
;;; SPDX-License-Identifier: MIT
;;;
;;; Copyright (C) 2025  Anthony Green <green@moxielogic.com>
;;;
;;;; Tests for the viewport component (src/components/viewport.lisp)

(in-package #:tuition-tests)

(def-suite viewport-tests
  :description "Tests for the viewport component."
  :in tuition-tests)

(in-suite viewport-tests)

(test viewport-no-wrap-truncates-horizontally
  "Without soft-wrap a long line is not split into extra visual lines."
  (let ((vp (tui.viewport:make-viewport :width 10 :height 5)))
    (tui.viewport:viewport-set-content vp "0123456789ABCDEFGHIJ")
    (is (= 1 (tui.viewport:viewport-total-visual-lines vp)))
    (is (= 1 (length (tui.viewport::viewport-visible-lines-list vp))))))

(test viewport-soft-wrap-counts-visual-lines
  "With soft-wrap a line wider than WIDTH occupies several visual lines."
  (let ((vp (tui.viewport:make-viewport :width 10 :height 5 :soft-wrap t)))
    (tui.viewport:viewport-set-content vp "0123456789ABCDEFGHIJ")
    ;; 20 chars at width 10 -> 2 visual lines.
    (is (= 2 (tui.viewport:viewport-total-visual-lines vp)))
    (is (= 1 (tui.viewport:viewport-total-lines vp)))))

(test viewport-soft-wrap-visible-window
  "Soft-wrap visible lines are windowed by height across visual lines."
  (let ((vp (tui.viewport:make-viewport :width 5 :height 2 :soft-wrap t)))
    (tui.viewport:viewport-set-content vp "aaaaabbbbbccccc")   ; 15 chars -> 3 visual
    (is (= 3 (tui.viewport:viewport-total-visual-lines vp)))
    (let ((visible (tui.viewport::viewport-visible-lines-list vp)))
      (is (= 2 (length visible)))
      (is (string= "aaaaa" (first visible)))
      (is (string= "bbbbb" (second visible))))
    ;; Scrolling advances by visual lines.
    (tui.viewport:viewport-scroll-down vp)
    (let ((visible (tui.viewport::viewport-visible-lines-list vp)))
      (is (string= "bbbbb" (first visible)))
      (is (string= "ccccc" (second visible))))))

(test viewport-soft-wrap-max-offset
  "The max Y offset accounts for wrapped visual lines."
  (let ((vp (tui.viewport:make-viewport :width 5 :height 2 :soft-wrap t)))
    (tui.viewport:viewport-set-content vp "aaaaabbbbbccccc")   ; 3 visual, height 2
    (tui.viewport:viewport-goto-bottom vp)
    (is (= 1 (tui.viewport:viewport-y-offset vp)))
    (is (tui.viewport:viewport-at-bottom-p vp))))

(test viewport-soft-wrap-preserves-blank-lines
  "Empty content lines remain as blank visual lines when wrapping."
  (let ((vp (tui.viewport:make-viewport :width 5 :height 5 :soft-wrap t)))
    (tui.viewport:viewport-set-content vp (format nil "aa~%~%bb"))
    (is (= 3 (tui.viewport:viewport-total-visual-lines vp)))))

(test viewport-set-content-lines
  "Content can be set directly from a list of lines."
  (let ((vp (tui.viewport:make-viewport :width 20 :height 5)))
    (tui.viewport:viewport-set-content-lines vp '("one" "two" "three"))
    (is (= 3 (tui.viewport:viewport-total-lines vp)))
    (is (string= "one" (first (tui.viewport::viewport-visible-lines-list vp))))))
