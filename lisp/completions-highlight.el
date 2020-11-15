;;; completions-highlight.el --- highlight and natural move throw *Completions* buffer -*- lexical-binding: t -*-

;; Copyright (C) 2020 Free Software Foundation, Inc.

;; Author: Jimmy Aguilar Mena <spacibba at aol dot com>
;; Created: Aug 2020 Jimmy Aguilar Mena spacibba@aol.com
;; Keywords: help, abbrev

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

;; Enabling this package implements more dynamic interaction with the
;; *Completions* buffer to give the user a similar experience than
;; interacting with Zle from zsh shell.

;; The package intents to implement such functionalities without using
;; hacks or complex functions.  And using the default Emacs *Completions*
;; infrastructure.


;;; Code:

(require 'simple)
(require 'minibuffer)

(defvar completions-highlight-overlay nil
  "Overlay to use when `completion-highlight-mode' is enabled.")

(defvar minibuffer-tab-through-completions-function-save nil
  "Saves the the original value of completion-in-minibuffer-scroll-window.")

(defvar completions-highlight-minibuffer-map-save nil
  "Saves the minibuffer current-localmap to restore it disabling the mode.")

(defvar completions-highlight-completions-map-save nil
  "Saves the Completions current-localmap to restore it disabling the mode.")

;; *Completions* side commands

(defun completions-highlight-this-completion (&optional n)
  "Highlight the completion under point or near.
N is set to 1 if not specified."
  (setq n (or (and n (/ n (abs n)))
	      1))
  (next-completion n)
  (completions-highlight-next-completion (* -1 n)))

(defun completions-highlight-next-completion (n)
  "Move to and highlight the next item in the completion list.
With prefix argument N, move N items (negative N means move backward).
If completion highlight is enabled, highlights the selected candidate.
Returns the completion string if available."
  (interactive "p")
  (next-completion n)

  (let* ((obeg (point))
         (oend (next-single-property-change obeg 'mouse-face nil (point-max)))
         (choice (buffer-substring-no-properties obeg oend)))

    (move-overlay completions-highlight-overlay obeg oend)
    (minibuffer-completion-set-suffix choice)

    ;; Return the current completion
    choice))

(defun completions-highlight-previous-completion (n)
  "Move to the previous N item in the completion list.
See `completions-highlight-next-completion' for more details."
  (interactive "p")
  (completions-highlight-next-completion (- n)))

(defun completions-highlight-next-line-completion (&optional arg try-vscroll)
  "Go to completion candidate in line above current.
With prefix argument ARG, move to ARG candidate bellow current.
TRY-VSCROLL is passed straight to `line-move'"
  (interactive "^p\np")
  (line-move arg t nil try-vscroll)
  (completions-highlight-this-completion arg))

(defun completions-highlight-previous-line-completion (&optional arg try-vscroll)
  "Go to completion candidate in line above current.
With prefix argument ARG, move to ARG candidate above current.
TRY-VSCROLL is passed straight to `line-move'"
  (interactive "^p\np")
  (completions-highlight-next-line-completion (- arg) try-vscroll))


;; Minibuffer side commands

(defmacro with-minibuffer-scroll-window (&rest body)
  "Execute BODY in *Completions* buffer and return to `minibuffer'.
The command is only executed if the `minibuffer-scroll-window' is
alive and active."
  `(and (window-live-p minibuffer-scroll-window)
	(eq t (frame-visible-p (window-frame minibuffer-scroll-window)))
	(with-selected-window minibuffer-scroll-window
          (with-current-buffer (window-buffer minibuffer-scroll-window)
            ,@body))))

(defun minibuffer-next-completion (n)
  "Execute `completions-highlight-next-completion' in *Completions*.
The argument N is passed directly to
`completions-highlight-next-completion', the command is executed
in another window, but cursor stays in minibuffer."
  (interactive "p")
  (with-minibuffer-scroll-window
   (completions-highlight-next-completion n)))


(defun minibuffer-previous-completion (n)
  "Execute `completions-highlight-previous-completion' in *Completions*.
The argument N is passed directly to
`completions-highlight-previous-completion', the command is
executed in another window, but cursor stays in minibuffer."
  (interactive "p")
  (with-minibuffer-scroll-window
   (completions-highlight-previous-completion n)))


(defun minibuffer-next-line-completion (n)
  "Execute `completions-highlight-next-line-completion' in *Completions*.
The argument N is passed directly to
`completions-highlight-next-line-completion', the command is
executed in another window, but cursor stays in minibuffer."
  (interactive "p")
  (with-minibuffer-scroll-window
   (completions-highlight-next-line-completion n)))


(defun minibuffer-previous-line-completion (n)
  "Execute `completions-highlight-previous-line-completion' in *Completions*.
The argument N is passed directly to
`completions-highlight-previous-line-completion', the command is
executed in another window, but cursor stays in minibuffer."
  (interactive "p")
  (with-minibuffer-scroll-window
   (completions-highlight-previous-line-completion n)))

;; General commands

(defun minibuffer-completion-set-suffix (choice)
  "Set CHOICE suffix to current completion.
It uses `completion-base-position' to determine the cursor
position.  If choice is the empty string the command removes the
suffix."
  (let* ((obase-position completion-base-position)
         (minibuffer-window (active-minibuffer-window))
         (minibuffer-buffer (window-buffer minibuffer-window))
         (completion-no-auto-exit t))

    (with-selected-window minibuffer-window
      (with-current-buffer minibuffer-buffer
	(let* ((prompt-end (minibuffer-prompt-end))
	       (cursor-pos (if obase-position
			       (cadr obase-position)
			     (choose-completion-guess-base-position choice)))
	       (prefix-len (- cursor-pos prompt-end))
	       (suffix (if (< prefix-len (length choice))
			   (substring choice prefix-len)
			 ""))
	       (suffix-len (string-width suffix)))

          (choose-completion-string suffix minibuffer-buffer
                                    (list cursor-pos (point-max)))
          (add-face-text-property cursor-pos (+ cursor-pos suffix-len) 'shadow)
          (goto-char cursor-pos))))))


(defvar completions-highlight-minibuffer-map
  (let ((map (make-sparse-keymap)))
    (define-key map [right] 'minibuffer-next-completion)
    (define-key map [left] 'minibuffer-previous-completion)
    (define-key map [down] 'minibuffer-next-line-completion)
    (define-key map [up] 'minibuffer-previous-line-completion)
    map)
  "Keymap used in minibuffer while *Completions* is active.")

(defvar completions-highlight-completions-map
  (let ((map (make-sparse-keymap)))
    (define-key map "\C-g" 'quit-window)

    (define-key map [up] 'completions-highlight-previous-line-completion)
    (define-key map "\C-p" 'completions-highlight-previous-line-completion)
    (define-key map [down] 'completions-highlight-next-line-completion)
    (define-key map "\C-n" 'completions-highlight-next-line-completion)

    (define-key map [right] 'completions-highlight-next-completion)
    (define-key map "\C-f" 'completions-highlight-next-completion)
    (define-key map [left] 'completions-highlight-previous-completion)
    (define-key map "\C-b" 'completions-highlight-previous-completion)
    map)
  "Keymap used in *Completions* while highlighting candidates.")


(defun completions-highlight-minibuffer-bindings (set)
  "Add extra/remove keybindings to `minibuffer-local-must-match-map'.
When SET is nil the bindings are removed."
  (if set
      (let ((local-map (current-local-map)))
        (setq completions-highlight-minibuffer-map-save local-map)
        (set-keymap-parent completions-highlight-minibuffer-map local-map)
        (use-local-map completions-highlight-minibuffer-map))

    (use-local-map completions-highlight-minibuffer-map-save)))


(defun completions-highlight-completions-bindings (set)
  "Add extra keybindings to `completion-list-mode-map'.
When SET is nil the bindings are removed."
  (if set
      (unless (keymap-parent completions-highlight-completions-map)
        (let ((local-map (current-local-map)))
          (setq completions-highlight-completions-map-save local-map)
          (set-keymap-parent completions-highlight-completions-map local-map)
          (use-local-map completions-highlight-completions-map)))

    ;; Set is called already inside *Completions* but unset not
    (when-let ((parent (keymap-parent completions-highlight-completions-map))
               (buffer (get-buffer "*Completions*")))
      (with-current-buffer buffer
        (use-local-map completions-highlight-completions-map-save)))))


(defun completions-highlight-minibuffer-tab-through-completions ()
  "Default action in `minibuffer-scroll-window' WINDOW.
This is called when *Completions* window is already visible and
should be assigned to completion-in-minibuffer-scroll-window."
  (let ((window minibuffer-scroll-window))
    (with-current-buffer (window-buffer window)
      (if (pos-visible-in-window-p (point-max) window)
	  (if (pos-visible-in-window-p (point-min) window)
	      ;; If all completions are shown point-min and point-max
	      ;; are both visible.  Then do the highlight.
	      (minibuffer-next-completion 1)
	    ;; Else the buffer is too long, so better just scroll it to
	    ;; the beginning as default behavior.
	    (set-window-start window (point-min) nil))
	;; Then point-max is not visible the buffer is too long and we
	;; can scroll.
	(with-selected-window window (scroll-up))))))

(defun completions-highlight-completions-pre-command-hook ()
  "Function `pre-command-hook' to use only in the *Completions."
  (move-overlay completions-highlight-overlay 0 0)
  (minibuffer-completion-set-suffix ""))

(defun completions-highlight-minibuffer-pre-command-hook ()
  "Function `pre-command-hook' to use only in the minibuffer."
  (unless (eq this-command 'minibuffer-complete-and-exit)
    (minibuffer-completion-set-suffix "")))

(defun completions-highlight-setup ()
  "Function to call when enabling the `completion-highlight-mode' mode.
It is called when showing the *Completions* buffer."

  (with-current-buffer standard-output
    (when (string= (buffer-name) "*Completions*")
      (unless (overlayp completions-highlight-overlay)
	  (setq completions-highlight-overlay (make-overlay 0 0))
	  (overlay-put completions-highlight-overlay 'face 'highlight))

      (add-hook 'pre-command-hook
		#'completions-highlight-completions-pre-command-hook nil t)
      (add-hook 'isearch-mode-end-hook
		#'completions-highlight-this-completion nil t)

      (completions-highlight-completions-bindings t)))

  (add-hook 'pre-command-hook
	    #'completions-highlight-minibuffer-pre-command-hook nil t)

  (completions-highlight-minibuffer-bindings t))

(defun completions-highlight-exit ()
  "Function to call when disabling the `completion-highlight-mode' mode.
It is called when hiding the *Completions* buffer."
  (completions-highlight-minibuffer-bindings nil))

(define-minor-mode completions-highlight-mode
  "Completion highlight mode to enable candidates highlight in the minibuffer."
  :global t
  :group 'minibuffer

  (if completions-highlight-mode
      (progn
	(setq minibuffer-tab-through-completions-function-save
	      minibuffer-tab-through-completions-function)

	(setq minibuffer-tab-through-completions-function
	      #'completions-highlight-minibuffer-tab-through-completions)

	(add-hook 'completion-setup-hook #'completions-highlight-setup t)
	(add-hook 'minibuffer-hide-completions-hook #'completions-highlight-exit)
	)

    ;; Restore the default completion-in-minibuffer-scroll-window
    (setq minibuffer-tab-through-completions-function
	  minibuffer-tab-through-completions-function-save)

    (remove-hook 'completion-setup-hook #'completions-highlight-setup)
    (remove-hook 'minibuffer-hide-completions-hook #'completions-highlight-exit)

    (completions-highlight-completions-bindings nil)))

(provide 'completions-highlight)
;;; completions-highlight.el ends here
