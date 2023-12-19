.include "popslide.inc"

.code

; Several NES games by Nintendo use the "NES Stripe Image RLE" data
; format (N-Stripe for short) to store title screen map layouts in
; ROM.  Because we use PB8 instead for ROM data, we use N-Stripe only
; in RAM as a transfer buffer format.  Not needing to decode from
; anywhere outside popslide_buf ($0100-$01BF) allows a simpler decoder.
;
; Each packet begins with a 3-byte header.
; Byte 1: bit 7: stop; 6-0 first PPUADDR write
; Byte 2: second PPUADDR write
; Byte 3: bit 7: vertical; bit 6: run; bit 5-0: data length minus 1
; If this is a run, exactly 1 data byte follows; otherwise, n+1
; literal bytes follow.
;
; We make one change to Nintendo's format.  Nintendo uses a VRAM
; address in $0000-$00FF as a terminator because Doki Doki Panic is
; the only game that uses N-Stripe to update CHR RAM.  We instead
; use an address in $8000-$FFFF as a terminator.
;
; The decode buffer is read only about half as fast as an unrolled
; copy, so don't try to send more than about 64 bytes in a frame.
;
; Source: http://wiki.nesdev.com/w/index.php/Tile_compression



.proc append_engine
bytesleft = nstripe_height

  ; Append stripe
stripeloop:
  iny
  bit nstripe_top
  bmi normal_top  ; $80-$FF
  bvc const_vmaddhi_top  ; $00-$3F
    clc
    pha
    lda (nstripe_srclo),y
    iny
    adc nstripe_left
    sta popslide_buf+1,x
    pla
    adc nstripe_top
    sta popslide_buf,x
    jmp address_written
  const_vmaddhi_top:
    ; A is low byte; nstripe_top is high byte
    sta popslide_buf+1,x
    lda nstripe_top
    sta popslide_buf,x
    bne address_written
  normal_top:
    ; A is high byte; next byte is low byte
    sta popslide_buf,x
    lda (nstripe_srclo),y
    iny
    sta popslide_buf+1,x
  address_written:
  inx
  inx
  lda (nstripe_srclo),y  ; direction, run flag, and length
  iny
  sta popslide_buf,x
  inx
  and #$7F
  cmp #$40  ; For runs, copy only one byte
  bcc notrun
    lda #0
  notrun:
  sta bytesleft
  bytesloop:
    lda (nstripe_srclo),y
    iny
    sta popslide_buf,x
    inx
    dec bytesleft
    bpl bytesloop
nextstripe:
  lda (nstripe_srclo),y  ; copy palette index
  bpl stripeloop
stripesdone:
  sta popslide_buf,x
  stx popslide_used
  rts
.endproc

;;
; Appends a set of stripes to the update buffer.
; @param XXAA pointer to the stripe
.proc nstripe_append
  ldy #$FF
.endproc

;;
; Appends a set of stripes to the update buffer.
; @param XXAA pointer to the stripe
; @param Y $00-$3F high byte of each destination address in
; video memory; $40-$7F add Y*$100+nstripe_left to each
; destination address; $80+: stripes contain 2-byte destinations
.proc nstripe_append_yhi
  sty nstripe_top
.endproc

;;
; Appends a set of stripes to the update buffer.
; @param XXAA pointer to the stripe
; @param nstripe_top $00-$3F high byte of each destination address in
; video memory; $40-$7F add nstripe_top*$100+nstripe_left to each
; destination address; $80+: stripes contain 2-byte destinations
.proc nstripe_append_tophi
  stx nstripe_srchi
  sta nstripe_srclo
.endproc

;;
; Appends a set of stripes to the update buffer.
; @param nstripe_src pointer to the stripe
; @param nstripe_top $00-$3F high byte of each destination address in
; video memory; $40-$7F add nstripe_top*$100+nstripe_left to each
; destination address; $80+: stripes contain 2-byte destinations
.proc nstripe_append_src
  ldy #0
  ldx popslide_used
  jmp append_engine::nextstripe
.endproc

_nstripe_append = nstripe_append
.export _nstripe_append
