;; Copyright (C) 2003-2008 Shawn Betts
;;
;;  This file is part of stumpwm.
;;
;; stumpwm is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; stumpwm is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this software; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 59 Temple Place, Suite 330,
;; Boston, MA 02111-1307 USA

;; Commentary:
;;
;; Frame functions
;;
;; Code:

(in-package #:stumpwm)

(export '(save-frame-excursion))

(defun populate-frames (group)
  "Try to fill empty frames in GROUP with hidden windows"
  (dolist (f (group-frames group))
    (unless (frame-window f)
      (choose-new-frame-window f group)
      (when (frame-window f)
        (maximize-window (frame-window f))
        (unhide-window (frame-window f))))))

(defun frame-by-number (group n)
  (unless (eq n nil)
    (find n (group-frames group)
          :key 'frame-number
          :test '=)))

(defun find-frame (group x y)
  "Return the frame of GROUP containing the pixel at X Y"
  (dolist (f (group-frames group))
    (let* ((fy (frame-y f))
           (fx (frame-x f))
           (fwx (+ fx (frame-width f)))
           (fhy (+ fy (frame-height f))))
      (when (and
             (>= y fy) (<= y fhy)
             (>= x fx) (<= x fwx)
             (return f))))))


(defun frame-set-x (frame v)
  (decf (frame-width frame)
        (- v (frame-x frame)))
  (setf (frame-x frame) v))

(defun frame-set-y (frame v)
  (decf (frame-height frame)
        (- v (frame-y frame)))
  (setf (frame-y frame) v))

(defun frame-set-r (frame v)
  (setf (frame-width frame)
        (- v (frame-x frame))))

(defun frame-set-b (frame v)
  (setf (frame-height frame)
        (- v (frame-y frame))))

(defun frame-r (frame)
  (+ (frame-x frame) (frame-width frame)))

(defun frame-b (frame)
  (+ (frame-y frame) (frame-height frame)))

(defun frame-intersect (f1 f2)
  "Return a new frame representing (only) the intersection of F1 and F2. WIDTH and HEIGHT will be <= 0 if there is no overlap"
  (let ((r (copy-frame f1)))
    (when (> (frame-x f2) (frame-x f1))
      (frame-set-x r (frame-x f2)))
    (when (< (+ (frame-x f2) (frame-width f2))
             (+ (frame-x f1) (frame-width f1)))
      (frame-set-r r (frame-r f2)))
    (when (> (frame-y f2) (frame-y f1))
      (frame-set-y r (frame-y f2)))
    (when (< (+ (frame-y f2) (frame-height f2))
             (+ (frame-y f1) (frame-height f1)))
      (frame-set-b r (frame-b f2)))
  (values r)))

(defun frames-overlap-p (f1 f2)
  "Returns T if frames F1 and F2 overlap at all"
  (check-type f1 frame)
  (check-type f2 frame)
  (and (and (frame-p f1) (frame-p f2))
       (let ((frame (frame-intersect f1 f2)))
         (values (and (plusp (frame-width frame))
                      (plusp (frame-height frame)))))))

(defun frame-raise-window (g f w &optional (focus t))
  "Raise the window w in frame f in group g. if FOCUS is
T (default) then also focus the frame."
  (let ((oldw (frame-window f)))
    ;; nothing to do when W is nil
    (setf (frame-window f) w)
    (unless (and w (eq oldw w))
      (if w
          (raise-window w)
          (mapc 'hide-window (frame-windows g f))))
    (when focus
      (focus-frame g f))
    (when (and w (not (window-modal-p w)))
      (raise-modals-of w))))

(defun focus-frame (group f)
  (let ((w (frame-window f))
        (last (tile-group-current-frame group))
        (show-indicator nil))
    (setf (tile-group-current-frame group) f)
    ;; record the last frame to be used in the fother command.
    (unless (eq f last)
      (setf (tile-group-last-frame group) last)
      (run-hook-with-args *focus-frame-hook* f last)
      (setf show-indicator t))
    (if w
        (focus-window w)
        (no-focus group (frame-window last)))
    (if show-indicator
        (show-frame-indicator group)
        (show-frame-outline group))))

(defun frame-windows (group f)
  (remove-if-not (lambda (w) (eq (window-frame w) f))
                 (group-windows group)))

(defun frame-sort-windows (group f)
  (remove-if-not (lambda (w) (eq (window-frame w) f))
                 (sort-windows group)))

(defun copy-frame-tree (tree)
  "Return a copy of the frame tree."
  (cond ((null tree) tree)
        ((typep tree 'frame)
         (copy-structure tree))
        (t
         (mapcar #'copy-frame-tree tree))))

(defun group-frames (group)
  (tree-accum-fn (tile-group-frame-tree group) 'nconc 'list))

(defun head-frames (group head)
  (tree-accum-fn (tile-group-frame-head group head) 'nconc 'list))

(defun find-free-frame-number (group)
  (find-free-number (mapcar (lambda (f) (frame-number f))
                            (group-frames group))))

(defun choose-new-frame-window (frame group)
  "Find out what window should go in a newly created frame."
  (let ((win (case *new-frame-action*
               (:last-window (other-hidden-window group))
               (t nil))))
    (setf (frame-window frame) win)
    (when win
      (setf (window-frame win) frame))))

(defun split-frame-h (group p)
  "Return 2 new frames. The first one stealing P's number and window"
  (let* ((w (truncate (/ (frame-width p) 2)))
         (h (frame-height p))
         (f1 (make-frame :number (frame-number p)
                         :x (frame-x p)
                         :y (frame-y p)
                         :width w
                         :height h
                         :window (frame-window p)))
         (f2 (make-frame :number (find-free-frame-number group)
                         :x (+ (frame-x p) w)
                         :y (frame-y p)
                         ;; gobble up the modulo
                         :width (- (frame-width p) w)
                         :height h
                         :window nil)))
    (run-hook-with-args *new-frame-hook* f2)
    (values f1 f2)))

(defun split-frame-v (group p)
  "Return 2 new frames. The first one stealing P's number and window"
  (let* ((w (frame-width p))
         (h (truncate (/ (frame-height p) 2)))
         (f1 (make-frame :number (frame-number p)
                         :x (frame-x p)
                         :y (frame-y p)
                         :width w
                         :height h
                         :window (frame-window p)))
         (f2 (make-frame :number (find-free-frame-number group)
                         :x (frame-x p)
                         :y (+ (frame-y p) h)
                         :width w
                         ;; gobble up the modulo
                         :height (- (frame-height p) h)
                         :window nil)))
    (run-hook-with-args *new-frame-hook* f2)
    (values f1 f2)))

(defun funcall-on-leaf (tree leaf fn)
  "Return a new tree with LEAF replaced with the result of calling FN on LEAF."
  (cond ((atom tree)
         (if (eq leaf tree)
             (funcall fn leaf)
             tree))
        (t (mapcar (lambda (sib)
                     (funcall-on-leaf sib leaf fn))
                   tree))))

(defun funcall-on-node (tree fn match)
  "Call fn on the node where match returns t."
  (if (funcall match tree)
      (funcall fn tree)
      (cond ((atom tree) tree)
            (t (mapcar (lambda (sib)
                         (funcall-on-node sib fn match))
                       tree)))))

(defun replace-frame-in-tree (tree f &rest frames)
  (funcall-on-leaf tree f (lambda (f)
                            (declare (ignore f))
                            frames)))

(defun sibling-internal (tree leaf fn)
  "helper for next-sibling and prev-sibling."
  (cond ((atom tree) nil)
        ((find leaf tree)
         (let* ((rest (cdr (member leaf (funcall fn tree))))
                (pick (car (if (null rest) (funcall fn tree) rest))))
           (unless (eq pick leaf)
             pick)))
        (t (find-if (lambda (x)
                      (sibling-internal x leaf fn))
                    tree))))

(defun next-sibling (tree leaf)
  "Return the sibling of LEAF in TREE."
  (sibling-internal tree leaf 'identity))

(defun prev-sibling (tree leaf)
  (sibling-internal tree leaf 'reverse))

(defun closest-sibling (tree leaf)
  "Return the sibling to the right/below of leaf or left/above if
leaf is the most right/below of its siblings."
  (let* ((parent (tree-parent tree leaf))
         (lastp (= (position leaf parent) (1- (length parent)))))
    (if lastp
        (prev-sibling parent leaf)
        (next-sibling parent leaf))))

(defun migrate-frame-windows (group src dest)
  "Migrate all windows in SRC frame to DEST frame."
  (mapc (lambda (w)
          (when (eq (window-frame w) src)
            (setf (window-frame w) dest)))
        (group-windows group)))

(defun tree-accum-fn (tree acc fn)
  "Run an accumulator function on fn applied to each leaf"
  (cond ((null tree) nil)
        ((atom tree)
         (funcall fn tree))
        (t (apply acc (mapcar (lambda (x) (tree-accum-fn x acc fn)) tree)))))

(defun tree-iterate (tree fn)
  "Call FN on every leaf in TREE"
  (cond ((null tree) nil)
        ((atom tree)
         (funcall fn tree))
        (t (mapc (lambda (x) (tree-iterate x fn)) tree))))

(defun tree-x (tree)
  (tree-accum-fn tree 'min 'frame-x))

(defun tree-y (tree)
  (tree-accum-fn tree 'min 'frame-y))

(defun tree-width (tree)
  (cond ((atom tree) (frame-width tree))
        ((tree-row-split tree)
         ;; in row splits, all children have the same width, so use the
         ;; first one.
         (tree-width (first tree)))
        (t
         ;; for column splits we add the width of each child
         (reduce '+ tree :key 'tree-width))))

(defun tree-height (tree)
  (cond ((atom tree) (frame-height tree))
        ((tree-column-split tree)
         ;; in row splits, all children have the same width, so use the
         ;; first one.
         (tree-height (first tree)))
        (t
         ;; for column splits we add the width of each child
         (reduce '+ tree :key 'tree-height))))

(defun tree-parent (top node)
  "Return the list in TOP that contains NODE."
  (cond ((atom top) nil)
        ((find node top) top)
        (t (loop for i in top
                 thereis (tree-parent i node)))))

(defun tree-leaf (top)
  "Return a leaf of the tree. Use this when you need a leaf but
you don't care which one."
  (tree-accum-fn top
                 (lambda (&rest siblings)
                   (car siblings))
                 #'identity))

(defun tree-row-split (tree)
  "Return t if the children of tree are stacked vertically"
  (loop for i in (cdr tree)
        with head = (car tree)
        always (= (tree-x head) (tree-x i))))

(defun tree-column-split (tree)
  "Return t if the children of tree are side-by-side"
  (loop for i in (cdr tree)
        with head = (car tree)
        always (= (tree-y head) (tree-y i))))

(defun tree-split-type (tree)
  "return :row or :column"
  (cond ((tree-column-split tree) :column)
        ((tree-row-split tree) :row)
        (t (error "tree-split-type unknown"))))

(defun offset-tree (tree x y)
  "move the screen's frames around."
  (tree-iterate tree (lambda (frame)
                       (incf (frame-x frame) x)
                       (incf (frame-y frame) y))))

(defun offset-tree-dir (tree amount dir)
  (ecase dir
    (:left   (offset-tree tree (- amount) 0))
    (:right  (offset-tree tree amount 0))
    (:top    (offset-tree tree 0 (- amount)))
    (:bottom (offset-tree tree 0 amount))))

(defun expand-tree (tree amount dir)
  "expand the frames in tree by AMOUNT in DIR direction. DIR can be :top :bottom :left :right"
  (labels ((expand-frame (f amount dir)
             (ecase dir
               (:left   (decf (frame-x f) amount)
                        (incf (frame-width f) amount))
               (:right  (incf (frame-width f) amount))
               (:top    (decf (frame-y f) amount)
                        (incf (frame-height f) amount))
               (:bottom (incf (frame-height f) amount)))))
    (cond ((null tree) nil)
          ((atom tree)
           (expand-frame tree amount dir))
          ((or (and (find dir '(:left :right))
                    (tree-row-split tree))
               (and (find dir '(:top :bottom))
                    (tree-column-split tree)))
           (dolist (i tree)
             (expand-tree i amount dir)))
          (t
           (let* ((children (if (find dir '(:left :top))
                              (reverse tree)
                              tree))
                  (sz-fn (if (find dir '(:left :right))
                           'tree-width
                           'tree-height))
                  (total (funcall sz-fn tree))
                  (amt-list (loop for i in children
                                  for old-sz = (funcall sz-fn i)
                                  collect (truncate (/ (* amount old-sz) total))))
                  (remainder (- amount (apply '+ amt-list)))
                  (ofs 0))
             ;; spread the remainder out as evenly as possible
             (assert (< remainder (length amt-list)))
             (loop for i upfrom 0
                   while (> remainder 0)
                   do
                   (incf (nth i amt-list))
                   (decf remainder))
             ;; resize proportionally
             (loop for i in children
                   for amt in amt-list
                   do
                   (expand-tree i amt dir)
                   (offset-tree-dir i ofs dir)
                   (incf ofs amt)))))))

(defun join-subtrees (tree leaf)
  "expand the children of tree to occupy the space of
LEAF. Return tree with leaf removed."
  (let* ((others (remove leaf tree))
         (newtree (if (= (length others) 1)
                      (car others)
                      others))
         (split-type (tree-split-type tree))
         (dir (if (eq split-type :column) :right :bottom))
         (ofsdir (if (eq split-type :column) :left :top))
         (amt (if (eq split-type :column)
                  (tree-width leaf)
                  (tree-height leaf)))
         (after (cdr (member leaf tree))))
    ;; align all children after the leaf with the edge of the
    ;; frame before leaf.
    (offset-tree-dir after amt ofsdir)
    (expand-tree newtree amt dir)
    newtree))

(defun resize-tree (tree w h &optional x y)
  "Scale TREE to width W and height H, ignoring aspect. If X and Y are
  provided, reposition the TREE as well."
  (let* ((tw (tree-width tree))
         (th (tree-height tree))
         (wf (/ 1 (/ tw w)))
         (hf (/ 1 (/ th h)))
         (xo (if x (- x (tree-x tree)) 0))
         (yo (if y (- y (tree-y tree)) 0)))
    (tree-iterate tree (lambda (f)
                         (setf (frame-height f) (round (* (frame-height f) hf))
                               (frame-y f) (round (* (frame-y f) hf))
                               (frame-width f) (round (* (frame-width f) wf))
                               (frame-x f) (round (* (frame-x f) wf)))
                         (incf (frame-y f) yo)
                         (incf (frame-x f) xo)))
    (dformat 4 "resize-tree ~Dx~D -> ~Dx~D~%" tw th (tree-width tree) (tree-height tree))))

(defun remove-frame (tree leaf)
  "Return a new tree with LEAF and it's sibling merged into
one."
  (cond ((atom tree) tree)
        ((find leaf tree)
         (join-subtrees tree leaf))
        (t (mapcar (lambda (sib)
                     (remove-frame sib leaf))
                   tree))))

(defun sync-frame-windows (group frame)
  "synchronize windows attached to FRAME."
  (mapc (lambda (w)
          (when (eq (window-frame w) frame)
            (dformat 3 "maximizing ~S~%" w)
            (maximize-window w)))
        (group-windows group)))

(defun sync-all-frame-windows (group)
  "synchronize all frames in GROUP."
  (let ((tree (tile-group-frame-tree group)))
    (tree-iterate tree
                  (lambda (f)
                    (sync-frame-windows group f)))))

(defun sync-head-frame-windows (group head)
  "synchronize all frames in GROUP and HEAD."
  (dolist (f (head-frames group head))
    (sync-frame-windows group f)))

(defun offset-frames (group x y)
  "move the screen's frames around."
  (let ((tree (tile-group-frame-tree group)))
    (tree-iterate tree (lambda (frame)
                         (incf (frame-x frame) x)
                         (incf (frame-y frame) y)))))

(defun resize-frame (group frame amount dim)
  "Resize FRAME by AMOUNT in DIM dimension, DIM can be
either :width or :height"
  (check-type group group)
  (check-type frame frame)
  (check-type amount integer)
  ;; (check-type dim (member :width :height))
  (labels ((max-amount (parent node min dim-fn)
             (dformat 10 "max ~@{~a~^ ~}~%" parent node min dim-fn)
             (if parent
                 (- (funcall dim-fn parent)
                    (funcall dim-fn node)
                    (* min (1- (length parent))))
                 ;; no parent means the frame can't get any bigger.
                 0)))
    (let* ((tree (tile-group-frame-tree group))
           (parent (tree-parent tree frame))
           (gparent (tree-parent tree parent))
           (split-type (tree-split-type parent)))
      (dformat 10 "~s ~s parent: ~s ~s width: ~s h: ~s~%" dim amount split-type parent (tree-width parent) (tree-height parent))
      ;; normalize amount
      (let* ((max (ecase dim
                    (:width
                     (if (>= (frame-width frame) (frame-width (frame-head group frame)))
                         0
                         (if (eq split-type :column)
                             (max-amount parent frame *min-frame-width* 'tree-width)
                             (max-amount gparent parent *min-frame-width* 'tree-width))))
                    (:height
                     (if (>= (frame-height frame) (frame-height (frame-head group frame)))
                         0
                         (if (eq split-type :row)
                             (max-amount parent frame *min-frame-height* 'tree-height)
                             (max-amount gparent parent *min-frame-height* 'tree-height))))))
             (min (ecase dim
                    ;; Frames taking up the entire HEAD in one
                    ;; dimension can't be resized in that dimension.
                    (:width
                     (if (and (eq split-type :row)
                              (or (null gparent)
                                  (>= (frame-width frame) (frame-width (frame-head group frame)))))
                         0
                         (- *min-frame-width* (frame-width frame))))
                    (:height
                     (if (and (eq split-type :column)
                              (or (null gparent)
                                  (>= (frame-height frame) (frame-height (frame-head group frame)))))
                         0
                         (- *min-frame-height* (frame-height frame)))))))
        (setf amount (max (min amount max) min))
        (dformat 10 "bounds ~d ~d ~d~%" amount max min))
      ;; if FRAME is taking up the whole DIM or if AMOUNT = 0, do nothing
      (unless (zerop amount)
        (let* ((resize-parent (or (and (eq split-type :column)
                                       (eq dim :height))
                                  (and (eq split-type :row)
                                       (eq dim :width))))
               (to-resize (if resize-parent parent frame))
               (to-resize-parent (if resize-parent gparent parent))
               (lastp (= (position to-resize to-resize-parent) (1- (length to-resize-parent))))
               (to-shrink (if lastp
                              (prev-sibling to-resize-parent to-resize)
                              (next-sibling to-resize-parent to-resize))))
          (expand-tree to-resize amount (ecase dim
                                          (:width (if lastp :left :right))
                                          (:height (if lastp :top :bottom))))
          (expand-tree to-shrink (- amount) (ecase dim
                                              (:width (if lastp :right :left))
                                              (:height (if lastp :bottom :top))))
          (unless (and *resize-hides-windows* (eq *top-map* *resize-map*))
            (tree-iterate to-resize
                          (lambda (leaf)
                            (sync-frame-windows group leaf)))
            (tree-iterate to-shrink
                          (lambda (leaf)
                            (sync-frame-windows group leaf)))))))))

(defun balance-frames-internal (group tree)
  "Resize all the children of tree to be of equal width or height
depending on the tree's split direction."
  (let* ((split-type (tree-split-type tree))
         (fn (if (eq split-type :column)
                 'tree-width
                 'tree-height))
         (side (if (eq split-type :column)
                   :right
                   :bottom))
         (total (funcall fn tree))
         size rem)
    (multiple-value-setq (size rem) (truncate total (length tree)))
    (loop
     for i in tree
     for j = rem then (1- j)
     for totalofs = 0 then (+ totalofs ofs)
     for ofs = (+ (- size (funcall fn i)) (if (plusp j) 1 0))
     do
     (expand-tree i ofs side)
     (offset-tree-dir i totalofs side)
     (tree-iterate i (lambda (leaf)
                       (sync-frame-windows group leaf))))))

(defun split-frame (group how)
  "split the current frame into 2 frames. return T if it succeeded. NIL otherwise."
  (check-type how (member :row :column))
  (let* ((frame (tile-group-current-frame group))
         (head (frame-head group frame)))
    ;; don't create frames smaller than the minimum size
    (when (or (and (eq how :row)
                   (>= (frame-height frame) (* *min-frame-height* 2)))
              (and (eq how :column)
                   (>= (frame-width frame) (* *min-frame-width* 2))))
      (multiple-value-bind (f1 f2) (funcall (if (eq how :column)
                                                'split-frame-h
                                                'split-frame-v)
                                            group frame)
        (setf (tile-group-frame-head group head)
              (if (atom (tile-group-frame-head group head))
                  (list f1 f2)
                  (funcall-on-node (tile-group-frame-head group head)
                                   (lambda (tree)
                                     (if (eq (tree-split-type tree) how)
                                         (list-splice-replace frame tree f1 f2)
                                         (substitute (list f1 f2) frame tree)))
                                   (lambda (tree)
                                     (unless (atom tree)
                                       (find frame tree))))))
        (migrate-frame-windows group frame f1)
        (choose-new-frame-window f2 group)
        (if (eq (tile-group-current-frame group)
                frame)
            (setf (tile-group-current-frame group) f1))
        (setf (tile-group-last-frame group) f2)
        (sync-frame-windows group f1)
        (sync-frame-windows group f2)
        ;; we also need to show the new window in the other frame
        (when (frame-window f2)
          (unhide-window (frame-window f2)))
        t))))

(defun draw-frame-outline (group f tl br)
  "Draw an outline around FRAME."
  (let* ((screen (group-screen group))
         (win (if (frame-window f) (window-xwin (frame-window f)) (screen-root screen)))
         (width (screen-frame-outline-width screen))
         (gc (screen-frame-outline-gc screen))
         (halfwidth (/ width 2)))
    (let ((x (frame-x f))
          (y (frame-display-y group f))
          (w (frame-width f))
          (h (frame-display-height group f)))
      (when tl
        (xlib:draw-line win gc
                        x (+ halfwidth y) w 0 t)
        (xlib:draw-line win gc
                        (+ halfwidth x) y 0 h t))
      (when br
        (xlib:draw-line win gc
                        (+ x (- w halfwidth)) y 0 h t)
        (xlib:draw-line win gc
                        x (+ y (- h halfwidth)) w 0 t)))))

(defun draw-frame-outlines (group &optional head)
  "Draw an outline around all frames in GROUP."
  (clear-frame-outlines group)
  (dolist (h (if head (list head) (group-heads group)))
    (draw-frame-outline group h nil t)
    (tree-iterate (tile-group-frame-head group h) (lambda (f)
                                                    (draw-frame-outline group f t nil)))))

(defun clear-frame-outlines (group)
  "Clear the outlines drawn with DRAW-FRAME-OUTLINES."
  (xlib:clear-area (screen-root (group-screen group))))

(defun draw-frame-numbers (group)
  "Draw the number of each frame in its corner. Return the list of
windows used to draw the numbers in. The caller must destroy them."
  (let ((screen (group-screen group)))
    (mapcar (lambda (f)
              (let ((w (xlib:create-window
                        :parent (screen-root screen)
                        :x (frame-x f) :y (frame-display-y group f) :width 1 :height 1
                        :background (screen-fg-color screen)
                        :border (screen-border-color screen)
                        :border-width 1
                        :event-mask '())))
                (xlib:map-window w)
                (setf (xlib:window-priority w) :above)
                (echo-in-window w (screen-font screen)
                                (screen-fg-color screen)
                                (screen-bg-color screen)
                                (string (get-frame-number-translation f)))
                (xlib:display-finish-output *display*)
                (dformat 3 "mapped ~S~%" (frame-number f))
                w))
            (group-frames group))))

(defmacro save-frame-excursion (&body body)
  "Execute body and then restore the current frame."
  (let ((oframe (gensym "OFRAME"))
        (ogroup (gensym "OGROUP")))
    `(let ((,oframe (tile-group-current-frame (current-group)))
           (,ogroup (current-group)))
      (unwind-protect (progn ,@body)
        (focus-frame ,ogroup ,oframe)))))