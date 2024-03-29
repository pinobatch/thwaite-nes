; Copyright 2011 Damian Yerrick
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.

xferBuf = $0100
OAM = $0200

; Replace the upper left tile of a threatened building with a !
SHOW_THREATENED = 0

; Show a C0DE at bottom center
BG_USE_DEBUGHEX = 0

; Breeze through the game when testing things
ONE_AMMO = 0

; Enable Right to change (and scroll to) the house to rebuild
CUT_SCROLL_DEBUGGING = 0

; Initialize RAM regions that aren't strictly necessary but serve
; to shut up Mesen
PEDANTIC_RAM_INIT = 1

; Turn this on to annoy Nova
CHECK_ILLEGAL_MISSILES = 1
ILLEGAL_MISSILES_TIP = 13

; main fields
STATE_INACTIVE = 0
STATE_NEW_LEVEL = 1
STATE_ACTIVE = 2
STATE_LEVEL_REWARD = 3
STATE_REBUILDING_SILO = 4
STATE_CUTSCENE = 5
STATE_REBUILDING_HOUSE = 6
STATE_GAMEOVER = 7
.globalzp nmis, oam_used, numPlayers, tvSystem, mouseEnabled
.globalzp debugHex1, debugHex2
.globalzp gameState
; main methods
.global doStateNewLevel

; ppuclear.s methods
.global ppu_clear_nt, ppu_clear_oam, ppu_screen_on

; pads fields
.globalzp cur_keys, new_keys, das_timer, das_keys
; pads methods
.global read_pads, autorepeat

; mouse fields
.globalzp cur_mbuttons, new_mbuttons
; mouse methods
.global read_mouse, mouse_change_sensitivity

; title constants
SELECTED_ARROW_TILE = $02
; title methods
.global titleScreen, display_textfile

; unpkb methods
.global PKB_unpackblk

; random fields
.globalzp rand0, rand1, rand2, rand3
; random methods
.global random, initRandomTarget, chooseRandomTarget
.global findRandomDestroyedHouse

; bg constants
NUM_BUILDINGS = 12
BUILDING_SILO0 = 2
BUILDING_SILO1 = 9
BUILDING_DESTROYED = 0
BUILDING_OK = 1
BUILDING_THREATENED = 2

BG_DIRTY_HOUSES = $01
BG_DIRTY_STATUS = $02
BG_DIRTY_TIP = $04
BG_DIRTY_PRACTICE_METER = $08

; bg fields
.global housesStanding, houseX, houseShape
.global score1s, score100s, hiscore1s, hiscore100s
.global gameDay, gameHour, gameMinute, gameSecond, gameTenthSecond, gameSubTenth
.global bgDirty, curTip, tipTimeLeft
.global buildingsDestroyedThisLevel, firstDestroyedHouse, houseToRebuild
.global main_palette
; bg methods
.global setupGameBG, blitBGUpdate, buildBGUpdate, buildLevelRewardBar
.global buildHouseRebuiltBar
.global newGame, addScore, incGameClock, countHousesLeft
.global puthex

; missiles constants
; missiles 0 and 2 are player 1's
; missiles 1 and 3 are player 2's
; missiles 4 through NUM_MISSILES - 1 are the enemy missiles
NUM_MISSILES = 20
MISSILE_SPAWN_Y = 8
BALLOON_SPAWN_Y = 40  ; in range 0-63 plus this
SILO_Y = 192  ; player missiles launch from here
BUILDING_HIT_Y = 200
CURSOR_X0 = 64  ; crosshair start position
CURSOR_X1 = 192

; missiles fields
.global crosshairXLo, crosshairXHi, crosshairDXLo, crosshairDXHi
.global crosshairYLo, crosshairYHi, crosshairDYLo, crosshairDYHi
.global missileXLo, missileXHi, missileYLo, missileYHi
.global missileDYHi, missileDYLo
.global missileType, missileTarget, missileTime, missileAngle
; and about 400 bytes of free space to use when missiles
; are not active
.global missilesOverlay

; missiles methods
.global clearAllMissiles, updateMissiles
.global moveCrosshairPlayerX, drawCrosshairPlayerX, mouse_to_vel
.global makeMissile, makeBalloon, firePlayerMissile
.global siloMissilesLeft

; explosion constants
NUM_EXPLOSIONS = 8
; explosion methods
.global clearExplosions, makeExplosion, updateAllExplosions

; smoke methods
.global makeSmoke, clearAllSmoke, updateSmoke

; math fields
.global missileSine, missileCosine
; math methods
.global getAngle, getSlope1, mul8, measureFromSilo

; bcd methods
.global bcd8bit

; levels constants
.globalzp NUM_MADE_DAYS, SKIP_TO_DAY
; levels fields
.global levelMissileSpeed, enemyMissilesLeft, levelReleasePeriod
.global levelMissileTypes, levelSalvoSizes
; levels methods
.global loadLevel

; scurry constants
NUM_VILLAGERS = NUM_BUILDINGS
; scurry methods
.global initVillagers, updateVillagers
.global testMissileThreats
.global villagersGoHome, warpVillagersToTargets

; paldetect constants
TV_SYSTEM_NTSC  = 0
TV_SYSTEM_PAL   = 1
TV_SYSTEM_DENDY = 2
TV_SYSTEM_OTHER = 3
; paldetect methods
.global getTVSystem

; sound constants
MUSIC_CLEARED_LEVEL = 5
MUSIC_1600 = 6

SFX_SPLIT = 0
SFX_ALERT_A = 4
SFX_ALERT_B = 5
SFX_LAUNCH = 6
SFX_BOOM_SQUARE = 7
SFX_BOOM_NOISE = 8
; Pently 3 sound methods
.global pently_init, pently_start_sound, pently_update
.global pently_start_music, pently_stop_music

; cutscene fields
.global character_name_offset, character_name0
.global actor_paranoid
; cutscene methods
.global load_cutscene, cut_choose_villagers

; kinematics args
abl_vel = 0
abl_maxVel = 2
abl_brakeRate = 4
abl_accelRate = 5
abl_keys = 6
; kinematics methods
.global accelBrakeLimit

; practice fields
.globalzp isPractice, practiceSide
; practice methods
.global practice_menu

; dte constants; must match paginate.py
DTE_OUTPUT_LEN = 32
DTE_MIN_CODEUNIT = $80
FIRST_PRINTABLE_CU = $10
; dte fields
dte_output_buf = $0180  ; temporary to get undte assembling
; dte methods
.global undte_line, undte_line0
