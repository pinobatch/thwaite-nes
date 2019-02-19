#!/usr/bin/env python3
import sys
import os
import charset
import dte
charset.register()  # as "thwaite"

DTE_MIN_CODEUNIT = 128

def ca65_bytearray(s):
    s = ['  .byte ' + ','.join("%3d" % ch for ch in s[i:i + 16])
         for i in range(0, len(s), 16)]
    return '\n'.join(s)

def lines_to_docs(lines):
    cur_page = cur_title = None
    for line in lines:
        # some parsers need leading whitespace to be preserved
        line = line.rstrip()
        linestrip = line.lstrip()

        # Page title syntax resembles a MediaWiki headline
        if linestrip.startswith("==") and linestrip.endswith("=="):
            # Strip trailing blank lines
            while cur_page and cur_page[-1] == '':
                del cur_page[-1]
            if cur_title: yield cur_title, cur_page

            # Start new page
            cur_title = line.strip("=").strip()
            cur_page = []
            continue

        # hash in first column as first thing on page: comment
        if line.startswith("#") and not cur_page: continue

        # skip initial blank lines
        if linestrip == '' and not cur_page: continue

        cur_page.append(line)

    # Push last page
    while cur_page and cur_page[-1] == '':
        del cur_page[-1]
    if cur_title: yield cur_title, cur_page

def parse_cutscripts(pages):
    lines_to_compress = []
    scripts = []
    for title, script in pages:
        speakers = ['X', 'Y', 'Z']
        cues = []
        for line in script:
            if len(line) >= 4 and line[0] == '<' and line[2] == '>':
                speaker = line[1]
                if speaker not in speakers:
                    speakers.append(speaker)
                    if len(speakers) > 4:
                        raise ValueError("%s has more than 4 speakers"
                                         % (title,))
                cues.append((speaker, []))
                line = line[3:]
            line = line.strip()
            if line:
                cues[-1][1].append(len(lines_to_compress))
                if len(cues[-1][1]) > 3:
                    raise ValueError("%s: %s cue has more than 3 lines"
                                     % (title, cues[-1][0]))
                lines_to_compress.append(line.strip())
        if len(speakers) < 4:
            speakers.append("N")
        speakers = "".join(speakers)
        scripts.append((title, speakers, cues))

    lines_to_compress = [
        line.replace("il","\u01C1").encode("thwaite")
        for line in lines_to_compress
    ]
    return scripts, lines_to_compress

def output_cutscripts(scripts, lines_to_compress):
    out = [
        """;Thwaite cut scene scripts generated with paginate.py
.segment "RODATA"
.export cut_scripts
.exportzp NUM_CUT_SCRIPTS:=%d
cut_scripts:""" % len(scripts)
    ]
    out.extend("  .addr %s" % row[0] for row in scripts)
    # TODO: Compress lines using DTE

    for title, speakers, cues in scripts:
        out.append("%s:" % title)
        out.append(ca65_bytearray(speakers.encode("thwaite")))
        enccues = []
        for speaker, linenos in cues:
            # $0A between lines of cue
            cuebytes = b"\n".join(
                lines_to_compress[lineno] for lineno in linenos
            )

            enccue = ['  .byte %d' % ord(speaker)]
            enccue.append(ca65_bytearray(cuebytes))
            enccues.append("\n".join(enccue))
        # $0C between cues in scene
        out.append("\n  .byte 12\n".join(enccues))
        # $00 at end of scene
        out.append("  .byte 0\n")

    return "\n".join(out)

def parse_text(pages):
    titles = []
    lines_to_compress = []
    for title, lines in pages:
        enc = "\n".join(lines).replace("il","\u01C1").encode("thwaite")
        titles.append(title)
        lines_to_compress.append(enc)
    return titles, lines_to_compress

def output_text(titles, lines_to_compress):
    out = [
        """;Thwaite texts generated with paginate.py
.segment "RODATA"
"""
    ]
    for title, enc in zip(titles, lines_to_compress):
        out.append(".export %s" % title)
        out.append("%s:" % title)
        out.append(ca65_bytearray(enc))
        out.append("  .byte 0\n")
    return "\n".join(out)

def output_tips(titles, lines_to_compress):
    out = [
        """;Thwaite tips generated with paginate.py
.segment "RODATA"
.export tipTexts
.exportzp NUM_TIP_TEXTS:=%d
tipTexts:""" % len(titles)
    ]
    out.extend("  .addr %s" % row for row in titles)
    for title, enc in zip(titles, lines_to_compress):
        out.append("%s:" % title)
        out.append(ca65_bytearray(enc))
        out.append("  .byte 0\n")
    return "\n".join(out)

output_funcs = {
    'cutscripts': (parse_cutscripts, output_cutscripts),
    'text': (parse_text, output_text),
    'tips': (parse_text, output_tips),
}

# Argument parsing ##################################################
#
# I have to reimplement getopt myself because each infile takes its
# own options, and import getopt provides no counterpart to
# urllib.parse.parse_qsl.

def search_long_opts(arg, longopts):
    """Find the long option that best matches the argument

arg -- a long option or a prefix thereof, without leading --
longopts -- an iterable of long options

The match must be either exact or a unique prefix.

Return the long option, which ends with '=' if it needs an argument.
"""
    # Find all matches
    matches = set(o for o in longopts if o.startswith(arg))
    if len(matches) == 0:
        raise ValueError("no such option --%s" % arg)

    # Look for exact matches
    if arg in matches:
        return arg
    elif arg + '=' in matches:
        return arg + '='

    # Look for a unique match
    if len(matches) > 1:
        raise ValueError("option --%s not unique, matching %s"
                         % (arg, ", ".join(sorted(matches))))
    return next(iter(matches))

