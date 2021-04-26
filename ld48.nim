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
    sbasic, striple, scircle, ssine, svert
  Timers = object
    eggs0, boiled0, toast1, eggs1, boiled1, formation, formation2: float32

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
      val: float32
    Egg = object
    Boiled = object
    Toast = object
    Fried = object
    Pickled = object
    Eggnog = object
    Omlette = object
    OmletteBig = object
      phase: float32

defineEffects:

  standardBullet:
    fillCircle(e.x, e.y, 4.px, z = layerBloom, color = e.color)
    fillCircle(e.x, e.y, 2.px, z = layerBloom, color = colorWhite)

  pdeath(lifetime = 0.5):
    particles(e.id, 10, e.x, e.y, 14.px * e.fin):
      fillCircle(x, y, 7.px * e.fout, color = %"ffffff")

  phit(lifetime = 0.2):
    particles(e.id, 5, e.x, e.y, 14.px * e.fin):
      fillCircle(x, y, 3.px * e.fout, color = %"ffffff")

  pickup(lifetime = 0.8):
    particles(e.id, 6, e.x, e.y, 30.px * e.fin):
      fillPoly(x, y, 3, 8.px * e.fout, angle(x, y), color = %"99e550")

  frogb1:
    fillCircle(e.x, e.y, 4.px, z = layerBloom, color = %"99e550")
    fillCircle(e.x, e.y, 2.px, z = layerBloom, color = colorWhite)

  flash(lifetime = 1):
    draw(fau.white, fau.cam.pos.x, fau.cam.pos.y, width = fau.cam.w, height = fau.cam.h, color = rgba(e.color.r, e.color.g, e.color.b, e.fout * e.color.a))

#endregion

var
  lastPos: Vec2
  lastPlayer: EntityRef
  timers: Timers
  spawnedBoss = false
  won = false
  started = false
  destroyed = 0
  startfade = 1f
  endfade = 0f

#region utilities

proc inBounds(value: Vec2): bool = value.x >= 0 and value.x <= worldw and value.y >= 0 and value.y <= worldh

template restart(start: bool = false) =
  sysAll.clearAll()
  fau.time = 0f
  timers = Timers()
  spawnedBoss = false
  destroyed = 0

  for value in timers.fields:
    value = rand(0f..1f)

  discard newEntityWith(Player(xs: 1f, ys: 1f), Pos(x: worldw/2f, y: worldh/2f), Input(), Solid(), Health(value: 4), Hit(s: 0.6))

  if not start:
    effectFlash(0, 0, col = colorWhite, life = 2f)
  else:
    when not defined(debug):
      effectFlash(0, 0, col = colorBlack, life = 3f)

macro shoot(t: untyped, ent: EntityRef, xp, yp, rot: float32, speed = 0.08f, damage = 1, life = 400f, size = 0.3f, color = colorWhite) =
  let effectId = ident("effectId" & t.repr.capitalizeAscii)
  result = quote do:
    let vel = vec2l(`rot`, `speed`)
    #hitEffect: effectIdHit,
    discard newEntityWith(Pos(x: `xp`, y: `yp`), Timed(lifetime: `life`), Effect(id: `effectId`, rotation: `rot`, color: `color`), Bullet(shooter: `ent`), Hit(s: `size`), Vel(x: vel.x, y: vel.y), Damage(amount: `damage`))

template makeEnemy(t: untyped, ex = worldw + 1f, ey = worldh / 2f, health: int = 5, hsize = 0.8f, dropchance = 0.05f, spr: string = "", v = 0f) =
  discard newEntityWith(t(), Enemy(sprite: spr, drop: dropchance, val: v), Pos(y: ey, x: ex), Solid(), Health(value: health), Hit(s: hsize))

template timer(time: untyped, delay: float32, body: untyped) =
  time += fau.delta
  if time >= delay:
    time = 0
    body

#endregion

#region systems

makeTimedSystem()

