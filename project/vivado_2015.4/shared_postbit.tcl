# Copyright 2019 The Aerospace Corporation
#
# This file is part of SatCat5.
#
# SatCat5 is free software: you can redistribute it and/or modify it under
# the terms of the GNU Lesser General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.
#
# SatCat5 is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
# License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.

# NOTE: Automatic path lookup is COMPLICATED in the TCL-hook context.
# The latter has various complicated context-shenanigans, more info here:
# https://forums.xilinx.com/t5/Vivado-TCL-Community/using-tcl-hook-scripts/td-p/398221
# Upside is that "current_project" and "current_run" work fine when run from
# the TCL console, but have no defined meaning when run as pre/post hooks.

# If running from console, use "current_run" command:
# If running as a hook, use "pwd" to point to the active run.
#set SRC_DIR [get_property DIRECTORY [current_run]]
set SRC_DIR [pwd]

# Set destination folder by relative path.
set DST_DIR $SRC_DIR/../../../backups
file mkdir $DST_DIR

# Create timestamp string.
set TIME_NOW [clock seconds]
set TIME_STR [clock format $TIME_NOW -format %Y%m%d_%H%M]

# For each bitfile in that folder...
cd $SRC_DIR
foreach BITFILE [glob -nocomplain *.bit] {
    # Remove the ".bit" suffix (last four characters).
    set FILE_STRLEN [string length $BITFILE]
    set DESIGN_NAME [string range $BITFILE 0 $FILE_STRLEN-5]
    # Append timestamp to the design name.
    set OUT_NAME ${DST_DIR}/${DESIGN_NAME}_${TIME_STR}
    # Copy the .bit file to the destination folder.
    file copy -force $BITFILE ${OUT_NAME}.bit
    # Create a .bin file with the same name.
    write_cfgmem -force -format BIN -interface SPIx4 -size 16 -loadbit "up 0x0 ${BITFILE}" ${OUT_NAME}.bin
}
