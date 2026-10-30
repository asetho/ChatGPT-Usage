"""Finder window layout for the ChatGPT Usage disk image."""

import os
from pathlib import Path

staging = Path(os.environ["CHATGPT_USAGE_DMG_STAGING"])
background = os.environ["CHATGPT_USAGE_DMG_BACKGROUND"]
unsigned = os.environ["CHATGPT_USAGE_DMG_UNSIGNED"] == "1"

files = [
    (str(staging / "ChatGPT Usage.app"), "ChatGPT Usage.app"),
]
if unsigned:
    files.append((str(staging / "LICENSE"), "LICENSE"))
    files.append((str(staging / "UNSIGNED-INSTALL.txt"), "UNSIGNED-INSTALL.txt"))

symlinks = {"Applications": "/Applications"}
icon = str(staging / "ChatGPT Usage.app" / "Contents" / "Resources" / "AppIcon.icns")
format = "UDZO"
filesystem = "HFS+"
size = "80M"
window_rect = ((120, 120), (660, 510))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 80
text_size = 12
arrange_by = None
show_icon_preview = False
show_item_info = False
include_icon_view_settings = True
include_list_view_settings = False
icon_locations = {
    "ChatGPT Usage.app": (170, 229),
    "Applications": (490, 229),
    ".background.png": (2000, 100),
    ".VolumeIcon.icns": (2200, 100),
}
if unsigned:
    icon_locations["LICENSE"] = (200, 367)
    icon_locations["UNSIGNED-INSTALL.txt"] = (460, 367)
hide = [".background.png", ".VolumeIcon.icns"]
