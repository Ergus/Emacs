;;; image-crop.el --- Image Cropping  -*- lexical-binding: t -*-

;; Copyright (C) 2022 Free Software Foundation, Inc.

;; Keywords: multimedia

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package provides an interface for cropping images
;; interactively, but relies on external programs to do the actual
;; modifications to files.

;;; Code:

(require 'svg)

(defvar image-crop-exif-rotate nil
  "If non-nil, rotate images by updating exif data.
If nil, rotate the images \"physically\".")

(defvar image-crop-resize-command '("convert" "-resize" "%wx" "-" "%f:-")
  "Command to resize an image.
The following `format-spec' elements are allowed:

%w: Width.
%f: Result file type.")

(defvar image-crop-elide-command '("convert" "-draw" "rectangle %l,%t %r,%b"
                                   "-" "%f:-")
  "Command to make a rectangle inside an image.

The following `format-spec' elements are allowed:
%l: Left.
%t: Top.
%r: Right.
%b: Bottom.
%f: Result file type.")

(defvar image-crop-crop-command '("convert" "+repage" "-crop" "%wx%h+%l+%t"
	                          "-" "%f:-")
  "Command to crop an image.

The following `format-spec' elements are allowed:
%l: Left.
%t: Top.
%w: Width.
%h: Height.
%f: Result file type.")

(defvar image-crop-rotate-command '("convert" "-rotate" "%r" "-" "%f:-")
  "Command to rotate an image.

The following `format-spec' elements are allowed:
%r: Rotation (in degrees).
%f: Result file type.")

;;;###autoload
(defun image-elide (&optional square)
  "Elide a square from the image under point.
If SQUARE (interactively, the prefix), elide a square instead of a
rectangle from the image."
  (interactive "P")
  (image-crop square t))

;;;###autoload
(defun image-crop (&optional square elide)
  "Crop the image under point.
If SQUARE (interactively, the prefix), crop a square instead of a
rectangle from the image.

If ELIDE, remove a rectangle from the image instead of cropping
the image.

After cropping an image, it can be saved by `M-x image-save' or
\\<image-map>\\[image-save] when point is over the image."
  (interactive "P")
  (unless (image-type-available-p 'svg)
    (error "SVG support is needed to crop images"))
  (unless (executable-find (car image-crop-crop-command))
    (error "Couldn't find %s command to crop the image"
           (car image-crop-crop-command)))
  (let ((image (get-text-property (point) 'display)))
    (unless (imagep image)
      (user-error "No image under point"))
    ;; We replace the image under point with an SVG image that looks
    ;; just like that image.  That allows us to draw lines over it.
    ;; At the end, we replace that SVG with a cropped version of the
    ;; original image.
    (let* ((data (cl-getf (cdr image) :data))
	   (undo-handle (prepare-change-group))
	   (type (cond
		  ((cl-getf (cdr image) :format)
		   (format "%s" (cl-getf (cdr image) :format)))
		  (data
		   (image-crop--content-type data))))
	   (image-scaling-factor 1)
	   (size (image-size image t))
	   (svg (svg-create (car size) (cdr size)
			    :xmlns:xlink "http://www.w3.org/1999/xlink"
			    :stroke-width 5))
	   (text (buffer-substring (pos-bol) (pos-eol)))
	   (inhibit-read-only t)
           orig-data)
      (with-temp-buffer
	(set-buffer-multibyte nil)
	(if (null data)
	    (insert-file-contents-literally (cl-getf (cdr image) :file))
	  (insert data))
	(let ((image-crop-exif-rotate nil))
	  (image-crop--possibly-rotate-buffer image))
	(setq orig-data (buffer-string))
	(setq type (image-crop--content-type orig-data))
        (image-crop--process image-crop-resize-command
                             `((?w . 600)
                               (?f . ,(cadr (split-string type "/")))))
	(setq data (buffer-string)))
      (svg-embed svg data type t
		 :width (car size)
		 :height (cdr size))
      (delete-region (pos-bol) (pos-eol))
      (svg-insert-image svg)
      (let ((area (condition-case _
		      (save-excursion
			(forward-line 1)
			(image-crop--crop-image-1
                         svg square (car size) (cdr size)))
		    (quit nil))))
	(delete-region (pos-bol) (pos-eol))
	(if area
	    (image-crop--crop-image-update area orig-data size type elide)
	  ;; If the user didn't complete the crop, re-insert the
	  ;; original image (and text).
	  (insert text))
	(undo-amalgamate-change-group undo-handle)))))

