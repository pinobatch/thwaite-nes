#!/usr/bin/env python3
import codecs

# Make a special character codepage mapping starting from ASCII printable
# characters and adding special characters in non-whitespace ASCII control
# characters. So that 128 of the 256 available characters can be used
# for DTE code units.
name = 'thwaite'
decoding_table = [
    # Some ASCII control characters
    # 0x00 and 0x0a are for termination and newline respectively
    *range(26),
    # Ligatures I' and ll.  Abuses code points:
    # Í U+00CD LATIN CAPITAL LETTER I WITH ACUTE for I'
    # ỻ U+1EFB LATIN SMALL LETTER MIDDLE-WELSH LL for ll
    0x00CD, 0x1EFB,
    # copyright, rocket, 's, il.  Abuses code points:
    # ś U+015B LATIN SMALL LETTER S WITH ACUTE for the "'s" ligature
    # ǁ U+01C1 LATIN LETTER LATERAL CLICK for the "il" ligature
    0x00A9, 0x1F680, 0x015B, 0x01C1,
    # ASCII printable characters
    *range(32,127),
    # house building, in the place of ASCII DEL (which looks like a
    # different house in cp437)
    0x1F3E0,
    # reserved for DTE
    *[0xFFFE]*128,
]

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
    s = s.replace("il", "ǁ")
    s = s.replace("'s", "ś")
    s = s.replace("I'", "Í")
    s = s.replace("ll", "ỻ")
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
