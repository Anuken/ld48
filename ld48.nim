import ecs, presets/[basic, effects, content], math, sequtils, quadtree, simplex, random, bloom

static: echo staticExec("faupack -p:assets-raw/sprites -o:assets/atlas")

#region types & consts

const
  scl = 48f
  worldSize = 20
  gravity = 2f
  pspeed = 12f
  hitw = 0.6f
  hith = 1f - 2f/12f
  jumpvel = 0.8f
  tsize = 12f
  maxvel = 0.7f
  pixelation = (scl / tsize).int
  edgeDark = rgb(1.6)
  edgeLight = rgb(0.4)
  backCol = rgb(0.4)
  layerBack = -2f
  hangTime = 0.05
  layerBloom = 50

type
  Rot = range[0..3]
  Tile = object
    back, wall: Block
    rot: Rot

  Block = ref object of Content
    solid: bool
    patches: seq[Patch]
    top: Patch
    border: bool
    color: Color
    sway: bool

  QuadRef = object
    entity: EntityRef
    x, y, w, h: float32

registerComponents(defaultComponentOptions):
  type
    Vel = object
      x, y, xdrag, ydrag: float32
      onGround: bool
      hang: float32

    Hit = object
      s: float32
    Player = object
    DrawPlayer = object
    Health = object
      value: int

    Input = object
    Falling = object
    Solid = object
    Bullet = object
      damage: float32
      shooter: EntityRef
    Damage = object
      amount: float32

    #enemies
    Enemy = object
      life: float32
    Spiker = object
      reload: float32

makeContent:
  air = Block()
  dirt = Block(solid: true, border: true, color: %"663931")
  grass = Block(solid: false, sway: true)

defineEffects:
  jump(lifetime = 0.3):
    particles(e.id, 5, e.x, e.y, 11.px * e.fin):
      fillCircle(x, y, 7.px * e.fout, color = %"c3c3c3")

  shadowBullet:
    fillCircle(e.x, e.y, 5.px, z = layerBloom, color = %"ff55ff")
    fillCircle(e.x, e.y, 2.px, z = layerBloom, color = %"ffc0ff")

#endregion

#region global variables

var tiles = newSeq[Tile](worldSize * worldSize)

#endregion

#region utilities

proc tile(x, y: int): Tile {.inline.} =
  if x >= worldSize or y >= worldSize or x < 0 or y < 0: Tile(back: blockAir, wall: blockAir) else: tiles[x + y*worldSize]

proc setWall(x, y: int, wall: Block) = tiles[x + y*worldSize].wall = wall
proc setBack(x, y: int, back: Block) = tiles[x + y*worldSize].back = back
proc solid(x, y: int): bool = tile(x, y).wall.solid
proc empty(t: Tile): bool {.inline.} = t.wall.id == 0

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

iterator allTiles*(): tuple[x, y: int, tile: Tile] =
  for x in 0..<worldSize:
    for y in 0..<worldSize:
      yield (x, y, tiles[x + y * worldSize])

template genWorld(cx, cy: int) =
  for tile in tiles.mitems:
    tile.wall = blockAir
    tile.back = blockAir

  clearAll(sysEnemy)
  clearAll(sysBullet)

  simplexSeed(rand(100000))

  for x, y, t in allTiles():
    if fractal(x.float, y.float, 2, freq = 0.1) > 0.2:
      setBack(x, y, blockDirt)

  for i in 0..<worldSize:
    let fit = abs(i + 0.5 - worldSize/2f) > 5
    #top
    if cy != -1 or fit: setWall(i, worldSize - 1, blockDirt)
    #left
    if cx != 1 or fit: setWall(0, i, blockDirt)
    #right
    if cx != -1 or fit: setWall(worldSize - 1, i, blockDirt)
    #bot
    if fit: setWall(i, 0, blockDirt)

  discard newEntityWith(Enemy(), Spiker(), Pos(y: 5, x: rand(0.5f..worldSize.float32 - 1)), Solid(), Vel())

  for x, y, t in allTiles():
    if t.empty and tile(x, y - 1).wall == blockDirt and chance(0.3):
      setWall(x, y, blockGrass)

    if t.empty and fractal(x.float, y.float + 30, 2, freq = 0.1) > 0.3:
      setWall(x, y, t.back)

macro shoot(t: untyped, ent: EntityRef, xp, yp, rot: float32, speed = 0.1, damage = 1f, life = 400f) =
  let effectId = ident("effectId" & t.repr.capitalizeAscii)
  result = quote do:
    let vel = vec2l(`rot`, `speed`)
    #hitEffect: effectIdHit,
    discard newEntityWith(Pos(x: `xp`, y: `yp`), Timed(lifetime: `life`), Effect(id: `effectId`, rotation: `rot`), Bullet(shooter: `ent`), Hit(s: 0.2), Vel(x: vel.x, y: vel.y), Damage(amount: `damage`))

template timer(time: untyped, delay: float32, body: untyped) =
  time += fau.delta
  if time >= delay:
    time = 0
    body

#endregion

#region systems

makeTimedSystem()

sys("controlled", [Input, Pos, Vel]):
  all:
    let v = vec2(axis(keyA, keyD), 0).lim(1) * pspeed * fau.delta
    item.vel.x += v.x
    item.vel.y += v.y

    if keySpace.tapped and item.vel.hang > 0:
      item.vel.y += jumpvel
      effectJump(item.pos.x, item.pos.y - hith/2f)
      item.vel.hang = 0

    #TODO attack
    if keyJ.tapped:
      discard

    template transition(cx, cy: int) =
      item.pos.x = (item.pos.x + 0.5f).emod(worldSize) - 0.5f
      item.pos.y = (item.pos.y + 0.5f).emod(worldSize) - 0.5f
      item.pos.x = clamp(item.pos.x, -0.4, worldSize - 0.6)
      item.pos.y = clamp(item.pos.y, -0.4, worldSize - 0.6)
      genWorld(cx, cy)

    #transition levels
    if item.pos.x < -0.5: transition(-1, 0)
    elif item.pos.y < -0.5: transition(0, -1)
    elif item.pos.x > worldSize - 0.5: transition(1, 0)
    #elif item.pos.x > worldSize: transition(1, 0)

