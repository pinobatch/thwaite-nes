#!/usr/bin/make -f
#
# Makefile for Thwaite
# Copyright 2011-2017 Damian Yerrick
#
# Copying and distribution of this file, with or without
# modification, are permitted in any medium without royalty
# provided the copyright notice and this notice are preserved.
# This file is offered as-is, without any warranty.
#
title = thwaite
version = 0.04wip
objlist = main random levels smoke bg missiles explosion scurry \
          title practice cutscene cutscripts tips \
          math bcd kinematics unpkb undte pads mouse ppuclear popslide16 \
          paldetect pentlysound pentlymusic musicseq ntscPeriods

CC65 = /usr/local/bin
AS65 = ca65
LD65 = ld65
#EMU := "/C/Program Files/nintendulator/Nintendulator.exe"
#EMU := mednafen -nes.pal 0 -nes.input.port1 gamepad -nes.input.port2 gamepad
DEBUGEMU := ~/.wine/drive_c/Program\ Files\ \(x86\)/FCEUX/fceux.exe
EMU := fceux
CC = gcc
ifdef COMSPEC
DOTEXE=.exe
else
DOTEXE=
endif
CFLAGS = -std=gnu99 -Wall -DNDEBUG -O
CFLAGS65 = 
objdir = obj/nes
srcdir = src
imgdir = tilesets

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

.PHONY: run debug all dist zip clean

run: $(title).nes
	$(EMU) $<
debug: $(title).nes
	$(DEBUGEMU) $<

all: $(title).nes

# Actually this depends on every single file in zip.in, but currently
# we use changes to thwaite.nes, makefile, and README as a heuristic
# for when something was changed.  Limitation: it won't see changes
# to docs or tools.
dist: zip
zip: $(title)-$(version).zip
$(title)-$(version).zip: zip.in $(title).nes README.html $(objdir)/index.txt
	zip -9 -u $@ -@ < $<

# Build zip.in from the list of files in the Git tree
zip.in:
	git ls-files | grep -e "^[^.]" > $@
	echo zip.in >> $@

# Some unzip tools won't create empty folders, so put a file there.
$(objdir)/index.txt: makefile CHANGES.txt
	echo "Files produced by build tools go here." > $@

clean:
	-rm $(objdir)/*.o $(objdir)/*.s $(objdir)/*.chr
	-rm $(title).chr $(title).prg

# assembly language

$(objdir)/%.o: $(srcdir)/%.s $(srcdir)/nes.inc $(srcdir)/global.inc
	$(AS65) $(CFLAGS65) $< -o $@

$(objdir)/%.o: $(objdir)/%.s
	$(AS65) $(CFLAGS65) $< -o $@

# extra headers

$(objdir)/bg.o $(objdir)/cutscene.o $(objdir)/popslide.o: $(srcdir)/popslide.inc
$(objdir)/popslide.o: $(srcdir)/popslideinternal.inc

# incbins

$(objdir)/title.o: src/title.pkb
$(objdir)/cutscene.o: src/cutscene.pkb

# data conversion

$(objdir)/ntscPeriods.s: tools/mktables.py
	$(PY) $< period $@

$(objdir)/cutscripts.s: \
  tools/paginate.py $(srcdir)/cutscripts.txt $(srcdir)/tips.txt
	$(PY) tools/paginate.py \
	-t cutscripts $(srcdir)/cutscripts.txt \
	-t tips $(srcdir)/tips.txt \
	-t text $(srcdir)/texts.txt \
	-o $@

map.txt $(title).prg: nrom256.x $(objlistntsc)
	$(LD65) -o $(title).prg -m map.txt -C $^

# graphics

$(objdir)/%.chr: $(imgdir)/%.png
	$(PY) tools/pilbmp2nes.py $< $@

%.nes: %.prg %.chr
	cat $^ > $@

$(title).chr: $(objdir)/maingfx.chr $(objdir)/cuthouses.chr
	cat $^ > $@

