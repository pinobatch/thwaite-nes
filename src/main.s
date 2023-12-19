; main.s
; Main program for Thwaite

;;; Copyright (C) 2011,2018 Damian Yerrick
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
.p02
.segment "ZEROPAGE"
psg_sfx_state: .res 32
.export psg_sfx_state

LAWN_MOWER_NMI = 0

.if LAWN_MOWER_NMI
  nmis_old: .res 1  ; Using nmis from lawn mower
  nmis = $FF
.else
  nmis: .res 1
.endif
oam_used: .res 1
debugHex1: .res 1
debugHex2: .res 1
cur_keys: .res 2
new_keys: .res 2
gameState: .res 1
numPlayers: .res 1
tvSystem: .res 1
mouseEnabled: .res 2

housesLeftClass: .res 1
investigationStep: .res 1

PROFILE_LIGHTGRAY = 0

; If this is nonzero, the game will start at 5 AM instead of 1 AM,
; allowing certain cut scene related things to be tested faster.
; Always set to 0 for release builds.
START_AT_5AM = 0

; When debugging villager selection, allow forcing the choice of one
; villager as the paranoid.
; Always set to 0 for release builds.
FORCE_PARANOID = 0

; When debugging cut scenes and shit, 
; Always set to 0 for release builds.
ONE_MISSILE_PER_LEVEL = 0

.segment "VECTORS"
  .addr nmi, reset, irq

.segment "CODE"

; we don't use irqs yet
.proc irq
  rti
.endproc

; tokumaru thinks only simple little single-screen puzzle games
; can get away with waiting for vblank
; https://forums.nesdev.com/viewtopic.php?t=6229
; and he isn't a big fan of simple little single-screen puzzle games
; https://forums.nesdev.com/viewtopic.php?t=5927
; https://forums.nesdev.com/viewtopic.php?p=59105#p59105
; but my philosophy is to do the simplest thing that could work
; http://c2.com/xp/DoTheSimplestThingThatCouldPossiblyWork.html
; and without a status bar, 'inc nmis' is the simplest thing because
; there isn't much of a penalty for missing a vblank
.proc nmi
  inc nmis
  rti
.endproc

.proc reset
  sei

  ; Acknowledge and disable interrupt sources during bootup
  ldx #0
  stx PPUCTRL    ; disable vblank NMI
  stx PPUMASK    ; disable rendering (and rendering-triggered mapper IRQ)
  lda #$40
  sta $4017      ; disable frame IRQ
  stx $4010      ; disable DPCM IRQ
  bit PPUSTATUS  ; ack vblank NMI
  bit $4015      ; ack DPCM IRQ
  cld            ; disable decimal mode to help generic 6502 debuggers
                 ; http://magweasel.com/2009/08/29/hidden-messagin/
  dex            ; set up the stack
  txs

  ; Wait for the PPU to warm up (part 1 of 2)
vwait1:
  bit PPUSTATUS
  bpl vwait1

  ; While waiting for the PPU to finish warming up, we have about
  ; 29000 cycles to burn without touching the PPU.  So we have time
  ; to initialize some of RAM to known values.
  ; Ordinarily the "new game" initializes everything that the game
  ; itself needs, so we'll just do zero page.
  ldx #$00
  txa
clear_zp:
  sta $00,x
  .if ::PEDANTIC_RAM_INIT
    ; If the Y coordinate is out of bounds ($F0-$FF), the tile,
    ; color/flip, and X bytes of the same entry will never be used,
    ; but Mesen complains anyway when copying shadow OAM to OAM.
    ; Initialize shadow OAM to all $00 while looking for more serious
    ; uninitialized RAM issues.
    sta OAM,x
  .endif
  inx
  bne clear_zp
  sta score100s
  sta score1s
  sta hiscore100s
  sta hiscore1s

  jsr pently_init
  
  lda #2
  sta practiceSide
  sta rand1
  sta rand2
  sta rand3
  sta rand0
  
  ; Wait for the PPU to warm up (part 2 of 2)
  ; after which all vblank waiting is through NMI
vwait2:
  bit PPUSTATUS
  bpl vwait2
  
  lda #VBLANK_NMI
  sta PPUCTRL

  jsr getTVSystem
  sta tvSystem
restart:
  jsr pently_stop_music
  
  lda isPractice
  bne practice_skiptitle
  jsr titleScreen
  lda numPlayers
  cmp #3
  bcc practice_skiptitle
  sta isPractice
practice_skiptitle:
  lda #$C0
  sta debugHex1
  lda #$DE
  sta debugHex2

  jsr newGame
  lda isPractice
  beq practice_skippracticemenu
  jsr practice_menu
  lda isPractice
  beq restart
  bne practice_nocutscene