sys("spawner", [Main]):
  vars:
    time: float32
  start:
    if not started: return
    #the game is split into several phases; each one lasts a few seconds, with 6 total
    var phase = (fau.time / 30).int

    #TODO remove later
    #when defined(debug): phase = 1

    case phase:
      of 0:
        timer(timers.eggs0, 14f):
          let vy = rand(6f..(worldh-6f))
          circlev(5, 4f):
            makeEnemy(Egg, ex = worldw + 5f + x, ey = y + vy, spr = "egg")
        timer(timers.boiled1, 3f):
          makeEnemy(Boiled, ex = worldw + 1f, ey = rand(1f..(worldh-1f)))
      of 1:
        timer(timers.eggs0, 1.8f):
          makeEnemy(Fried, ex = worldw + 1f, ey = rand(0.1f..(worldh-10f)), health = 7, hsize = 1f)
        timer(timers.boiled1, 8f):
          for v in [worldh - 1f, worldh - 2f, 1f, 2f]:
            makeEnemy(Boiled, ex = worldw + 1f, ey = v, health = 4)
      of 2:
        timer(timers.boiled1, 0.45f):
          makeEnemy(Boiled, ex = worldw + 1f, ey = timers.formation + 1, health = 4)
          timers.formation += 1f
          if timers.formation >= worldh - 1f:
            timers.formation = 0
            timers.boiled1 = -7f

        timer(timers.eggs0, 12f):
          let max = 5
          for i in 1..max:
            makeEnemy(Egg, ex = worldw + 1f, ey = worldh / max * i.float32 - 2f, spr = "egg")
      of 3:
        timer(timers.eggs0, 20f):
          makeEnemy(Toast, ex = worldw + 0.5f, ey = worldh / 2f, health = 25, hsize = 1.2f)

        timer(timers.boiled1, 4f):
          makeEnemy(Fried, ex = worldw + 1f, ey = worldh/2f, health = 6, hsize = 1f)
          makeEnemy(Fried, ex = worldw + 1f, ey = 1f, health = 6, hsize = 1f)
      of 4:
        timer(timers.eggs0, 5f):
          makeEnemy(Omlette, ex = worldw + 1f, ey = worldh - 1f, health = 8, hsize = 1.2f, v = 181f.rad)
          makeEnemy(Omlette, ex = worldw + 1f, ey = 1f, health = 8, hsize = 1.2f, v = 179f.rad)

        timer(timers.boiled1, 0.3f):
          for i in signs():
            makeEnemy(Boiled, ex = worldw + 1f, ey = worldh/2f + (worldh/2f - (timers.formation + 0.75f)) * i, health = 4)
          timers.formation += 1f
          if timers.formation >= 3f:
            timers.formation = 0
            timers.boiled1 = -2f

        timer(timers.eggs1, 15f):
          makeEnemy(Toast, ex = worldw + 0.5f, ey = worldh / 2f, health = 22, hsize = 1.2f)
      of 5:
        timer(timers.boiled1, 0.75f):
          for i in signs():
            makeEnemy(Omlette, ex = worldw + 1f, ey = worldh/2f + (worldh/2f - (timers.formation * 2f + 0.75f)) * i, v = 181f.rad + i * 12.rad)
          timers.formation += 1f
          if timers.formation >= 4f:
            timers.formation = 0
            timers.boiled1 = -3f

        timer(timers.boiled0, 0.75f):
          for i in signs():
            makeEnemy(Omlette, ex = worldw + 1f, ey = worldh/2f + ((timers.formation2 * 2f + 0.75f)) * i, v = 181f.rad + i * 14.rad)
          timers.formation2 += 1f
          if timers.formation2 >= 4f:
            timers.formation2 = 0
            timers.boiled0 = -3f

        timer(timers.eggs1, 8f):
          makeEnemy(Eggnog, ex = worldw + 1f, ey = worldh / 2f, health = 10, hsize = 1.1f, v = 180f.rad)
      of 6:
        timer(timers.eggs1, 8f):
          makeEnemy(Pickled, ex = worldw + 1f, ey = worldh / 2f, health = 15, hsize = 1.3f)

        timer(timers.eggs0, 5f):
          makeEnemy(Eggnog, ex = worldw + 1f, ey = 0, health = 8, hsize = 1.1f, v = 140f.rad)
          makeEnemy(Eggnog, ex = worldw + 1f, ey = worldh, health = 8, hsize = 1.1f, v = 220f.rad)
      of 7:
        timer(timers.boiled1, 1f):
          makeEnemy(Fried, ex = worldw + 1f, ey = worldh/2f, health = 5, hsize = 1f)
          makeEnemy(Fried, ex = worldw + 1f, ey = 1f, health = 5, hsize = 1f)
      of 8:
        timer(timers.eggs1, 5f):
          makeEnemy(Pickled, ex = worldw + 1f, ey = rand(1f..(worldh-1f)), health = 15, hsize = 1.3f)
      of 9:
        timer(timers.eggs1, 2f):
          if not spawnedBoss:
            makeEnemy(OmletteBig, ex = worldw + 2f, ey = worldh/2f, health = 90, hsize = 2f, v = 180f.rad)
            spawnedBoss = true

        timer(timers.boiled1, 0.3f):
          for i in signs():
            makeEnemy(Boiled, ex = worldw + 1f, ey = worldh/2f + (worldh/2f - (timers.formation + 0.75f)) * i, health = 4)
          timers.formation += 1f
          if timers.formation >= 3f:
            timers.formation = 0
            timers.boiled1 = -2f
      else:
        #TODO
        discard

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
    #if v.y.abs > 0:
    #  item.player.ys += 0.08f

    item.player.invuln -= fau.delta / invulnSecs

    if started:
      case item.player.shoot:
        of sbasic:
          timer(item.player.reload, 0.1): shoot(frogb1, item.entity, item.pos.x, item.pos.y, 0, speed = 0.4f)
        of svert:
          timer(item.player.reload, 0.05):
            for i in signs():
              shoot(frogb1, item.entity, item.pos.x, item.pos.y, i * 90f.rad, speed = 0.45f)
        of striple:
          timer(item.player.reload, 0.15):
            shotgun(3, 10f):
              shoot(frogb1, item.entity, item.pos.x, item.pos.y, angle, speed = 0.4f)
        of scircle:
          timer(item.player.reload, 0.12):
            circle(9):
              shoot(frogb1, item.entity, item.pos.x, item.pos.y, angle, speed = 0.4f)
        of ssine:
          timer(item.player.reload, 0.03): shoot(frogb1, item.entity, item.pos.x, item.pos.y, sin(fau.time, 6.inv, 11f.rad), speed = 0.4f)

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
        not elem.entity.has(Bullet) and
        not(elem.entity.has(Enemy) and (not(item.bullet.shooter.alive) or item.bullet.shooter.has(Enemy))) and
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
              soundHit.play()

              whenComp(target, Player):
                soundPlayerHit.play()
                player.invuln = 1f
                effectFlash(0, 0, col = %"ff464688", life = 0.3f)

        if kill:
          if target.has Player:
            soundDeath.play()
            restart()
            break
          else:
            whenComp(target, Enemy):
              soundKill.play()
              destroyed.inc
              if chance(enemy.drop):
                whenComp(target, Pos):
                  discard newEntityWith(Pos(x: pos.x, y: pos.y), Powerup(shoot: rand(striple..Shoot.high)))

              if target.has(OmletteBig):
                won = true
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
    elif item.pos.vec2.within(lastPos, 0.8) and lastPlayer.alive:
      effectPickup(item.pos.x, item.pos.y)
      lastPlayer.fetch(Player).shoot = item.powerup.shoot
      item.entity.delete()
      soundPowerup.play()

