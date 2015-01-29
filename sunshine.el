;;; sunshine.el --- Provide weather and forecast information.

;; Author: Aaron Bieber

;; Version 0.1

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;; 1) Copy this file somewhere in your Emacs `load-path'.  To see what
;;    your `load-path' is, run inside emacs: C-h v load-path<RET>
;;
;; 2) Add the following to your .emacs file:
;;
;;    (require 'sunshine)
;;
;; 3) Configure your location by setting the variable
;;    `sunshine-location'.  You can provide a string, like "New York,
;;    NY" or a ZIP code, like "90210".  This variable is available
;;    through the Customize facility.
;;
;; To display the forecast for your location, call
;; `sunshine-forecast'.
;;
;; If you are using a GUI Emacs, you may like to display the weather
;; forecast icons automatically. To do so, set `sunshine-show-icons'
;; to t.

;;; Open issues:

;; * Try to resize windows more politely (fit-window-to-buffer expands
;;   the window below; it should try to shrink it to compensate,
;;   maybe). Magit seems to handle this well.

;;; Code:

(require 'cl-macs)
(require 'url)
(require 'url-cache)
(require 'time-date)
(require 'json)

;;; Options available for customization.
(defgroup sunshine nil
  "A utility for viewing your local weather forecast."
  :group 'tools)
  
(defcustom sunshine-buffer-name "*Sunshine*"
  "Name for the Sunshine buffer.  You probably don't need to change this."
  :group 'sunshine
  :type 'string)

(defcustom sunshine-mode-hook nil
  "Hook to run upon entering `sunshine-mode'.
See `run-hooks'."
  :group 'sunshine
  :type 'hook)

(defcustom sunshine-location "New York, NY"
  "The default location for which to retrieve weather.
The location value should be a city/state value like \"New York, NY\""
  :group 'sunshine
  :type 'string)

(defcustom sunshine-units 'imperial
  "The unit type to use for measurements."
  :group 'sunshine
  :type '(radio (const :tag "Metric (C)" metric)
                (const :tag "Imperial (F)" imperial)))

(defcustom sunshine-cache-ttl (seconds-to-time 900)
  "How long to keep forecast data cached; sorry, it is a time value.
The default value is 15 minutes (900 seconds)."
  :group 'sunshine
  :type '(repeat integer))

(defcustom sunshine-icon-cache-ttl (days-to-time 1)
  "How long to keep icon data cached; sorry, it is a time value.
The default value is one day (86400 seconds)."
  :group 'sunshine
  :type '(repeat integer))

(defcustom sunshine-show-icons nil
  "Whether to display icons in the forecast."
  :group 'sunshine
  :type 'boolean)

(defvar sunshine-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "q" 'sunshine-quit)
    (define-key map "i" 'sunshine-toggle-icons)
    map)
  "Get the keymap for the Sunshine window.")

;;; INTERACTIVE FUNCTIONS (COMMANDS):

(define-derived-mode sunshine-mode nil "Sunshine"
  "A major mode for the Sunshine window.

The following keys are available in `sunshine-mode':

  \\{sunshine-mode-map}"
  (setq truncate-lines t))

