if app.apiVersion < 3 then
  app.alert("API version is outdated")
  return
end


local importChrFileDefaultText <const> = "Import CHR File..."
local importPaletteFileDefaultText <const> = "Import Palette File..."
local exportChrFileDefaultText <const> = "Export CHR File..."
local exportPaletteFileDefaultText <const> = "Export Palette File..."

-- palette from: http://www.firebrandx.com/nespalette.html
local nesPalleteBytes <const> = (
  '6A6D6A0013801E008A39007A5500565A00184F10003D1C00253200003D00004000003924002E55000000000000000000' ..
  'B9BCB91850C74B30E37322D6951FA99D285C9837007F4C005E6400227700027E02007645006E8A000000000000000000' ..
  'FFFFFF68A6FF8C9CFFB586FFD975FDE377B9E58D68D49D29B3AF0C7BC21155CA4746CB8147C1C54A4D4A000000000000' ..
  'FFFFFFCCEAFFDDDEFFECDAFFF8D7FEFCD6F5FDDBCFF9E7B5F1F0AADAFAA9C9FFBCC3FBD7C4F6F6BEC1BE000000000000'
):gsub("%x%x", function(digits) return string.char(tonumber(digits, 16)) end)

-- palette from: https://forums.nesdev.org/viewtopic.php?p=160537#p160537
--local nesPalleteBytes <const> = (
--  '454b4e00007213007232005f44004444000e440000361b002929000e290000290e003636003652000000060707060707' ..
--  '484e510036b1440ebe5f00be7a00968800447a29006d360052520029520000520000524400446d060707060707060707' ..
--  '222426003ba30000854a00a3740e9f8d2a639b381ca36d009688005f96001b961b1b965f1b96a333373a060707060707' ..
--  '2224260038703034362500704b00706911575e1313693411746311576f2032632121634b115769484e51060707060707'
--):gsub("%x%x", function(digits) return string.char(tonumber(digits, 16)) end)


local function isValidNesSprite(sprite)
  if not sprite then
    app.alert{title="Error", text="Sprite must be open", buttons="OK"}
    return false
  end
  if sprite.colorMode ~= ColorMode.INDEXED then
    app.alert{title="Error", text="Sprite must have indexed color", buttons="OK"}
    return false
  end
  if (sprite.width % 8) ~= 0 or (sprite.height % 8) ~= 0 then
    app.alert{title="Error", text="Sprite size must be multiple of 8", buttons="OK"}
    return false
  end
  return true
end

local function fileSize(file)
  local current <const> = file:seek()
  local size <const> = file:seek("end")
  file:seek("set", current)
  return size
end

local function makeImageForTile(data)
  local imageTarget <const> = Image(8, 8, ColorMode.INDEXED)
  for y = 1, 8 do
    local highByte = string.byte(data, y)
    local lowByte = string.byte(data, y + 8)

    for x = 8, 1, -1 do
      local value = (1 & highByte) << 1 | (1 & lowByte)
      highByte = highByte >> 1
      lowByte = lowByte >> 1
      imageTarget:drawPixel(x-1, y-1, value)
    end
  end

  return imageTarget
end

local function makeImageFromChrFile(input, spec, inputSize, imageWidth, tilesPerRow)
  local inputSpriteImage <const> = Image(spec)
  for i = 1, inputSize / 16 do
    inputSpriteImage:drawImage(
      makeImageForTile(input:read(16)),
      ((i - 1) * 8) % imageWidth,
      (math.ceil(i / tilesPerRow) - 1) * 8
    )
  end
  return inputSpriteImage
end

local function importChr()
  local chrFilePath <const> = dialog.data.importchrfile
  if chrFilePath == importChrFileDefaultText then return end
  dialog:modify{id="importchrfile", filename=importChrFileDefaultText}

  if not app.fs.isFile(chrFilePath) then
    app.alert{title="Error", text="Not a file.", buttons="OK"}
    return
  end

  local input <close> = assert(io.open(app.fs.normalizePath(chrFilePath), "rb"))
  local inputSize <const> = fileSize(input)

  local tilesPerRow <const> = 32
  local imageWidth <const> = tilesPerRow * 8

  app.command.NewFile {
    ui=false,
    width = imageWidth,
    height=math.ceil((inputSize / 2) / imageWidth) * 8, -- div by 2 because tiles are 2 bytes, not 1.
    colorMode=ColorMode.INDEXED,
    fromClipboard=false
  }
  app.transaction(function()
    local inputSprite <const> = app.activeSprite
    app.command.BackgroundFromLayer()
    inputSprite.cels[1].layer.name = "NES Tiles"

    inputSprite.cels[1].image = makeImageFromChrFile(
      input,
      inputSprite.spec,
      inputSize,
      imageWidth,
      tilesPerRow
    )

    app.refresh()
  end)
end


local function getNesChrFromImage(img, x, y)
  local highChars = ""
  local lowChars = ""
  local highByte = 0
  local lowByte = 0
  local column = 7
  for pixelIter in img:pixels(Rectangle(x, y, 8, 8)) do
    local pixelValue = pixelIter()

    -- (column-1) because this is moving FROM THE SECOND bit)
    highByte = highByte | ((pixelValue & 0x02) << (column-1))
    lowByte = lowByte | ((pixelValue & 0x01) << column)

    column = column - 1
    if column < 0 then
      column = 7
      highChars = highChars..string.char(highByte)
      lowChars = lowChars..string.char(lowByte)
      highByte = 0
      lowByte = 0
    end
  end

  return highChars..lowChars
end

