;
; title.s
; title screen code for Thwaite

;;; Copyright (C) 2011 Damian Yerrick
;
;   This program is free software; you can redistribute it and/or
;   modify it under the terms of the GNU General Public License
;   as published by the Free Software Foundation; either version 3
;   of the License, or (at your option) any later version.
;
;   This program is distributed in the hope that it will be useful,
;   but WITHOUT ANY WARRANTY; without even the implied warranty of
;   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;   GNU General Public License for more details.
;
;   You should have received a copy of the GNU General Public License
;   along with this program; if not, write to 
;     Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;     Boston, MA  02111-1307, USA.
;
;   Visit http://www.pineight.com/ for more information.

.include "nes.inc"
.include "global.inc"
.include "popslide.inc"

.global todo_txt

B_TO_RESET = 0
WITH_EXIT_OPTION = 0

.segment "LIBCODE"
;;
; Displays the text file pointed to at (0)
; starting at (2, 3) on nametable $2000.
.proc display_textfile
src   = $00
dstLo = $05
dstHi = $06
  lda #$20
  sta dstHi
  lda #$62
  sta dstLo
  txt_rowloop:
    jsr undte_line0
    clc
    adc src+0
    sta src+0
    bcc :+
      inc src+1
    :
    lda dstHi
    sta PPUADDR
    lda dstLo
    sta PPUADDR
    clc
    adc #32
    sta dstLo
    bcc :+
      inc dstHi
    :
    ldx #0
    txt_charloop:
      lda dte_output_buf,x
      beq txt_done
      cmp #$0A
      beq is_newline
      sta PPUDATA
      inx
      bne txt_charloop
    is_newline:
    lda dstLo
    cmp #$C0
    lda dstHi
    sbc #$23
    bcc txt_rowloop
  txt_done:
  rts
.endproc

.segment "CODE"
;;
; Initializes Popslide, waits for vblank, turns off rendering, and
; loads the title screen palette.

.proc screen_off_title_palette
  jsr popslide_init
  ldx #>title_palette_stripe
  lda #<title_palette_stripe
  jsr nstripe_append
  lda nmis
  :
    cmp nmis
    beq :-
  lda #VBLANK_NMI
  sta PPUCTRL
  asl a
  sta PPUMASK
  jmp popslide_terminate_blit
.endproc

.proc display_todo
  jsr screen_off_title_palette

  ; clear nametable
  ldx #$20
  txa
  ldy #$FF
  sty cur_keys+0
  iny
  jsr ppu_clear_nt

  lda #>todo_txt
  sta 1
  lda #<todo_txt
  sta 0
  jsr display_textfile

  ;use this when testing a new song
;  lda #4
;  jsr pently_start_music

loop:
  lda nmis
:
  cmp nmis
  beq :-
  ldx #0
  lda #VBLANK_NMI|BG_0000
  ldy #0
  clc
  jsr ppu_screen_on
  jsr pently_update
  jsr read_pads
  jsr title_detect_mice

.if ::B_TO_RESET
  lda new_keys
  and #KEY_B
  beq notB
  jmp ($FFFC)
notB:
.endif

  lda mouseEnabled+0
  beq no_mouse
  lda new_mbuttons+0
  and #MOUSE_L
  bne done
no_mouse:
  lda new_keys
  and #KEY_A|KEY_START
  beq loop
done:
  rts
.endproc

TITLE_NUM_OPTIONS   = 3 + (WITH_EXIT_OPTION <> 0)
TITLE_OPTION_LOG_HT = 4
TITLE_MENU_LEFT   =  48
TITLE_MENU_RIGHT  = 208
TITLE_ARROW_X     =  76
TITLE_MENU_TOP    = 128
TITLE_MENU_BOTTOM = TITLE_MENU_TOP + ((TITLE_NUM_OPTIONS + 1) << TITLE_OPTION_LOG_HT)

