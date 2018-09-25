; practice.s
; Practice mode for Thwaite

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

.segment "RODATA0"
practice_txt:
  .incbin "src/practice.txt"
  .byt 0
.segment "ZEROPAGE"
isPractice:   .res 1
practiceSide: .res 1
practiceDay:  .res 1
practiceHour: .res 1

.segment "CODE"

.proc practice_menu
  lda practiceDay
  sta gameDay
  lda practiceHour
  sta gameHour
  lda #2
  sta isPractice
  lda #STATE_NEW_LEVEL
  sta gameState
  jsr setupGameBG
  lda #<practice_txt
  sta 0
  lda #>practice_txt
  sta 1
  jsr display_textfile
loop:
  ldx #0
  stx oam_used
  jsr moveCrosshairPlayerX
  jsr drawCrosshairPlayerX
  jsr drawPracticeMenuSprites
  ldx oam_used
  jsr ppu_clear_oam
  jsr buildBGUpdate
  jsr update_sound

  lda nmis
:
  cmp nmis
  beq :-
  ; it's vblank!
  jsr blitBGUpdate
  lda #0
  sta PPUSCROLL
  sta PPUSCROLL
  sta OAMADDR
  lda #>OAM
  sta OAM_DMA
  lda #VBLANK_NMI|BG_0000|OBJ_1000
  sta PPUCTRL
  lda #BG_ON|OBJ_ON
  sta PPUMASK

  jsr read_pads
  jsr mouse_to_vel
  lda new_keys
  and #KEY_A|KEY_B
  beq noClick
  jsr practiceDoClick
  
noClick:

  lda gameState
  cmp #STATE_NEW_LEVEL
  bne noReloadLevel
  jsr practiceSetSide
  jsr doStateNewLevel
  lda #BG_DIRTY_STATUS|BG_DIRTY_HOUSES|BG_DIRTY_PRACTICE_METER
  ora bgDirty
  sta bgDirty
noReloadLevel:

  lda new_keys
  and #KEY_START
  beq notStart
  lda #1
  sta isPractice
notStart:

  lda isPractice
  lsr a
  bne loop

  ; clear the tip so that doStateLevelReward won't
  ; kick us out prematurely
  lda #0
  sta curTip
  lda #STATE_NEW_LEVEL
  sta gameState
  rts
.endproc

.proc practiceDoClick
  lda crosshairYHi
  cmp #$24
  bcc noClick1
  cmp #$34
  bcs noDayClick
  
  ; handle day click
  lda crosshairXHi
  sec
  sbc #60
  lsr a
  lsr a
  lsr a
  lsr a
  cmp #7
  bcs noClick1
  sta practiceDay
  sta gameDay
  lda #STATE_NEW_LEVEL
  sta gameState
noClick1:
  rts
noDayClick:

  cmp #$44
  bcs noHourClick

  ; handle hour click
  lda crosshairXHi
  sec
  sbc #60
  lsr a
  lsr a
  lsr a
  lsr a
  cmp #5
  bcs noClick1
  sta practiceHour
  sta gameHour
  lda #STATE_NEW_LEVEL
  sta gameState
  rts
noHourClick:

  cmp #$5C
  bcc noClick1
  cmp #$7C
  bcs noSideClick
  sbc #$5C
  and #$10
  beq :+
  lda #1
:
  sta 0
  lda crosshairXHi
  sec
  sbc #$38
  bmi noClick2
  cmp #$30
  lda 0
  rol a
  sta practiceSide
  lda #STATE_NEW_LEVEL
  sta gameState
  rts
  
noSideClick:
  cmp #$8C
  bcs noClick2
  lda crosshairXHi
  cmp #176
  bcs noClick2
  cmp #92
  lda #0
  rol a
  sta isPractice
  
noClick2:
  rts

.endproc

.proc practiceSetSide
firstHouseOK = 0
lastHouseOK = 1

  ; side 0: through 6; otherwise through 12
  lda #12
  ldy practiceSide  ; keep side in y
  bne :+
  lda #6
:
  sta lastHouseOK

  ; side 1: start at 6; otherwise start at 0
  lda #0
  cpy #1
  bne :+
  lda #6
:
  sta firstHouseOK

  ; side 3: 2 players; otherwise 1 player
  lda #1
  cpy #3
  bne :+
  lda #2
:
  sta numPlayers

  ldy #11
sethouseloop:
  lda #0
  cpy firstHouseOK
  bcc houseNotOK
  cpy lastHouseOK
  bcs houseNotOK
  lda #1
houseNotOK:
  sta housesStanding,y
  dey
  bpl sethouseloop
  rts

.endproc


.proc drawPracticeMenuSprites
  ldx oam_used

  lda #39
  sta OAM,x
  lda #55
  sta OAM+4,x
  lda practiceSide
  and #$02
  asl a
  asl a
  asl a
  adc #95
  sta OAM+8,x

  ; set x coords
  lda gameDay
  asl a
  asl a
  asl a
  asl a
  adc #60
  sta OAM+3,x
  lda gameHour
  asl a
  asl a
  asl a
  asl a
  adc #60
  sta OAM+7,x
  lda practiceSide
  and #$01
  beq :+
  lda #48
:
  clc
  adc #60
  sta OAM+11,x
  
  lda #SELECTED_ARROW_TILE
  sta OAM+1,x
  sta OAM+5,x
  sta OAM+9,x
  lda #%00100001  ; behind; color set 1
  sta OAM+2,x
  sta OAM+6,x
  sta OAM+10,x

  txa
  clc
  adc #12
  tax

; At this point, draw the possible salvos

salvoID = 0
salvoY = 1
salvoX = 2

  lda #0
  sta salvoID
  lda #39
  sta salvoY
salvoLoop:
  lda #192
  sta salvoX
  ldy salvoID
  lda levelSalvoSizes,y
  cmp #8
  beq isBalloon
  bcs isMIRV

  ; Regular missiles; draw each
  tay
salvoElLoop:
  lda #$0A
mirvFinish:
  sta OAM+1,x
  lda salvoY
  sta OAM+0,x
  lda #$01
  sta OAM+2,x
  lda salvoX
  sta OAM+3,x
  clc
  adc #6
  sta salvoX
  inx
  inx
  inx
  inx
  dey
  bne salvoElLoop
  lda #12
  bne salvoAddToY

isMIRV:
  ldy #1
  lda #$1A
  bne mirvFinish

isBalloon:
  lda salvoY
  sta OAM+0,x
  clc
  adc #8
  sta OAM+4,x
  lda #$06
  sta OAM+1,x
  lda #$16
  sta OAM+5,x
  lda #$01
  sta OAM+2,x
  lsr a
  sta OAM+6,x
  lda salvoX
  sta OAM+3,x
  sta OAM+7,x
  txa
  clc
  adc #8
  tax
  lda #20

salvoAddToY:
  clc
  adc salvoY
  sta salvoY
  inc salvoID
  lda salvoID
  cmp #4
  bcc salvoLoop
  stx oam_used
  rts
.endproc

