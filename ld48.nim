import ecs, presets/[basic, effects, content], math, sequtils

static: echo staticExec("faupack -p:assets-raw/sprites -o:assets/atlas")

#region types & consts

const
  scl = 40f
  pixelation = 4
  worldSize = 20
  gravity = 2f
  pspeed = 12f
  hitsize = 0.6f
  jumpvel = 0.7f
  tsize = 12f
  maxvel = 0.7f

type
  Rot = range[0..3]
  Tile = object
    back, wall: Block
    rot: Rot

  Block = ref object of Content
    solid: bool
    patches: seq[Patch]


registerComponents(defaultComponentOptions):
  type
    Vel = object
      x, y, xdrag, ydrag: float32

    Player = object
    DrawPlayer = object

    Input = object
    Falling = object
    Solid = object

makeContent:
  air = Block()
  dirt = Block(solid: true)

#endregion

#region global variables

var tiles = newSeq[Tile](worldSize * worldSize)

#endregion

#region utilities

proc tile(x, y: int): Tile =
  if x >= worldSize or y >= worldSize or x < 0 or y < 0: Tile(back: blockAir, wall: blockAir) else: tiles[x + y*worldSize]

proc setWall(x, y: int, wall: Block) = tiles[x + y*worldSize].wall = wall
proc setBack(x, y: int, back: Block) = tiles[x + y*worldSize].back = back

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

sys("controlled", [Input, Pos, Vel]):
  all:
    let v = vec2(axis(keyA, keyD), 0).lim(1) * pspeed * fau.delta
    item.vel.x += v.x
    item.vel.y += v.y

    if keySpace.tapped:
      item.vel.y += jumpvel

sys("falling", [Falling, Vel]):
  all:
    item.vel.y -= gravity * fau.delta

sys("moveSolid", [Pos, Vel, Solid]):
  all:
    let delta = moveDelta(rectCenter(item.pos.x, item.pos.y, hitsize, hitsize), item.vel.x, item.vel.y, proc(x, y: int): bool = solid(x, y))
    item.pos.x += delta.x
    item.pos.y += delta.y
    if delta.x.zero: item.vel.x = 0
    if delta.y.zero: item.vel.y = 0

sys("momentum", [Vel]):
  all:
    item.vel.x = clamp(item.vel.x, -maxvel, maxvel)
    item.vel.y = clamp(item.vel.y, -maxvel, maxvel)
    item.vel.x *= (1f - item.vel.xdrag * fau.delta)
    item.vel.y *= (1f - item.vel.ydrag * fau.delta)

sys("camfollow", [Input, Pos]):
  all:
    fau.cam.pos = item.pos.vec2

sys("draw", [Main]):
  vars:
    buffer: Framebuffer
  init:
    sys.buffer = newFramebuffer()
    fau.pixelScl = 1f / tsize
    initContent()

    for tile in tiles.mitems:
      tile.wall = blockAir
      tile.back = blockAir

    for i in 0..<worldSize:
      setWall(i, 0, blockDirt)

    discard newEntityWith(Player(), DrawPlayer(), Pos(y: 5), Input(), Falling(), Solid(), Vel(xdrag: 50, ydrag: 2))

    #load all block textures before rendering
    for b in blockList:
      var maxFound = 0
      for i in 1..12:
        if not fau.atlas.patches.hasKey(b.name & $i): break
        maxFound = i

      if maxFound == 0:
        if fau.atlas.patches.hasKey(b.name):
          b.patches = @[b.name.patch]
      else:
        b.patches = (1..maxFound).toSeq().mapIt((b.name & $it).patch)

  start:
    if keyEscape.tapped: quitApp()
    
    fau.cam.resize(fau.widthf / scl, fau.heightf / scl)
    fau.cam.use()

    #sys.buffer.resize(fau.width div pixelation, fau.height div pixelation)

    #draw all tiles TODO
    for x, y, t in eachTile():
      let r = hashInt(x + y * worldSize)
      if t.back.id != 0:
        draw(t.back.patches[r mod t.back.patches.len], x, y)

      if t.wall.id != 0:
        let reg = t.wall.name.patch
        draw(reg, x, y)

sys("drawPlayer", [Player, Pos]):
  all:
    draw("player".patch, item.pos.x, item.pos.y)

#endregion

launchFau("ld48")