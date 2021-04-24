import ecs, presets/[basic, effects, content], math, sequtils, quadtree

static: echo staticExec("faupack -p:assets-raw/sprites -o:assets/atlas")

#region types & consts

const
  scl = 48f
  worldSize = 20
  gravity = 2f
  pspeed = 12f
  hitsize = 0.6f
  jumpvel = 0.7f
  tsize = 12f
  maxvel = 0.7f
  pixelation = (scl / tsize).int

type
  Rot = range[0..3]
  Tile = object
    back, wall: Block
    rot: Rot

  Block = ref object of Content
    solid: bool
    patches: seq[Patch]

  QuadRef = object
    entity: EntityRef
    x, y, w, h: float32

registerComponents(defaultComponentOptions):
  type
    Vel = object
      x, y, xdrag, ydrag: float32
      onGround: bool

    Hit = object
      s: float32
    Player = object
    DrawPlayer = object
    Health = object
      value, max: float32

    Enemy = object
    Input = object
    Falling = object
    Solid = object
    Bullet = object
      damage: float32
      shooter: EntityRef

makeContent:
  air = Block()
  dirt = Block(solid: true)

defineEffects:
  jump(lifetime = 0.3):
    particles(e.id, 5, e.x, e.y, 10.px * e.fin):
      fillCircle(x, y, 9.px * e.fout, color = %"663931")

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

makeTimedSystem()

sys("controlled", [Input, Pos, Vel]):
  all:
    let v = vec2(axis(keyA, keyD), 0).lim(1) * pspeed * fau.delta
    item.vel.x += v.x
    item.vel.y += v.y

    if keySpace.tapped and item.vel.onGround:
      item.vel.y += jumpvel
      effectJump(item.pos.x, item.pos.y - hitsize)

sys("falling", [Falling, Vel]):
  all:
    item.vel.y -= gravity * fau.delta

sys("moveSolid", [Pos, Vel, Solid]):
  all:
    let delta = moveDelta(rectCenter(item.pos.x, item.pos.y, hitsize, hitsize), item.vel.x, item.vel.y, proc(x, y: int): bool = solid(x, y))
    item.pos.x += delta.x
    item.pos.y += delta.y
    #is considered on ground when something is blocking the path down
    item.vel.onGround = item.vel.y < 0 and delta.y.zero
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

sys("quadtree", [Pos, Vel, Hit]):
  vars:
    tree: Quadtree[QuadRef]
  init:
    sys.tree = newQuadtree[QuadRef](rect(-0.5, -0.5, worldSize + 1, worldSize + 1))
  start:
    sys.tree.clear()
  all:
    sys.tree.insert(QuadRef(entity: item.entity, x: item.pos.x - item.hit.s/2.0, y: item.pos.y - item.hit.s/2.0, w: item.hit.s, h: item.hit.s))

sys("collide", [Pos, Vel, Bullet, Hit]):
  vars:
    output: seq[QuadRef]
  all:
    sys.output.setLen(0)
    let r = rectCenter(item.pos.x, item.pos.y, item.hit.s, item.hit.s)
    sysQuadtree.tree.intersect(r, sys.output)
    for elem in sys.output:
      if elem.entity != item.bullet.shooter and elem.entity != item.entity and elem.entity.alive and item.bullet.shooter.alive and not(elem.entity.hasComponent(Enemy) and item.bullet.shooter.hasComponent(Enemy)):
        discard

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

    sys.buffer.resize(fau.width div pixelation, fau.height div pixelation)
    sys.buffer.push(colorClear)
    let buf = sys.buffer

    draw(100, proc() =
      buf.pop()
      buf.blitQuad()
    )

    #draw all tiles
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

makeEffectsSystem()

#endregion

launchFau("ld48")