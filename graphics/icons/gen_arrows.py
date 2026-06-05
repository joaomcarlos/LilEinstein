from PIL import Image
import os

p = os.path.dirname(os.path.abspath(__file__))

for suffix in ["", "_black"]:
    src = os.path.join(p, f"arrow_up_small{suffix}.png")
    img = Image.open(src).convert("RGBA")

    left = img.rotate(90, expand=True)
    left.save(os.path.join(p, f"arrow_left_small{suffix}.png"))

    right = img.rotate(270, expand=True)
    right.save(os.path.join(p, f"arrow_right_small{suffix}.png"))

print("Done")
