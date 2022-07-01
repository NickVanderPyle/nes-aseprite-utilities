# nes-aseprite-utilities
Import/export utilities for NES palette and pixel bytes

## Install

In Aseprite click File, Scripts, Open Scripts Folder.

Copy `nes-utilities` directory into Aseprite's Scripts directory.

In Aseprite click File, Scripts, Rescan Scripts Folder.

## Usage

Open the menu in Aseprite click File, Scripts, nes-utilties, nes-utilities.

### Import CHR File

Open a 2 Bit Per Pixel CHR file containing raw bytes from CHR-ROM.

The tiles will open in a new image with a default palette.

### Import Palette File

Open a PAL file which contains raw 4 bytes of palette colors for this tile.

Aseprite's palette will reduce to the 4 colors from the file.

### Export Palette File

Exports 4 colors of Aseprite's palette as 4 bytes. The colors will be converted to the closest NES palette.

## Usage in Code

Include the binary CHR-ROM and palette data with `.incbin` instruction.

```assembly
LoadPalettes:
  lda PaletteData, X
  sta PPU_VRAM_IO
  inx
  cpx #$20
  bne LoadPalettes

; ...

PaletteData:
  ; background palette
  .incbin "background-4byte-palette-1.bin"
  .incbin "background-4byte-palette-2.bin"
  .incbin "background-4byte-palette-3.bin"
  .incbin "background-4byte-palette-4.bin"
  ; sprite palette
  .incbin "sprite-4byte-palette-1.bin"
  .incbin "sprite-4byte-palette-2.bin"
  .incbin "sprite-4byte-palette-3.bin"
  .incbin "sprite-4byte-palette-4.bin"

; ...

.segment "CHARS"
  .incbin "sprite-bytes.chr"
```