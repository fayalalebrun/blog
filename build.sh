#!/bin/sh
export TERM="${TERM:-xterm-256color}"
emacs --batch -Q -l build-site.el
