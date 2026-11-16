"""Gera ícones derivados da logo oficial, sem redesenhar a marca."""

from pathlib import Path
from shutil import copy2

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "frontend" / "assets" / "images" / "ubs_rapida_logo.jpg"


def square_brand(size: int, safe_ratio: float = 0.78) -> Image.Image:
    source = Image.open(SOURCE).convert("RGB")
    # Recorte do símbolo oficial dentro da arte 1408x768. A proporção interna
    # permanece intacta; somente o cenário fotográfico e o lettering saem.
    symbol = source.crop((500, 145, 870, 465))
    maximum = round(size * safe_ratio)
    symbol.thumbnail((maximum, maximum), Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", (size, size), "white")
    canvas.paste(symbol, ((size - symbol.width) // 2, (size - symbol.height) // 2))
    return canvas


def save_png(path: Path, size: int, safe_ratio: float = 0.78) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    square_brand(size, safe_ratio).save(path, "PNG", optimize=True)


def main() -> None:
    web = ROOT / "frontend" / "web"
    save_png(web / "favicon.png", 48, 0.88)
    save_png(web / "icons" / "Icon-192.png", 192)
    save_png(web / "icons" / "Icon-512.png", 512)
    save_png(web / "icons" / "Icon-maskable-192.png", 192, 0.62)
    save_png(web / "icons" / "Icon-maskable-512.png", 512, 0.62)

    android_res = ROOT / "frontend" / "android" / "app" / "src" / "main" / "res"
    for density, size in {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }.items():
        save_png(android_res / density / "ic_launcher.png", size, 0.70)
    save_png(android_res / "drawable" / "launch_logo.png", 384, 0.84)

    ico_path = ROOT / "frontend" / "windows" / "runner" / "resources" / "app_icon.ico"
    ico_path.parent.mkdir(parents=True, exist_ok=True)
    square_brand(256, 0.76).save(
        ico_path,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )

    download_assets = ROOT / "packaging" / "downloads" / "assets"
    download_assets.mkdir(parents=True, exist_ok=True)
    copy2(SOURCE, download_assets / "ubs-rapida-logo.jpg")


if __name__ == "__main__":
    main()