sys("egg", [Egg, Pos, Enemy]):
  all:
    item.pos.x -= 1f * fau.delta
    timer(item.enemy.reload, 1.1f):
      circle(2):
        shoot(standardBullet, item.entity, item.pos.x, item.pos.y, angle + item.enemy.life / 2.0, color = %"eec39a")

sys("eggnog", [Eggnog, Pos, Enemy]):
  all:
    let m = vec2l(item.enemy.val, 7f * fau.delta)
    item.pos.x += m.x
    item.pos.y += m.y

    timer(item.enemy.reload, 0.23f):
      circle(2):
        shoot(standardBullet, item.entity, item.pos.x, item.pos.y, angle + item.enemy.val + 90.rad, color = %"eec39a")

sys("pickled", [Pickled, Pos, Enemy]):
  all:
    item.pos.x -= 4f * fau.delta

    timer(item.enemy.reload, 0.1f):
      item.enemy.val += 6f.rad
      circle(2):
        shoot(standardBullet, item.entity, item.pos.x, item.pos.y, angle + item.enemy.val + 90.rad + item.enemy.val, color = %"d8dff7")

sys("boiled", [Enemy, Pos, Boiled]):
  all:
    if item.pos.x > worldw - 1f:
      item.pos.x -= 0.85f * fau.delta
    elif not item.enemy.val.awithin(90.rad, 0.01f):
      item.enemy.val = aapproach(item.enemy.val, 90f.rad, 2f * fau.delta)
    else:
      item.pos.x -= 3.5f * fau.delta
      timer(item.enemy.reload, 1.3f):
        shoot(standardBullet, item.entity, item.pos.x, item.pos.y, 180f.rad, color = %"d8dff7", speed = 0.05f)

