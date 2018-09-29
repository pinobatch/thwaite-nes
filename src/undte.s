.include "global.inc"
.import dte_replacements

; BPE (Byte Pair Encoding) or DTE (Digram Tree Encoding)
; Code units less then DTE_MIN_CODEUNIT map to literal characters.
; Code units greater than or equal to DTE_MIN_CODEUNIT (which must
; be at least 128 and must match the value in a53build.py) map to
; pairs of code units.  The second is added to a stack, and the
; first is interpreted as above.

.code
.proc undte_line
srcaddr = $00
  sty srcaddr
  sta srcaddr+1
.endproc
.proc undte_line0
srcaddr = $00
repltable = $02
ysave = $04

  ; Copy the compressed data to the END of dte_output_buf.
  ; First calculate compressed data length
  lda #<dte_replacements
  sta repltable + 0
  lda #>dte_replacements
  sta repltable + 1
  ldy #0
strlenloop:
  lda (srcaddr),y
  iny
  cpy #DTE_OUTPUT_LEN
  bcs have_strlen
  cmp #FIRST_PRINTABLE_CU
  bcs strlenloop
have_strlen:
  tya
  pha  ; Save compressed byte count

  ; Now copy backward
  ldx #DTE_OUTPUT_LEN
poolypoc:
  dey
  dex
  lda (srcaddr),y
  sta dte_output_buf,x
  cpy #0
  bne poolypoc

  ; at this point, Y = 0, pointing to the decompressed data,
  ; and X points to the remaining compressed data
decomploop:
  lda dte_output_buf,x
decomp_code:
  cmp #DTE_MIN_CODEUNIT
  bcs handle_bytepair
  sta dte_output_buf,y
  iny
  inx
  cpx #DTE_OUTPUT_LEN
  bcc decomploop

  ; A: compressed bytes read; Y: decompressed bytes written
  pla
  rts

handle_bytepair:
  ; For a bytepair, stack the second byte on the compressed data
  ; and reprocess the first byte
  sty ysave
  ; sec  ; always set by bcs
  rol a  ; A = (bytecode - 128) * 2 + 1
  tay
  lda (repltable),y
  sta dte_output_buf,x
  dex
  dey  ; Y = (bytecode - 128) * 2
  lda (repltable),y
  ldy ysave
  jmp decomp_code
.endproc
