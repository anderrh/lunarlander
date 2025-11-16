INCLUDE "hardware.inc"

DEF BRICK_LEFT EQU $05
DEF BRICK_RIGHT EQU $06
DEF DIGIT_OFFSET EQU $1A
DEF BLANK_TILE EQU $08
DEF SCORE_TENS   EQU $9870
DEF SCORE_ONES   EQU $9871

SECTION "header", ROM0[$100]

    jp EntryPoint

    ds $150 - @, 0 ; Make room for the header

EntryPoint:
    ; Do not turn the LCD off outside of VBlank
WaitVBlank:
    ld a, [rLY]
    cp 144
    jp c, WaitVBlank

    ; Turn the LCD off
    ld a, 0
    ld [rLCDC], a

    ; Copy the tile data
    ld de, Tiles
    ld hl, $9000
    ld bc, TilesEnd - Tiles
		call Memcopy

    ; Copy the tilemap
    ld de, Tilemap
    ld hl, $9800
    ld bc, TilemapEnd - Tilemap
		call Memcopy

		; Copy the Lander tile
		ld de, Lander
    ld hl, $8000
    ld bc, LanderEnd - Lander
    call Memcopy

    ld a, 0
    ld b, 160
    ld hl, _OAMRAM
ClearOam:
    ld [hli], a
    dec b
    jp nz, ClearOam


    ld hl, _OAMRAM
    ; Now initialize the Lander sprite
    ld a, 60 + 16
    ld [hli], a
    ld a, 32 + 8
    ld [hli], a
    ld a, 2
    ld [hli], a
    ld a, 0
    ld [hli], a

    ; The Lander starts out going up and to the right
    ld a, 0
    ld [wLanderMomentumX], a
    ld a, 0
    ld [wLanderMomentumY], a
    ld a, 0 ; -1 if going left, 0 if going right
    ld [wLanderMomentumX+1], a
    ld a, 0 ; -1 if going left, 0 if going right
    ld [wLanderMomentumY+1], a
    ld a, (0)
    ld [wLanderX], a
    ld a, (60)
    ld [wLanderX+1], a
    ld a, (0)
    ld [wLanderY], a
    ld a, (32)
    ld [wLanderY+1], a
    ld a, (0)
    ld [wLanderAngle], a

    ; Turn the LCD on
    ld a, LCDCF_ON | LCDCF_BGON | LCDCF_OBJON
    ld [rLCDC], a

    ; During the first (blank) frame, initialize display registers
    ld a, %11100100
    ld [rBGP], a
    ld a, %11100100
    ld [rOBP0], a

    ; Initialize global variables
    ld a, 0
    ld [wCurKeys], a
    ld [wNewKeys], a
    ld [wScore], a

Main:
    ld a, [rLY]
    cp 144
    jp nc, Main
WaitVBlank2:
    ld a, [rLY]
    cp 144
    jp c, WaitVBlank2

    ; Add the Lander's momentum to its position in OAM.
    ld a, [wLanderMomentumX+1]
    ld c, a
    ld a, [wLanderMomentumX]
    ld b, a
    ld a, [wLanderX]
    add a, b
    ld b, a
    ld [wLanderX], a
    ld a, [wLanderX+1]
    adc c
    ld c, a
    ld [wLanderX+1], a

    ; Use the de-scaled low byte as the backgrounds position
    ld a, c
    ld [_OAMRAM+1], a
    ld a, [wLanderAngle]  
    call getlandercostume
    ld a, b
    ld [_OAMRAM+2], a

    ld a, [wLanderMomentumY+1]
    ld c, a
    ld a, [wLanderMomentumY]
    
    ld b, a
    ld a, [wLanderY]
    add a, b
    ld b, a
    ld [wLanderY], a
    ld a, [wLanderY+1]
    adc c
    ld c, a
    ld [wLanderY+1], a

    ; Use the de-scaled low byte as the backgrounds position
    ld a, c
    ld [_OAMRAM], a


    ; Check the current keys every frame and move left or right.
    call UpdateKeys

    ; First, check if the left button is pressed.
CheckLeft:
    ld a, [wCurKeys]
    and a, PADF_LEFT
    jp z, CheckRight
