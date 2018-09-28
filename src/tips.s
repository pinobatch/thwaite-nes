; tips.s
; In-game play tips for Thwaite

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

.segment "RODATA"
.export levelTips
levelTips:
  .byt  5, 6, 7, 8, 9
  .byt 12,10, 0, 0, 0
  .byt  0, 0, 0, 0, 0
  .byt 14, 0, 0, 0, 0
  .byt  0, 0, 0, 0, 0
  .byt  0, 0, 0, 0, 0
  .byt  0, 0, 0, 0, 0
; Level $01's tip is replaced with tipTwoPlayer
; inside levels.s::loadLevel
