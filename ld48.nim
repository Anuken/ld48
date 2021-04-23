import ecs, presets/[basic, effects]

static: echo staticExec("faupack -p:assets-raw/sprites -o:assets/atlas")

const scl = 4.0

registerComponents(defaultComponentOptions):
  type
    Vel = object
      x, y: float32

sys("init", [Main]):

  init:
    discard

  start:
    if keyEscape.tapped: quitApp()
    
    fau.cam.resize(fau.widthf / scl, fau.heightf / scl)
    fau.cam.use()

    fillPoly(0, 0, 6, 30)
  
  finish:
    discard

launchFau("ld48")
