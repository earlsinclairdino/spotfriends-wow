"""Turns the 1254x1254 icon renders into the addon's 128x128 textures in Textures/.

The renders are not in this repository (about 27 MB). By default they are read from
../SpotFriends_Resources/Icons next to the addon's folder; pass another folder as the first
argument. Needs Pillow (`pip install pillow`).

    python tools/convert-icons.py [renders-folder]
    python tools/convert-icons.py [renders-folder] --tga    # 32-bit TGA instead of PNG

It prints the Icons.List block for Icons.lua, in this file's order.
"""
import glob
import os
import sys

from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET = os.path.join(REPO, "Textures")
SOURCE = os.path.join(os.path.dirname(REPO), "SpotFriends_Resources", "Icons")
SIZE = 128
# The renders carry a soft glow down to alpha 1 or 2 at the very edge; cropping to the faint
# glow would keep the margin that makes the icon look small on a nameplate.
ALPHA_FLOOR = 24

# The hash in the render's file name -> the icon's key (its file and saved name) and label.
# Keys are saved in players' settings: rename one only with an entry in Icons.RENAMED.
MAPPING = [
    ("7fd49e1e", "gold-star", "Gold Star"),
    ("4e90f402", "silver-blue-star", "Silver-Blue Star"),
    ("9b8a5d8b", "sapphire-crystal-star", "Sapphire Crystal Star"),
    ("8fbee754", "mint-outline-star", "Mint Outline Star"),
    ("bdff8c1f", "gold-medallion-star", "Gold Medallion Star"),
    ("67335e20", "shield-star", "Shield Star"),
    ("ec714cb8", "winged-star", "Winged Star"),
    ("306abd1d", "violet-starburst", "Violet Starburst"),
    ("557d5005", "ruby-hex-star", "Ruby Hex Star"),
    ("d84b9090", "double-gold-stars", "Double Gold Stars"),
    ("8017bdf3", "teal-circle", "Teal Circle Friends"),
    ("62dc25ea", "cyan-outline-circle", "Cyan Outline Friends"),
    ("cd13ca9a", "navy-square", "Navy Square Friends"),
    ("feed2fc9", "gold-medallion", "Gold Medallion Friends"),
    ("f4c4d303", "emerald-circle", "Emerald Circle Friends"),
    ("1413d3ce", "cyan-shield", "Cyan Shield Friends"),
    ("8f8eefba", "violet-crystal", "Violet Circle Friends"),
    ("04aa6edf", "blue-gold-split", "Blue & Gold Friends"),
    ("b69dc1eb", "linked-rings", "Linked Rings"),
    ("932bfd0c", "black-gold-minimal", "Black & Gold Friends"),
    ("13d0f8a8", "silver-crescent", "Silver Crescent"),
    ("501b7532", "sapphire-crescent", "Sapphire Crescent"),
    ("52278756", "ruby-heart", "Ruby Heart"),
    ("ecbab28e", "red-heart", "Red Heart"),
    ("32c5dc41", "blue-spot", "Blue Spot"),
    ("d8e2b235", "gold-spot", "Gold Spot"),
]


def find(prefix):
    matches = glob.glob(os.path.join(SOURCE, "exec-%s*.png" % prefix))
    if len(matches) != 1:
        sys.exit("expected one render for %s, found %d" % (prefix, len(matches)))
    return matches[0]


def convert(path, out, fmt):
    image = Image.open(path).convert("RGBA")
    mask = image.getchannel("A").point(lambda a: 255 if a >= ALPHA_FLOOR else 0)
    box = mask.getbbox() or (0, 0, image.width, image.height)
    image = image.crop(box)
    side = max(image.width, image.height)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.paste(image, ((side - image.width) // 2, (side - image.height) // 2))
    square = square.resize((SIZE, SIZE), Image.LANCZOS)
    square.save(out, format=fmt)


def main():
    global SOURCE
    folders = [a for a in sys.argv[1:] if not a.startswith("--")]
    if folders:
        SOURCE = folders[0]
    if not os.path.isdir(SOURCE):
        sys.exit("no renders folder at %s: pass it as the first argument" % SOURCE)
    tga = "--tga" in sys.argv
    ext, fmt = (".tga", "TGA") if tga else (".png", "PNG")
    os.makedirs(TARGET, exist_ok=True)
    seen = set()
    for prefix, key, _ in MAPPING:
        if key in seen:
            sys.exit("duplicate key " + key)
        seen.add(key)
        convert(find(prefix), os.path.join(TARGET, key + ext), fmt)
    print("Icons.List = {")
    for _, key, label in MAPPING:
        print('\t{ key = "%s", label = "%s", file = "%s%s" },' % (key, label, key, ext))
    print("}")
    print("%d icons written to %s" % (len(MAPPING), TARGET))


if __name__ == "__main__":
    main()