sys("falling", [Falling, Vel]):
  all:
    item.vel.y -= gravity * fau.delta

sys("bullet", [Pos, Vel, Bullet, Hit]):
  all:
    item.pos.x += item.vel.x
    item.pos.y += item.vel.y

    if collidesTiles(rectCenter(item.pos.x, item.pos.y, item.hit.s, item.hit.s), proc(x, y: int): bool = solid(x, y)):
      item.entity.delete()

sys("bulletEffect", [Pos, Vel, Bullet, Effect]):
  all:
    item.effect.rotation = item.vel.vec2.angle

sys("moveSolid", [Pos, Vel, Solid]):
  all:
    let delta = moveDelta(rectCenter(item.pos.x, item.pos.y, hitw, hith), item.vel.x, item.vel.y, proc(x, y: int): bool = solid(x, y))
    item.pos.x += delta.x
    item.pos.y += delta.y
    #is considered on ground when something is blocking the path down
    item.vel.onGround = item.vel.y < 0 and delta.y.zero
    if item.vel.onGround:
      item.vel.hang = hangTime
    else:
      item.vel.hang -= fau.delta
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
    fau.cam.pos = vec2(worldSize.float32) / 2.0 - 0.5f
    fau.cam.pos += vec2((fau.widthf mod scl) / scl, (fau.heightf mod scl) / scl) * fau.pixelScl
    #fau.cam.pos = item.pos.vec2

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
      if elem.entity != item.bullet.shooter and elem.entity != item.entity and elem.entity.alive and not elem.entity.has(Bullet) and item.bullet.shooter.alive and not(elem.entity.has(Enemy) and item.bullet.shooter.has(Enemy)):
        let
          hitter = item.entity
          target = elem.entity
        hitter.delete()
        break


sys("enemy", [Enemy]):
  all:
    item.enemy.life += fau.delta

sys("spiker", [Spiker, Pos, Enemy]):
  all:
    timer(item.spiker.reload, 1):
      circle(4):
        shoot(shadowBullet, item.entity, item.pos.x, item.pos.y, angle + item.enemy.life / 2.0)

sys("draw", [Main]):
  vars:
    buffer: Framebuffer
    bloom: Bloom
  init:
    sys.buffer = newFramebuffer()
    sys.bloom = newBloom()

    fau.pixelScl = 1f / tsize
    initContent()

    genWorld(0, 1)

    discard newEntityWith(Player(), DrawPlayer(), Pos(y: 5, x: worldSize/2), Input(), Falling(), Solid(), Vel(xdrag: 50, ydrag: 2), Health(value: 2), Hit(s: 0.8))

    #load all block textures before rendering
    for b in blockList:
      b.top = (b.name & "-top").patch
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

    #TODO for a better cam: fau.cam.resize(fau.widthf / (fau.heightf / worldSize), worldSize)
    fau.cam.resize(fau.widthf / scl, fau.heightf / scl)
    fau.cam.use()

    sys.buffer.resize(fau.width div pixelation, fau.height div pixelation)
    sys.buffer.push(colorClear)
    let buf = sys.buffer
    let bloom = sys.bloom

    draw(1000, proc() =
      buf.pop()
      buf.blitQuad()
      #replace with pause in the main bloom layer for smoother results
      #bloom.render()
    )

    drawLayer(layerBloom, proc() = bloom.capture(), proc() = bloom.render())

    var edge = "edge".patch

    #draw all tiles
    for x, y, t in eachTile():
      let r = hashInt(x + y * worldSize)

      #background
      if t.back.id != 0:
        draw(t.back.patches[r mod t.back.patches.len], x, y, z = layerBack, color = backCol)
        for dx, dy, i in d4i():
          if tile(x + dx, y + dy).back.id != t.back.id:
            draw(edge, x, y, rotation = i * 90.rad, color = if i > 1: edgeLight * t.back.color * backCol else: edgeDark * t.back.color * backCol, z = layerBack + 0.1)

      #draw wall stuff
      if t.wall.id != 0:
        let reg = t.wall.patches[r mod t.wall.patches.len]

        if t.wall.sway:
          let trns = noise((fau.time + x + y) / 2) * 6.px
          drawv(reg, x, y, c2 = vec2(trns, 0), c3 = vec2(trns, 0))
        else:
          draw(reg, x, y)

        #borders
        if t.wall.border:
          for dx, dy, i in d4i():
            if tile(x + dx, y + dy).wall.id != t.wall.id:
              draw(edge, x, y, rotation = i * 90.rad, color = if i > 1: edgeLight * t.wall.color else: edgeDark * t.wall.color)

      #top region, if applicable
      if t.wall.top.exists and not tile(x, y + 1).wall.solid:
        draw(t.wall.top, x, y)


sys("drawPlayer", [Player, Pos]):
  all:
    draw("player".patch, item.pos.x, item.pos.y)

sys("drawSpiker", [Spiker, Pos, Enemy]):
  all:
    let s = 1f + sin(item.enemy.life, 0.1f, 0.1f)
    draw("spiker-spikes".patch, item.pos.x, item.pos.y, rotation = item.enemy.life * 2.0, scl = s)
    draw("spiker".patch, item.pos.x, item.pos.y, scl = s)

makeEffectsSystem()

#endregion

launchFau("ld48")