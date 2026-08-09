;;; test-list-component.lisp
;;;
;;; SPDX-License-Identifier: MIT
;;;
;;; Copyright (C) 2025  Anthony Green <green@moxielogic.com>
;;;
;;;; Tests for the paginated list component (src/components/list.lisp).
;;;; (Distinct from test-list.lisp, which covers the static list renderer.)

(in-package #:tuition-tests)

(def-suite list-component-tests
  :description "Tests for the paginated list component."
  :in tuition-tests)

(in-suite list-component-tests)

(defun lc-make (items &key (height 3) infinite-scrolling)
  (tui.list:make-list-view :items items :height height
                           :infinite-scrolling infinite-scrolling))

(defun lc-items (n)
  (loop for i below n collect (format nil "item~d" i)))

(test list-pagination-basic
  "Items are split into pages of PER-PAGE rows."
  (let ((lv (lc-make (lc-items 7) :height 3)))
    (is (= 3 (tui.list:list-per-page lv)))
    (is (= 3 (tui.list:list-total-pages lv)))     ; 7 items / 3 = 3 pages
    (is (= 3 (tui.list:list-items-on-page lv)))
    (is (= 0 (tui.list:list-index lv)))))

(test list-cursor-down-advances-page
  "Moving down past the page bottom advances to the next page."
  (let ((lv (lc-make (lc-items 7) :height 3)))
    (dotimes (_ 3) (tui.list:list-cursor-down lv))   ; rows 0->1->2->next page row 0
    (is (= 1 (tui.list:list-page lv)))
    (is (= 0 (tui.list:list-cursor lv)))
    (is (= 3 (tui.list:list-index lv)))
    (is (string= "item3" (tui.list:list-get-selected lv)))))

(test list-cursor-clamps-on-partial-last-page
  "On a short last page the cursor never points past the last item (#831)."
  (let ((lv (lc-make (lc-items 7) :height 3)))
    ;; Page 2 holds a single item (item6).
    (tui.list:list-go-to-end lv)
    (is (= 2 (tui.list:list-page lv)))
    (is (= 0 (tui.list:list-cursor lv)))           ; only 1 item on last page
    (is (= 6 (tui.list:list-index lv)))
    ;; Trying to move down further does not overshoot.
    (tui.list:list-cursor-down lv)
    (is (= 6 (tui.list:list-index lv)))
    (is (string= "item6" (tui.list:list-get-selected lv)))))

(test list-next-page-clamps-cursor
  "Paging onto a shorter page clamps the cursor onto it (#837)."
  (let ((lv (lc-make (lc-items 7) :height 3)))
    ;; Select the last row of page 0, then page forward twice to the 1-item page.
    (tui.list:list-cursor-down lv)
    (tui.list:list-cursor-down lv)                 ; cursor row 2 on page 0
    (tui.list:list-next-page lv)                   ; page 1 still has 3 items
    (is (= 2 (tui.list:list-cursor lv)))
    (tui.list:list-next-page lv)                   ; page 2 has 1 item -> clamp
    (is (= 0 (tui.list:list-cursor lv)))
    (is (= 6 (tui.list:list-index lv)))))

(test list-cursor-up-goes-to-prev-page-last-item
  "Moving up off the top of a page lands on the previous page's last item."
  (let ((lv (lc-make (lc-items 7) :height 3)))
    (tui.list:list-next-page lv)                   ; page 1, cursor 0 (item3)
    (tui.list:list-cursor-up lv)
    (is (= 0 (tui.list:list-page lv)))
    (is (= 2 (tui.list:list-cursor lv)))           ; last item of page 0
    (is (= 2 (tui.list:list-index lv)))))

(test list-cursor-up-stops-at-top
  "Without infinite scrolling, up at the very top stays put."
  (let ((lv (lc-make (lc-items 5) :height 3)))
    (tui.list:list-cursor-up lv)
    (is (= 0 (tui.list:list-index lv)))))

(test list-infinite-scrolling-wraps
  "With infinite scrolling, up at the top wraps to the end and down at the end
wraps to the start."
  (let ((lv (lc-make (lc-items 5) :height 3 :infinite-scrolling t)))
    (tui.list:list-cursor-up lv)                   ; wrap to last item (index 4)
    (is (= 4 (tui.list:list-index lv)))
    (tui.list:list-cursor-down lv)                 ; wrap back to first
    (is (= 0 (tui.list:list-index lv)))))

(test list-go-to-start-and-end
  "Go-to-start / go-to-end land on the first / last items."
  (let ((lv (lc-make (lc-items 10) :height 4)))
    (tui.list:list-go-to-end lv)
    (is (= 9 (tui.list:list-index lv)))
    (tui.list:list-go-to-start lv)
    (is (= 0 (tui.list:list-index lv)))))

(test list-filter-narrows-items
  "Filtering restricts the visible items and repaginates from the top."
  (let ((lv (lc-make '("apple" "banana" "apricot" "cherry" "avocado") :height 10)))
    (tui.list:list-set-filter lv "ap")
    (is (equal '("apple" "apricot") (tui.list:list-visible-items lv)))
    (is (= 0 (tui.list:list-index lv)))
    (is (string= "apple" (tui.list:list-get-selected lv)))
    (tui.list:list-reset-filter lv)
    (is (= 5 (length (tui.list:list-visible-items lv))))))

(test list-set-selected-derives-page-cursor
  "Setting the global selected index derives the page and cursor."
  (let ((lv (lc-make (lc-items 10) :height 4)))
    (setf (tui.list:list-selected lv) 6)
    (is (= 1 (tui.list:list-page lv)))             ; 6 / 4 = page 1
    (is (= 2 (tui.list:list-cursor lv)))           ; 6 mod 4 = 2
    (is (string= "item6" (tui.list:list-get-selected lv)))))

(test list-empty-is-safe
  "An empty list reports index -1 and nil selection without error."
  (let ((lv (lc-make '() :height 3)))
    (is (= -1 (tui.list:list-index lv)))
    (is (null (tui.list:list-get-selected lv)))
    (tui.list:list-cursor-down lv)
    (tui.list:list-cursor-up lv)
    (is (= -1 (tui.list:list-index lv)))))

(test list-render-marks-cursor
  "The rendered page marks the selected row with '>'."
  (let ((lv (lc-make (lc-items 5) :height 3)))
    (tui.list:list-cursor-down lv)                 ; select row 1 (item1)
    (let ((lines (tuition:split-string-by-newline (tui.list:list-view-render lv))))
      (is (search "  item0" (first lines)))
      (is (search "> item1" (second lines))))))
