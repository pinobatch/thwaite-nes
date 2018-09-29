#
# Linker script for Concentration Room (lite version)
# Copyright 2010 Damian Yerrick
#
# Copying and distribution of this file, with or without
# modification, are permitted in any medium without royalty
# provided the copyright notice and this notice are preserved.
# This file is offered as-is, without any warranty.
#
MEMORY {
  ZP:       start = $10, size = $f0, type = rw;
  # use first $10 zeropage locations as locals
  HEADER:   start = 0, size = $0010, type = ro, file = %O, fill=yes, fillval=$00;
  RAM:      start = $0300, size = $0500, type = rw;

  # Organize so that library code is in its own bank in case
  # Thwaite 0.4 goes to press on a multicart
  ROM0:     start = $8000, size = $4000, type = ro, file = %O, fill=yes, fillval=$FF;
  ROM7:     start = $C000, size = $4000, type = ro, file = %O, fill=yes, fillval=$FF;
}

SEGMENTS {
  INESHDR:    load = HEADER, type = ro, align = $10;
  ZEROPAGE:   load = ZP, type = zp;
  BSS:        load = RAM, type = bss, define = yes, align = $100;
  CODE:       load = ROM0, type = ro, align = $10;
  RODATA:     load = ROM0, type = ro, align = $10;
  LIBCODE:    load = ROM7, type = ro, align = $100, optional=1;
  LIBDATA:    load = ROM7, type = ro, align = $10, optional=1;
  PENTLYCODE: load = ROM7, type = ro, optional=1;
  PENTLYDATA: load = ROM7, type = ro, optional=1;
  VECTORS:    load = ROM7, type = ro, start = $FFFA;
}

FILES {
  %O: format = bin;
}

