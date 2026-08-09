;;; components/list.lisp
;;;
;;; SPDX-License-Identifier: MIT
;;;
;;; Copyright (C) 2025  Anthony Green <green@moxielogic.com>
;;;
;;;; List component - a paginated, filterable, scrollable list.
;;;;
;;;; Ports the bubbles list model: items are laid out across pages of PER-PAGE
;;;; rows, a cursor moves within the current page (advancing pages at the
;;;; edges), and the cursor is always clamped so the selection can never point
;;;; past the last item on a page (bubbles #831/#837).

(defpackage #:tuition.components.list
  (:use #:cl)
  (:nicknames #:tui.list)
  (:export
   ;; Model
   #:list-view
   #:make-list-view

   ;; Accessors
   #:list-items
   #:list-selected
   #:list-height
   #:list-cursor
   #:list-page
   #:list-per-page
   #:list-infinite-scrolling
   #:list-filter-text
   #:list-filter-state
   #:list-filtered-items

   ;; Derived queries
   #:list-visible-items
   #:list-index
   #:list-total-pages
   #:list-items-on-page

   ;; Operations
   #:list-init
   #:list-update
   #:list-view-render
   #:list-move-up
   #:list-move-down
   #:list-cursor-up
   #:list-cursor-down
   #:list-next-page
   #:list-prev-page
   #:list-go-to-start
   #:list-go-to-end
   #:list-get-selected
   #:list-set-items

   ;; Filtering
   #:list-set-filter
   #:list-reset-filter))

(in-package #:tuition.components.list)

;;; List model
(defclass list-view ()
  ((items :initarg :items
          :initform '()
          :accessor list-items
          :documentation "List of items (strings, or anything printable)")
   (cursor :initform 0
           :accessor list-cursor
           :documentation "Selected row within the current page")
   (page :initform 0
         :accessor list-page
         :documentation "Current page index (0-based)")
   (height :initarg :height
           :initform 10
           :accessor list-height
           :documentation "Visible height of the list; also the page size")
   (infinite-scrolling :initarg :infinite-scrolling
                       :initform nil
                       :accessor list-infinite-scrolling
                       :documentation "When true, moving past the last item wraps
to the first and vice versa")
   (filter-text :initform ""
                :accessor list-filter-text
                :documentation "Current filter text")
   (filter-state :initform :unfiltered
                 :accessor list-filter-state
                 :documentation "One of :UNFILTERED, :FILTERING, :APPLIED")
   (filtered-items :initform nil
                   :accessor list-filtered-items
                   :documentation "Items matching the current filter"))
  (:documentation "A paginated, filterable, scrollable list component."))

(defun make-list-view (&key (items '()) (height 10) infinite-scrolling)
  "Create a new list."
  (make-instance 'list-view :items items :height height
                            :infinite-scrolling infinite-scrolling))

;;; Internal helpers

(defun %clamp (v lo hi)
  "Clamp V into [LO, HI], swapping the bounds if they are reversed."
  (when (> lo hi) (rotatef lo hi))
  (min hi (max lo v)))

(defun %item-string (item)
  "Render ITEM as a display string."
  (if (stringp item) item (princ-to-string item)))

;;; Derived queries

(defun list-per-page (list-view)
  "Number of items shown per page (at least 1)."
  (max 1 (list-height list-view)))

(defun list-visible-items (list-view)
  "The items currently in view: the filtered subset while filtering/applied,
otherwise all items."
  (if (member (list-filter-state list-view) '(:filtering :applied))
      (list-filtered-items list-view)
      (list-items list-view)))

(defun list-total-pages (list-view)
  "Total number of pages (at least 1)."
  (let ((n (length (list-visible-items list-view)))
        (pp (list-per-page list-view)))
    (max 1 (ceiling n pp))))

(defun %slice-bounds (list-view)
  "Return (VALUES START END) into the visible items for the current page."
  (let* ((n (length (list-visible-items list-view)))
         (pp (list-per-page list-view))
         (start (min (* (list-page list-view) pp) n))
         (end (min (+ start pp) n)))
    (values start end)))

(defun list-items-on-page (list-view)
  "Number of items on the current page."
  (multiple-value-bind (start end) (%slice-bounds list-view)
    (max 0 (- end start))))

(defun %max-cursor-index (list-view)
  "Largest valid cursor row on the current page."
  (max 0 (1- (list-items-on-page list-view))))

(defun %on-last-page-p (list-view)
  (>= (list-page list-view) (1- (list-total-pages list-view))))

(defun list-index (list-view)
  "Global 0-based index of the selection within the visible items, or -1 when
the list is empty."
  (if (zerop (length (list-visible-items list-view)))
      -1
      (+ (* (list-page list-view) (list-per-page list-view))
         (list-cursor list-view))))

;;; Navigation

(defun list-go-to-start (list-view)
  "Jump to the first item on the first page."
  (setf (list-page list-view) 0
        (list-cursor list-view) 0)
  list-view)

(defun list-go-to-end (list-view)
  "Jump to the last item on the last page."
  (setf (list-page list-view) (max 0 (1- (list-total-pages list-view))))
  (setf (list-cursor list-view) (%max-cursor-index list-view))
  list-view)

(defun list-prev-page (list-view)
  "Move to the previous page, clamping the cursor onto it."
  (when (> (list-page list-view) 0)
    (decf (list-page list-view)))
  (setf (list-cursor list-view)
        (%clamp (list-cursor list-view) 0 (%max-cursor-index list-view)))
  list-view)

(defun list-next-page (list-view)
  "Move to the next page, clamping the cursor onto it."
  (unless (%on-last-page-p list-view)
    (incf (list-page list-view)))
  (setf (list-cursor list-view)
        (%clamp (list-cursor list-view) 0 (%max-cursor-index list-view)))
  list-view)

(defun list-cursor-up (list-view)
  "Move the selection up one item, advancing to the previous page at the top
edge (or wrapping to the end when infinite scrolling is enabled)."
  (decf (list-cursor list-view))
  (cond
    ;; At the very top of the first page.
    ((and (< (list-cursor list-view) 0) (zerop (list-page list-view)))
     (if (list-infinite-scrolling list-view)
         (list-go-to-end list-view)
         (setf (list-cursor list-view) 0)))
    ;; Still within the current page.
    ((>= (list-cursor list-view) 0) nil)
    ;; Off the top of a later page: move to the previous page's last item.
    (t
     (when (> (list-page list-view) 0)
       (decf (list-page list-view)))
     (setf (list-cursor list-view) (%max-cursor-index list-view))))
  list-view)

(defun list-cursor-down (list-view)
  "Move the selection down one item, advancing to the next page at the bottom
edge (or wrapping to the start when infinite scrolling is enabled)."
  (let ((max-cursor (%max-cursor-index list-view)))
    (incf (list-cursor list-view))
    (cond
      ;; Still within the current page.
      ((<= (list-cursor list-view) max-cursor) nil)
      ;; More pages remain: advance to the top of the next page.
      ((not (%on-last-page-p list-view))
       (incf (list-page list-view))
       (setf (list-cursor list-view) 0))
      ;; On the last page: clamp, or wrap around when infinite scrolling.
      (t
       (setf (list-cursor list-view) (max 0 max-cursor))
       (when (list-infinite-scrolling list-view)
         (list-go-to-start list-view)))))
  list-view)

;; Backwards-compatible aliases.
(defun list-move-up (list-view)
  "Move selection up (alias for LIST-CURSOR-UP)."
  (list-cursor-up list-view))

(defun list-move-down (list-view)
  "Move selection down (alias for LIST-CURSOR-DOWN)."
  (list-cursor-down list-view))

;;; Selection accessors (global index, backwards compatible)

(defun list-selected (list-view)
  "Global 0-based index of the current selection (-1 when empty)."
  (list-index list-view))

(defun (setf list-selected) (index list-view)
  "Set the selection to global INDEX, deriving the page and cursor."
  (let* ((n (length (list-visible-items list-view)))
         (pp (list-per-page list-view)))
    (if (<= n 0)
        (list-go-to-start list-view)
        (let ((i (%clamp index 0 (1- n))))
          (setf (list-page list-view) (floor i pp)
                (list-cursor list-view) (mod i pp)))))
  index)

(defun list-get-selected (list-view)
  "Return the currently selected item, or NIL when the list is empty."
  (let ((idx (list-index list-view))
        (vis (list-visible-items list-view)))
    (when (and (>= idx 0) (< idx (length vis)))
      (nth idx vis))))

;;; Content management

(defun list-set-items (list-view items)
  "Replace the list items, clearing any filter and resetting the selection."
  (setf (list-items list-view) items
        (list-filter-state list-view) :unfiltered
        (list-filtered-items list-view) nil
        (list-filter-text list-view) "")
  (list-go-to-start list-view))

;;; Filtering

(defun list-set-filter (list-view text)
  "Filter items to those containing TEXT (case-insensitive substring match) and
jump to the first match.  An empty TEXT clears the filter."
  (setf (list-filter-text list-view) text)
  (if (zerop (length text))
      (setf (list-filter-state list-view) :unfiltered
            (list-filtered-items list-view) nil)
      (let ((needle (string-downcase text)))
        (setf (list-filtered-items list-view)
              (remove-if-not
               (lambda (item)
                 (search needle (string-downcase (%item-string item))))
               (list-items list-view))
              (list-filter-state list-view) :applied)))
  (list-go-to-start list-view))

(defun list-reset-filter (list-view)
  "Clear the active filter and reset the selection."
  (setf (list-filter-text list-view) ""
        (list-filter-state list-view) :unfiltered
        (list-filtered-items list-view) nil)
  (list-go-to-start list-view))

;;; Component protocol

(defun list-init (list-view)
  "Initialize the list. Returns nil (no command needed)."
  (declare (ignore list-view))
  nil)

(defun list-update (list-view msg)
  "Update the list with a key message. Returns (values new-list cmd)."
  (if (typep msg 'tuition:key-press-msg)
      (let ((key (tuition:key-event-code msg)))
        (cond
          ((or (eq key :up) (and (characterp key) (char= key #\k)))
           (list-cursor-up list-view))
          ((or (eq key :down) (and (characterp key) (char= key #\j)))
           (list-cursor-down list-view))
          ((or (eq key :left) (eq key :page-up)
               (and (characterp key) (char= key #\h)))
           (list-prev-page list-view))
          ((or (eq key :right) (eq key :page-down)
               (and (characterp key) (char= key #\l)))
           (list-next-page list-view))
          ((or (eq key :home) (and (characterp key) (char= key #\g)))
           (list-go-to-start list-view))
          ((or (eq key :end) (and (characterp key) (char= key #\G)))
           (list-go-to-end list-view))
          (t nil))
        (values list-view nil))
      (values list-view nil)))

(defun list-view-render (list-view)
  "Render the current page, marking the selected row with '>'."
  (multiple-value-bind (start end) (%slice-bounds list-view)
    (let ((vis (list-visible-items list-view))
          (cursor (list-cursor list-view)))
      (with-output-to-string (s)
        (loop for i from start below end
              for row from 0
              do (format s "~A ~A~%"
                         (if (= row cursor) ">" " ")
                         (%item-string (nth i vis))))))))