practice_skippracticemenu:

  .if ::FORCE_PARANOID
    lda #4
    sta actor_paranoid
    ldx #0
  .else
    ldx #1
  .endif
  jsr cut_choose_villagers
  
  lda #15  ; message from Pino before the game starts
  jsr load_cutscene
practice_nocutscene:

  jsr setupGameBG
  jsr clearAllMissiles  ; and explosions, and smoke
  jsr initVillagers
  lda #STATE_NEW_LEVEL
  sta gameState
  lda #0
  sta housesLeftClass
  sta investigationStep

.if ::START_AT_5AM
  sta gameHour  ; DEBUG! testing the cut scene code
.endif
  
gameLoop:
  jsr incGameClock
  jsr read_pads
  jsr mouse_to_vel
  jsr pently_update

  lda new_keys
  and #KEY_START
  beq notPaused
  jsr pauseScreen
notPaused:
  ldx #0
  jsr moveCrosshairPlayerX
  inx
  jsr moveCrosshairPlayerX

.if ::PROFILE_LIGHTGRAY
  ldx #BG_ON|OBJ_ON|LIGHTGRAY|TINT_R
  stx PPUMASK
.endif  

  ; Draw sprites
  ldx #0
  stx oam_used
drawAllCrosshairs:
  jsr drawCrosshairPlayerX
  inx
  cpx numPlayers
  bcc drawAllCrosshairs
.if ::PROFILE_LIGHTGRAY
  ldx #BG_ON|OBJ_ON
  stx PPUMASK
.endif  

  ; Move and draw sprites appropriate for this game state
  jsr doStateAction
  
.if ::PROFILE_LIGHTGRAY
  ldx #BG_ON|OBJ_ON|LIGHTGRAY|TINT_G
  stx PPUMASK
.endif  

  jsr tenthUpdates
  jsr buildBGUpdate

.if ::PROFILE_LIGHTGRAY
  ldx #BG_ON|OBJ_ON
  stx PPUMASK
.endif  
  ldx oam_used
  jsr ppu_clear_oam
  
  ; we're done preparing all updates
  lda nmis
:
  cmp nmis
  beq :-
  jsr blitBGUpdate

  ldx #0
  ldy #0
  stx OAMADDR
  lda #>OAM
  sta OAM_DMA
  lda #VBLANK_NMI|BG_0000|OBJ_1000
  sec
  jsr ppu_screen_on

  lda gameState  
  cmp #STATE_INACTIVE
  bne gameLoop

  jmp restart
.endproc

;;
; These are done 10 times a second
.proc tenthUpdates
  jsr updateAllExplosions
  jsr updateMissiles
  jsr updateVillagers

  lda gameSubTenth
  cmp #1
  bne :+
  jsr testMissileThreats
:
  jmp updateSmoke

.endproc

.proc pauseScreen

  ; Draw "PAUSE" as sprites
  ldy #0
  ldx #0
buildPauseText:
  lda #111
  sta OAM,x
  lda pauseText,y
  sta OAM+1,x
  lda #%00000001
  sta OAM+2,x
  tya
  asl a
  asl a
  asl a
  asl a
  adc #92
  sta OAM+3,x
  inx
  inx
  inx
  inx
  iny
  cpy #5
  bcc buildPauseText
  jsr ppu_clear_oam

loop:
  lda nmis
:
  cmp nmis
  beq :-
  sta nmis  ; in pause, NMI counting is frozen
  ldx #0
  ldy #0
  sty OAMADDR
  lda #>OAM
  sta OAM_DMA
  lda #VBLANK_NMI|OBJ_0000|BG_0000
  sec
  jsr ppu_screen_on
  jsr pently_update
  jsr read_pads

  ; Start Select in practice: Return to practice screen
  lda new_keys
  and #KEY_SELECT
  beq notSelect
  lda isPractice
  beq notSelect
  lda #STATE_INACTIVE
  sta gameState
  rts
notSelect:
  lda new_keys
  and #KEY_START
  beq loop
  rts
.endproc

.segment "RODATA"
pauseText:
  .byt "PAUSE"

stateHandlers:
  .addr doStateInactive-1, doStateNewLevel-1, doStateActive-1
  .addr doStateLevelReward-1, doStateRebuildSilo-1, doStateCutscene-1
  .addr doStateRebuildHouse-1, doStateGameOver-1

.segment "CODE"
.proc doStateAction
  lda gameState
  asl a
  tax
  lda stateHandlers+1,x
  pha
  lda stateHandlers,x
  pha
  rts
.endproc

.proc doStateInactive
  rts
.endproc

