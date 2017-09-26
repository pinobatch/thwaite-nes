#!/usr/bin/make -f
#
# Makefile for Thwaite
# Copyright 2011 Damian Yerrick
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
          math bcd unpkb pads mouse kinematics \
          paldetect sound music musicseq ntscPeriods

CC65 = /usr/local/bin
AS65 = ca65
LD65 = ld65
#EMU := "/C/Program Files/nintendulator/Nintendulator.exe"
#EMU := mednafen -nes.pal 0 -nes.input.port1 gamepad -nes.input.port2 gamepad
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
PY:=py
else
DOTEXE:=
PY:=
endif

objlistntsc = $(foreach o,$(objlist),$(objdir)/$(o).o)

.PHONY: run dist zip

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
	echo Files produced by build tools go here, but caulk goes where? > $@

$(objdir)/%.o: $(srcdir)/%.s $(srcdir)/nes.inc $(srcdir)/global.inc
	$(AS65) $(CFLAGS65) $< -o $@

$(objdir)/%.o: $(objdir)/%.s
	$(AS65) $(CFLAGS65) $< -o $@

# incbins

$(objdir)/title.o: todo.txt src/title.pkb
$(objdir)/cutscene.o: src/cutscene.pkb
$(objdir)/practice.o: src/practice.txt

$(objdir)/ntscPeriods.s: tools/mktables.py
	$(PY) $< period $@

map.txt $(title).prg: nes.ini $(objlistntsc)
	$(LD65) -o $(title).prg -m map.txt -C $^

$(objdir)/%.chr: $(imgdir)/%.png
	$(PY) tools/pilbmp2nes.py $< $@

%.nes: %.prg %.chr
	cat $^ > $@

$(title).chr: $(objdir)/maingfx.chr $(objdir)/cuthouses.chr
	cat $^ > $@