.proc titleScreen
  ; display_todo calls the title_detect_mice version of controller
  ; reading, which updates player 1's cursor position as if the
  ; title screen were running.  Though this cursor position is never
  ; displayed, Mesen's debugger still complains that the position
  ; isn't initialized the first time through.
  .if ::PEDANTIC_RAM_INIT
    lda #128
    sta crosshairYHi+0
    sta crosshairXHi+0
  .endif
  jsr display_todo

  ldx #1
  stx numPlayers
  lda #128
  sta crosshairYHi+0
  sta crosshairXHi+0
  jsr screen_off_title_palette

  ldx #$04
  jsr ppu_clear_oam
  ; ldx #0  ; after ppu_clear_oam
  txa
  tay
  ldx #$20
  jsr ppu_clear_nt

  ; Most of the title screen is increasing horizontal runs
  ; Y is still 0
  incstriploop:
    lda titlestrips,y
    iny
    sta PPUADDR
    lda titlestrips,y
    iny
    sta PPUADDR
    ldx titlestrips,y
    iny
    lda titlestrips,y
    iny
    clc
    striptileloop:
      sta PPUDATA
      adc #1
      dex
      bne striptileloop
    cpy #titlestripsend-titlestrips
    bcc incstriploop

  ; The 1, 2, and P down the left side
  lda #<onetwop_stripe
  ldx #>onetwop_stripe
  jsr nstripe_append
  jsr popslide_terminate_blit

  ; Draw last score
  ldy #$62
  ldx score100s
  lda score1s
  jsr title_draw_one_score
  ldy #$78
  ldx hiscore100s
  lda hiscore1s
  jsr title_draw_one_score

loop:
  jsr title_draw_sprites
  lda nmis
:
  cmp nmis
  beq :-
  bit PPUSTATUS
  
  ldy #0
  ldx #>OAM
  sty OAMADDR
  stx OAM_DMA
  ldx #0
  lda #VBLANK_NMI|BG_0000|OBJ_1000
  sec
  jsr ppu_screen_on
  jsr pently_update
  jsr read_pads
  jsr title_detect_mice

s0wait0:
  bit PPUSTATUS
  bvs s0wait0
s0wait1:
  bit PPUSTATUS
  bmi s0waitfail
  bvc s0wait1
  lda #VBLANK_NMI|BG_1000|OBJ_1000
  sta PPUCTRL
s0waitfail:

  jsr title_move_numPlayers
  
.if ::B_TO_RESET
  lda new_keys
  and #KEY_B
  beq notB
  jmp ($FFFC)
notB:
.endif

  ; Let the buttons of the first mouse
  ldx #0
  lda mouseEnabled,x
  bne handleClick
  inx
  lda mouseEnabled,x
  bne handleClick
doneClick:
  lda new_keys+0
  and #(KEY_START | KEY_A)
  beq loop
done:

  .if ::WITH_EXIT_OPTION
    lda numPlayers
    cmp #4
    bcc notExit
      jmp ($FFFC)
    notExit:
  .endif

  ; mix the current time into the rng
  lda nmis
  eor rand3
  clc
  adc rand1
  sta rand1
  ldy #8
  jmp random  ; and off we go, done with the title screen

  ; Appendix: How to handle mouse clicks
handleClick:
  lda new_mbuttons,x
  and #MOUSE_L
  beq doneClick
  lda crosshairYHi+0
  sec
  sbc #TITLE_MENU_TOP
  .repeat ::TITLE_OPTION_LOG_HT
    lsr a
  .endrepeat
  
  ; Row 0: Change speed
  ; Row 1: 1 player; 2: 2 player; 3: Practice
  beq changeSpd
  cmp #TITLE_NUM_OPTIONS+1
  bcs doneClick
  sta numPlayers
  jmp done
changeSpd:
  ldx #0
  lda crosshairXHi+0
  bpl :+
  inx
:
  jsr mouse_change_sensitivity
  jmp doneClick
.endproc

;;
; Checks for the signature of a Super NES Mouse, which is $x1
; on the second read report.
; Stores 0 for no mouse or 1-3 for mouse sensitivity 1/4, 1/2, 1
.proc title_detect_mice
  lda #0
  sta 4
  sta 5
  ldx #1
