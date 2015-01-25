# sunshine.el

An Emacs package for displaying the forecast from OpenWeatherMap.

## Installation and Configuration

1. Copy this file somewhere in your Emacs `load-path`.  To see what your
   `load-path` is, run inside emacs: `C-h v load-path<RET>`.

2. Add the following to your .emacs file:

   `(require 'sunshine)`

3. Configure your location by setting the variable `sunshine-location`.  You can
   provide a string, like "New York, NY" or a ZIP code, like "90210".  This
   variable is available through the Customize facility.

A few other configuration options are available, see the configuration group
called `sunshine`.

## Usage

To display the forecast for your location, call `sunshine-forecast'.

Two key mappings are available within the forecast window:

* `q` - Kill the Sunshine buffer and close the window.
* `i` - Toggle the display of forecast icons (only available in GUI Emacs, of
        course)

If you are using a GUI Emacs, you may like to display the weather forecast icons
automatically. To do so, set `sunshine-show-icons' to t.
