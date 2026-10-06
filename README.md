# Rhino 8 on Fedora with Wine

A script and guide for running Rhinoceros 8 on Fedora Linux (KDE Plasma, Wayland)
under Wine. Tested on Fedora 44 with Rhino 8.35, an AMD RX 7600, and a 4K display
at 1.45× scaling. Rhino installs, licenses through a Rhino account, and runs
stably.

Nothing here needs root. Your system Wine is left alone.

## Why this is needed

Rhino 8 moved to .NET 8 and crashed on startup under every Wine release up to
11.0 with a stack overflow in `System.Private.CoreLib`. The root cause was a
missing `uxtheme` dark-mode API that sent Rhino into infinite recursion. The fix
landed upstream in **Wine 11.14**. Fedora ships Wine 11.0, so a newer build is
required.

This repo uses the pre-built patched **Wine 11.18** from
[Jabern/rhino-linux](https://github.com/Jabern/rhino-linux), which carries the
upstream fix plus 20 Rhino-specific patches (WebView2 hosting for Cloud Zoo
licensing, task dialogs, viewport repaint fixes, multi-monitor handling).
The install flow is adapted from
[ItHasLegs/rhino8-wine](https://github.com/ItHasLegs/rhino8-wine).

## Quick start

```bash
# 1. Vulkan drivers (probably already installed on a desktop Fedora)
sudo dnf install vulkan-loader mesa-vulkan-drivers freetype gnutls

# 2. Download the Rhino 8 installer from https://www.rhino3d.com/download/
#    (McNeel emails you a link; it lands in ~/Downloads as rhino_en-us_8.x.exe)

# 3. Install
git clone https://github.com/bdswaney/rhino8-wine-fedora.git
cd rhino8-wine-fedora
./install.sh ~/Downloads/rhino_en-us_8.*.exe

# 4. Run
rhino8
```

A normal Rhino installer window opens in step 3. Click through it with the
defaults. It bundles .NET 8, WebView2, and the Visual C++ runtimes, so no
`winetricks` verbs are needed.

## What gets installed where

| Item | Location |
|---|---|
| Patched Wine 11.18 | `~/.local/share/wine-rhino/` |
| Wine prefix with Rhino | `~/.local/share/wineprefixes/rhino8/` |
| Launcher | `~/.local/bin/rhino8` |
| Menu entry | `~/.local/share/applications/rhino8.desktop` |
| Download cache and log | `~/.cache/rhino8-wine-fedora/` |

To remove everything, delete those five paths.

## Licensing

First launch asks you to sign in with a Rhino account. The sign-in opens in your
Linux browser and redirects back to Rhino on `http://127.0.0.1:1717/`. If that
page says it cannot connect, the Wine HTTP service is in a stale state. Quit
Rhino and run:

```bash
rhino8 --fresh
```

Some users on the McNeel forum report Cloud Zoo licenses sticking in evaluation
mode under Wine while standalone license keys activate fine. A Rhino account
login worked on the tested setup.

## HiDPI scaling

Wine ignores KDE's display scaling, so Rhino's UI comes up small on a 4K
screen. Setting a non-default DPI inside Wine (`LogPixels`) **breaks Rhino's
UI**, so don't do that. The working fix is to let KDE upscale X11 apps:

```bash
./install.sh --kde-scaling
```

That sets System Settings → Display & Monitor → *Legacy applications (X11)* to
*Scaled by the system*. It takes effect immediately and survives relogins. Text
is slightly soft because the compositor is scaling a rendered image. It affects
every X11 app, though nearly everything else on Fedora KDE is native Wayland.

Undo it in the same System Settings page, or with:

```bash
kwriteconfig6 --notify --file kdeglobals --group KScreen --key XwaylandClientsScale true
```

Note for anyone scripting this: the `[Xwayland] Scale` value in `kwinrc` is
KWin's computed output, not the preference. The preference is
`XwaylandClientsScale` in the `KScreen` group of `kdeglobals`, and it must be
written with `--notify` or KWin ignores it until the next login.

## Troubleshooting

- **Rhino exits immediately.** Check `~/.cache/rhino8-wine-fedora/rhino.log`.
  Confirm you're on the patched Wine with
  `~/.local/share/wine-rhino/bin/wine --version` (should print 11.18).
- **Viewport is black or red.** Switch Rhino to OpenGL under Options →
  Advanced, or check that `vulkaninfo --summary` lists your GPU.
- **Launching from a script kills Rhino after a timeout.** Detach it:
  `setsid nohup rhino8 >/dev/null 2>&1 &`
- **Updating Rhino.** Download the new installer and run `./install.sh` again
  against the existing prefix. It reuses the prefix and upgrades in place.

## Security notes

The install script downloads one binary: the patched Wine tarball, pinned by
SHA-256. The Jabern patches were reviewed and only touch Wine source under
`dlls/`, `server/`, and `include/`. If you'd rather not trust a pre-built
binary, the Jabern repo documents building Wine 11.18 from source with the same
patch set.

## Credits

- [ItHasLegs/rhino8-wine](https://github.com/ItHasLegs/rhino8-wine) for
  tracking down the uxtheme crash and getting the fix upstreamed.
- [Jabern/rhino-linux](https://github.com/Jabern/rhino-linux) for the patch set
  and pre-built Wine.
- The [Rhino on Linux - Technicalities](https://discourse.mcneel.com/t/rhino-on-linux-technicalities/203861)
  thread on the McNeel forum.

## License

MIT
