; cutscene.s
; Cut scene code and character data for Thwaite

;;; Copyright (C) 2011-2018 Damian Yerrick
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
.import cut_scripts

.segment "ZEROPAGE"
script_ptr: .res 2
name_interp_pos: .res 1
decomp_buf_pos: .res 1
cutscene_vram_dst_lo: .res 1
cutscene_vram_dst_hi: .res 1
cutscene_x_scroll: .res 1
cutscene_x_scroll_target: .res 1
; cutStateTimer = tipTimeLeft

CUT_STATE_SCRIPT = 0
CUT_STATE_WAIT_A = 2
CUT_STATE_CLS = 4
CUT_STATE_NEW_GRAPH = 6

PRESS_A_MARKER_Y = 184
FADEIN_SPEED = 3
FADEIN_START = $3F
FADEOUT_SPEED = 4
FADEOUT_END = $30
HOUSES_TOPLEFT = $2181
DIALOGUE_TOPLEFT = $22A2

.segment "BSS"

cutFadeDir: .res 1
cutFadeAmount: .res 1
variable_actor_ids: .res 3
actor_paranoid = variable_actor_ids
actor_detective = variable_actor_ids + 1
actor_laidback = variable_actor_ids + 2
cutscene_actors: .res 4

.segment "CODE"

.if CUT_SCROLL_DEBUGGING
.proc rechoose_scroll
  ; Set initial scroll position
  ldy houseToRebuild
  iny
  cpy #NUM_BUILDINGS
  bcc :+
    ldy #0
  :
  sty houseToRebuild
  lda houseScrollX,y
  sta cutscene_x_scroll_target
  sta cutscene_x_scroll
  rts
.endproc
.endif

.proc load_cutscene_bg

  ; Set initial scroll position
  ldy houseToRebuild
  bpl :+
    ldy #BUILDING_SILO1
  :
  lda houseScrollX,y
  sta cutscene_x_scroll_target
  eor #$80
  sta cutscene_x_scroll

  lda #<-FADEIN_SPEED
  sta cutFadeDir
  lda #FADEIN_START
  sta cutFadeAmount

  ; turn off rendering
  lda #VBLANK_NMI
  sta PPUCTRL
  asl a
  sta PPUMASK

  jsr popslide_init
  jsr cut_draw_skyground
  jsr cut_draw_dialogue_frame
  jsr popslide_terminate_blit
  jsr cut_draw_buildings

  ; load the sprite table (trees and the like)
  ldx #cutscene_init_oam_end - cutscene_init_oam - 1
oamcopyloop:
  lda cutscene_init_oam,x
  sta OAM,x
  dex
  bne oamcopyloop
  lda cutscene_init_oam
  sta OAM+0
  ldx #cutscene_init_oam_end - cutscene_init_oam
  jmp ppu_clear_oam
.endproc

SKY_TILE = $00
FLOOR_TILE = $C7
GRASS_TILE = $04
; rows 5-14: sky
; row 15: floor
; rows 16-17: grass
.proc cut_draw_skyground
  lda #$03
  ldy #$00
  ldx #$20
  jsr ppu_clear_nt
  ldx #$24
  jsr ppu_clear_nt
  ldx #$20
  jsr oneside
  ldx #$24

oneside:
  ; $23D8 and $27D8: attributes for houses
  txa
  ora #$03
  sta PPUADDR
  lda #$D8
  sta PPUADDR

  ; First NT: FF55AAFFFF55AAFF
  ; Second NT: 55AAFF5555AAFF55
  txa  ; $FF first NT, $55 second NT
  and #$04
  beq :+
    lda #$AA
  :
  eor #$FF
  jsr halfattr
  jsr halfattr

  ; Now that attributes are done, write the tilemap proper.
  ; Top letterbox
  stx PPUADDR
  ; ldy #0
  sty PPUADDR
  lda #1
  ldy #32*5/2
  jsr wr_2y_bytes

  ; Sky
  ldy #32*10/2
  lda #SKY_TILE
  jsr wr_2y_bytes
  ; Ground
  ldy #32/2
  lda #FLOOR_TILE
  jsr wr_2y_bytes
  ; Grass
  lda #GRASS_TILE
  jsr onegrass
  lda #GRASS_TILE+2
