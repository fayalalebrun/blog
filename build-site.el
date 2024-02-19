;; Set the package installation directory so that packages aren't stored in the
;; ~/.emacs.d/elpa path.
(require 'package)
(setq package-user-dir (expand-file-name "./.packages"))
(setq package-archives '(("melpa" . "https://melpa.org/packages/")
                         ("elpa" . "https://elpa.gnu.org/packages/")))

;; Initialize the package system
(package-initialize)
(unless package-archive-contents
  (package-refresh-contents))

;; Install dependencies
(package-install 'htmlize)

;; Load the publishing system
(require 'ox-publish)

;; Customize the HTML output
(setq org-html-validation-link nil            ;; Don't show validation link
      org-html-head-include-scripts nil       ;; Use our own scripts
      org-html-head-include-default-style nil ;; Use our own styles
      org-html-head "<link rel=\"stylesheet\" href=\"https://cdn.simplecss.org/simple.min.css\" />")


(defun sitemap-entry (entry style project)
  (cond ((not (directory-name-p entry))
	 (format "%s [[file:%s][%s]]"
		 (format-time-string "%Y-%m-%d" (org-publish-find-date entry project))
		 entry
		 (org-publish-find-title entry project)
		 ))
	((eq style 'tree)
	 ;; Return only last subdir.
	 (file-name-nondirectory (directory-file-name entry)))
	(t entry)))

(defun file-to-string (file)
  "File to string function"
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))

;; Define the publishing project
(setq org-publish-project-alist
      (list
       (list "org-site:main"
             :recursive t
             :base-directory "./content"
             :publishing-function 'org-html-publish-to-html
             :publishing-directory "./public"
             :with-author nil
	     :with-date t
             :with-creator t
             :with-toc t
             :section-numbers nil
             :time-stamp-file nil
	     :auto-sitemap t
	     :sitemap-title ""
	     :sitemap-format-entry 'sitemap-entry
	     :sitemap-sort-files 'anti-chronologically
	     :sitemap-filename     "index.org"
	     :html-preamble (file-to-string "preamble.html")
	     :html-head (file-to-string "header.html")
	     )
       (list "org-site:assets"
	     :base-directory "./content/assets"
	     :base-extension "png\\|jpg\\|svg\\|css"
	     :publishing-directory "./public/assets"
	     :publishing-function 'org-publish-attachment
	)))

;; Generate the site output
(org-publish-all t)

(message "Build complete!")
