name: Build unsigned IPA
on:
  workflow_dispatch:
  push:
    branches: [main]
jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install XcodeGen
        run: brew install xcodegen
      - name: Download Ruffle
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          mkdir -p dl www/ruffle
          gh release download --repo ruffle-rs/ruffle --pattern '*web-selfhosted.zip' --dir dl
          unzip -o dl/*.zip -d www/ruffle
      - name: Make app icon
        run: |
          python3 -m venv .venv
          .venv/bin/pip install pillow
          .venv/bin/python - <<'PY'
          from PIL import Image, ImageDraw, ImageFilter
          import json, os
          S = 2048
          cx = cy = S // 2
          R = 640
          bg = Image.new("RGB", (S, S))
          d = ImageDraw.Draw(bg)
          top, bot = (40, 22, 88), (7, 7, 16)
          for y in range(S):
              t = y / (S - 1)
              d.line([(0, y), (S, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
          bg = bg.convert("RGBA")
          glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
          ImageDraw.Draw(glow).ellipse([cx - R - 70, cy - R - 70, cx + R + 70, cy + R + 70], fill=(255, 120, 20, 170))
          bg = Image.alpha_composite(bg, glow.filter(ImageFilter.GaussianBlur(120)))
          D = 2 * R
          grad = Image.new("RGB", (D, D))
          g = ImageDraw.Draw(grad)
          c1, c2 = (255, 178, 30), (238, 64, 44)
          for y in range(D):
              t = y / (D - 1)
              g.line([(0, y), (D, y)], fill=tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3)))
          mask = Image.new("L", (D, D), 0)
          ImageDraw.Draw(mask).ellipse([0, 0, D - 1, D - 1], fill=255)
          bg.paste(grad, (cx - R, cy - R), mask)
          ring = Image.new("RGBA", (S, S), (0, 0, 0, 0))
          ImageDraw.Draw(ring).ellipse([cx - R - 46, cy - R - 46, cx + R + 46, cy + R + 46], outline=(255, 255, 255, 60), width=10)
          bg = Image.alpha_composite(bg, ring)
          pts = [(cx - 0.26 * R, cy - 0.46 * R), (cx - 0.26 * R, cy + 0.46 * R), (cx + 0.50 * R, cy)]
          t = ImageDraw.Draw(bg)
          t.polygon(pts, fill=(255, 255, 255, 255))
          t.line(pts + [pts[0]], fill=(255, 255, 255, 255), width=56, joint="curve")
          for (x, y) in pts:
              t.ellipse([x - 28, y - 28, x + 28, y + 28], fill=(255, 255, 255, 255))
          out = bg.convert("RGB").resize((1024, 1024), Image.LANCZOS)
          os.makedirs("Sources/Assets.xcassets/AppIcon.appiconset", exist_ok=True)
          out.save("Sources/Assets.xcassets/AppIcon.appiconset/icon.png")
          json.dump({"info": {"author": "xcode", "version": 1}}, open("Sources/Assets.xcassets/Contents.json", "w"))
          json.dump({"images": [{"filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": {"author": "xcode", "version": 1}}, open("Sources/Assets.xcassets/AppIcon.appiconset/Contents.json", "w"))
          PY
      - name: Generate project
        run: xcodegen generate
      - name: Build (no signing)
        run: |
          xcodebuild -project SWFPlayer.xcodeproj -scheme SWFPlayer \
            -configuration Release -sdk iphoneos -derivedDataPath build \
            ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon \
            CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
      - name: Make IPA
        run: |
          mkdir Payload
          cp -r build/Build/Products/Release-iphoneos/SWFPlayer.app Payload/
          zip -qr SWFPlayer.ipa Payload
      - uses: actions/upload-artifact@v4
        with:
          name: SWFPlayer-ipa
          path: SWFPlayer.ipa