onegrass:
  ldy #32
  clc
  grassloop:
    sta PPUDATA
    adc #1
    and #$03
    ora #GRASS_TILE
    dey
    bne grassloop
  rts

halfattr:
  sta PPUDATA
  ldy #3
  attrcell:
    clc
    adc #$55
    bcc :+
      lda #$55
    :
    sta PPUDATA
    dey
    bne attrcell
  rts

wr_2y_bytes:
  sta PPUDATA
  sta PPUDATA
  dey
  bne wr_2y_bytes
  rts
.endproc

.proc cut_draw_buildings
housesrc = $00
bldg_id = $02
opaquebits = $03

  ldx #NUM_BUILDINGS-1
bldgloop:
  stx bldg_id

  ; Find building top left corner
  ; $2180-$219E for houses with X=0-15
  ; $2580-$259E for houses with X=0-15
  lda houseX,x
  and #$10
  lsr a
  lsr a
  ora #$21
  sta cutscene_vram_dst_hi
  lda houseX,x
  and #$0F
  asl a
  ora #$80
  sta cutscene_vram_dst_lo

  ; Find building tile definition
  lda housesStanding,x
  cmp #1
  lda houseShape,x
  bcs :+
    lda #$8C
  :
  asl a
  asl a  ; 0, 8, 16, ..., 48
  adc #<houseShapeBig
  sta housesrc+0
  lda #0
  adc #>houseShapeBig
  sta housesrc+1

  ldy #0
  rowloop:
    lda cutscene_vram_dst_hi
    sta PPUADDR
    lda cutscene_vram_dst_lo
    sta PPUADDR
    clc
    adc #32
    sta cutscene_vram_dst_lo
    lda (housesrc),y
    iny
    sta opaquebits
    lda (housesrc),y
    iny
    ldx #4
    tileloop:
      asl opaquebits
      bcc isxparent
        sta PPUDATA
        clc
        bcc afterwrite
      isxparent:
        bit PPUDATA
      afterwrite:
      adc #1
      dex
      bne tileloop
    cpy #8
    bcc rowloop

  ldx bldg_id
  dex
  bpl bldgloop
  rts
.endproc

.proc cut_draw_dialogue_frame
  ldy #0
  ldx popslide_used
  copyloop:
    lda dialogue_frame_strips,y
    sta popslide_buf,x
    inx
    iny
    cpy #dialogue_frame_strips_end-dialogue_frame_strips
    bcc copyloop
  stx popslide_used
.endproc
.proc cut_clear_dialogue
  lda #$81
  sta cutscene_vram_dst_lo
  ; Add 4 Popslide packets, one to clear each line of text
  ldy #4
  ldx popslide_used
  rowloop:
    lda #>DIALOGUE_TOPLEFT
    sta popslide_buf+0,x
    lda cutscene_vram_dst_lo
    sta popslide_buf+1,x
    clc
    adc #32
    sta cutscene_vram_dst_lo
    lda #29|$40
    sta popslide_buf+2,x
    lda #' '
    sta popslide_buf+3,x
    inx
    inx
    inx
    inx
    dey
    bne rowloop
  stx popslide_used
  rts
.endproc

.proc cut_draw_trees
treexpos = $00
  ldy #8
  lda #116
  jsr one_tree
  lda #164
one_tree:
  sec
  sbc cutscene_x_scroll
  sta treexpos
  ldx #tree_oam_end-tree_oam-4
  oamloop:
    lda tree_oam+3,x
    clc
    adc treexpos
    sta OAM+3,y
    lda tree_oam+2,x
    sta OAM+2,y
    lda tree_oam+1,x
    sta OAM+1,y
    lda tree_oam+0,x
    sta OAM+0,y
    iny
    iny
    iny
    iny
    dex
    dex
    dex
    dex
    bpl oamloop
  rts
.endproc

.proc load_cutscene
  asl a
  tax
  lda cut_scripts,x
  sta script_ptr
  lda cut_scripts+1,x
  sta script_ptr+1

  jsr pently_update
  lda nmis
