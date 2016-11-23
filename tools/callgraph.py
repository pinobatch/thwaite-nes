#!/usr/bin/env python3
from __future__ import with_statement, print_function
import os
import re
from itertools import groupby
import subprocess
import sys

includeInternalColonLabels = True

srcFolder = '../src'
labelRE = re.compile('^(@?[a-z_][a-z_0-9]*)\s*:\s*(.*)$', re.IGNORECASE)
equateRE = re.compile('^(@?[a-z_][a-z_0-9]*)\s*(?:=|.?equ)\s*(.*)$', re.IGNORECASE)
wordRE = re.compile('[0-9]+|\$[0-9a-f]+|(?:(?:[a-z_][a-z_0-9]*::)*|@?)[a-z_][a-z_0-9]*', re.IGNORECASE)
isNumberRE = re.compile('^[0-9]+|\$[0-9a-f]+|\%[01]+$', re.IGNORECASE)

symbolsToIgnore = frozenset([
    'a', 'x', 'y',
    'vblank_nmi', 'vram_down', 
    'lightgray',
    'rest', 'clhat', 'kick', 'snare', 'instrument'
])

prefixesToIgnore = (
    '$', '@', 'STATE_', 'NUM_', 'S0_TRIGGER_',
    'KEY_', 'MOUSE_', 'PPU', 'OAM', 'BG_', 'OBJ_', 'TINT_',
    'N_', 'D_', 'SFX_',
)

def findWordsInExpr(line):
    """Find symbols (not literal numbers or strings) in an operand."""
    unquotedChars = []
    isQuoted = False
    for c in line:
        if c == '"':
            isQuoted = not isQuoted
        elif not isQuoted:
            unquotedChars.append(c)
    line = ''.join(unquotedChars)
    words = [word for word in wordRE.findall(line)
             if (not word.isdigit()
                 and not word.startswith(prefixesToIgnore)
                 and word.lower() not in symbolsToIgnore)]
    return words

def stripCommentFromLine(line):
    isQuoted = False
    for (i, c) in zip(range(len(line)), line):
        if c == '"':
            isQuoted = not isQuoted
        elif c == ';' and not isQuoted:
            return line[:i].strip()
    return line.strip()

def parseFile(body):
    lines = [stripCommentFromLine(line) for line in body.split('\n')]

    labels = []
    refs = {}
    scopeStack = []
    segmentStack = ['CODE']
    for (i, line) in zip(range(len(lines)), lines):
        hasLabel = labelRE.match(line)
        if hasLabel and not line.startswith(('-', '+')):
            (label, line) = hasLabel.groups()

            # make sure it's not anonymous local symbol (e.g. bcc :+ )
            if (not label.startswith('@')
                and (line == '' or line[0] not in "-+")
                and (includeInternalColonLabels or len(scopeStack) == 0)):
                labels.append((segmentStack[-1], '::'.join(scopeStack), label))

        hasEquate = equateRE.match(line)
        if hasEquate and not line.startswith(('-', '+')):
            (label, line) = hasEquate.groups()
            if (line.startswith('*')
                and (includeInternalColonLabels or len(scopeStack) == 0)):
                labels.append((segmentStack[-1], '::'.join(scopeStack), label))
                print("Equ *", labels[-1])
                continue

            # Make a label for this line, and attach any refs in
            # the expression to the enclosing scope
            labels.append(('', '::'.join(scopeStack), label))

        if line == '':
            continue
        firstWord = line.split(None, 1)
        fwl = firstWord[0].lower()
        line = firstWord[1] if len(firstWord) > 1 else ''

        # we used to have .if and .export here but they ended up as
        # spurious unused symbols
        if fwl in ('.global', '.import', '.include', '.incbin'):
            continue
        if fwl == '.endproc':
            scopeStack.pop()
            continue
        if fwl in ('.proc', '.scope'):
            if line:
                labels.append((segmentStack[-1], '::'.join(scopeStack), line))
            scopeStack.append(line)
            continue
        if fwl == '.pushseg':
            segmentStack.append(segmentStack[-1])
            continue
        if fwl == '.popseg':
            segmentStack.pop()
            continue
        if fwl == '.segment':
            segmentStack[-1] = line.strip('"')
            continue

        # we have references to other labels by this point
        if segmentStack[-1] in ('VECTORS', 'INESHDR'):
            continue
        words = findWordsInExpr(line)
        if not words:
            continue
        
        if len(scopeStack) > 0:
            scopeName = '::'.join(scopeStack)
        elif len(labels) > 0:
            scopeName = labels[-1][2]
        else:
            scopeName = ''
        refskey = (segmentStack[-1], scopeName)
        refs.setdefault(refskey, set())
        refs[refskey].update(words)
    labels.sort()
    refs = sorted((seg, scope, sorted(v))
                  for ((seg, scope), v) in refs.items())
    return (labels, refs)

