#!/bin/sh

# This file has no copyright assigned and is placed in the Public Domain.
# No warranty is given.

export PKG_CONFIG_DIR=
export PKG_CONFIG_SYSROOT_DIR=/opt/retroroot/target/@TRIPLE@
export PKG_CONFIG_LIBDIR=/opt/retroroot/target/@TRIPLE@/usr/lib/pkgconfig:/opt/retroroot/target/@TRIPLE@/usr/share/pkgconfig

# You can use PKG_CONFIG_PATH_CUSTOM to tweak pkg-config behavior further
export PKG_CONFIG_PATH=${PKG_CONFIG_PATH_CUSTOM}:${PKG_CONFIG_LIBDIR}

# Now just execute pkg-config with the given command line args.
pkg-config $@

