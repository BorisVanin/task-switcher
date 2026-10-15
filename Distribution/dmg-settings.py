# dmgbuild settings for the Task Switcher disk image (used by build-dmg.sh).
#
# dmgbuild writes the Finder window layout straight into the disk's .DS_Store, so Finder is never
# scripted and the values below are stored exactly as written. Finder adjusts a window it is asked
# to lay out through AppleScript; on macOS 26 it widened this one to 920 pt.
#
# Paths come from build-dmg.sh: -D app=... -D icon=... -D background=...
# The window size and icon positions must match DiskImageBackground in the app, which draws the background.
import os.path

app = defines["app"]

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines["icon"]              # icon of the mounted disk
background = defines["background"]  # 1x + 2x TIFF, 640 x 420 pt

default_view = "icon-view"
show_toolbar = False
show_status_bar = False             # stored explicitly: otherwise Finder adds the status bar and
show_pathbar = False                # path bar whenever the user has them on (View menu)
show_sidebar = False
show_tab_view = False
show_icon_preview = False

window_rect = ((200, 120), (640, 428))  # frame: ~400 pt of content under the title bar
icon_size = 128
text_size = 13
icon_locations = {
    os.path.basename(app): (180, 250),
    "Applications": (460, 250),
}