def resolveScope(callees, name, scope):
    """Resolve scope.

callees -- a dictionary of dictionaries of the form
callees [name][scope] where name is the last component and scope is
all components preceding it
name -- the name of a function
callerScope -- the name of a scope from which the name is referred

Parts of a name are delimited by '::', which in English is called
Pair of Colons or in Hebrew is called Pa'amayim Nekudotayim.

"""

    # starting the name with '::' (e.g. ::WITHOUT_PAL)
    # forces the resolver to ignore the caller's scope
    if name.startswith('::'):
        name = name[2:]
        scope = ''
    try:
        innerscope = name[:name.index('::')]
        name = name[len(innerscope) + 2:]
    except ValueError:
        innerscope = ''

    while True:
        scopekey = ("::" if innerscope and scope else "").join((scope, innerscope))
        try:
            return (scopekey, callees[name][scopekey])
        except KeyError as e:
            if scope == '':
                raise
            try:
                scope = scope[:scope.index('::')]
            except ValueError:
                scope = ''

def callsToDOTInput(allCallees, sectionReplace=None):
    """

Example of a valid .dag file:
strict digraph hello {
  reset -> initMissiles;
  reset -> cutscene;
  reset -> moveMissiles -> moveMissileNumberX;
  reset -> drawMissiles -> drawMissileNumberX;
}

Rendered as follows:
dot -Tpng thwaitecalls.dag -o thwaitecalls.png

"""

    callset = set()
    for ((eescope, name), (eefilename, eeseg, callers)) in allCallees.items():
        if eeseg in ('', 'ZEROPAGE', 'BSS'):
            continue
        callers = ((erscope,
                    "%s::%s" % (eescope, name) if eescope else name)
                   for (erfilename, erseg, erscope) in callers
                   if (erscope
                       and (erscope != eescope or erseg != eeseg)
                       ))
        if sectionReplace:
            callers = ((sectionReplace.get(erscope, erscope),
                        sectionReplace.get(name, name))
                       for (erscope, name) in callers)
        callers = ((erscope, name) for (erscope, name) in callers
                   if erscope != name)
        callset.update(callers)
    all_nodes = set(erscope for (erscope, name) in callset)
    all_nodes.update(name for (erscope, name) in callset)
    lines = ['strict digraph thwaitecalls {',
             '  graph [ ] ;']
    lines.extend('  "%s"  [fontname="Droid Sans" fontsize=8 shape=box height=".25" style="rounded"];' % name
                 for name in sorted(all_nodes))
    lines.extend('  "%s" -> "%s";' % (erscope, name)
                 for (erscope, name) in sorted(callset)
                 if erscope != name)
    lines.append('}')
    lines = "\n".join(lines)
    return lines

def load_sections():
    with open('sections.in', 'rU') as infp:
        lines = [line.strip() for line in infp]
    curSection = None
    symToSection = {}
    for line in lines:
        if not line or line.startswith(('#', ';')):
            continue
        if line.startswith('[') and line.endswith(']'):
            curSection = line.lstrip('[').rstrip(']').strip()
            continue
        line = line.lstrip(':')
        symToSection[line] = curSection
    return symToSection

srcFiles = [filename
            for filename in os.listdir(srcFolder)
            if filename.lower().endswith('.s')]
bodies = []
decodeerrors = 0
for filename in srcFiles:
    try:
        path = os.path.join(srcFolder, filename)
        with open(path) as infp:
            body = infp.read()
    except Exception:
        import traceback
        print("callgraph.py: while reading %s:" % path, file=sys.stderr)
        traceback.print_exc()
        decodeerrors += 1
    bodies.append((filename, body))
if decodeerrors > 0:
    sys.exit(1)

allLabels = []
allRefs = []
while bodies:
    (filename, body) = bodies.pop()
    (labels, refs) = parseFile(body)
    allLabels.append((filename, labels))
    allRefs.append((filename, refs))

byLabel = {}
for (filename, labels) in allLabels:
    for (seg, scope, name) in labels:
        if name not in byLabel:
            byLabel[name] = {}
        if scope not in byLabel[name]:
            byLabel[name][scope] = (filename, seg)
