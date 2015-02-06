# sunshine.el

[![MELPA](http://melpa.org/packages/sunshine-badge.svg)](http://melpa.org/#/sunshine)

An Emacs package for displaying the forecast from OpenWeatherMap.

![Screenshot](images/sunshine-screenshot.png?raw=true "Sunshine Screenshot")

## Installation and Configuration

1. Copy `sunshine.el` somewhere in your Emacs `load-path`.  To see what your
   `load-path` is, run inside emacs: `C-h v load-path<RET>`.

2. Add the following to your .emacs file:

   `(require 'sunshine)`

3. Configure your location by setting the variable `sunshine-location`.  You can
   provide a string, like "New York, NY" or a ZIP code, like "90210".  This
   variable is available through the Customize facility.

   When specifying a ZIP code, you may receive results from a foreign country.
   This is due to weird behavior from OpenWeatherMap.  To resolve this, append
   a comma and the country code after the ZIP code.  Note the lack of a space
   in the example below.

   `(setq sunshine-location "90210,USA")`

A few other configuration options are available, see the configuration group
called `sunshine`.

## Usage

To display the forecast for your location, call `sunshine-forecast`.

Two key mappings are available within the forecast window:

* `q` - Kill the Sunshine buffer and close the window.
* `i` - Toggle the display of forecast icons (only available in GUI Emacs, of
        course)

If you are using a GUI Emacs, you may like to display the weather forecast icons
by default. To do so, set `sunshine-show-icons` to t.

## License

This program is not part of GNU Emacs.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2, or (at your option) any later version.

This file is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.  See the GNU General Public License for more details.
