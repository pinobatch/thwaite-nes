#!/usr/bin/env python3
import codecs

# Make a special character codepage mapping starting from ASCII printable
# characters and adding special characters in non-whitespace ASCII control
# characters. So that 128 of the 256 available characters can be used
# for DTE code units.
name = 'thwaite'
decoding_table = [
    # Reserve first 16 for ASCII control characters
    # 0x00 and 0x0a are for termination and newline respectively
    *range(16),
    # Other ligatures as discovered to be needed
    *range(16, 25),
    # Ligatures 'r, I', and ll.  Abuses code points for ligatures:
    # ŕ U+0155 LATIN SMALL LETTER R WITH ACUTE for r'
    # Í U+00CD LATIN CAPITAL LETTER I WITH ACUTE for I'
    # ỻ U+1EFB LATIN SMALL LETTER MIDDLE-WELSH LL for ll
    0x0155, 0x00CD, 0x1EFB,
    # copyright, rocket, 's, il.  Abuses code points for ligatures:
    # ś U+015B LATIN SMALL LETTER S WITH ACUTE for 's
    # ǁ U+01C1 LATIN LETTER LATERAL CLICK for il
    0x00A9, 0x1F680, 0x015B, 0x01C1,
    # ASCII printable characters
    *range(32,127),
    # house building, in the place of ASCII DEL (which looks like a
    # different house in cp437)
    0x1F3E0,
    # reserved for DTE
    *[0xFFFE]*128,
]

# This one was considered and rejected for being used only once:
# ḑ U+1E11 LATIN SMALL LETTER D WITH CEDILLA for 'd

### encoding map from decoding table

#encoding_table = codecs.charmap_build(''.join(chr(x) for x in decoding_table))
encoding_table = dict((c,i) for (i,c) in enumerate(decoding_table))

# Codecs API boilerplate ############################################

### Codec APIs

class Codec(codecs.Codec):

    def encode(self,input,errors='strict'):
        return codecs.charmap_encode(input,errors,encoding_table)

    def decode(self,input,errors='strict'):
        return codecs.charmap_decode(input,errors,decoding_table)

class IncrementalEncoder(codecs.IncrementalEncoder):
    def encode(self, input, final=False):
        return codecs.charmap_encode(input,self.errors,encoding_table)[0]

class IncrementalDecoder(codecs.IncrementalDecoder):
    def decode(self, input, final=False):
        return codecs.charmap_decode(input,self.errors,decoding_table)[0]

class StreamWriter(Codec,codecs.StreamWriter):
    pass

class StreamReader(Codec,codecs.StreamReader):
    pass

### encodings module API

def getregentry():
    return codecs.CodecInfo(
        name=name,
        encode=Codec().encode,
        decode=Codec().decode,
        incrementalencoder=IncrementalEncoder,
        incrementaldecoder=IncrementalDecoder,
        streamreader=StreamReader,
        streamwriter=StreamWriter,
    )

def register():
    ci = getregentry()
    def lookup(encoding):
        if encoding == name:
            return ci
    codecs.register(lookup)

# End boilerplate ###################################################

### Testing

def preencode(s):
    """Convert ligatures into their presentation forms used with this encoding."""
    # Narrow-narrow pairs have priority over apostrophe contractions
    s = s.replace("I'", "Í")
    s = s.replace("il", "ǁ")
    s = s.replace("ll", "ỻ")
    s = s.replace("'r", "ŕ")
    s = s.replace("'s", "ś")
    return s

def main():
    register()
    tests = [
        "© 2018 Damian Yerrick",
        "Tilda's house has been rebuilt",
    ]
    for s in tests:
        p = preencode(s)
        b = p.encode(name)
        print(s)
        print(p)
        print(b.hex())

if __name__=='__main__':
    main()
