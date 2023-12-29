#!/usr/bin/env python3
"""
Python frontend for JRoatch's C language DTE compressor
"""
import sys, os, subprocess

def dte_compress(lines, compctrl=False, mincodeunit=128):
    cwd = os.path.dirname(sys.argv[0])
    pardir = os.path.join(cwd, os.pardir)
    objdir = os.path.join(pardir, "obj")
    dte_path = os.path.join(cwd, "dte")
    ifile = os.path.join(objdir, "uncompressed_data")
    ofile = os.path.join(objdir, "compressed_data")
    delimiter = b'\0'
    if len(lines) > 1:
        unusedvalues = set(range(1 if compctrl else 32))
        for line in lines:
            unusedvalues.difference_update(line)
        delimiter = min(unusedvalues)
        delimiter = bytes([delimiter])
    excluderange = ("0x00-0x%02x" % (compctrl-1) if isinstance(compctrl, int)
                    else "0x00-0x00" if compctrl
                    else "0x00-0x1F")
    digramrange = "0x%02x-0xFF" % mincodeunit
    compress_cmd_line = [
        dte_path, "-c", "-e", excluderange, "-r", digramrange, ifile, ofile
    ]
    inputdata = delimiter.join(lines)
    with open(ifile, "wb") as f:
        f.write(bytes(inputdata))
    if os.path.exists(ofile):
        os.remove(ofile)
    spresult = subprocess.run(
        compress_cmd_line, check=True
    )
    with open(ofile, "rb") as f:
        spresult = f.read()

    table_len = (256 - mincodeunit) * 2
    repls = [spresult[i:i + 2] for i in range(0, table_len, 2)]
    clines = spresult[table_len:].split(delimiter)

    return clines, repls, None

def main(argv=None):
    argv = argv or sys.argv
    with open(argv[1], "rb") as infp:
        lines = [x.rstrip(b"\r\n") for x in infp]
    clines, repls = dte_compress(lines)[:2]
    print(clines)
    print(repls)

if __name__=='__main__':
    if 'idlelib' in sys.modules:
        main(["dtefe.py", "../README.md"])
    else:
        main()

    
    
