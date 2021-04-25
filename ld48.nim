import ecs, presets/[basic, effects], math, sequtils, quadtree, random, bloom

static: echo staticExec("faupack -p:assets-raw/sprites -o:assets/atlas")

#region types & consts

const
  scl = 48f
  worldh = 24
  worldw = 30
  pspeed = 12f
  hitw = 0.6f
  hith = 1f - 2f/12f
  jumpvel = 0.8f
  tsize = 12f
  maxvel = 0.7f
  edgeDark = rgb(1.6)
  edgeLight = rgb(0.4)
  backCol = rgb(0.4)
  layerBack = -2f
  hangTime = 0.05
  layerBloom = 50
  invulnSecs = 0.5

type
  QuadRef = object
    entity: EntityRef
    x, y, w, h: float32
  Shoot = enum
    sbasic, striple, scircle

registerComponents(defaultComponentOptions):
  type
    Vel = object
      x, y: float32

    Hit = object
      s: float32
    Player = object
      xs, ys: float32
      reload: float32
      invuln: float32
      shoot: Shoot
    Health = object
      value: int
      flash: float32

    Input = object
    Solid = object
    Bullet = object
      shooter: EntityRef
    Damage = object
      amount: int

    Powerup = object
      shoot: Shoot

    #enemies
    Enemy = object
      life: float32
      reload: float32
      sprite: string
      drop: float32
    Spiker = object
    Egg = object

defineEffects:

  shadowBullet:
    fillCircle(e.x, e.y, 4.px, z = layerBloom, color = %"ff55ff")
    fillCircle(e.x, e.y, 2.px, z = layerBloom, color = %"ffc0ff")

  pdeath(lifetime = 0.5):
    particles(e.id, 10, e.x, e.y, 14.px * e.fin):
      fillCircle(x, y, 7.px * e.fout, color = %"ffc0ff")

  phit(lifetime = 0.2):
    particles(e.id, 5, e.x, e.y, 14.px * e.fin):
      fillCircle(x, y, 3.px * e.fout, color = %"ffffff")

  pickup(lifetime = 0.8):
    particles(e.id, 6, e.x, e.y, 30.px * e.fin):
      fillPoly(x, y, 3, 8.px * e.fout, angle(x, y), color = %"99e550")

  bolt(lifetime = 0.1):
    fillPoly(e.x, e.y, 3, 8.px * e.fout, z = layerBloom, rotation = e.rotation, color = colorWhite)

  frogb1:
    fillCircle(e.x, e.y, 4.px, z = layerBloom, color = %"99e550")
    fillCircle(e.x, e.y, 2.px, z = layerBloom, color = colorWhite)

  flash(lifetime = 1):
    draw(fau.white, fau.cam.pos.x, fau.cam.pos.y, width = fau.cam.w, height = fau.cam.h, color = rgba(e.color.r, e.color.g, e.color.b, e.fout * e.color.a))

#endregion

var lastPos: Vec2
var lastPlayer: EntityRef

#region utilities

proc inBounds(value: Vec2): bool = value.x >= 0 and value.x <= worldw and value.y >= 0 and value.y <= worldh

template restart(start: bool = false) =
  sysAll.clearAll()

  discard newEntityWith(Player(xs: 1f, ys: 1f), Pos(y: 5, x: worldh/2), Input(), Solid(), Health(value: 3), Hit(s: 0.6))
  discard newEntityWith(Egg(), Enemy(sprite: "egg"), Pos(y: 5, x: worldw - 1), Solid(), Health(value: 5), Hit(s: 0.8))

  if not start:
    effectFlash(0, 0, col = colorWhite, life = 2f)
  else:
    when not defined(debug):
      effectFlash(0, 0, col = colorBlack, life = 3f)

macro shoot(t: untyped, ent: EntityRef, xp, yp, rot: float32, speed = 0.1, damage = 1, life = 400f, size = 0.3f) =
  let effectId = ident("effectId" & t.repr.capitalizeAscii)
  result = quote do:
    let vel = vec2l(`rot`, `speed`)
    #hitEffect: effectIdHit,
    discard newEntityWith(Pos(x: `xp`, y: `yp`), Timed(lifetime: `life`), Effect(id: `effectId`, rotation: `rot`), Bullet(shooter: `ent`), Hit(s: `size`), Vel(x: vel.x, y: vel.y), Damage(amount: `damage`))

template makeEnemy(t: untyped, ey: float32, health: int = 5, hsize = 0.8f, dropchance = 0.1f) =
  discard newEntityWith(t(), Enemy(sprite: "egg", drop: dropchance), Pos(y: ey, x: worldw + 1), Solid(), Health(value: health), Hit(s: hsize))

