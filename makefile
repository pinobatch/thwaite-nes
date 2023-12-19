#!/usr/bin/make -f
#
# Makefile for Thwaite
# Copyright 2011-2019 Damian Yerrick
#
# Copying and distribution of this file, with or without
# modification, are permitted in any medium without royalty
# provided the copyright notice and this notice are preserved.
# This file is offered as-is, without any warranty.
#
title = thwaite
version = 0.04
objlist = popslide16 \
          main random levels smoke bg missiles explosion scurry \
          title practice cutscene dtescripts \
          math bcd kinematics undte pads mouse ppuclear nstripe \
          paldetect pentlysound pentlymusic musicseq ntscPeriods

CC65 = /usr/local/bin
AS65 = ca65
LD65 = ld65
#EMU := "/C/Program Files/nintendulator/Nintendulator.exe"
#EMU := mednafen -nes.pal 0 -nes.input.port1 gamepad -nes.input.port2 gamepad
DEBUGEMU := Mesen
EMU := fceux
CC := gcc
CFLAGS := -std=gnu99 -Wall -Wextra -DNDEBUG -Os
CFLAGS65 := -g
objdir := obj/nes
srcdir := src
imgdir := tilesets

# The Windows Python installer puts py.exe in the path, but not
# python3.exe, which confuses MSYS Make.  COMSPEC will be set to
# the name of the shell on Windows and not defined on UNIX.
ifdef COMSPEC
DOTEXE:=.exe
PY:=py -3
else
DOTEXE:=
PY:=python3
endif

objlistntsc = $(foreach o,$(objlist),$(objdir)/$(o).o)

.PHONY: run debug all dist zip clean ctools

run: $(title).nes
	$(EMU) $<
debug: $(title).nes
	$(DEBUGEMU) $<
all: $(title).nes $(title)128.nes
dist: zip
zip: $(title)-$(version).zip
ctools: tools/dte$(EXE)
clean:
	-rm $(objdir)/*.o $(objdir)/*.s $(objdir)/*.chr
	-rm map128.txt map.txt
	-rm tools/dte$(EXE)

# packaging

# Actually this depends on every single file in zip.in, but currently
# we use changes to thwaite.nes, makefile, and README as a heuristic
# for when something was changed.  Limitation: it won't see changes
# to docs or tools.
$(title)-$(version).zip: \
  zip.in $(title).nes $(title)128.nes README.md USAGE.html $(objdir)/index.txt
	$(PY) tools/zipup.py $< $(title)-$(version) -o $@

# Build zip.in from the list of files in the Git tree
zip.in:
	git ls-files | grep -e "^[^.]" > $@
	echo $(title).nes >> $@
	echo $(title)128.nes >> $@
	echo zip.in >> $@

# Some unzip tools won't create empty folders, so put a file there.
$(objdir)/index.txt: makefile CHANGES.txt
	echo "Files produced by build tools go here." > $@

# forming the ROM

map.txt $(title).nes: nrom256.x $(objdir)/nrom256.o $(objlistntsc)
	$(LD65) -o $(title).nes -m map.txt --dbgfile $(title).dbg -C $^

map128.txt $(title)128.nes: nrom128.x $(objdir)/nrom128.o $(objlistntsc)
	$(LD65) -o $(title)128.nes -m map128.txt --dbgfile $(title)128.dbg -C $^

# assembly language

$(objdir)/%.o: $(srcdir)/%.s \
  $(srcdir)/nes.inc $(srcdir)/global.inc $(srcdir)/popslide.inc
	$(AS65) $(CFLAGS65) $< -o $@

$(objdir)/%.o: $(objdir)/%.s
	$(AS65) $(CFLAGS65) $< -o $@

# extra headers

$(objdir)/bg.o $(objdir)/cutscene.o $(objdir)/popslide.o: $(srcdir)/popslide.inc
$(objdir)/popslide.o: $(srcdir)/popslideinternal.inc

# incbins

$(objdir)/main.o: $(objdir)/maingfx.chr $(objdir)/cuthouses.chr

# data conversion

$(objdir)/ntscPeriods.s: tools/mktables.py
	$(PY) $< period $@

$(objdir)/cutscripts.s: tools/paginate.py \
  $(srcdir)/cutscripts.txt
	$(PY) tools/paginate.py \
	-o $@

$(objdir)/dtescripts.s: tools/paginate.py tools/dte$(DOTEXE) \
  $(srcdir)/texts.txt $(srcdir)/tips.txt $(srcdir)/cutscripts.txt
	$(PY) tools/paginate.py --dte \
	-t cutscripts $(srcdir)/cutscripts.txt \
	-t tips $(srcdir)/tips.txt \
	-t text $(srcdir)/texts.txt \
	-o $@

tools/dte$(DOTEXE): tools/dte.c
	$(CC) -static $(CFLAGS) -o $@ $^

# graphics

$(objdir)/%.chr: $(imgdir)/%.png
	$(PY) tools/pilbmp2nes.py $< $@