vw1:
  cmp nmis
  beq vw1

  jsr load_cutscene_bg

; Load the actors
  ldy #0
  load_actors_loop:
    lda (script_ptr),y
    sta cutscene_actors,y
    iny
    cpy #4
    bcc load_actors_loop
  clc
  tya
  adc script_ptr
  sta script_ptr
  bcc :+
    inc script_ptr+1
  :
  jsr cut_handle_state_new_graph

  lda #MUSIC_1600
  jsr pently_start_music

main_loop:
  jsr pently_update

  lda cutFadeAmount
  beq doneFading
    and #$30
    sta $00
    ldx popslide_used
    lda #$3F
    sta popslide_buf,x
    lda #$01
    sta popslide_buf+1,x
    tay
    lda #$1E
    sta popslide_buf+2,x
    txa
    clc
    adc #34
    sta popslide_used

    palloop:
      lda cutscene_palette,y
      sec
      sbc $00
      bpl palNotNeg
      cmp #$F0
      bne palNotF0
      lda #$02
      bne palNotNeg
    palNotF0:
      lda #$0F
    palNotNeg:
      sta popslide_buf+3,x
      inx
      iny
      cpy #$20
      bcc palloop
    bcs skipHandleScript
  doneFading:
    jsr cut_handle_state
  skipHandleScript:

  ; Move the camera
  lda nmis
  lsr a
  bcs no_update_scroll
  lda cutscene_x_scroll_target
  cmp cutscene_x_scroll
  beq no_update_scroll
    lda #0
    adc #$FF
    ora #$01
    clc
    adc cutscene_x_scroll
    sta cutscene_x_scroll
  no_update_scroll:
  jsr cut_draw_trees

  lda nmis
  vw:
    cmp nmis
    beq vw

  lda #>OAM
  ldy #0
  sty OAMADDR
  sta OAM_DMA
  jsr popslide_terminate_blit
  lda #VBLANK_NMI|BG_1000|OBJ_1000
  ldy #0
  ldx cutscene_x_scroll
  sec
  jsr ppu_screen_on

  jsr read_pads
  lda mouseEnabled+0
  beq no_read_mouse
    ldx #0
    jsr read_mouse
  no_read_mouse:

  .if ::CUT_SCROLL_DEBUGGING
    lda new_keys
    and #KEY_RIGHT
    beq notRight
      jsr rechoose_scroll
    notRight:
  .endif

  lda new_keys
  and #KEY_START
  beq notStart
    lda #FADEOUT_SPEED
    sta cutFadeDir
  notStart:

  ; Wait for sprite 0
  s0wait0:
    bit $2002
    bvs s0wait0
  s0wait1:
    bit $2002
    bmi s0waitfail
    bvc s0wait1
  ; Change the bank immediately; change the scroll 16 lines later
  lda #VBLANK_NMI|BG_0000|OBJ_1000
  sta PPUCTRL
  ldy #16*341/3/8
  posts0wait:
    bit $00
    dey
    bne posts0wait
  lda #0
  sta PPUSCROLL
  bit PPUSTATUS
  
s0waitfail:

  ; Adjust fade amount
  lda cutFadeDir
  clc
  adc cutFadeAmount
  sta cutFadeAmount
  and cutFadeDir
  bpl notWrappedToNeg
    lda #0
    sta cutFadeAmount
    sta cutFadeDir
  notWrappedToNeg:
  
  lda cutFadeDir
  bmi not_fading_out
    lda cutFadeAmount
    cmp #FADEOUT_END
    bcs bail
  not_fading_out:
  jmp main_loop
bail:
  jmp pently_stop_music

.endproc

.proc cut_handle_state
  lda #$FF
  sta OAM+4  ; Y coordinate of A Button indicator
  ldx gameState
  lda handlers+1,x
  pha
  lda handlers,x
  pha
  rts
.pushseg
.segment "RODATA"
handlers:
  .addr cut_handle_state_script-1
  .addr cut_handle_state_wait_a-1
  .addr cut_handle_state_cls-1
  .addr cut_handle_state_new_graph-1