template timer(time: untyped, delay: float32, body: untyped) =
  time += fau.delta
  if time >= delay:
    time = 0
    body

#endregion

#region systems

makeTimedSystem()

sys("spawner", [Main]):
  start:
    if chance(0.01):
      makeEnemy(Egg, rand(0f..worldh.float32))

sys("controlled", [Input, Pos, Player]):
  all:
    let v = vec2(axis(keyA, keyD), axis(KeyCode.keyS, keyW)).lim(1) * pspeed * fau.delta
    item.pos.x += v.x
    item.pos.y += v.y
    item.pos.x = clamp(item.pos.x, 0, worldw)
    item.pos.y = clamp(item.pos.y, 0, worldh)
    lastPlayer = item.entity

    lastPos = item.pos.vec2

    if v.x.abs > 0:
      item.player.xs += sin(fau.time, 1f / 20f, 0.06)

    item.player.invuln -= fau.delta / invulnSecs

    case item.player.shoot:
      of sbasic:
        timer(item.player.reload, 0.1): shoot(frogb1, item.entity, item.pos.x, item.pos.y, 0, speed = 0.4f)
      of striple:
        timer(item.player.reload, 0.1):
          shotgun(3, 10f):
            shoot(frogb1, item.entity, item.pos.x, item.pos.y, angle, speed = 0.4f)
      of scircle:
        timer(item.player.reload, 0.12):
          circle(6):
            shoot(frogb1, item.entity, item.pos.x, item.pos.y, angle, speed = 0.4f)

sys("bullet", [Pos, Vel, Bullet, Hit]):
  all:
    item.pos.x += item.vel.x
    item.pos.y += item.vel.y

    if not inBounds(item.pos.vec2):
      effectPhit(item.pos.x, item.pos.y)
      item.entity.delete()

sys("bulletEffect", [Pos, Vel, Bullet, Effect]):
  all:
    item.effect.rotation = item.vel.vec2.angle

sys("vel", [Pos, Vel]):
  all:
    item.pos.x += item.vel.x
    item.pos.y += item.vel.y

sys("quadtree", [Pos, Hit]):
  vars:
    tree: Quadtree[QuadRef]
  init:
    sys.tree = newQuadtree[QuadRef](rect(-1f, -1f, worldw + 2, worldh + 2))
  start:
    sys.tree.clear()
  all:
    sys.tree.insert(QuadRef(entity: item.entity, x: item.pos.x - item.hit.s/2.0, y: item.pos.y - item.hit.s/2.0, w: item.hit.s, h: item.hit.s))

sys("collide", [Pos, Bullet, Hit]):
  vars:
    output: seq[QuadRef]
  all:
    sys.output.setLen(0)
    let r = rectCenter(item.pos.x, item.pos.y, item.hit.s, item.hit.s)
    sysQuadtree.tree.intersect(r, sys.output)
    for elem in sys.output:
      if elem.entity != item.bullet.shooter and
        elem.entity != item.entity and
        elem.entity.alive and
        item.bullet.shooter.alive and
        not elem.entity.has(Bullet) and
        not(elem.entity.has(Enemy) and item.bullet.shooter.has(Enemy)) and
        not(elem.entity.has(Player) and elem.entity.fetch(Player).invuln > 0):

        let
          hitter = item.entity
          target = elem.entity

        var kill = false

        whenComp(hitter, Damage):
          whenComp(target, Health):
            whenComp(target, Pos):
              health.value -= damage.amount
              health.flash = 1f

              if health.value <= 0:
                effectPdeath(pos.x, pos.y)
                kill = true

              whenComp(target, Player):
                player.invuln = 1f
                effectFlash(0, 0, col = %"ff464688", life = 0.3f)

        if kill:
          if target.has Player:
            restart()
            break
          else:
            whenComp(target, Enemy):
              if chance(enemy.drop):
                whenComp(target, Pos):
                  discard newEntityWith(Pos(x: pos.x, y: pos.y), Powerup(shoot: rand(striple..Shoot.high)))
            target.delete()

        effectPhit(item.pos.x, item.pos.y)
        hitter.delete()
        break

sys("hflash", [Health]):
  all:
    item.health.flash -= fau.delta / 0.3f

sys("enemy", [Enemy, Pos]):
  all:
    item.enemy.life += fau.delta
    if item.pos.x < -1f:
      item.entity.delete()

sys("powerup", [Powerup, Pos]):
  all:
    item.pos.x -= fau.delta * 0.7f
    if item.pos.x < -1f:
      item.entity.delete()
    elif item.pos.vec2.within(lastPos, 0.6) and lastPlayer.alive:
      effectPickup(item.pos.x, item.pos.y)
      lastPlayer.fetch(Player).shoot = item.powerup.shoot
      item.entity.delete()