(defun sunshine-forecast ()
  "The main entry into Sunshine; display the forecast in a window."
  (interactive)
  (sunshine-prepare-window)
  (sunshine-get-forecast sunshine-location sunshine-units 'full))

(defun sunshine-quick-forecast ()
  "Display a quick forecast in the minibuffer."
  (interactive)
  (sunshine-get-forecast sunshine-location sunshine-units 'quick))

(defun sunshine-quit ()
  "Destroy the Sunshine buffer."
  (interactive)
  (kill-buffer (get-buffer sunshine-buffer-name)))

(defun sunshine-toggle-icons ()
  "Turn Sunshine icons on or off."
  (interactive)
  (progn
    (setq sunshine-show-icons (not sunshine-show-icons))
    (sunshine-forecast)))

;;; INTERNAL FUNCTIONS:

(defun sunshine-make-url (location units)
  "Make a URL for retrieving the weather for LOCATION in UNITS."
  (concat "http://api.openweathermap.org/data/2.5/forecast/daily?q="
                      (url-encode-url location)
                      "&mode=json&units="
                      (url-encode-url (symbol-name units))
                      "&cnt=5"))

(defun sunshine-get-forecast (location units display-type)
  "Get forecast data from OpenWeatherMap's API.
Provide a LOCATION and optionally the preferred unit of measurement as
UNITS (e.g. 'metric' or 'imperial').
DISPLAY-TYPE determines whether a full or quick forecast is shown.
Its value may be 'full or 'quick."
  (let* ((url (sunshine-make-url location units)))
    (if (sunshine-forecast-cache-expired url)
        (url-retrieve url 'sunshine-retrieved (list display-type))
      ;; Cache is not expired; pull out the cached data.
      (with-temp-buffer
        (mm-disable-multibyte)
        (url-cache-extract (url-cache-create-filename url))
        ;; Use a fake status value; we don't use it anyway.
        (sunshine-retrieved "status" display-type)))))

(defun sunshine-retrieved (status display-type)
  "Process the retrieved data; receives STATUS, which we discard.
DISPLAY-TYPE defines the type of display that will be shown."
  (let ((buf (get-buffer-create sunshine-buffer-name))
        (forecast (sunshine-extract-response)))
    (if forecast
        (let ((simple-forecast (sunshine-build-simple-forecast forecast)))
          (cond ((equal display-type 'full)
                 (progn
                   (with-current-buffer buf
                     (progn
                       (sunshine-draw-forecast simple-forecast)
                       (fit-window-to-buffer (get-buffer-window buf))
                       (select-window (get-buffer-window sunshine-buffer-name)))))))
          (cond ((equal display-type 'quick)
                 (sunshine-draw-quick-forecast simple-forecast))))
      (sunshine-display-error))))

(defun sunshine-extract-response ()
  "Extract the JSON response from the buffer returned by url-http."
  (progn
    (if (re-search-forward "^HTTP/.+ 200 OK$" (line-end-position) t)
        (when (search-forward "\n\n" nil t)
          (prog1 (json-read)
            (url-store-in-cache (current-buffer))
            (kill-buffer)
            ))
      (kill-buffer))))

(defun sunshine-display-error ()
  "Display an error in the Sunshine window."
  (let ((quit-key (key-description (where-is-internal 'sunshine-quit sunshine-mode-map t))))
    (with-current-buffer sunshine-buffer-name
      (progn
        (setq buffer-read-only nil)
        (erase-buffer)
        (insert (propertize "\u26A0\n" 'font-lock-face '(:foreground "gold" :height 3.0))
                "There was an error retrieving weather data.\n"
                "Please try again in a while; this response was not cached.\n\n"
                "  Press " quit-key " to quit.")
        (setq buffer-read-only t)
        (select-window (get-buffer-window (current-buffer)))
        (goto-char 3)))))

(defun sunshine-get-cached-time (&optional format)
  "Return the last modified time of the Sunshine cache, if it exists.
If provided, FORMAT is used as an argument to `format-time-string'.
If omitted, or nil, a date object is returned."
  (let ((cache-time (url-is-cached (sunshine-make-url sunshine-location sunshine-units))))
    (if format
        (format-time-string format cache-time)
      cache-time)))

(defun sunshine-forecast-cache-expired (url)
  "Return t if the forecast cache for URL is expired."
  (sunshine-cache-expired url sunshine-cache-ttl))

(defun sunshine-icon-cache-expired (url)
  "Return t if the icon cache for URL is expired."
  (sunshine-cache-expired url sunshine-icon-cache-ttl))

(defun sunshine-cache-expired (url ttl)
  "Return t if the cache for URL is older than TTL."
  (cond (url-standalone-mode
         (not (file-exists-p (url-cache-create-filename url))))
        (t (let ((cache-time (url-is-cached url)))
             (if cache-time
                 (time-less-p
                  (time-add
                   cache-time
                   ttl)
                  (current-time))
               t)))))

(defun sunshine-build-simple-forecast (forecast)
  "Build a simple, legible forecast from FORECAST.
FORECAST is the raw forecast data resulting from calling json-read on the
forecast results."
  (let* ((citylist (cdr (assoc 'city forecast)))
         (city (cdr (assoc 'name citylist)))
         (country (cdr (assoc 'country citylist)))
         (temp-symbol (sunshine-units-symbol)))
    (list
     (cons 'location (concat city ", " country))
     (cons 'days (cl-loop for day across (cdr (assoc 'list forecast)) collect
                         (list
                          (cons 'date (format-time-string "%A, %h. %e" (seconds-to-time (cdr (assoc 'dt day)))))
                          (cons 'desc (cdr (assoc 'main (elt (cdr (assoc 'weather day)) 0))))
                          (cons 'icon (cdr (assoc 'icon (elt (cdr (assoc 'weather day)) 0))))
                          (cons 'temp
                                (list
                                 (cons 'min (format "%s %s" (cdr (assoc 'min (cdr (assoc 'temp day)))) temp-symbol))
                                 (cons 'max (format "%s %s" (cdr (assoc 'max (cdr (assoc 'temp day)))) temp-symbol))))
                          (cons 'pressure (cdr (assoc 'pressure day)))))))))

(defun sunshine-prepare-window ()
  "Create the window and buffer used to display the forecast."
  (let* ((buf (get-buffer-create sunshine-buffer-name))
         (win (or (get-buffer-window sunshine-buffer-name)
                  (split-window-vertically))))
    (set-window-buffer win buf)
    ;; Start the window rather short so it doesn't jarringly change
    ;; size after the download.
    (window-resize win (- 10 (window-total-height win)))
    (with-current-buffer buf
      (setq buffer-read-only nil)
      (erase-buffer)
      (kill-all-local-variables)
      (set-window-dedicated-p (get-buffer-window buf) t)
      (sunshine-mode)
      (insert "Loading...")
      (setq buffer-read-only t))))

(defun sunshine-pivot-forecast-rows (forecast)
  "Pivot FORECAST rows of days into rows of elements from each day.
This puts the elements in display order.

Given a forecast dataset like:

  (((date . date1)
    (high . high1)
    (low  . low1))
   ((date . date2)
    (high . high2)
    (low  . low2)))

Pivot it into a dataset like:

  ((dates . (date1 date2))
   (highs . (high1 high2))
   (lows  . (low1 low2)))"
  (let ((days (cdr (assoc 'days forecast))))
    (cl-loop for day in days
             collect (cdr (assoc 'date day)) into dates
             collect (cdr (assoc 'icon day)) into icons
             collect (cdr (assoc 'desc day)) into descs
             collect (format "High: %s" (cdr (assoc 'max (cdr (assoc 'temp day))))) into highs
             collect (format "Low:  %s" (cdr (assoc 'min (cdr (assoc 'temp day))))) into lows
             ;; This new list now contains one list for each
             ;; screen line.
             finally (return (list
                              (cons "icons" icons)
                              (cons "dates" dates)
                              (cons "descs" descs)
                              (cons "highs" highs)
                              (cons "lows" lows))))))

(defun sunshine-draw-forecast (forecast)
  "Draw FORECAST in pretty ASCII."
  (let* ((cached (sunshine-get-cached-time "%b. %e at %l:%M %p"))
         (location (cdr (assoc 'location forecast)))
         (output-rows (sunshine-pivot-forecast-rows forecast)))
    (setq buffer-read-only nil)
    (erase-buffer)
    (insert (concat " "
                    ;; Heading, in tall text.
                    (propertize (concat "Forecast for " location)
                                    'font-lock-face '(:foreground "navajo white" :height 1.5))
                    ;; Newline, providing extra space below.
                    (propertize "\n" 'line-spacing .5)))
    (while output-rows
      (let* ((wholerow (car output-rows))
             (type (car wholerow))
             (row (cdr wholerow))
             (col 1))
        (while row
          (if (or sunshine-show-icons
                  (not (equal type "icons")))
              (insert (sunshine-pad-or-trunc (sunshine-row-type-propertize (car row) type col) 20 1)
                      (if (and (/= 1 (length row))
                               (not (equal type "icons")))
                          (propertize "\u2502" 'font-lock-face '(:foreground "gray50"))
                        " ")))
          (setq col (1+ col))
          (setq row (cdr row)))
        (insert (sunshine-newline-propertize type))
        (setq output-rows (cdr output-rows))))
    (insert (concat " Last updated " cached
                    (propertize "\n"
                                'line-height 1.5)))
    (goto-char 0)
    (setq buffer-read-only t)
    (if sunshine-show-icons
        (sunshine-get-icons))))

(defun sunshine-draw-quick-forecast (forecast)
  "Draw a quick FORECAST in the minibuffer."
  (let* ((cached (sunshine-get-cached-time "%b. %e at %l:%M %p"))
         (location (cdr (assoc 'location forecast)))
         (output-rows (sunshine-pivot-forecast-rows forecast))
         
         )
    (message (concat
      "Forecast for " location " (updated " cached ")\n\n"
      ;; Dates
      (propertize (sunshine-pad-or-trunc (cadr (assoc "dates" output-rows)) 20)
                  'face '(:weight bold))
      (propertize (sunshine-pad-or-trunc (caddr (assoc "dates" output-rows)) 20)
                  'face '(:weight bold)) "\n"
      ;; Conditions
      (sunshine-pad-or-trunc (cadr (assoc "descs" output-rows)) 20)
      (sunshine-pad-or-trunc (caddr (assoc "descs" output-rows)) 20) "\n"
      ;; Highs
      (sunshine-pad-or-trunc (cadr (assoc "highs" output-rows)) 20)
      (sunshine-pad-or-trunc (caddr (assoc "highs" output-rows)) 20) "\n"
      ;; Lows
      (sunshine-pad-or-trunc (cadr (assoc "lows" output-rows)) 20)
      (sunshine-pad-or-trunc (caddr (assoc "lows" output-rows)) 20) "\n"
      ))))

(defun sunshine-seek-to-icon-marker (number)
  "Move point to the location of the icon marker for icon NUMBER."
  (let ((icon-point (text-property-any (point-min) (point-max) 'icon number)))
    (when icon-point
      (goto-char icon-point))))

(defun sunshine-get-icons ()
  "Trigger downloads of any weather icons in the buffer."
  (cl-loop for col from 1 upto 5 do
           (let* ((icon-point (sunshine-seek-to-icon-marker col))
                  (icon-code (if icon-point
                           (save-excursion
                             (progn (goto-char icon-point)
                                    (thing-at-point 'word)))))
                  (icon-url (if icon-code
                                (sunshine-make-icon-url icon-code))))
             (when (and icon-point icon-url)
               (goto-char icon-point)
               (if (sunshine-icon-cache-expired icon-url)
                   ;; Live download.
                   (url-retrieve icon-url 'sunshine-icon-retrieved (list col))
                 ;; Use cache.
                 (with-temp-buffer
                   (mm-disable-multibyte)
                   (url-cache-extract (url-cache-create-filename icon-url))
                   (sunshine-icon-retrieved "status" (list col))))))))

(defun sunshine-extract-icon ()
  "Extract icon image data from the current buffer.
Expected to be used by the callback from `url-retrieve'."
  (create-image
   (save-excursion
     (goto-char (point-min))
     (when (re-search-forward "^HTTP/.+ 200 OK$" nil (line-end-position))
       (when (search-forward "\n\n" nil t)
         (buffer-substring (point) (point-max)))))
   'png t))

(defun sunshine-icon-retrieved (status number)
  "Callback from `url-retrieve' that places icon NUMBER into the buffer."
  (let ((image-desc (sunshine-extract-icon)))
    (if image-desc
        (progn
          (url-store-in-cache (current-buffer))
          (with-current-buffer sunshine-buffer-name
            (sunshine-seek-to-icon-marker number)
            (setq buffer-read-only nil)
            ;; Make room!
            (delete-region (point) (+ (round (car (image-size image-desc))) (point)))
            (insert-image image-desc)
            (setq buffer-read-only t)
            (fit-window-to-buffer)
            (goto-char 0))))))

(defun sunshine-make-icon-url (icon-name)
  "Make the URL pointing to the icon file for ICON-NAME."
  (concat "http://openweathermap.org/img/w/" (url-encode-url icon-name) ".png"))

(defun sunshine-newline-propertize (type)
  "Output a newline appropriate for a line of TYPE."
  (if (equal type "icons")
      (if sunshine-show-icons
        (propertize "\n"
                    'line-spacing .5)
        "")
    "\n"))

(defun sunshine-row-type-propertize (string type col)
  "Return STRING with face properties appropriate for TYPE in column COL."
  (or (cond ((equal type "dates") (propertize
                                   string
                                   'font-lock-face
                                   '(:weight ultra-bold :foreground "white")))
            ((equal type "descs") string)
            ((equal type "highs") string)
            ((equal type "lows") string)
            ((equal type "icons") (propertize
                                   string
                                   'icon col)))
      string))

(defun sunshine-pad-or-trunc (string column-width &optional pad trunc-string)
  "Pad or truncate STRING to fit in COLUMN-WIDTH.
Optionally, add PAD spaces before and after STRING, and if STRING exceeds the
available width, truncate it to fit, optionally appending TRUNC-STRING."
  (let* ((actual-width (- column-width (if pad (* pad 2) 0)))
         (display-string (if (> (length string) actual-width)
                             ;; If string exceeds size, truncate.
                             (concat (substring string 0 (- actual-width (if trunc-string (length trunc-string) 0))) trunc-string)
                           ;; Otherwise, pad.
                           (concat string (make-string (- actual-width (length string)) ? )))))
    (concat (if pad (make-string pad ? ))
            display-string
            (if pad (make-string pad ? )))))

(defun sunshine-units-symbol ()
  "Return the symbol appropriate for the current value of sunshine-units."
  (cond ((equal sunshine-units 'imperial) "F")
        ((equal sunshine-units 'metric) "C")))

(provide 'sunshine)
;;; sunshine.el ends here