.popseg
.endproc

.proc cut_handle_state_script
  ; is a name (e.g. $X) being interpolated?
  ldy name_interp_pos
  cpy #$FF
  beq no_name_interp
    inc name_interp_pos
    lda character_name0,y
    bne have_codeunit
    lda #$FF
    sta name_interp_pos
  no_name_interp:
  ldy decomp_buf_pos
  inc decomp_buf_pos

  ; NUL: Stop the script, then wait for pressing A
  lda dte_output_buf,y
  bne not_nul
    sta script_ptr+1
  goto_A_press:
    lda #CUT_STATE_WAIT_A
    sta gameState
    rts
  not_nul:

  ; Form feed: Wait for pressing A
  cmp #12
  beq goto_A_press

  ; Newline: Move cursor to next line and decompress another
  ; line of text
  cmp #10
  bne not_newline
    lda cutscene_vram_dst_lo
    and #%11100000
    clc
    adc #32+(DIALOGUE_TOPLEFT & $1F)
    sta cutscene_vram_dst_lo
    bcc :+
      inc cutscene_vram_dst_hi
    :
    jmp cut_load_line
  not_newline:

  ; Anything but dollar: Write a single code unit
  cmp #'$'
  beq is_dollar

  have_codeunit:
    ldx popslide_used
    sta popslide_buf+3,x
    lda cutscene_vram_dst_hi
    sta popslide_buf+0,x
    lda cutscene_vram_dst_lo
    inc cutscene_vram_dst_lo
    sta popslide_buf+1,x
    lda #0
    sta popslide_buf+2,x
    txa
    clc
    adc #4
    sta popslide_used
    rts
  is_dollar:

  ; load a character name
  iny
  lda dte_output_buf,y
  inc decomp_buf_pos
  jsr cut_translate_actorid
  clc
  tax
  lda character_name_offset,x
  sta name_interp_pos
  jmp cut_handle_state_script
.endproc

.proc cut_handle_state_wait_a
  ; Flash A Button indicator into place
  lda nmis
  and #%00011000
  beq no_show_marker
  lda #PRESS_A_MARKER_Y - 1
  sta OAM+4
no_show_marker:
  lda mouseEnabled
  beq not_pressed_lmb
    lda new_mbuttons
    and #MOUSE_L
    bne pressed_A
  not_pressed_lmb:
  lda #KEY_A
  and new_keys
  beq not_pressed_A
  pressed_A:

    ; If the script has ended (high byte 0), go to fadeout.
    ; Otherwise clear the screen and load the next paragraph.
    lda script_ptr+1
    bne cut_handle_state_cls
    lda #FADEOUT_SPEED
    sta cutFadeDir
  not_pressed_A:
  rts
.endproc

.proc cut_handle_state_cls
  jsr cut_clear_dialogue
.endproc
.proc cut_handle_state_new_graph
src = 0

  ; Fetch the speaker's name
  ldy #0
  lda (script_ptr),y
  inc script_ptr
  bne :+
    inc script_ptr+1
  :
  jsr cut_translate_actorid

  ; Fetch the speaker's name
  cmp #NUM_SPEAKERS
  bcc :+
    lda #NUM_SPEAKERS - 1
    clc
  :
  tax
  lda #<character_name0
  adc character_name_offset,x
  sta src
  lda #>character_name0
  adc #0
  sta src+1

  ; Form a Popslide packet of the following form:
  ; 0-1: address; 2: strlen+1; 3: '<'; 4:4+strlen: name; 4+strlen: '>'
  ; Because names are nul-terminated, the length shall be written last.

  ; Write address
  ldx popslide_used
  lda #>DIALOGUE_TOPLEFT
  sta popslide_buf+0,x
  sta cutscene_vram_dst_hi
  lda #<DIALOGUE_TOPLEFT - 32 - 1
  sta popslide_buf+1,x
  lda #<DIALOGUE_TOPLEFT
  sta cutscene_vram_dst_lo

  ; Write name
  lda #'<'
  sta popslide_buf+3,x
  ldy #0
  loop:
    lda (0),y
    beq nul
    sta popslide_buf+4,x
    inx
    iny
    bne loop
  nul:
  lda #'>'
  sta popslide_buf+4,x

  ; Write length
  txa
  clc
  adc #5
  ldx popslide_used
  sta popslide_used
  iny
  tya
  sta popslide_buf+2,x

  lda #CUT_STATE_SCRIPT
  sta gameState
  ; and fall through to
