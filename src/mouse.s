.export read_mouse, mouse_change_sensitivity
.exportzp cur_mbuttons, new_mbuttons
.segment "ZEROPAGE"
cur_mbuttons: .res 2
new_mbuttons: .res 2

.segment "LIBCODE"
;;
; Reads the Super NES Mouse after the 8 leading bits (corresponding
; to the controller) are already read.
; @param X controller port (0 or 1)
; @return cur_mbuttons[x] and new_mbuttons[x]updated;
; $01: sig, , and ; $02: y; $03: x
.proc read_mouse
  lda #1
  sta 1
  sta 2
  sta 3
:
  lda $4016,x
  lsr a
  rol 1
  bcc :-
  lda cur_mbuttons,x
  eor #$FF
  and 1
  sta new_mbuttons,x
  lda 1
  sta cur_mbuttons,x
:
  lda $4016,x
  lsr a
  rol 2
  bcc :-
:
  lda $4016,x
  lsr a
  rol 3
  bcc :-
  rts
.endproc

;;
; Changes the sensitivity of the Super NES Mouse by sending a clock
; while strobe is true.
; @param X controller port (0 or 1)
.proc mouse_change_sensitivity
  lda #1
  sta $4016
  lda $4016,x
  lda #0
  sta $4016
  rts
.endproc