sys("fried", [Enemy, Pos, Fried]):
  all:
    item.pos.x -= 2f * fau.delta
    item.pos.y += sin(item.enemy.life, 1.1f, 0.07f)

    item.enemy.val += fau.delta * 4f

    timer(item.enemy.reload, 1f):
      shoot(standardBullet, item.entity, item.pos.x, item.pos.y, 90f.rad + item.enemy.val, color = %"fbf236")

sys("omlette", [Enemy, Pos, Omlette]):
  all:
    let s = (item.enemy.val > 180.rad).sign
    item.enemy.val += s * 0.14 * fau.delta

    let m = vec2l(item.enemy.val, 6f * fau.delta)
    item.pos.x += m.x
    item.pos.y += m.y

    timer(item.enemy.reload, 0.48f):
      shoot(standardBullet, item.entity, item.pos.x, item.pos.y, item.enemy.val + 90.rad * s, color = %"e2cd4c")

sys("toast", [Enemy, Pos, Toast]):
  all:
    item.pos.x -= 2f * fau.delta

    timer(item.enemy.reload, 0.5f):
      shotgun(3, 15):
        shoot(standardBullet, item.entity, item.pos.x, item.pos.y, 180.rad + angle + sin(item.enemy.life, 4f.inv, 10f).rad, color = %"663931")

sys("bigomlette", [Enemy, Pos, OmletteBig]):
  all:
    if item.pos.x > worldw - 3f:
      item.pos.x -= 2f * fau.delta

    item.omletteBig.phase += fau.delta
    let phase = (item.omletteBig.phase / 8f).int mod 3
    case phase:
      of 0:
        timer(item.enemy.reload, 0.25f):
          shotgun(3, 2f):
            shoot(standardBullet, item.entity, item.pos.x, item.pos.y, 180.rad + angle + sin(item.enemy.life, 4f.inv, 10f).rad, color = %"e2cd4c")
      of 1:
        timer(item.enemy.reload, 0.22f):
          circle(20):
            shoot(standardBullet, item.entity, item.pos.x, item.pos.y, angle + sin(item.enemy.life, 4f.inv, 10f).rad, color = %"e2cd4c")
      of 2:
        timer(item.enemy.reload, 0.16f):
          for i in signs():
            shoot(standardBullet, item.entity, item.pos.x, item.pos.y, 180.rad + sin(item.enemy.life, 3f.inv, 27f).rad * i + item.pos.vec2.angle(lastPos) + 180f.rad, color = %"e2cd4c")
      else: discard

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

    when not defined(debug): musicAwful.play(loop = true, volume = 0.8f)
    restart(true)

  start:
    if keyEscape.tapped: quitApp()

    if keyW.down or KeyCode.keyS.down or keyA.down or keyD.down:
      started = true

    if won:
      sysCollide.paused = true
      sysControlled.paused = true
      endfade = endfade.lerp(1f, 0.1f)

    startfade = startfade.lerp(if started: 0f else: 1f, 5f * fau.delta)

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

    if startfade > 0.01f or not started:
      draw("tutorial".patch, worldw/2f, worldh/2f, z = 52, color = startfade.alpha)

    if endfade > 0.01f:
      draw(fau.white, fau.cam.pos.x, fau.cam.pos.y, width = fau.cam.w, height = fau.cam.h, color = endfade.alpha, z = 53)
      draw("victory".patch, worldw/2f, worldh/2f, color = endfade.alpha, z = 54)

    var bgp = sys.bg.Patch
    bgp.scroll(fau.time / 100f, 0f)
    draw(bgp, worldw/2f, worldh/2f, z = -999)

    var r = initRand(123)

    for i in 0..50:
      let
        sscl = r.rand(0.6..1.5)
        cx = (r.rand(0..worldw) - fau.time * 16.0 * sscl + 10f).emod(worldw + 20f) - 10f
        cy = r.rand(0..worldh)
        len = r.rand(3f..7f)
      line(cx, cy, cx + len, cy, color = alpha(0.8f))

    draw(1000, proc() =
      buf.pop()
      screenMat()
      draw(buf.texture, fau.widthf/2f, fau.heightf/2f, width = fau.heightf * worldw / worldh, height = -fau.heightf)
      for i in signs():
        draw("border".patch, fau.widthf/2f + i * fau.heightf * worldw / worldh / 2f, fau.heightf/2f, height = fau.heightf, width = 3f * 4f)
      drawFlush()
    )

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
      of ssine: "p-sine"
      of svert: "p-vert"
      else: "powerup"
    draw(name.patch, item.pos.x, item.pos.y, mixcolor = rgba(1, 1, 1, absin(fau.time, 1f / 10f, 1f)))