loop:
  jsr read_mouse
  lda 1
  and #$0F
  cmp #1
  bne notMouse
  lda 2
  sta 4
  lda 3
  sta 5
  lda 1
  and #$30
  lsr a
  lsr a
  lsr a
  lsr a
  clc
  adc #1
  bne isMouse
notMouse:
  lda #0
isMouse:
  sta mouseEnabled,x
  dex
  bpl loop

  ; If a mouse is connected, 4 will have Y motion and 5 will have
  ; X motion
  
  lda 4
  bpl mouseNotDown
  eor #$7F
  clc
  adc #$01
mouseNotDown:
  clc
  adc crosshairYHi+0
  cmp #TITLE_MENU_TOP
  bcs noClipTop
  lda #TITLE_MENU_TOP
noClipTop:
  cmp #TITLE_MENU_BOTTOM-1
  bcc noClipBottom
  lda #TITLE_MENU_BOTTOM-1
noClipBottom:
  sta crosshairYHi+0

  lda 5
  bpl mouseNotLeft
  eor #$7F
  clc
  adc #$01
mouseNotLeft:
  clc
  adc crosshairXHi+0
  cmp #TITLE_MENU_LEFT
  bcs noClipLeft
  lda #TITLE_MENU_LEFT
noClipLeft:
  cmp #TITLE_MENU_RIGHT-1
  bcc noClipRight
  lda #TITLE_MENU_RIGHT-1
noClipRight:
  sta crosshairXHi+0
  rts
.endproc

.proc title_move_numPlayers
  ldx numPlayers
  lda new_keys
  and #KEY_SELECT
  beq notSelect
  inx
  cpx #TITLE_NUM_OPTIONS+1
  bcc notSelect
  ldx #1
notSelect:

  lda new_keys
  and #KEY_DOWN
  beq notDown
  inx
  cpx #TITLE_NUM_OPTIONS+1
  bcc notDown
  dex
notDown:

  lda new_keys
  and #KEY_UP
  beq notUp
  dex
  bne notUp
  inx
notUp:

  stx numPlayers
  rts
.endproc

.proc title_draw_sprites
  ldx #4  ; skip sprite 0

  lda mouseEnabled
  ora mouseEnabled+1
  beq noMouseCrosshair
  lda crosshairYHi+0
  sec
  sbc #5
  sta OAM,x
  lda crosshairXHi+0
  sec
  sbc #4
  sta OAM+3,x
  lda #4
  sta OAM+1,x
  lda #0
  sta OAM+2,x

  inx
  inx
  inx
  inx
noMouseCrosshair:

  ; Draw arrow for number of players
  lda numPlayers
  .repeat ::TITLE_OPTION_LOG_HT
    asl a
  .endrepeat
  adc #TITLE_MENU_TOP+2
  sta OAM+0,x
  lda #SELECTED_ARROW_TILE
  sta OAM+1,x
  lda #1
  sta OAM+2,x
  lda #TITLE_ARROW_X
  sta OAM+3,x
  inx
  inx
  inx
  inx
  
  ldy #1
miceloop:
  lda mouseEnabled,y
  beq not_mouse
  jsr draw_mouse_player_y
not_mouse:
  dey
  bpl miceloop

  ; x = new oam_used value
  jsr ppu_clear_oam

  ; draw sprite 0, used to switch in CHR for "1 Player" text
  ; (which is written in FH, 15px autohinted)
  lda #102
  sta OAM+0
  lda #$01
  sta OAM+1
  lda #$23  ; black sprite on black bg, behind
  sta OAM+2
  lda #172
  sta OAM+3
  rts