Left:
    ; Move the angle one unit to the left.
    ld a, [wLanderAngle]
    
    ; If we've already turned to -180, don't move.
    cp a, -128
    jp z, Main
    dec a
    ld [wLanderAngle], a
    jp Main

; Then check the right button.
CheckRight:
    ld a, [wCurKeys]
    and a, PADF_RIGHT
    jp z, Main
Right:
    ; Move the angle one unit to the right.
    ld a, [wLanderAngle]
    ; If we've already turned to 127, don't move.
    cp a, 127
    jp z, Main
    inc a
    ld [wLanderAngle], a
    jp Main

; Copy bytes from one area to another.
; @param de: Source
; @param hl: Destination
; @param bc: Length
Memcopy:
    ld a, [de]
    ld [hli], a
    inc de
    dec bc
    ld a, b
    or a, c
    jp nz, Memcopy
    ret

UpdateKeys:
  ; Poll half the controller
  ld a, P1F_GET_BTN
  call .onenibble
  ld b, a ; B7-4 = 1; B3-0 = unpressed buttons

  ; Poll the other half
  ld a, P1F_GET_DPAD
  call .onenibble
  swap a ; A7-4 = unpressed directions; A3-0 = 1
  xor a, b ; A = pressed buttons + directions
  ld b, a ; B = pressed buttons + directions

  ; And release the controller
  ld a, P1F_GET_NONE
  ldh [rP1], a

  ; Combine with previous wCurKeys to make wNewKeys
  ld a, [wCurKeys]
  xor a, b ; A = keys that changed state
  and a, b ; A = keys that changed to pressed
  ld [wNewKeys], a
  ld a, b
  ld [wCurKeys], a
  ret

.onenibble
  ldh [rP1], a ; switch the key matrix
  call .knownret ; burn 10 cycles calling a known ret
  ldh a, [rP1] ; ignore value while waiting for the key matrix to settle
  ldh a, [rP1]
  ldh a, [rP1] ; this read counts
  or a, $F0 ; A7-4 = 1; A3-0 = unpressed keys
.knownret
  ret

; Convert a pixel position to a tilemap address
; hl = $9800 + X + Y * 32
; @param b: X
; @param c: Y
; @return hl: tile address
GetTileByPixel:
    ; First, we need to divide by 8 to convert a pixel position to a tile position.
    ; After this we want to multiply the Y position by 32.
    ; These operations effectively cancel out so we only need to mask the Y value.
    ld a, c
    and a, %11111000
    ld l, a
    ld h, 0
    ; Now we have the position * 8 in hl
    add hl, hl ; position * 16
    add hl, hl ; position * 32
    ; Convert the X position to an offset.
    ld a, b
    srl a ; a / 2
    srl a ; a / 4
    srl a ; a / 8
    ; Add the two offsets together.
    add a, l
    ld l, a
    adc a, h
    sub a, l
    ld h, a
    ; Add the offset to the tilemap's base address, and we are done!
    ld bc, $9800
    add hl, bc
    ret

; @param a: tile ID
; @return z: set if a is a wall.
IsWallTile:
    cp a, $00
    ret z
    cp a, $01
    ret z
    cp a, $02
    ret z
    cp a, $04
    ret z
    cp a, $05
    ret z
    cp a, $06
    ret z
    cp a, $07
    ret

; Increase score by 1 and store it as a 1 byte packed BCD number
; changes A and HL
IncreaseScorePackedBCD:
    xor a               ; clear carry flag and a
    inc a               ; a = 1
    ld hl, wScore       ; load score
    adc [hl]            ; add 1
    daa                 ; convert to BCD
    ld [hl], a          ; store score
    call UpdateScoreBoard
    ret
		; Read the packed BCD score from wScore and updates the score display
UpdateScoreBoard:
    ld a, [wScore]      ; Get the Packed score
    and %11110000       ; Mask the lower nibble
    swap a              ; Move the upper nibble to the lower nibble (divide by 16)
    add a, DIGIT_OFFSET ; Offset + add to get the digit tile
    ld [SCORE_TENS], a  ; Show the digit on screen

    ld a, [wScore]      ; Get the packed score again
    and %00001111       ; Mask the upper nibble
    add a, DIGIT_OFFSET ; Offset + add to get the digit tile again
    ld [SCORE_ONES], a  ; Show the digit on screen
    ret