sys("spiker", [Spiker, Pos, Enemy]):
  all:
    timer(item.enemy.reload, 1):
      circle(4):
        shoot(shadowBullet, item.entity, item.pos.x, item.pos.y, angle + item.enemy.life / 2.0)

sys("egg", [Egg, Pos, Enemy]):
  all:
    item.pos.x -= 0.5f * fau.delta
    timer(item.enemy.reload, 1):
      circle(4):
        shoot(shadowBullet, item.entity, item.pos.x, item.pos.y, angle + item.enemy.life / 2.0)

sys("draw", [Main]):
  vars:
    buffer: Framebuffer
    bloom: Bloom
    bg: Texture
  init:
    sys.buffer = newFramebuffer()
    sys.bloom = newBloom()
    sys.bg = loadTextureStatic("space.png")
    sys.bg.wrapRepeat()

    fau.pixelScl = 1f / tsize

    restart(true)

  start:
    if keyEscape.tapped: quitApp()

    let
      wsizepx = worldh * tsize
      pixelation = (scl / tsize).int

    fau.cam.resize(worldw, worldh)
    fau.cam.pos = vec2(worldw / 2f, worldh / 2f)
    fau.cam.use()

    sys.buffer.resize((worldw * tsize).int, (worldh * tsize).int)
    sys.buffer.push(colorClear)
    let buf = sys.buffer
    let bloom = sys.bloom

    var bgp = sys.bg.Patch
    bgp.scroll(fau.time / 100f, 0f)
    draw(bgp, worldw/2f, worldh/2f, z = -999)

    var r = initRand(123)

    for i in 0..50:
      let
        sscl = r.rand(0.6..1.5)
        cx = (r.rand(0..worldw) - fau.time * 15.0 * sscl + 10f).emod(worldw + 20f) - 10f
        cy = r.rand(0..worldh)
        len = r.rand(3f..7f)
      line(cx, cy, cx + len, cy)

    draw(1000, proc() =
      buf.pop()
      screenMat()
      draw(buf.texture, fau.widthf/2f, fau.heightf/2f, width = fau.heightf * worldw / worldh, height = -fau.heightf)
      for i in signs():
        draw("border".patch, fau.widthf/2f + i * fau.heightf * worldw / worldh / 2f, fau.heightf/2f, height = fau.heightf, width = 3f * 4f)
      drawFlush()
      #replace with pause in the main bloom layer for smoother results
      #bloom.render()
    )

    #drawLayer(layerBloom, proc() = bloom.capture(), proc() = bloom.render())


sys("drawPlayer", [Player, Pos, Health]):
  all:
    let alpha = 10.0 * fau.delta
    item.player.xs = item.player.xs.lerpc(1.0, alpha)
    item.player.ys = item.player.ys.lerpc(1.0, alpha)
    let
      sscl = 10f.inv
      ox = sin(fau.time, sscl, 0.1f)
      oy = cos(fau.time, sscl, 0.1f)
    draw("player".patch, item.pos.x + ox, item.pos.y + oy, xscl = item.player.xs, yscl = item.player.ys, mixcolor = rgba(1, 1, 1, clamp(item.health.flash)))
    draw("boost".patch, item.pos.x - 4.px + ox, item.pos.y - 2.px + oy, xscl = 1f + sin(fau.time, 1f / 14f, 0.15f))

    let max = item.health.value

    draw(2001, proc() =
      const size = 12f * 5f
      for i in 0..<max:
        draw("life".patch, 10f + i * (10f + size), fau.heightf - 10f, align = daTopLeft, width = size, height = size)
    )

sys("drawpowerup", [Pos, Powerup]):
  all:
    let name = case item.powerup.shoot:
      of striple: "p-triple"
      of scircle: "p-circle"
      else: "powerup"
    draw(name.patch, item.pos.x, item.pos.y, mixcolor = rgba(1, 1, 1, absin(fau.time, 1f / 10f, 1f)))

sys("drawSpiker", [Spiker, Pos, Enemy]):
  all:
    let s = 1f + sin(item.enemy.life, 0.1f, 0.1f)
    draw("spiker-spikes".patch, item.pos.x, item.pos.y, rotation = item.enemy.life * 2.0, xscl = s, yscl = s)
    draw("spiker".patch, item.pos.x, item.pos.y, xscl = s, yscl = s)

sys("enemyDraw", [Enemy, Pos, Health]):
  all:
    if item.enemy.sprite != "":
      draw(item.enemy.sprite.patch, item.pos.x, item.pos.y, mixcolor = rgba(1, 1, 1, clamp(item.health.flash)))

sys("all", [Pos]):
  init:
    discard

makeEffectsSystem()

#endregion

launchFau("ld48")