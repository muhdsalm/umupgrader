import std/options
import strutils, strformat
import owlkettle, owlkettle/adw
import defs, askpass, server

const
  title: string = "Ultramarine System Upgrader"
  icon: string = "system-upgrade"
  startmsg: string = dedent """
    ——— Below are logs from umupgrader ———
    GitHub Repository: https://github.com/Ultramarine-Linux/umupgrader/

    Checking for updates… (Make sure your system is connected to the Internet)
  """
  downloadFailMsg: string = dedent """
    Failed to download system upgrade. This is usually caused by missing packages.

    You should check in the logs if vital/system/co0re packages would be removed. You may seek help via:
    - Fediverse: @ultramarine@fedi.fyralabs.com
    - Ultramarine Discord: https://discord.gg/bUuQasHdrF
    - Reddit: r/ultramarine
    - Twitter/X: @UltramarineProj

    If you are certain the system upgrade would not break your computer, you may continue by clicking the download button again. This will force the package manager to remove packages that could not be upgraded.
  """
  css: string = dedent """
    textview:disabled text {
      color: @theme_fg_color;
    }
    .bright-fg {
      color: @theme_fg_color;
    }
  """

proc handle_main_recv(app: AppState) =
  while app.hub[].toMain.peek > 0:
    let msg = app.hub[].toMain.recv
    if msg.starts_with "\n":
      app.buffer.insert(app.buffer.selection.a, msg[1..^1])
    elif msg.starts_with "newver\n":
      app.newVer = parseInt msg["newver\n".len..^1]
    elif msg.starts_with "dlstat\n":
      if app.newVer > 0 and app.dlfailed: return  # handled by dlerr
      case msg["dlstat\n".len..^1]
      of "0": app.newVer *= -1
      of "1": app.canApplyUpdate = true
      else: msg.recv_unknown_msg "main"
    elif msg == "dlerr":
      app.dlfailed = true
      discard app.open: gui:
        MessageDialog:
          message = downloadFailMsg
          DialogButton {.addButton.}:
            text = "Ok"
            res = DialogAccept
      app.newVer *= -1
    elif msg.starts_with "rebootstat\n":
      case msg["rebootstat\n".len..^1]
      of "0": discard # WTF.
      of "1": quit(0)
      else: msg.recv_unknown_msg "main"
    else: msg.recv_unknown_msg "main"

method view(app: AppState): Widget =
  handle_main_recv app

  let layout = (app.leftButtons, app.rightButtons)
  result = gui:
    Window:
      title = title
      defaultSize = (800, 600)
      iconName = icon

      AdwHeaderBar {.addTitlebar.}:
        windowControls = layout
        centeringPolicy = CenteringPolicyLoose
        showLeftButtons = true
        showRightButtons = true
        showBackButton = true
        tooltip = ""
        sizeRequest = app.sizeRequest

        if AdwVersion >= (1, 4):
          Box {.addTitle.}:
            Label(text = title)
            Icon(name = icon) {.expand: false.}

      Box(orient = OrientY):
        Box(orient = OrientX, margin = 12, spacing = 6) {.expand: false.}:

          Button:
            text = if app.dlfailed: "Force Download Update" else: "Download Update"
            sensitive = app.newVer > 0
            if app.dlfailed:
              style = [ButtonDestructive]
            elif app.newVer > 0 and not app.canApplyUpdate:
              style = [ButtonSuggested]

            proc clicked() =
              if app.dlfailed:
                let ver = app.newVer
                app.newVer *= -1
                app.hub[].toThrd.send fmt "forcedl\n{app.user.name}\n{app.user.password}\n{ver}"
              var ver = app.newVer
              app.newVer *= -1 # disables the button
              app.user = askpass app
              if app.user.name == "":
                app.newVer = ver
                return
              app.hub[].toThrd.send fmt "download\n{app.user.name}\n{app.user.password}\n{ver}"

          Button:
            text = "Apply Update (Reboot RIGHT NOW)"
            sensitive = app.canApplyUpdate
            if app.canApplyUpdate:
              style = [ButtonSuggested]

            proc clicked() =
              app.hub[].toThrd.send fmt "reboot\n{app.user.name}\n{app.user.password}"

        ScrolledWindow:
          TextView:
            margin = 12
            buffer = app.buffer
            monospace = true
            cursorVisible = true
            editable = false
            acceptsTab = false
            indent = 0
            sensitive = false
            tooltip = ""
            sizeRequest = app.sizeRequest
            style = [StyleClass("bright-fg")]

proc setupClient(hub: ref Hub) =
  hub[].toThrd.send "updck"
  let buf = newTextBuffer()
  discard buf.registerTag("marker", TagStyle(
    background: some("#ffff77"),
    weight: some(700)
  ))
  buf.insert(buf.selection.a, startmsg)
  adw.brew(gui(App(buffer = buf, hub = hub)), stylesheets=[newStyleSheet(css)])

proc main() =
  var hub = new Hub
  open hub[].toMain
  open hub[].toThrd
  let server = setupServer hub
  setupClient hub
  hub[].toThrd.send "bai"
  echo "Joining thread…"
  joinThread server
  close hub[].toMain
  close hub[].toThrd

when isMainModule:
  main()