.endproc

;;
; Decompresses 1 line of text
.proc cut_load_line
  lda script_ptr
  sta $00
  lda script_ptr+1
  sta $01
  jsr undte_line0
  clc
  adc $00
  sta script_ptr
  lda #0
  sta decomp_buf_pos
  adc $01
  sta script_ptr+1
  lda #$FF
  sta name_interp_pos
  rts
.endproc

;;
; Translates a role letter ('A'-'Z') into a name id (0-22).
; Trashes Y.
; @param A role letter
; @return name id
.proc cut_translate_actorid
  sec
  sbc #'A'
  cmp #'X'-'A'
  bcc not_role
  sbc #'X'-'A'
    tay
    lda variable_actor_ids,y
  not_role:
  rts
.endproc

;;
; Chooses three villagers at random to fit the three roles in the
; game's script, according to the villagers' personalities.
; Allows forcing choice of one of them as the paranoid one,
; which occurs at the start of the non-100% track.
; @param X 1 for game start, 0 for already having chosen paranoid
.proc cut_choose_villagers
randacc = 3

  ldy #6
  jsr random
  lda rand3
  sta randacc
  cpx #0
  beq alreadyParanoid

  ; choose the paranoid one
  jsr randpull3
  tax
  lda paranoid_characters,x
  sta actor_paranoid
alreadyParanoid:

  ; choose the laid-back one
  jsr randpull3
  tax
  lda laidback_characters,x
  cmp actor_paranoid
  bne laidback_is_ok
  
  ; if the laid-back is the same person as the paranoid (which
  ; could happen by promotion after the old laid-back's house
  ; was destroyed), get a new laid-back
  ldy #1
  jsr random
  lda rand3
  lsr a  ; carry is randomly 0 or 1
  txa
  adc #1  ; a is randomly x + 1 or x + 2
  cmp #3
  bcc laidback_no_wrap
  sbc #3
laidback_no_wrap:
  tax
  lda laidback_characters,x
laidback_is_ok:
  sta actor_laidback

  ; choose the detective
  ldy #2
  jsr random
  lda #%00000011
  and rand3
  tax
  lda detective_characters,x
  sta actor_detective
  
  ; if the detective is the same person as the paranoid (which
  ; could happen by promotion after the old detective's house
  ; was destroyed), get a new detective
  cmp actor_paranoid
  beq find_another_detective

  ; if all three are the same sex, also get a new detective
  tay
  lda character_sex,y
  ldy actor_laidback
  eor character_sex,y
  bmi opposite_sexes
  ldy actor_laidback
  lda character_sex,y
  ldy actor_paranoid
  eor character_sex,y
  bmi opposite_sexes

  ; then find another detective.  They're arranged in the list
  ; alternating by sex, so xor 
find_another_detective:
  txa
  eor #%00000001
  tax
  lda detective_characters,x
  sta actor_detective
opposite_sexes:

  rts

randpull3:
  lda randacc
  and #%00111111
  sta randacc
  asl randacc
  adc randacc
  sta randacc
  and #%11000000
  asl a
  rol a
  rol a
  rts  
.endproc

.segment "RODATA"

houseScrollX:
  .byte 16, 24,   40,   88, 104, 120, 136, 152, 168,   216,   232, 240

