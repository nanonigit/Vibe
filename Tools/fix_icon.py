import os
from PIL import Image, ImageDraw

def fix_icon():
    src_path = "Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
    img = Image.open(src_path).convert("RGBA")
    
    # 中央の本体部分（アイコン本体）をクロップ
    crop_box = (170, 170, 854, 854)
    cropped = img.crop(crop_box)
    
    # 1024x1024にリサイズ
    cropped_1024 = cropped.resize((1024, 1024), Image.Resampling.LANCZOS)
    
    # macOS標準の角丸マスク（外側の灰色を完全に透明化）
    mask = Image.new("L", (1024, 1024), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, 1024, 1024), radius=230, fill=255)
    
    final_1024 = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    final_1024.paste(cropped_1024, (0, 0), mask=mask)
    
    # 各サイズにリサイズして保存
    sizes = [16, 32, 64, 128, 256, 512, 1024]
    iconset_dir = "Resources/Assets.xcassets/AppIcon.appiconset"
    
    for size in sizes:
        resized = final_1024.resize((size, size), Image.Resampling.LANCZOS)
        out_path = os.path.join(iconset_dir, f"AppIcon-{size}.png")
        resized.save(out_path, "PNG")
        print(f"Saved: {out_path} ({size}x{size})")
        
    print("Icon regeneration complete!")

if __name__ == "__main__":
    fix_icon()