getlandercostume:
    cp a, 32
    ld b, 2
    ret c
    cp a, 96
    ld b, 3
    ret c
    cp a, 128
    ld b, 4
    ret c
    cp a, 160
    ld b, 0
    ret c
    cp a,224
    ld b, 1
    ret c
    ld b, 2
    ret


Tiles:
; moon surface
  ; space
  dw `33333333
  dw `33333333
  dw `33333333
  dw `33333333
  dw `33333333
  dw `33333333
  dw `33333333
  dw `33333333
  ; stars
  dw `33033333
  dw `33333333
  dw `33333303
  dw `30333333
  dw `33333333
  dw `33333333
  dw `33330333
  dw `33333333

  dw `33333333
  dw `33333133
  dw `33333333
  dw `33333333
  dw `33133333
  dw `33333333
  dw `33333133
  dw `33333333

  ; landing surface
  dw `12312312
  dw `23123123
  dw `31231231
  dw `12312312
  dw `11111111
  dw `11111111
  dw `11111111
  dw `11111111
  ;clear moon surface
  dw `11111111
  dw `11111111
  dw `11111111
  dw `11111111
  dw `11111111
  dw `11111111
  dw `11111111
  dw `11111111
  ; crater
  dw `11111111
  dw `11222211
  dw `12233221
  dw `12333321
  dw `12333321
  dw `12233221
  dw `11222211
  dw `11111111
  ;uphill
  dw `33333331
  dw `33333311
  dw `33333111
  dw `33331111
  dw `33311111
  dw `33111111
  dw `31111111
  dw `11111111
  ;downhill
  dw `13333333
  dw `11333333
  dw `11133333
  dw `11113333
  dw `11111333
  dw `11111133
  dw `11111113
  dw `11111111

; digits
	; 0
	dw `33333333
	dw `33000033
	dw `30033003
	dw `30033003
	dw `30033003
	dw `30033003
	dw `33000033
	dw `33333333
	; 1
	dw `33333333
	dw `33300333
	dw `33000333
	dw `33300333
	dw `33300333
	dw `33300333
	dw `33000033
	dw `33333333
	; 2
	dw `33333333
	dw `33000033
	dw `30330003
	dw `33330003
	dw `33000333
	dw `30003333
	dw `30000003
	dw `33333333
	; 3
	dw `33333333
	dw `30000033
	dw `33330003
	dw `33000033
	dw `33330003
	dw `33330003
	dw `30000033
	dw `33333333
	; 4
	dw `33333333
  dw `33000033
  dw `30030033
  dw `30330033
  dw `30330033
  dw `30000003
  dw `33330033
  dw `33333333
  ; 5
  dw `33333333
  dw `30000033
  dw `30033333
  dw `30000033
  dw `33330003
  dw `30330003
  dw `33000033
  dw `33333333
  ; 6
  dw `33333333
  dw `33000033
  dw `30033333
  dw `30000033
  dw `30033003
  dw `30033003
  dw `33000033
  dw `33333333
  ; 7
  dw `33333333
  dw `30000003
  dw `33333003
  dw `33330033
  dw `33300333
  dw `33000333
  dw `33000333
  dw `33333333
  ; 8
  dw `33333333
  dw `33000033
  dw `30333003
  dw `33000033
  dw `30333003
  dw `30333003
  dw `33000033
  dw `33333333
  ; 9
  dw `33333333
  dw `33000033
  dw `30330003
  dw `30330003
  dw `33000003
  dw `33330003
  dw `33000033
  dw `33333333
TilesEnd:

Tilemap:
	db $00, $00, $02, $01, $00, $00, $00, $01, $01, $02, $00, $01, $01, $02, $00, $01, $01, $02, $01, $02, 0,0,0,0,0,0,0,0,0,0,0,0
	db $01, $01, $02, $01, $02, $01, $02, $01, $01, $01, $00, $01, $02, $02, $00, $01, $02, $00, $02, $02, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $01, $00, $01, $01, $02, $00, $02, $01, $02, $01, $02, $01, $02, $01, $00, $01, $01, $01, $01, 0,0,0,0,0,0,0,0,0,0,0,0
	db $02, $01, $02, $00, $02, $02, $02, $01, $01, $00, $02, $00, $02, $01, $01, $01, $02, $01, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $01, $00, $01, $02, $01, $02, $00, $02, $01, $02, $01, $01, $01, $02, $02, $01, $00, $01, $00, $01, 0,0,0,0,0,0,0,0,0,0,0,0
	db $01, $01, $02, $01, $02, $00, $02, $01, $02, $00, $02, $02, $02, $01, $00, $02, $02, $00, $01, $02, 0,0,0,0,0,0,0,0,0,0,0,0
	db $02, $01, $01, $02, $01, $01, $00, $02, $01, $00, $01, $01, $00, $00, $01, $00, $00, $02, $02, $01, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $01, $00, $01, $02, $01, $01, $02, $00, $01, $02, $01, $00, $02, $01, $00, $01, $02, $01, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $01, $01, $02, $01, $02, $01, $02, $01, $01, $01, $00, $01, $02, $02, $00, $01, $02, $00, $02, $02, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $01, $00, $01, $01, $02, $00, $02, $01, $02, $01, $02, $01, $02, $01, $00, $01, $01, $01, $01, 0,0,0,0,0,0,0,0,0,0,0,0
	db $05, $04, $04, $04, $04, $04, $04, $03, $03, $03, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, 0,0,0,0,0,0,0,0,0,0,0,0
	db $04, $05, $04, $04, $04, $04, $04, $05, $04, $04, $04, $05, $04, $04, $04, $04, $04, $04, $05, $04, 0,0,0,0,0,0,0,0,0,0,0,0
	db $04, $04, $04, $05, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, 0,0,0,0,0,0,0,0,0,0,0,0
	db $04, $04, $04, $05, $04, $04, $04, $05, $04, $04, $05, $04, $04, $04, $04, $04, $04, $04, $04, $04, 0,0,0,0,0,0,0,0,0,0,0,0
	db $04, $04, $04, $04, $04, $04, $04, $04, $05, $04, $04, $04, $04, $04, $04, $05, $04, $04, $04, $04, 0,0,0,0,0,0,0,0,0,0,0,0
	db $04, $04, $04, $04, $04, $05, $05, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, 0,0,0,0,0,0,0,0,0,0,0,0
	db $04, $04, $05, $04, $04, $04, $04, $04, $05, $05, $04, $04, $04, $04, $05, $04, $04, $04, $04, $04, 0,0,0,0,0,0,0,0,0,0,0,0
	db $05, $04, $04, $04, $04, $05, $04, $05, $04, $05, $05, $04, $04, $04, $04, $04, $05, $04, $04, $04, 0,0,0,0,0,0,0,0,0,0,0,0
TilemapEnd:

Lander:
    dw `10001100
    dw `11011110
    dw `02233331
    dw `02233331
    dw `02233331
    dw `02233331
    dw `11011110
    dw `10001100

    dw `00011100
    dw `00133310
    dw `00133331
    dw `11233331
    dw `01223331
    dw `00222110
    dw `00011000
    dw `00001000

    dw `00111100
    dw `01333310
    dw `11333311
    dw `11333311
    dw `01333310
    dw `00222200
    dw `01222210
    dw `11000011

    dw `00111000
    dw `01333100
    dw `13333100
    dw `13333211
    dw `13332210
    dw `01122200
    dw `00011000
    dw `00010000

    dw `00110001
    dw `01111011
    dw `13333220
    dw `13333220
    dw `13333220
    dw `13333220
    dw `01111011
    dw `00110001

LanderEnd:


SECTION "Input Variables", WRAM0
wCurKeys: db
wNewKeys: db

SECTION "Lander Data", WRAM0
wLanderMomentumX: dw
wLanderMomentumY: dw
wLanderX: dw
wLanderY: dw
wLanderAngle:db

SECTION "Score", WRAM0
wScore: db