sys("enemyDraw", [Enemy, Pos, Health]):
  all:
    if item.enemy.sprite != "":
      draw(item.enemy.sprite.patch, item.pos.x, item.pos.y, mixcolor = rgba(1, 1, 1, clamp(item.health.flash)))

sys("drawboiled", [Boiled, Enemy, Pos, Health]):
  all:
    draw("boiled".patch, item.pos.x, item.pos.y, mixcolor = rgba(1, 1, 1, clamp(item.health.flash)), rotation = item.enemy.val)

sys("drawpickled", [Pickled, Enemy, Pos, Health]):
  all:
    draw("pickled".patch, item.pos.x, item.pos.y, mixcolor = rgba(1, 1, 1, clamp(item.health.flash)), rotation = 90.rad)

sys("drawfried", [Fried, Enemy, Pos, Health]):
  all:
    draw("fried".patch, item.pos.x, item.pos.y, mixcolor = rgba(1, 1, 1, clamp(item.health.flash)), rotation = item.enemy.val)

sys("draweggnog", [Eggnog, Enemy, Pos, Health]):
  all:
    draw("eggnog".patch, item.pos.x, item.pos.y, mixcolor = rgba(1, 1, 1, clamp(item.health.flash)), rotation = item.enemy.val + 90.rad)

sys("drawomlette", [Omlette, Enemy, Pos, Health]):
  all:
    draw("omlette".patch, item.pos.x, item.pos.y, mixcolor = rgba(1, 1, 1, clamp(item.health.flash)), rotation = item.enemy.val, yscl = (if item.enemy.val < 180f.rad: -1f else: 1f))

sys("drawtoast", [Toast, Enemy, Pos, Health]):
  all:
    let s = sin(item.enemy.life, 1f / 10f, 0.2f)
    draw("toast".patch, item.pos.x, item.pos.y, mixcolor = rgba(1, 1, 1, clamp(item.health.flash)), rotation = item.enemy.val, xscl = 1f + s, yscl = 1f - s)

sys("drawbigomlette", [OmletteBig, Enemy, Pos, Health]):
  all:
    let s = sin(item.enemy.life, 1f / 10f, 0.2f)
    draw("omlette-big".patch, item.pos.x, item.pos.y, mixcolor = rgba(1, 1, 1, clamp(item.health.flash)), rotation = item.enemy.life.rad, xscl = 1f + s, yscl = 1f - s)

sys("all", [Pos]):
  init:
    discard

makeEffectsSystem()

#endregion

launchFau("ld48")