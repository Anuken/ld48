import ecs, presets/[basic, effects, content], math

static: echo staticExec("faupack -p:assets-raw/sprites -o:assets/atlas")

#region types & consts

const
  scl = 4.0
  worldSize = 60

type
  Rot = range[0..3]
  Tile = object
    floor, wall: Block
    rot: Rot

  Block = ref object of Content
    solid: bool


registerComponents(defaultComponentOptions):
  type
    Vel = object
      x, y: float32

makeContent:
  air = Block()
  metal = Block()

#endregion

#region global variables

var tiles = newSeq[Tile](worldSize * worldSize)

#endregion

#region utilities

proc tile(x, y: int): Tile =
  if x >= worldSize or y >= worldSize or x < 0 or y < 0: Tile(floor: blockAir, wall: blockAir) else: tiles[x + y*worldSize]

proc setWall(x, y: int, wall: Block) = tiles[x + y*worldSize].wall = wall

proc solid(x, y: int): bool = tile(x, y).wall.solid

iterator eachTile*(): tuple[x, y: int, tile: Tile] =
  const pad = 2
  let
    xrange = (fau.cam.w / 2).ceil.int + pad
    yrange = (fau.cam.h / 2).ceil.int + pad
    camx = fau.cam.pos.x.ceil.int
    camy = fau.cam.pos.y.ceil.int

  for cx in -xrange..xrange:
    for cy in -yrange..yrange:
      let
        wcx = camx + cx
        wcy = camy + cy

      yield (wcx, wcy, tile(wcx, wcy))

#endregion

#region systems

sys("init", [Main]):
  init:
    initContent()

  start:
    if keyEscape.tapped: quitApp()
    
    fau.cam.resize(fau.widthf / scl, fau.heightf / scl)
    fau.cam.use()

    fillPoly(0, 0, 6, 30)
  
  finish:
    discard

launchFau("ld48")

#endregion