filename = seg = scope = name = bodies = None

##print("\n".join("%s found in:\n%s" % (k, v)
##                for (k, v) in byLabel.items()
##                if len(v) > 1))

# Resolve scope
undefineds = set()
allCallees = {}
for (erfilename, refs) in allRefs:
    for (erseg, erscope, names) in refs:
        eefilename = eeseg = eescope = None
        for name in names:
            try:
                (eescope, (eefilename, eeseg)) = resolveScope(byLabel, name, erscope)
            except KeyError:
                undefineds.add((erscope, name))
                continue
            if (eescope, name) not in allCallees:
                allCallees[(eescope, name)] = (eefilename, eeseg, [])
            allCallees[(eescope, name)][2].append((erfilename, erseg, erscope))

print(len(allCallees), "labels are called at least once")

sections = load_sections()
print("Put %d symbols into %d sections"
      % (len(sections), len(frozenset(sections.values()))))
dagfile = callsToDOTInput(allCallees, sections)
with open('thwaitecalls.dag', 'wt') as outfp:
    outfp.write(dagfile)
print("Building PNG")
subprocess.call('dot -Tpng thwaitecalls.dag -o thwaitecalls.png'.split())

##print("Undefined symbols:")
##print("\n".join("%s::%s" % row for row in sorted(undefineds)))

lines2 = []
seenCallers = set()
calleeCounts = {}
for ((eescope, name), (eefilename, eeseg, callers)) in allCallees.items():
    if eeseg in ('', 'ZEROPAGE', 'BSS'):
        continue

    lines = []
    lines.append('%s::%s (in segment "%s", defined in %s) called %d times'
                 % (eescope, name, eeseg, eefilename, len(callers)))
    for (erfilename, erseg, erscope) in callers:
        
        if erscope == eescope and erseg == eeseg:
            continue
        lines.append('  called by %s (in segment "%s", defined in %s)'
                     % (erscope, erseg, erfilename))
        seenCallers.add(erscope)
        calleeCounts.setdefault((eescope, name), [0, erscope])
        calleeCounts[(eescope, name)][0] += 1
    if lines:
        lines2.append("\n".join(lines))
        if len(lines2) > 100:
##            print("\n".join(lines2))
            lines2 = []
##if len(lines2) > 0:
##    print("\n".join(lines2))
calledOnce = [(eescope, name, firstCaller)
              for ((eescope, name), (n, firstCaller)) in calleeCounts.items()
              if n < 2]

calledOnce.sort(key=lambda s_n_c: (s_n_c[2], s_n_c[0], s_n_c[1]))
print("%d labels are called only once" % len(calledOnce))
calledOnceCallers = [(caller, [call[:2] for call in calls])
                     for (caller, calls)
                     in groupby(calledOnce, lambda x: x[2])]
calledOnceTxt = ["%s:\n" % caller
                 + "\n".join("  .addr %s::%s" % (c, s)
                             for (c, s) in calls)
                 for (caller, calls) in calledOnceCallers]
##print("\n".join(calledOnceTxt))

# To do: call itertools.groupby(iterable, keyfunc)
# to put symbols with 1 caller into into sets by caller

print("== leaf symbols ==")
leafSymbols = set()
for ((eescope, name), (eefilename, eeseg, callers)) in allCallees.items():
    if eeseg in ('', 'ZEROPAGE', 'BSS'):
        continue
    # Only top level symbols can be leaf symbols
    if eescope:
        continue
        name = '::'.join((eescope, name))
    if name not in seenCallers:
        leafSymbols.add(name)
##print(leafSymbols)
##print("\n".join(sorted(leafSymbols)))

print("== unused symbols ==")
unusedSymbols = {}
for (name, scopes) in byLabel.items():
    for (eescope, (eefilename, eeseg)) in scopes.items():
        if ((eescope, name) not in allCallees
            and not name.startswith(prefixesToIgnore)
            and name.lower() not in symbolsToIgnore):
            if eescope:
                name = '::'.join((eescope, name))
            unusedSymbols[name] = eefilename
print("\n".join("%s in %s is unused" % (name, eefilename))
                for (name, eefilename) in sorted(unusedSymbols.items()))

# Problems:
# 1. when buildHouseRebuiltBar calls buildTipBar::suffix,
#    make resolveScope handle innerscope correctly
# 2. why is it still unused?