(defun image-crop--crop-image-update (area data size type elide)
  (let* ((image-scaling-factor 1)
	 (osize (image-size (create-image data nil t) t))
	 (factor (/ (float (car osize)) (car size)))
	 ;; width x height + left + top
	 (width (abs (truncate (* factor (- (cl-getf area :right)
					    (cl-getf area :left))))))
	 (height (abs (truncate (* factor (- (cl-getf area :bottom)
					     (cl-getf area :top))))))
	 (left (truncate (* factor (min (cl-getf area :left)
					(cl-getf area :right)))))
	 (top (truncate (* factor (min (cl-getf area :top)
				       (cl-getf area :bottom))))))
    (image-crop--insert-image-data
     (with-temp-buffer
       (set-buffer-multibyte nil)
       (insert data)
       (if elide
	   (image-crop--process image-crop-elide-command
                                `((?l . ,left)
                                  (?t . ,top)
                                  (?r . ,(+ left width))
                                  (?b . ,(+ top height))
                                  (?f . ,(cadr (split-string type "/")))))
	 (image-crop--process image-crop-crop-command
                              `((?l . ,left)
                                (?t . ,top)
                                (?w . ,width)
                                (?h . ,height)
                                (?f . ,(cadr (split-string type "/"))))))
       (buffer-string)))))

