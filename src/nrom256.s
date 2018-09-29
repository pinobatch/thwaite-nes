; I don't think an iNES header is eligible for copyright

.segment "INESHDR"
  .byt "NES",$1A
  .byt 2  ; 32 KiB PRG ROM with separate library
  .byt 1  ; 8 KiB CHR ROM
  .byt 1  ; vertical mirroring; low mapper nibble: 0
  .byt 0  ; high mapper nibble: 0; no NES 2.0 features used