def read_getopt(args, shortopts="", longopts=[]):
    """Like getopt.getopt but interleaves positionals with optionals

shortopts - string of option letters, with those requiring an argument
    followed by ':'
longopts - list of option words, with those requiring an argument foll
    (e.g. "palette-name=" for --palette-name)

Return an iterator over 2-tuples:
    ("", value) for positionals
    ("-x", "") or ("--long-x", "") for options with no argument
    ("-x", value) or ("--long-x", value) for options with an argument

"""
    args = iter(args)
    nomoreoptions = False

    # Format short options for fast searching
    shorttakesarg = {}
    arg = None
    for c in shortopts:
        if c == ':':
            shorttakesarg[arg] = True
        else:
            arg = c
            shorttakesarg[arg] = False
    
    for arg in args:
        # Positionals
        if nomoreoptions or len(arg) < 2 or arg[0] != '-':
            yield "", arg
            continue
        if arg == "--":
            nomoreoptions = True
            continue

        # Long options
        if arg.startswith("--"):
            arg_value = arg[2:].split("=", 1)
            arg = arg_value[0]
            value = arg_value[1] if len(arg_value) > 1 else None

            arg = search_long_opts(arg, longopts)
            if arg.endswith("="):
                if value is None:
                    value = next(args)
                yield "--"+arg[:-1], value
            else:
                if value is not None:
                    raise ValueError("option --%s takes no argument" % (arg,))
                yield "--"+arg, ""
            continue

        # Short options
        for i in range(1, len(arg)):
            c = arg[i]
            try:
                takesarg = shorttakesarg[c]
            except KeyError:
                raise ValueError("no such option -%s" % c)
            if takesarg:
                value = arg[i + 1:] if i + 1 < len(arg) else next(args)
                yield "-"+c, value
                break
            else:
                yield "-"+c, ""

helpText = """usage: %prog [options] infile [[options] infile]... [-o outfile]

options:
    -h, -?, --help   display this help and exit
    -o outfile       write assembly output to this file instead of
                     standard output
    --dte            compress all text with digram tree encoding
    -t parsetype, --type parsetype
                     treat the following infile(s) as this type
                     (text, cutscripts) (default: text)
"""

def parse_argv(argv):
    parsetype, outfile, jobs, use_dte = "text", None, [], False
    longopts = ["type=", "output=", "dte"]
    for n, v in read_getopt(argv[1:], "h?t:o:", longopts):
        if n in ("-h", "--help", "-?"):
            progname = os.path.basename(argv[0])
            print(helpText.replace("%prog", progname))
            sys.exit(0)
        if n in ("-t", "--type"):
            parsetype = v
        elif n == '--dte':
            use_dte = True
        elif n in ("-o", "--output"):
            if outfile is not None:
                raise ValueError("output to %s but already set to %s"
                                 % (outfile, v))
            outfile = v
        elif n == '':
            jobs.append((v, output_funcs[parsetype]))
    if outfile is None:
        outfile = '-'
    return outfile, jobs, use_dte

def main(argv=None):
    argv = argv or sys.argv
    try:
        outfile, jobs, use_dte = parse_argv(argv)
    except Exception as e:
        progname = os.path.basename(argv[0])
        print("%s: %s; try %s --help"
              % (progname, e, progname), file=sys.stderr)
        sys.exit(1)
        
    # Parse all jobs
    all_lines = []
    all_parsed = []
    for infilename, (parsefunc, outfunc) in jobs:
        with open(infilename, "r", encoding="utf-8") as infp:
            pages = list(lines_to_docs(infp))
        parsed, ltc = parsefunc(pages)
        all_parsed.append((outfunc, parsed, len(ltc)))
        all_lines.extend(ltc)

    # TODO: compress all_lines
    all_out = []
    if use_dte:
        bytesbefore = sum(len(x) for x in all_lines)
        all_lines, repls, _ = dte.dte_compress(all_lines, mincodeunit=DTE_MIN_CODEUNIT)
        bytesafter = sum(len(x) for x in all_lines)
        print("compressed %d bytes to %d bytes"
              % (bytesbefore, bytesafter+256), file=sys.stderr)
        all_out.append("""; Digram tree compression dictionary
.segment "RODATA"
.export dte_replacements
dte_replacements:
""")
        all_out.append(ca65_bytearray(b"".join(repls)))
        all_out.append("\n")

    # Write compressed data for all jobs
    startline = 0
    for outfunc, parsed, nlines in all_parsed:
        endline = startline + nlines
        ltc = all_lines[startline:endline]
        startline = endline
        all_out.append(outfunc(parsed, ltc))
        all_out.append("\n")

    if outfile == '-':
        sys.stdout.writelines(all_out)
    else:
        with open(outfile, "w", encoding="utf-8") as outfp:
            outfp.writelines(all_out)

if __name__=='__main__':
    in_IDLE = 'idlelib.__main__' in sys.modules or 'idlelib.run' in sys.modules
    if in_IDLE:
        cmd = """
paginate.py
-t cutscripts ../src/cutscripts.txt
-t text ../src/texts.txt
-t tips ../src/tips.txt
--dte
"""
        main(cmd.split())
    else:
        main()