.proc doStateNewLevel
  lda gameDay
  cmp #NUM_MADE_DAYS
  bne notRestart
  lda #STATE_INACTIVE
  sta gameState
  rts
notRestart:
  asl a
  asl a
  adc gameDay
  adc gameHour
  jsr loadLevel
  .if ::ONE_MISSILE_PER_LEVEL
    lda #1
    sta enemyMissilesLeft
  .endif
  lda #BG_DIRTY_STATUS
  ora bgDirty
  sta bgDirty

  ; put missiles in silos
  lda #15
  sta siloMissilesLeft+1
  sta siloMissilesLeft
  
  ; but don't replenish destroyed silos
  lda housesStanding+BUILDING_SILO0
  bne standing0
  sta siloMissilesLeft
  lda #20
  sta siloMissilesLeft+1
standing0:
  lda housesStanding+BUILDING_SILO1
  bne standing1
  sta siloMissilesLeft+1
  lda #20
  sta siloMissilesLeft
standing1:

  lda #0
  sta buildingsDestroyedThisLevel
  lda #STATE_ACTIVE
  sta gameState

  ; choose song
  lda isPractice
  cmp #2
  bcs notPracticeMenu
  ldx gameHour
  lda hourlyMusic,x
  jsr pently_start_music
notPracticeMenu:

  jmp initRandomTarget
.segment "RODATA"
hourlyMusic:
  .byt 0, 1, 2, 3, 4
.segment "CODE"
.endproc

; "Active" is the only state in which player missiles get fired.
.proc doStateActive
  ; end game if no silos are standing
  lda housesStanding+BUILDING_SILO0
  ora housesStanding+BUILDING_SILO1
  bne silosStillExist
  lda #STATE_GAMEOVER
  sta gameState
  jsr pently_stop_music
  rts
silosStillExist:

  ; First player fires from left silo
  lda #KEY_B
  ldx numPlayers
  cpx #2
  bne :+
  lda #KEY_B|KEY_A
:
  ldx #0
  and new_keys,x
  beq notPressB
  lda crosshairXHi,x
  sta 2
  lda crosshairYHi,x
  sta 3
  ldx #0
  jsr firePlayerMissile
notPressB:

  ; Last player fires from right silo
  lda #KEY_A
  ldx numPlayers
  cpx #2
  bne :+
  lda #KEY_B|KEY_A
:
  dex
  and new_keys,x
  beq notPressA
  lda crosshairXHi,x
  sta 2
  lda crosshairYHi,x
  sta 3
  ldx #1
  jsr firePlayerMissile
notPressA:

  lda enemyMissilesLeft
  bne levelNotOver
  ldx #4
levelOverSearchLoop:
  lda missileYHi,x
  bne levelNotOver
  inx
  cpx #NUM_MISSILES
  bcc levelOverSearchLoop
  lda #STATE_LEVEL_REWARD
  sta gameState

levelNotOver:
  rts
.endproc

.proc doStateLevelReward
  lda #2
  cmp curTip
  beq alreadySet

  ; and add 10 * houses to the score
  jsr pently_stop_music
  jsr countHousesLeft
  sty 0
  tya
  asl a
  asl a
  adc 0
  bne notHousesGameOver
  lda #STATE_GAMEOVER
  sta gameState
  rts
notHousesGameOver:
  asl a
  adc siloMissilesLeft
  adc siloMissilesLeft+1
  sta 1
  jsr addScore
  jsr villagersGoHome
  jmp buildLevelRewardBar

alreadySet:
  lda tipTimeLeft
  bne notYet

  jsr warpVillagersToTargets
  lda #STATE_REBUILDING_SILO
  ldy isPractice
  beq notPractice
  lda #STATE_INACTIVE
notPractice:
  sta gameState
notYet:
  lda tipTimeLeft

  ; Change music once 47.0 tenths are left
  eor #47
  ora gameSubTenth
  bne notMusic
  lda #MUSIC_CLEARED_LEVEL
  jsr pently_start_music
notMusic:
  rts
.endproc

.proc doStateRebuildSilo

  ; 2011-05-03: The NPCs have time to repair both silos
  ; during the daytime cut scene.
  ; $04 (5 AM) means next screen will be the daytime cut scene
  lda gameHour
  cmp #$04
  beq repairEvenIfHouseDestroyed

  ; In any other hour, if any houses were destroyed this level,
  ; don't repair the silo.
  lda buildingsDestroyedThisLevel
  bne stateIsDone

repairEvenIfHouseDestroyed:
  
  ; If the tip is being displayed, don't repair another one.
  lda #3
  cmp curTip
  beq alreadySet
  ldx housesStanding+BUILDING_SILO0
  bne leftIsStillStanding
  inc housesStanding+BUILDING_SILO0
  bne finishStateSetup

