;;; dired-tests.el --- Test suite. -*- lexical-binding: t -*-

;; Copyright (C) 2015-2025 Free Software Foundation, Inc.

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

;;; Code:
(require 'ert)
(require 'ert-x)
(require 'dired)

(ert-deftest dired-autoload ()
  "Tests to see whether dired-x has been autoloaded"
  (should
   (fboundp 'dired-do-relsymlink))
  (should
   (autoloadp
    (symbol-function
     'dired-do-relsymlink))))

(ert-deftest dired-test-bug22694 ()
  "Test for https://debbugs.gnu.org/22694 ."
  (let* ((dir       (expand-file-name "bug22694" default-directory))
         (file      "test")
         (full-name (expand-file-name file dir))
         (regexp    "bar")
         (dired-always-read-filesystem t) buffers)
    (if (file-exists-p dir)
        (delete-directory dir 'recursive))
    (make-directory dir)
    (with-temp-file full-name (insert "foo"))
    (push (find-file-noselect full-name) buffers)
    (push (dired dir) buffers)
    (with-temp-file full-name (insert "bar"))
    (dired-mark-files-containing-regexp regexp)
    (unwind-protect
        (should (equal (dired-get-marked-files nil nil nil 'distinguish-1-mark)
                       `(t ,full-name)))
      ;; Clean up
      (dolist (buf buffers)
        (when (buffer-live-p buf) (kill-buffer buf)))
      (delete-directory dir 'recursive))))

(defvar dired-query)
(ert-deftest dired-test-bug25609 ()
  "Test for https://debbugs.gnu.org/25609 ."
  (let* ((from (make-temp-file "foo" 'dir))
         ;; Make sure we have long file-names in 'from' and 'to', not
         ;; their 8+3 short aliases, because the latter will confuse
         ;; Dired commands invoked below.
         (from (if (memq system-type '(ms-dos windows-nt))
                   (file-truename from)
                 from))
         (to (make-temp-file "bar" 'dir))
         (to (if (memq system-type '(ms-dos windows-nt))
                 (file-truename to)
                 to))
         (target (expand-file-name (file-name-nondirectory from) to))
         (nested (expand-file-name (file-name-nondirectory from) target))
         (dired-dwim-target t)
         (dired-recursive-copies 'always) ; Don't prompt me.
         buffers)
    (advice-add 'dired-query ; Don't ask confirmation to overwrite a file.
                :override
                (lambda (_sym _prompt &rest _args) (setq dired-query t))
                '((name . "advice-dired-query")))
    (advice-add 'completing-read ; Don't prompt me: just return init.
                :override
                (lambda (_prompt _coll &optional _pred _match init _hist _def _inherit _keymap)
                  init)
                '((name . "advice-completing-read")))
    (delete-other-windows) ; We don't want to display any other dired buffers.
    (push (dired to) buffers)
    (push (dired-other-window temporary-file-directory) buffers)
    (unwind-protect
        (let ((ok-fn
	       (lambda ()
		 (let ((win-buffers (mapcar #'window-buffer (window-list))))
		   (and (memq (car buffers) win-buffers)
			(memq (cadr buffers) win-buffers))))))
	  (dired-goto-file from)
	  ;; Right before `dired-do-copy' call, to reproduce the bug conditions,
	  ;; ensure we have windows displaying the two dired buffers.
	  (and (funcall ok-fn) (dired-do-copy))
	  ;; Call `dired-do-copy' again: this must overwrite `target'; if the bug
	  ;; still exists, then it creates `nested' instead.
	  (when (funcall ok-fn)
	    (dired-do-copy)
            (should (file-exists-p target))
            (should-not (file-exists-p nested))))
      (dolist (buf buffers)
        (when (buffer-live-p buf) (kill-buffer buf)))
      (delete-directory from 'recursive)
      (delete-directory to 'recursive)
      (advice-remove 'dired-query "advice-dired-query")
      (advice-remove 'completing-read "advice-completing-read"))))

;; (ert-deftest dired-test-bug27243 ()
;;   "Test for https://debbugs.gnu.org/27243 ."
;;   (let ((test-dir (make-temp-file "test-dir-" t))
;;         (dired-auto-revert-buffer t) buffers)
;;     (with-current-buffer (find-file-noselect test-dir)
;;       (make-directory "test-subdir"))
;;     (push (dired test-dir) buffers)
;;     (unwind-protect
;;         (let ((buf (current-buffer))
;;               (pt1 (point))
;;               (test-file (concat (file-name-as-directory "test-subdir")
;;                                  "test-file")))
;;           (write-region "Test" nil test-file nil 'silent nil 'excl)
;;           ;; Sanity check: point should now be on the subdirectory.
;;           (should (equal (dired-file-name-at-point)
;;                          (concat (file-name-as-directory test-dir)
;;                                  (file-name-as-directory "test-subdir"))))
;;           (push (dired-find-file) buffers)
;;           (let ((pt2 (point)))          ; Point is on test-file.
;;             (switch-to-buffer buf)
;;             ;; Sanity check: point should now be back on the subdirectory.
;;             (should (eq (point) pt1))
;;             ;; Case 1: https://debbugs.gnu.org/cgi/bugreport.cgi?bug=27243#5
;;             (push (dired-find-file) buffers)
;;             (should (eq (point) pt2))
;;             ;; Case 2: https://debbugs.gnu.org/cgi/bugreport.cgi?bug=27243#28
;;             (push (dired test-dir) buffers)
;;             (should (eq (point) pt1))))
;;       (dolist (buf buffers)
;;         (when (buffer-live-p buf) (kill-buffer buf)))
;;       (delete-directory test-dir t))))

(ert-deftest dired-test-bug27243-01 ()
  "Test for https://debbugs.gnu.org/cgi/bugreport.cgi?bug=27243#5 ."
  (ert-with-temp-directory test-dir
    (let* ((save-pos (lambda ()
                       (with-current-buffer (car (dired-buffers-for-dir test-dir))
                         (dired-save-positions))))
           (dired-auto-revert-buffer t) buffers)
      ;; On MS-Windows, get rid of 8+3 short names in test-dir, if the
      ;; corresponding long file names exist, otherwise such names trip
      ;; dired-buffers-for-dir.
      (if (eq system-type 'windows-nt)
          (setq test-dir (file-truename test-dir)))
      (should-not (dired-buffers-for-dir test-dir))
      (with-current-buffer (find-file-noselect test-dir)
        (make-directory "test-subdir"))
      (message "Saved pos: %S" (funcall save-pos))
      ;; Point must be at end-of-buffer.
      (with-current-buffer (car (dired-buffers-for-dir test-dir))
        (should (eobp)))
      (push (dired test-dir) buffers)
      (message "Saved pos: %S" (funcall save-pos))
      ;; Previous dired call shouldn't create a new buffer: must visit the one
      ;; created by `find-file-noselect' above.
      (should (eq 1 (length (dired-buffers-for-dir test-dir))))
      (unwind-protect
          (let ((buf (current-buffer))
                (pt1 (point))
                (test-file (concat (file-name-as-directory "test-subdir")
                                   "test-file")))
            (message "Saved pos: %S" (funcall save-pos))
            (write-region "Test" nil test-file nil 'silent nil 'excl)
            (message "Saved pos: %S" (funcall save-pos))
            ;; Sanity check: point should now be on the subdirectory.
            (should (equal (dired-file-name-at-point)
                           (concat test-dir (file-name-as-directory "test-subdir"))))
            (message "Saved pos: %S" (funcall save-pos))
            (push (dired-find-file) buffers)
            (let ((pt2 (point)))         ; Point is on test-file.
              (pop-to-buffer-same-window buf)
              ;; Sanity check: point should now be back on the subdirectory.
              (should (eq (point) pt1))
              (push (dired-find-file) buffers)
              (should (eq (point) pt2))))
        (dolist (buf buffers)
          (when (buffer-live-p buf) (kill-buffer buf)))))))

(ert-deftest dired-test-bug27243-02 ()
  "Test for https://debbugs.gnu.org/cgi/bugreport.cgi?bug=27243#28 ."
  (ert-with-temp-directory test-dir
    (let ((dired-auto-revert-buffer t)
          buffers)
      ;; On MS-Windows, get rid of 8+3 short names in test-dir, if the
      ;; corresponding long file names exist, otherwise such names trip
      ;; string comparisons below.
      (if (eq system-type 'windows-nt)
          (setq test-dir (file-truename test-dir)))
      (with-current-buffer (find-file-noselect test-dir)
        (make-directory "test-subdir"))
      (push (dired test-dir) buffers)
      (unwind-protect
          (let ((buf (current-buffer))
                (pt1 (point))
                (test-file (concat (file-name-as-directory "test-subdir")
                                   "test-file")))
            (write-region "Test" nil test-file nil 'silent nil 'excl)
            ;; Sanity check: point should now be on the subdirectory.
            (should (equal (dired-file-name-at-point)
                           (concat (file-name-as-directory test-dir)
                                   (file-name-as-directory "test-subdir"))))
            (push (dired-find-file) buffers)
            ;; Point is on test-file.
            (switch-to-buffer buf)
            ;; Sanity check: point should now be back on the subdirectory.
            (should (eq (point) pt1))
            (push (dired test-dir) buffers)
            (should (equal (dired-file-name-at-point)
                           (concat (file-name-as-directory test-dir)
                                   (file-name-as-directory "test-subdir")))))
        (dolist (buf buffers)
          (when (buffer-live-p buf) (kill-buffer buf)))))))

(ert-deftest dired-test-bug27243-03 ()
  "Test for https://debbugs.gnu.org/cgi/bugreport.cgi?bug=27243#61 ."
  (ert-with-temp-directory test-dir
    (let ((dired-auto-revert-buffer t)
          allbufs)
      (unwind-protect
          (progn
            (with-current-buffer (find-file-noselect test-dir)
              (push (current-buffer) allbufs)
              (make-directory "test-subdir1")
              (make-directory "test-subdir2")
              (let ((test-file1 "test-file1")
                    (test-file2 "test-file2"))
                (with-current-buffer (find-file-noselect "test-subdir1")
                  (push (current-buffer) allbufs)
                  (write-region "Test1" nil test-file1 nil 'silent nil 'excl))
                (with-current-buffer (find-file-noselect "test-subdir2")
                  (push (current-buffer) allbufs)
                  (write-region "Test2" nil test-file2 nil 'silent nil 'excl))))
            ;; Call find-file with a wild card and test point in each file.
            (let ((buffers (find-file (concat (file-name-as-directory test-dir)
                                              "*")
                                      t)))
              (setq allbufs (append buffers allbufs))
              (dolist (buf buffers)
                (let ((pt (with-current-buffer buf (point))))
                  (switch-to-buffer (find-file-noselect test-dir))
                  (find-file (buffer-name buf))
                  (should (equal (point) pt))))))
        (dolist (buf allbufs)
          (when (buffer-live-p buf) (kill-buffer buf)))))))

(ert-deftest dired-test-bug7131 ()
  "Test for https://debbugs.gnu.org/7131 ."
  (let* ((dir (expand-file-name "lisp" source-directory))
         (buf (dired dir)))
    (unwind-protect
        (progn
          (setq buf (dired (list dir "simple.el")))
          (dired-toggle-marks)
          (should-not (cdr (dired-get-marked-files)))
          (kill-buffer buf)
          (setq buf (dired (list dir "simple.el"))
                buf (dired dir))
          (dired-toggle-marks)
          (should (cdr (dired-get-marked-files))))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest dired-test-bug27631 ()
  "Test for https://debbugs.gnu.org/27631 ."
  ;; For dired using 'ls' emulation we test for this bug in
  ;; ls-lisp-tests.el and em-ls-tests.el.
  (skip-unless (not (or (featurep 'ls-lisp)
                        (featurep 'eshell))))
  (ert-with-temp-directory dir
    (let* ((dir1 (expand-file-name "dir1" dir))
           (dir2 (expand-file-name "dir2" dir))
           (default-directory dir)
           buf)
      (unwind-protect
          (progn
            (make-directory dir1)
            (make-directory dir2)
            (with-temp-file (expand-file-name "a.txt" dir1))
            (with-temp-file (expand-file-name "b.txt" dir2))
            (setq buf (dired (expand-file-name "dir*/*.txt" dir)))
            (dired-toggle-marks)
            (should (cdr (dired-get-marked-files))))
        (when (buffer-live-p buf) (kill-buffer buf))))))

(ert-deftest dired-test-bug27899 ()
  "Test for https://debbugs.gnu.org/27899 ."
  :tags '(:unstable)
  (dired (list (expand-file-name "src" source-directory)
               "cygw32.c" "alloc.c" "w32xfns.c" "xdisp.c"))
  (let ((orig dired-hide-details-mode))
    (dired-goto-file (expand-file-name "cygw32.c"))
    (forward-line 0)
    (unwind-protect
        (progn
          (let ((inhibit-read-only t))
            (dired-align-file (point) (point-max)))
          (dired-hide-details-mode t)
          (dired-move-to-filename)
          (should (eq 2 (current-column))))
      (dired-hide-details-mode orig))))

(ert-deftest dired-test-bug27968 ()
  "Test for https://debbugs.gnu.org/27968 ."
  (ert-with-temp-directory top-dir
    (let* ((subdir (expand-file-name "subdir" top-dir))
           (header-len-fn (lambda ()
                            (save-excursion
                              (goto-char 1)
                              (forward-line 1)
                              (- (pos-eol) (point)))))
           orig-len len diff pos line-nb)
      (make-directory subdir 'parents)
      (with-current-buffer (dired-noselect subdir)
        (setq orig-len (funcall header-len-fn)
              pos (point)
              line-nb (line-number-at-pos))
        ;; Bug arises when the header line changes its length; this may
        ;; happen if the used space has changed: for instance, with the
        ;; creation of additional files.
        (make-directory "subdir" t)
        (dired-revert)
        ;; Change the header line.
        (save-excursion
          (goto-char 1)
          (forward-line 1)
          (let ((inhibit-read-only t)
                (new-header "  test-bug27968"))
            (delete-region (point) (pos-eol))
            (when (= orig-len (length new-header))
              ;; Wow lucky guy! I must buy lottery today.
              (setq new-header (concat new-header " :-)")))
            (insert new-header)))
        (setq len (funcall header-len-fn)
              diff (- len orig-len))
        (should-not (zerop diff))    ; Header length has changed.
        ;; If diff > 0, then the point moves back.
        ;; If diff < 0, then the point moves forward.
        ;; If diff = 0, then the point doesn't move.
        ;; Sometimes this point movement causes
        ;; line-nb != (line-number-at-pos pos), so that we get
        ;; an unexpected file at point if we store buffer points.
        ;; Note that the line number before/after revert
        ;; doesn't change.
        (should (= line-nb
                   (line-number-at-pos)
                   (line-number-at-pos (+ pos diff))))
        ;; After revert, the point must be in 'subdir' line.
        (should (equal "subdir" (dired-get-filename 'local t)))))))


(ert-deftest dired-test-bug59047 ()
  "Test for https://debbugs.gnu.org/59047 ."
  (dired (list (expand-file-name "src" source-directory)
               "cygw32.c" "alloc.c" "w32xfns.c" "xdisp.c"))
  (dired-hide-all)
  (dired-hide-all)
  (dired-next-line 1)
  (should (equal 'dired-hide-details-detail
                 (get-text-property
                  (1+ (line-beginning-position)) 'invisible))))

(defmacro dired-test-with-temp-dirs (just-empty-dirs &rest body)
  "Helper macro for Bug#27940 test."
  (declare (indent 1) (debug (body)))
  (let ((dir (make-symbol "dir")))
    `(ert-with-temp-directory ,dir
       (let* ((dired-deletion-confirmer (lambda (_) "yes")) ; Suppress prompts.
              (inhibit-message t)
              (default-directory ,dir))
         (dotimes (i 5) (make-directory (format "empty-dir-%d" i)))
         (unless ,just-empty-dirs
           (dotimes (i 5) (make-directory (format "non-empty-%d/foo" i) 'parents)))
         (make-directory "zeta-empty-dir")
         (unwind-protect
             (progn
               ,@body)
           (kill-buffer (current-buffer)))))))

(ert-deftest dired-test-bug27940 ()
  "Test for https://debbugs.gnu.org/27940 ."
  ;; If just empty dirs we shouldn't be prompted.
  (dired-test-with-temp-dirs
   'just-empty-dirs
   (let (asked)
     (advice-add 'read-answer
                 :override
                 (lambda (_q _a) (setq asked t) "")
                 '((name . dired-test-bug27940-advice)))
     (dired default-directory)
     (dired-toggle-marks)
     (dired-do-delete nil)
     (unwind-protect
         (progn
           (should-not asked)
           (should-not (dired-get-marked-files))) ; All dirs deleted.
       (advice-remove 'read-answer 'dired-test-bug27940-advice))))
  ;; Answer yes
  (dired-test-with-temp-dirs
   nil
   (advice-add 'read-answer :override (lambda (_q _a) "yes")
               '((name . dired-test-bug27940-advice)))
   (dired default-directory)
   (dired-toggle-marks)
   (dired-do-delete nil)
   (unwind-protect
       (should-not (dired-get-marked-files)) ; All dirs deleted.
     (advice-remove 'read-answer 'dired-test-bug27940-advice)))
  ;; Answer no
  (dired-test-with-temp-dirs
   nil
   (advice-add 'read-answer :override (lambda (_q _a) "no")
               '((name . dired-test-bug27940-advice)))
   (dired default-directory)
   (dired-toggle-marks)
   (dired-do-delete nil)
   (unwind-protect
       (should (= 5 (length (dired-get-marked-files)))) ; Just the empty dirs deleted.
     (advice-remove 'read-answer 'dired-test-bug27940-advice)))
  ;; Answer all
  (dired-test-with-temp-dirs
   nil
   (advice-add 'read-answer :override (lambda (_q _a) "all")
               '((name . dired-test-bug27940-advice)))
   (dired default-directory)
   (dired-toggle-marks)
   (dired-do-delete nil)
   (unwind-protect
       (should-not (dired-get-marked-files)) ; All dirs deleted.
     (advice-remove 'read-answer 'dired-test-bug27940-advice)))
  ;; Answer quit
  (dired-test-with-temp-dirs
   nil
   (advice-add 'read-answer :override (lambda (_q _a) "quit")
               '((name . dired-test-bug27940-advice)))
   (dired default-directory)
   (dired-toggle-marks)
   (let ((inhibit-message t))
     (dired-do-delete nil))
   (unwind-protect
       (should (= 6 (length (dired-get-marked-files)))) ; All empty dirs but zeta-empty-dir deleted.
     (advice-remove 'read-answer 'dired-test-bug27940-advice))))

(ert-deftest dired-test-directory-files ()
  "Test for `directory-files'."
  (let ((testdir (expand-file-name
                  "directory-files-test" (temporary-file-directory)))
        (nod directory-files-no-dot-files-regexp))
    (unwind-protect
        (progn
          (when (file-directory-p testdir)
            (delete-directory testdir t))

          (make-directory testdir)
          (when (file-directory-p testdir)
            ;; directory-empty-p: test non-existent dir
            (should-not (directory-empty-p "some-imaginary-dir"))
            (should (= 2 (length (directory-files testdir))))
            ;; directory-empty-p: test empty dir
            (should (directory-empty-p testdir))
            (should-not (directory-files testdir nil nod t 1))
            (dolist (file '(a b c d))
              (make-empty-file (expand-file-name (symbol-name file) testdir)))
            (should (= 6 (length (directory-files testdir))))
            (should (equal "abcd" (mapconcat #'identity (directory-files
                                                         testdir nil nod))))
            (should (= 2 (length (directory-files testdir nil "[bc]"))))
            (should (= 3 (length (directory-files testdir nil nod nil 3))))
            (dolist (file '(5 4 3 2 1))
              (make-empty-file
               (expand-file-name (number-to-string file) testdir)))
            ;;(should (= 0 (length (directory-files testdir nil "[0-9]" t -1))))
            (should (= 5 (length (directory-files testdir nil "[0-9]" t))))
            (should (= 5 (length (directory-files testdir nil "[0-9]" t 50))))
            (should-not (directory-empty-p testdir))))

      (delete-directory testdir t))))

(ert-deftest dired-test-directory-files-and-attributes ()
  "Test for `directory-files-and-attributes'."
  (let ((testdir (expand-file-name
                  "directory-files-test" (temporary-file-directory)))
        (nod directory-files-no-dot-files-regexp))

    (unwind-protect
        (progn
          (when (file-directory-p testdir)
            (delete-directory testdir t))

          (make-directory testdir)
          (when (file-directory-p testdir)
            (should (= 2 (length (directory-files testdir))))
            (should-not (directory-files-and-attributes testdir t nod t 1))
            (dolist (file '(a b c d))
              (make-directory (expand-file-name (symbol-name file) testdir)))
            (should (= 6 (length (directory-files-and-attributes testdir))))
            (dolist (dir (directory-files-and-attributes testdir t nod))
              (should (file-directory-p (car dir)))
              (should-not (file-regular-p (car dir))))
            (should (= 2 (length
                          (directory-files-and-attributes testdir nil "[bc]"))))
            (should (= 3 (length
                          (directory-files-and-attributes
                           testdir nil nod nil nil 3))))
            (dolist (file '(5 4 3 2 1))
              (make-empty-file
               (expand-file-name (number-to-string file) testdir)))
            ;; (should (= 0 (length (directory-files-and-attributes testdir nil
            ;;                                                      "[0-9]" t
            ;;                                                      nil -1))))
            (should (= 5 (length
                          (directory-files-and-attributes
                           testdir nil "[0-9]" t))))
            (should (= 5 (length
                          (directory-files-and-attributes
                           testdir nil "[0-9]" t nil 50))))))
      (when (file-directory-p testdir)
        (delete-directory testdir t)))))

(ert-deftest dired-test-hide-absolute-location-enabled ()
  "Test for https://debbugs.gnu.org/72272 ."
  (let* ((dired-hide-details-hide-absolute-location t)
         (dir-name (expand-file-name "lisp" source-directory))
         (buffer (prog1 (dired (list dir-name "dired.el" "play"))
                   (dired-insert-subdir (file-name-concat default-directory
                                                          "play")))))
    (unwind-protect
        (progn
          (goto-char (point-min))
          (re-search-forward dired-subdir-regexp)
          (goto-char (match-beginning 1))
          (should (equal "lisp" (file-name-nondirectory
                                 (directory-file-name (dired-get-subdir)))))
          (should (equal 'dired-hide-details-absolute-location
                         (get-text-property (match-beginning 1) 'invisible)))
          (re-search-forward dired-subdir-regexp)
          (goto-char (match-beginning 1))
          (should (equal "play" (file-name-nondirectory
                                 (directory-file-name (dired-get-subdir)))))
          (should (equal 'dired-hide-details-absolute-location
                         (get-text-property (match-beginning 1) 'invisible))))
      (kill-buffer buffer))))

(ert-deftest dired-test-hide-absolute-location-disabled ()
  "Test for https://debbugs.gnu.org/72272 ."
  (let* ((dired-hide-details-hide-absolute-location nil)
         (dir-name (expand-file-name "lisp" source-directory))
         (buffer (prog1 (dired (list dir-name "dired.el" "play"))
                   (dired-insert-subdir (file-name-concat default-directory
                                                          "play")))))
    (unwind-protect
        (progn
          (goto-char (point-min))
          (re-search-forward dired-subdir-regexp)
          (goto-char (match-beginning 1))
          (should (equal "lisp" (file-name-nondirectory
                                 (directory-file-name (dired-get-subdir)))))
          (should-not (get-text-property (match-beginning 1) 'invisible))
          (re-search-forward dired-subdir-regexp)
          (goto-char (match-beginning 1))
          (should (equal "play" (file-name-nondirectory
                                 (directory-file-name (dired-get-subdir)))))
          (should-not (get-text-property (match-beginning 1) 'invisible)))
      (kill-buffer buffer))))

;; `dired-insert-directory' output tests.
(let* ((data-dir "insert-directory")
       (test-dir (file-name-as-directory
                  (ert-resource-file
                   (concat data-dir "/test_dir"))))
       (test-dir-other (file-name-as-directory
                        (ert-resource-file
                         (concat data-dir "/test_dir_other"))))
       (test-files `(,test-dir "foo" "bar")) ;expected files to be found
       ;; Free space test data for `insert-directory'.
       ;; Meaning: (path free-space-bytes-to-stub expected-free-space-string)
       (free-data `((,test-dir 10 "available 10 B")
                    (,test-dir-other 100 "available 100 B")
                    (:default 999 "available 999 B"))))

  (defun files-tests--look-up-free-data (path)
    "Look up free space test data, with a default for unspecified paths."
    (let ((path (file-name-as-directory path)))
      (cdr (or (assoc path free-data)
               (assoc :default free-data)))))

  (defun files-tests--make-file-system-info-stub (&optional static-path)
    "Return a stub for `file-system-info' using dynamic or static test data.
If that data should be static, pass STATIC-PATH to choose which
path's data to use."
    (lambda (path)
      (let* ((path (cond (static-path)
                         ;; file-system-info knows how to handle ".", so we
                         ;; do the same thing
                         ((equal "." path) default-directory)
                         (path)))
             (return-size
              ;; It is always defined but this silences the byte-compiler:
              (when (fboundp 'files-tests--look-up-free-data)
                (car (files-tests--look-up-free-data path)))))
        (list return-size return-size return-size))))

  (defun files-tests--insert-directory-output (dir &optional _verbose)
    "Run `insert-directory' and return its output."
    (with-current-buffer-window "files-tests--insert-directory" nil nil
      (let ((dired-free-space 'separate))
        (dired-insert-directory dir "-l" nil nil t))
      (buffer-substring-no-properties (point-min) (point-max))))

  (ert-deftest files-tests-insert-directory-shows-files ()
    "Verify `insert-directory' reports the files in the directory."
    ;; It is always defined but this silences the byte-compiler:
    (when (fboundp 'files-tests--insert-directory-output)
      (let* ((test-dir (car test-files))
             (files (cdr test-files))
             (output (files-tests--insert-directory-output test-dir)))
        (dolist (file files)
          (should (string-match-p file output))))))

  (defun files-tests--insert-directory-shows-given-free (dir &optional
                                                             info-func)
    "Run `insert-directory' and verify it reports the correct available space.
Stub `file-system-info' to ensure the available space is consistent,
either with the given stub function or a default one using test data."
    ;; It is always defined but this silences the byte-compiler:
    (when (and (fboundp 'files-tests--make-file-system-info-stub)
               (fboundp 'files-tests--look-up-free-data)
               (fboundp 'files-tests--insert-directory-output))
      (cl-letf (((symbol-function 'file-system-info)
                 (or info-func
                     (files-tests--make-file-system-info-stub))))
        (should (string-match-p (cadr
                                 (files-tests--look-up-free-data dir))
                                (files-tests--insert-directory-output dir t))))))

  (ert-deftest files-tests-insert-directory-shows-free ()
    "Test that verbose `insert-directory' shows the correct available space."
    ;; It is always defined but this silences the byte-compiler:
    (when (and (fboundp 'files-tests--insert-directory-shows-given-free)
               (fboundp 'files-tests--make-file-system-info-stub))
      (files-tests--insert-directory-shows-given-free
       test-dir
       (files-tests--make-file-system-info-stub test-dir))))

  (ert-deftest files-tests-bug-50630 ()
    "Verify verbose `insert-directory' shows free space of the target directory.
The current directory at call time should not affect the result (Bug#50630)."
    ;; It is always defined but this silences the byte-compiler:
    (when (fboundp 'files-tests--insert-directory-shows-given-free)
      (let ((default-directory test-dir-other))
        (files-tests--insert-directory-shows-given-free test-dir)))))

(provide 'dired-tests)
;;; dired-tests.el ends here