local function getAllNesChrFromSprite(spr)
  local bin = ""
  for i = 1, (spr.height/8) do
    for j = 1, (spr.width/8) do
      bin = bin..getNesChrFromImage(
        spr.cels[1].image,
        (j - 1) * 8,
        (i - 1) * 8)
    end
  end
  return bin
end

local function exportChr()
  local exportFilePath <const> = dialog.data.exportchrfile
  if exportFilePath == exportChrFileDefaultText then return end
  dialog:modify{id="exportchrfile", filename=exportChrFileDefaultText}

  if exportFilePath == exportChrFileDefaultText then return end

  local spr <const> = app.activeSprite
  if not isValidNesSprite(spr) then return end

  local bin = getAllNesChrFromSprite(spr)

  local out <close> = assert(io.open(app.fs.normalizePath(exportFilePath), "wb"))
  out:write(bin)

  app.refresh()
end


local function getPaletteFromNesPalFile(file)
  local palette <const> = Palette(4)
  for i = 0, 3 do
    local nesPalettePosition <const> = string.byte(file:read(1)) * 3
    local nesR <const> = string.byte(nesPalleteBytes:sub(nesPalettePosition + 1, nesPalettePosition + 1))
    local nesG <const> = string.byte(nesPalleteBytes:sub(nesPalettePosition + 2, nesPalettePosition + 2))
    local nesB <const> = string.byte(nesPalleteBytes:sub(nesPalettePosition + 3, nesPalettePosition + 3))
    local col <const> = {
      r = nesR,
      g = nesG,
      b = nesB
    }
    palette:setColor(i, col)
  end
  return palette
end

local function importPalette()
  local paletteFilePath <const> = dialog.data.importpalettefile
  if paletteFilePath == importPaletteFileDefaultText then return end
  dialog:modify{id="importpalettefile", filename = importPaletteFileDefaultText}

  if paletteFilePath == importPaletteFileDefaultText then return end

  if not app.fs.isFile(paletteFilePath) then
    app.alert{title="Error", text="Not a file.", buttons="OK"}
    return
  end

  local palFile <close> = assert(io.open(app.fs.normalizePath(paletteFilePath), "rb"))
  local inputSize <const> = fileSize(palFile)

  if inputSize ~= 4 then
    app.alert{title="Error", text="File is not 4 bytes long.", buttons="OK"}
    return
  end

  app.transaction(function()
    local palette <const> = getPaletteFromNesPalFile(palFile)

    app.activeSprite:setPalette(palette)

    app.refresh()
  end)
end


local function getNearestNesColor(r, g, b)
  local closestColorIndex = 0x0F -- start at black.
  local closestDistanceToColor = (r^2) + (g^2) + (b^2)
  for i = 1, #nesPalleteBytes, 3 do
    local colorIndex <const> = (i - 1) // 3
    -- skip the last 2 columns of colors since they're pretty much black
    if (colorIndex & 0x0F) > 0x0D then goto continue end

    local nearR <const> = string.byte(nesPalleteBytes:sub(i, i))
    local nearG <const> = string.byte(nesPalleteBytes:sub(i + 1, i + 1))
    local nearB <const> = string.byte(nesPalleteBytes:sub(i + 2, i + 2))

    local distR <const> = nearR - r
    local distG <const> = nearG - g
    local distB <const> = nearB - b
    local dist <const> = (distR^2) + (distG^2) + (distB^2)
    if dist < closestDistanceToColor then
      closestColorIndex = colorIndex
      closestDistanceToColor = dist
    end

    ::continue::
  end

  return closestColorIndex
end

local function getNesPaletteDataFromImagePallet(palette)
  local paletteChars = ""
  for i = 1, 4 do
    local col <const> = palette:getColor(i-1)
    paletteChars = paletteChars..string.char(getNearestNesColor(col.red, col.green, col.blue))
  end
  return paletteChars
end

local function exportPalette()
  local exportFilePath <const> = dialog.data.exportpalettefile
  if exportFilePath == exportPaletteFileDefaultText then return end
  dialog:modify{id="exportpalettefile", filename = exportPaletteFileDefaultText}

  if exportFilePath == exportPaletteFileDefaultText then return end

  local currentpal <const> = app.activeSprite.palettes[1]
  if #currentpal ~= 4 then
    app.alert{title="Error", text="Palette must have 4 colors.", buttons="OK"}
    return
  end

  local paletteChars = getNesPaletteDataFromImagePallet(app.activeSprite.palettes[1])

  local f <close> = assert(io.open(app.fs.normalizePath(exportFilePath), "wb"))
  f:write(paletteChars)

  app.refresh()
end


dialog =
  Dialog("NES Utilities")
  :separator{text="Import"}
  :file{
    id="importchrfile",
    title=importChrFileDefaultText,
    open=true,
    filename=importChrFileDefaultText,
    filetypes={"chr"},
    onchange=importChr
  }
  :file{
    id="importpalettefile",
    title=importPaletteFileDefaultText,
    open=true,
    filename=importPaletteFileDefaultText,
    filetypes={"pal"},
    onchange=importPalette
  }
  :newrow()
  :separator{
    text="Export"
  }
  :file{
    id="exportchrfile",
    title=exportChrFileDefaultText,
    save=true,
    filename=exportChrFileDefaultText,
    filetypes={"chr"},
    onchange=exportChr
  }
  :file{
    id="exportpalettefile",
    title=exportPaletteFileDefaultText,
    save=true,
    filename=exportPaletteFileDefaultText,
    filetypes={"pal"},
    onchange=exportPalette
  }
  :close()
  :show{ wait=false }