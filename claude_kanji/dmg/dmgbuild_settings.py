import os.path

application = defines.get("app", "/Users/agni/MyGit/01HAKA/claude_kanji/build/DerivedData/Build/Products/Release/01haka.app")
appname = os.path.basename(application)

format = "UDZO"
size = None
files = [application]
symlinks = {"Applications": "/Applications"}

badge_icon = None
background = defines.get("background", "/Users/agni/MyGit/01HAKA/claude_kanji/dmg/dmg_background.png")

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 0

window_rect = ((100, 100), (640, 480))
icon_size = 80
icon_locations = {
    appname: (195, 240),
    "Applications": (445, 240),
}

default_view = "icon-view"