dialogue_frame_strips:
  .dbyt $2261,$40B0  ; Top row
  .dbyt $2262,$5BB8
  .dbyt $227E,$40B1
  .dbyt $2301,$40B6  ; Bottom row
  .dbyt $2302,$5BBB
  .dbyt $231E,$40B7
  .dbyt $2280  ; Left side
  .byte $83,$B2,$B9,$B9,$B4
  .dbyt $229F  ; Right side
  .byte $83,$B3,$BA,$BA,$B5
  .dbyt $21AC  ; Tree trunks
  .byte $82,$F4,$F4,$F6
  .dbyt $21AD
  .byte $82,$F5,$F5,$F7
  .dbyt $21B2
  .byte $82,$F4,$F4,$F6
  .dbyt $21B3
  .byte $82,$F5,$F5,$F7
  .dbyt $25AC
  .byte $82,$F4,$F4,$F6
  .dbyt $25AD
  .byte $82,$F5,$F5,$F7
  .dbyt $25B2
  .byte $82,$F4,$F4,$F6
  .dbyt $25B3
  .byte $82,$F5,$F5,$F7
dialogue_frame_strips_end:


houseShapeBig:
  .word $C0F0,$D0F0,$E0F0,$F0F0  ; house shape $80
  .word $C4E0,$D4F0,$E4F0,$FCF0  ; house shape $82
  .word $C8F0,$D8F0,$E8F0,$F8F0  ; house shape $84
  .word $CC70,$DCF0,$ECF0,$FCF0  ; house shape $86
  .word $80F0,$90F0,$A0F0,$B0F0  ; left silo
  .word $8460,$94F0,$A4F0,$B4F0  ; right silo
  .word $0000,$0000,$B8F0,$BCF0  ; destroyed house

cutscene_init_oam:
  .byt 126,$01,$21,248  ; sprite 0 for CHR split
  .byt 255,$56,$02,232  ; last entry is "press A" marker
cutscene_init_oam_end:

tree_oam:
  .byt 118,$55,$01,240  ; trunk
  .byt 110,$54,$01,240
  .byt 102,$55,$81,240
  .byt  95,$52,$20,232  ; leafy parts
  .byt  95,$53,$20,240
  .byt  95,$52,$60,248
  .byt  87,$50,$20,232
  .byt  87,$51,$20,240
  .byt  87,$50,$60,248
  .byt  79,$50,$20,236
  .byt  79,$50,$60,244
tree_oam_end:

cutscene_palette:
  .byt $22,$18,$2A,$0F  ; grass and text
  .byt $22,$20,$16,$08  ; houseR
  .byt $22,$20,$2A,$08  ; houseG
  .byt $22,$20,$12,$08  ; houseB
  .byt $22,$1A,$2A,$26  ; tree, people (green)
  .byt $22,$17,$27,$26  ; tree trunk
  .byt $22,$16,$12,$26  ; people 1
  .byt $22,$00,$10,$26  ; clouds, people 2

character_name_offset:
  .byt character_name0-character_name0
  .byt character_name1-character_name0
  .byt character_name2-character_name0
  .byt character_name3-character_name0
  .byt character_name4-character_name0
  .byt character_name5-character_name0
  .byt character_name6-character_name0
  .byt character_name7-character_name0
  .byt character_name8-character_name0
  .byt character_name9-character_name0
  .byt character_name10-character_name0
  .byt character_name11-character_name0
  .byt character_name12-character_name0
  .byt character_name13-character_name0
NUM_SPEAKERS = * - character_name_offset

il = $1F

character_name0:  .byt "T",il,"da",0
character_name1:  .byt "Meg",0
character_name2:  .byt "M",il,"o",0    ; Player 1
character_name3:  .byt "Isca",0
character_name4:  .byt "Gnivad",0
character_name5:  .byt "Justin",0
character_name6:  .byt "Briar",0
character_name7:  .byt "Acha",0
character_name8:  .byt "Torben",0
character_name9:  .byt "Staisy",0  ; Player 2
character_name10: .byt "Thad",0
character_name11: .byt "Oliver",0
character_name12: .byt "L.T.D.",0  ; Traveling musician
character_name13: .byt "Pino",0    ; Voice on phone

; $00 for male, $80 for female
character_sex: .byt $80,$80, $00, $80,$00,$00,$80,$80,$00, $80, $00,$00
paranoid_characters:  .byt 0, 6, 8
laidback_characters:  .byt 1, 5, 10
detective_characters: .byt 3, 4, 7, 11