(defun image-crop--crop-image-1 (svg &optional square image-width image-height)
  (track-mouse
    (cl-loop
     with prompt = (if square "Move square" "Set start point")
     and state = (if square 'move-unclick 'begin)
     and area = (if square
		    (list :left (- (/ image-width 2)
				   (/ image-height 2))
			  :top 0
			  :right (+ (/ image-width 2)
				    (/ image-height 2))
			  :bottom image-height)
		  (list :left 0
			:top 0
			:right 0
			:bottom 0))
     and corner = nil
     for event = (read-event prompt)
     do (if (or (not (consp event))
		(not (consp (cadr event)))
		(not (nth 7 (cadr event)))
		;; Only do things if point is over the SVG being
		;; tracked.
		(not (eq (cl-getf (cdr (nth 7 (cadr event))) :type)
			 'svg)))
	    ()
	  (let ((pos (nth 8 (cadr event))))
	    (cl-case state
	      ('begin
	       (cond
		((eq (car event) 'down-mouse-1)
		 (setq state 'stretch
		       prompt "Stretch to end point")
		 (setf (cl-getf area :left) (car pos)
		       (cl-getf area :top) (cdr pos)
		       (cl-getf area :right) (car pos)
		       (cl-getf area :bottom) (cdr pos)))))
	      ('stretch
	       (cond
		((eq (car event) 'mouse-movement)
		 (setf (cl-getf area :right) (car pos)
		       (cl-getf area :bottom) (cdr pos)))
		((memq (car event) '(mouse-1 drag-mouse-1))
		 (setq state 'corner
		       prompt "Choose corner to adjust (RET to crop)"))))
	      ('corner
	       (cond
		((eq (car event) 'down-mouse-1)
		 ;; Find out what corner we're close to.
		 (setq corner (image-crop--find-corner
			       area pos
			       '((:left :top)
				 (:left :bottom)
				 (:right :top)
				 (:right :bottom))))
		 (when corner
		   (setq state 'adjust
			 prompt "Adjust crop")))))
	      ('adjust
	       (cond
		((memq (car event) '(mouse drag-mouse-1))
		 (setq state 'corner
		       prompt "Choose corner to adjust"))
		((eq (car event) 'mouse-movement)
		 (setf (cl-getf area (car corner)) (car pos)
		       (cl-getf area (cadr corner)) (cdr pos)))))
	      ('move-unclick
	       (cond
		((eq (car event) 'down-mouse-1)
		 (setq state 'move-click
		       prompt "Move"))))
	      ('move-click
	       (cond
		((eq (car event) 'mouse-movement)
		 (setf (cl-getf area :left) (car pos)
		       (cl-getf area :right) (+ (car pos) image-height)))
		((memq (car event) '(mouse-1 drag-mouse-1))
		 (setq state 'move-unclick
		       prompt "Click to move")))))))
     do (svg-line svg (cl-getf area :left) (cl-getf area :top)
		  (cl-getf area :right) (cl-getf area :top)
		  :id "top-line" :stroke-color "white")
     (svg-line svg (cl-getf area :left) (cl-getf area :bottom)
	       (cl-getf area :right) (cl-getf area :bottom)
	       :id "bottom-line" :stroke-color "white")
     (svg-line svg (cl-getf area :left) (cl-getf area :top)
	       (cl-getf area :left) (cl-getf area :bottom)
	       :id "left-line" :stroke-color "white")
     (svg-line svg (cl-getf area :right) (cl-getf area :top)
	       (cl-getf area :right) (cl-getf area :bottom)
	       :id "right-line" :stroke-color "white")
     while (not (member event '(return ?q)))
     finally (return (and (eq event 'return)
			  area)))))

(defun image-crop--find-corner (area pos corners)
  (cl-loop for corner in corners
	   ;; We accept 10 pixels off.
	   when (and (< (- (car pos) 10)
			(cl-getf area (car corner))
			(+ (car pos) 10))
		     (< (- (cdr pos) 10)
			(cl-getf area (cadr corner))
			(+ (cdr pos) 10)))
	   return corner))

(defun image-crop--content-type (image)
  ;; Get the MIME type by running "file" over it.
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert image)
    (call-process-region (point-min) (point-max)
			 "file" t (current-buffer) nil
			 "--mime-type" "-")
    (cadr (split-string (buffer-string)))))

(defun image-crop--possibly-rotate-buffer (image)
  (when (imagep image)
    (let ((content-type (image-crop--content-type (buffer-string))))
      (when (image-property image :rotation)
	(cond
	 ;; We can rotate jpegs losslessly by setting the correct
	 ;; orientation.
	 ((and image-crop-exif-rotate
	       (equal content-type "image/jpeg")
	       (executable-find "exiftool"))
	  (call-process-region
	   (point-min) (point-max) "exiftool" t (list (current-buffer) nil) nil
	   (format "-Orientation#=%d"
		   (cl-case (truncate (image-property image :rotation))
		     (0 0)
		     (90 6)
		     (180 3)
		     (270 8)
		     (otherwise 0)))
	   "-o" "-" "-"))
	 ;; Most other image formats have to be reencoded to do
	 ;; rotation.
	 (t
          (image-crop--process
           image-crop-rotate-command
           `((?r . ,(image-property image :rotation))
             (?f . ,(cadr (split-string content-type "/")))))
	  (when (and (equal content-type "image/jpeg")
		     (executable-find "exiftool"))
	    (call-process-region
	     (point-min) (point-max) "exiftool"
             t (list (current-buffer) nil) nil
	     "-Orientation#=0"
	     "-o" "-" "-")))))
      (when (image-property image :width)
        (image-crop--process
         image-crop-resize-command
         `((?w . ,(image-property image :width))
           (?f . ,(cadr (split-string content-type "/")))))))))

(defun image-crop--insert-image-data (image)
  (insert-image
   (create-image image nil t
		 :max-width (- (frame-pixel-width) 50)
		 :max-height (- (frame-pixel-height) 150))
   (format "<img src=\"data:%s;base64,%s\">"
	   (image-crop--content-type image)
	   ;; Get a base64 version of the image.
	   (with-temp-buffer
	     (set-buffer-multibyte nil)
	     (insert image)
	     (base64-encode-region (point-min) (point-max) t)
	     (buffer-string)))
   nil nil t))

(defun image-crop--process (command expansions)
  "Use `call-process-region' with COMMAND expanded with EXPANSIONS."
  (apply
   #'call-process-region (point-min) (point-max)
   (format-spec (car command) expansions)
   t (list (current-buffer) nil) nil
   (mapcar (lambda (elem)
             (format-spec elem expansions))
           (cdr command))))

(provide 'image-crop)

;;; image-crop.el ends here