draw_mouse_player_y:
  ; Y coordinate
  lda #127
  sta OAM+0,x
  sta OAM+4,x
  sta OAM+8,x
  sta OAM+12,x
  lda #135
  sta OAM+16,x
  sta OAM+20,x
  sta OAM+24,x
  sta OAM+28,x

  ; Tile numbers
  tya
  ora #$60
  sta OAM+1,x
  ora #$10
  sta OAM+17,x
  lda mouseEnabled,y
  clc
  adc #$56
  sta OAM+13,X
  sta OAM+29,x
  lda #$68
  sta OAM+5,x
  lda #$69
  sta OAM+9,x
  lda #$78
  sta OAM+21,x
  lda #$79
  sta OAM+25,x

  ; Colors
  lda #$00
  sta OAM+2,x
  sta OAM+14,x
  sta OAM+18,x
  sta OAM+30,x
  lda #$02
  sta OAM+6,x
  sta OAM+10,x
  sta OAM+22,x
  sta OAM+26,x

  ; X coordinate
  lda mouse_icon_x,y
  sta OAM+3,x
  sta OAM+19,x
  adc #8
  sta OAM+7,x
  sta OAM+23,x
  adc #8
  sta OAM+11,x
  sta OAM+27,x
  ; and the speed lines
  adc #6
  sta OAM+15,x
  adc #1
  sta OAM+31,x

  txa
  clc
  adc #32
  tax
  rts
.endproc

;;
; Draws X hundreds and A ones to $2300+Y
.proc title_draw_one_score
highDigits = $00
draw_digitbase = $01

  pha
  lda #$23
  sta PPUADDR
  sty PPUADDR
  lda #$00
  sta draw_digitbase
  txa
  jsr do2dig
  pla
do2dig:
  jsr bcd8bit
  pha
  lda highDigits
  jsr do1dig
  pla
do1dig:
  beq :+
    ldy #$40
    sty draw_digitbase
  :
  ora draw_digitbase
  sta PPUDATA
  rts
.endproc


.segment "RODATA"
; backdrop: black
; bg0: dark gray, light gray, white
; bg1: brown, red, white
; bg2: brown, green, white
; bg3: brown, blue, white
; obj0: blue, light blue, ? (player 1 crosshair and presents)
; obj1: red, orange, pale yellow (player 2 crosshair, missiles, balloons, and explosions)
; obj2: red, green, peach (villagers)
; obj3: gray, orange, peach (villagers, smoke)

title_palette_stripe:
  .dbyt $3F00
  .byt 32-1
  .byt $0F,$00,$10,$20, $0F,$17,$16,$20, $0F,$17,$2A,$20, $0F,$17,$12,$20
  ;    grayscale        arrow            mouse            sprite 0
  .byt $0F,$00,$10,$20, $0F,$16,$27,$38, $0F,$00,$10,$13, $0F,$0F,$0F,$0F
  .byt $FF

mouse_icon_x:
  .byt 92, 140

titlestrips:
  ; start address

  ; Tops of "t" and "h"
  .dbyt $2128,$01F1
  .dbyt $212A,$01F2
  .dbyt $2133,$01F1
  ; "t"
  .dbyt $2148,$02DC
  .dbyt $2168,$02EC
  .dbyt $2188,$02FC
  ; "hwaite"
  .dbyt $214A,$0DD3
  .dbyt $216A,$0DE3
  .dbyt $218A,$0DF3
  ; "Player", "Players", "ractice"
  .dbyt $224D,$0562
  .dbyt $226D,$0572
  .dbyt $228D,$0662
  .dbyt $22AD,$0672
  .dbyt $22CC,$066A
  .dbyt $22EC,$067A
  .if WITH_EXIT_OPTION
    .dbyt $230B,$044C
    .dbyt $232B,$045C
  .endif
titlestripsend:

onetwop_stripe:
  .dbyt $224B
  .byt (6-1)|NSTRIPE_DOWN
  .byt $60,$70,$61,$71,$62,$72

  .dbyt $2366
  .byt (2-1)|NSTRIPE_RUN
  .byt $40
  .dbyt $2374
  .byt (2-1)
  .byt $30,$31  ; HI:
  .dbyt $237C
  .byt (2-1)|NSTRIPE_RUN
  .byt $40
  .byt $FF
