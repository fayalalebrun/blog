;; Set the package installation directory so that packages aren't stored in the
;; ~/.emacs.d/elpa path.
(require 'cl-lib)
(require 'org)
(require 'ox-publish)
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
(package-install 'ox-rss)

;; Load the publishing system
(require 'ox-rss)

;; Disable timestamp caching (needed for sandboxed builds like nix)
(setq org-publish-use-timestamps-flag nil)
(setq org-publish-timestamp-directory (expand-file-name "./.org-timestamps/"))

;; Customize the HTML output
(setq org-html-validation-link nil            ;; Don't show validation link
      org-html-head-include-scripts nil       ;; Use our own scripts
      org-html-head-include-default-style nil  ;; Use our own styles
      org-html-metadata-timestamp-format "%Y-%m-%d")

(setq org-export-date-timestamp-format "%Y-%m-%d")

(defun getenv-default (name fallback)
  (let ((value (getenv name)))
    (if (and value (not (string-empty-p value))) value fallback)))

(defun ensure-trailing-slash (value)
  (if (string-suffix-p "/" value) value (concat value "/")))

(defconst site-url
  (ensure-trailing-slash (getenv-default "SITE_URL" "https://noquiche.fyi")))

(defconst site-title
  (getenv-default "SITE_TITLE" "Blog"))

(defconst site-description
  (getenv-default "SITE_DESCRIPTION" "Posts from the blog."))

(defconst site-author
  (getenv-default "SITE_AUTHOR" site-title))

(defconst site-email
  (getenv-default "SITE_EMAIL" "noreply@example.com"))

(defun content-file-to-url (file)
  (concat site-url
          (file-name-sans-extension
           (file-relative-name file (expand-file-name "./content")))
          ".html"))

(defun org-file-keyword (keyword)
  (car (cdr (assoc-string keyword (org-collect-keywords (list keyword)) t))))

(defun fallback-post-title (file)
  (mapconcat (lambda (word)
               (if (<= (length word) 3)
                   (upcase word)
                 (capitalize word)))
             (split-string (file-name-base file) "[-_]" t)
             " "))

(defun summary-candidate-p (text)
  (let ((plain-text (replace-regexp-in-string
                     "\\[\\[[^]]+\\]\\[\\([^]]+\\)\\]\\]"
                     "\\1"
                     text)))
    (and (> (length plain-text) 40)
         (not (string-prefix-p "[[" text))
         (not (string-prefix-p "#+" text))
         (not (string-prefix-p "IMAGE " plain-text))
         (not (string-prefix-p "SCREENSHOT:" plain-text))
         (not (string-prefix-p "Play " plain-text)))))

(defun extract-post-summary ()
  (let ((ast (org-element-parse-buffer)))
    (catch 'summary
      (org-element-map ast 'paragraph
        (lambda (paragraph)
          (let ((text (string-trim
                       (buffer-substring-no-properties
                        (org-element-property :begin paragraph)
                        (org-element-property :end paragraph)))))
            (when (summary-candidate-p text)
              (throw 'summary text)))))
      "Read the full post.")))

(defun collect-post-metadata (file)
  (with-temp-buffer
    (insert-file-contents file)
    (org-mode)
    (let* ((title (or (org-file-keyword "TITLE")
                      (fallback-post-title file)))
           (date (or (org-file-keyword "DATE")
                     (format-time-string
                      "<%Y-%m-%d>"
                      (file-attribute-modification-time (file-attributes file)))))
           (summary (extract-post-summary)))
      (list :file file
            :title title
            :date date
            :summary summary
            :url (content-file-to-url file)
            :time (org-time-string-to-time date)))))

(defun content-org-file-p (file)
  (let ((name (file-name-nondirectory file)))
    (and (string-suffix-p ".org" name)
         (not (string-prefix-p "." name))
         (not (string-prefix-p ".#" name)))))

(defun format-feed-entry (post)
  (format (concat "* %s\n"
                  ":PROPERTIES:\n"
                  ":PUBDATE: %s\n"
                  ":RSS_PERMALINK: %s\n"
                  ":END:\n\n"
                  "%s\n\n"
                  "[[%s][Read the full post]]\n")
          (plist-get post :title)
          (plist-get post :date)
          (substring (plist-get post :url) (length site-url))
          (plist-get post :summary)
          (plist-get post :url)))

(defun generate-rss-source-file ()
  (let* ((content-directory (expand-file-name "./content"))
         (generated-directory (expand-file-name "./.generated"))
         (feed-source (expand-file-name "feed.org" generated-directory))
         (posts (sort
                 (mapcar #'collect-post-metadata
                         (cl-remove-if
                          (lambda (file)
                            (or (member (file-name-nondirectory file)
                                        '("index.org"))
                                (not (content-org-file-p file))))
                          (directory-files-recursively content-directory "\\.org$")))
                 (lambda (left right)
                   (time-less-p (plist-get right :time)
                                (plist-get left :time))))))
    (make-directory generated-directory t)
    (with-temp-file feed-source
      (insert (format "#+TITLE: %s\n" site-title))
      (insert (format "#+DESCRIPTION: %s\n" site-description))
      (insert (format "#+HTML_LINK_HOME: %s\n" site-url))
      (insert (format "#+RSS_FEED_URL: %sfeed.xml\n" site-url))
      (insert "#+OPTIONS: toc:nil num:nil\n\n")
      (dolist (post posts)
        (insert (format-feed-entry post))
        (insert "\n")))))


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
             :exclude "^\\.|/\\."
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
	)
       (list "org-site:rss"
	     :base-directory "./.generated"
	     :base-extension "org"
	     :publishing-directory "./public"
	     :publishing-function 'org-rss-publish-to-rss
	     :exclude ".*"
	     :include '("feed.org")
	     :html-link-home site-url
	     :html-link-use-abs-url t
	     :rss-feed-url (concat site-url "feed.xml")
	     :rss-extension "xml"
	     :with-author t
	     :author site-author
	     :email site-email
	     :section-numbers nil
	     :table-of-contents nil
	     :time-stamp-file nil
	)))

;; Generate the site output
(generate-rss-source-file)
(org-publish-all t)

(message "Build complete!")