leftIsStillStanding:
  ldx housesStanding+BUILDING_SILO1
  bne stateIsDone
  inc housesStanding+BUILDING_SILO1
finishStateSetup:
  sta curTip
  lda #40
  sta tipTimeLeft
  lda #BG_DIRTY_TIP|BG_DIRTY_HOUSES
  ora bgDirty
  sta bgDirty

alreadySet:
  lda tipTimeLeft
  bne notYet
stateIsDone:
  lda #STATE_CUTSCENE
  sta gameState
notYet:
  rts
.endproc

.proc doStateCutscene
  ; Go to the next level
  inc gameHour
  lda gameHour
  cmp #5
  bcc readyForNextLevel

  ; Choose which house will be rebuilt
  ldy houseToRebuild
  bpl rebuildAlreadySet
  jsr findRandomDestroyedHouse
  cpy #NUM_BUILDINGS
  bcc haveHouseToRebuild

  ; If there's nothing to rebuild, point at a silo
  lda gameDay
  lsr a
  ldy #BUILDING_SILO0
  bcc haveHouseToRebuild
  ldy #BUILDING_SILO1
haveHouseToRebuild:
  sty houseToRebuild
rebuildAlreadySet:

  ; Check if we're still on the perfect run track
  lda gameDay
  ldy firstDestroyedHouse
  bmi haveCutsceneNumberInA

  ; Count the number of buildings left, then decide on a level
  cpy actor_paranoid
  beq no_pick_new_actors
  sty actor_paranoid
  ldx #0
  jsr cut_choose_villagers
  
no_pick_new_actors:
  lda gameDay
  cmp #NUM_MADE_DAYS-1
  bne notLastDay
  lda #14
  bne haveCutsceneNumberInA
notLastDay:
  jsr countHousesLeft
  sty 0
  ldx #2
  cpy #4
  bcc :+
  dex
  cpy #10
  bcc :+
  dex
:

  ; At thois point, x=0 means perfect, x=1 means 4-9 left
  ; and x=2 means 1-3 left.
  cpx housesLeftClass
  ; At this point, P is set for old - new.  If old <= new, skip to
  ; advancePlot
  beq advancePlot
  bcc advancePlot
  stx housesLeftClass
  txa
  adc #6  ; 8 and 9, and carry is 1
  bne haveCutsceneNumberInA
advancePlot:

  ; Advance the investigation forward one step
  lda investigationStep
  inc investigationStep
  cmp #2
  bcc :+
  lda #2
  clc
:
  adc #10

haveCutsceneNumberInA:
  jsr load_cutscene
  
  ; The cutscene code trashes gameState, the missile states, and the
  ; background, so make sure those have values before continuing.
  jsr clearAllMissiles
  lda #STATE_REBUILDING_HOUSE
  sta gameState
  jmp setupGameBG

readyForNextLevel:
  lda #STATE_NEW_LEVEL
  sta gameState
  rts
.endproc  

.proc doStateRebuildHouse
  lda #4
  cmp curTip
  beq alreadySet

  ; so now the level is at the end of the day.
.if ::START_AT_5AM
  lda #4
.else
  lda #0
.endif
  sta gameHour
  inc gameDay
  lda #BG_DIRTY_TIP|BG_DIRTY_HOUSES
  ora bgDirty
  sta bgDirty

  ; choose a house to rebuild
  ldy houseToRebuild
  bmi nothingToRebuild
  lda #$FF
  sta houseToRebuild
  lda housesStanding,y  ; probably a silo
  bne nothingToRebuild
  lda #1
  sta housesStanding,y
  lda #4
  sta curTip
  lda #40
  sta tipTimeLeft
  lda #BG_DIRTY_HOUSES|BG_DIRTY_TIP
  ora bgDirty
  sta bgDirty
  jmp buildHouseRebuiltBar
  
alreadySet:
  lda tipTimeLeft
  bne notYet
nothingToRebuild:
  lda #STATE_NEW_LEVEL
  sta gameState
notYet:
  rts
.endproc

.proc doStateGameOver
  lda #1
  cmp curTip
  beq tipAlreadySet
  sta curTip
  lda #50
  sta tipTimeLeft
  lda #BG_DIRTY_TIP
  ora bgDirty
  sta bgDirty
  rts
tipAlreadySet:
  lda tipTimeLeft
  bne :+
  lda #STATE_INACTIVE
  sta gameState
:
  rts
.endproc

.segment "CHR"
.incbin "obj/nes/maingfx.chr"
.incbin "obj/nes/cuthouses.chr"
