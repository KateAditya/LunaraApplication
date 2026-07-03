"""
Generate app launcher icons from the Lunara logo for Android and iOS
"""
from PIL import Image
import os

# Source logo
source_logo = r"E:\Development\SampleData\lunara.png"

# Android icon sizes (in pixels)
android_sizes = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
}

# iOS icon sizes (in pixels)
ios_sizes = {
    'Icon-App-20x20@1x.png': 20,
    'Icon-App-20x20@2x.png': 40,
    'Icon-App-20x20@3x.png': 60,
    'Icon-App-29x29@1x.png': 29,
    'Icon-App-29x29@2x.png': 58,
    'Icon-App-29x29@3x.png': 87,
    'Icon-App-40x40@1x.png': 40,
    'Icon-App-40x40@2x.png': 80,
    'Icon-App-40x40@3x.png': 120,
    'Icon-App-60x60@2x.png': 120,
    'Icon-App-60x60@3x.png': 180,
    'Icon-App-76x76@1x.png': 76,
    'Icon-App-76x76@2x.png': 152,
    'Icon-App-83.5x83.5@2x.png': 167,
    'Icon-App-1024x1024@1x.png': 1024,
}

def generate_icons():
    # Load the source image
    img = Image.open(source_logo)
    print(f"Source image size: {img.size}")
    
    # Generate Android icons
    print("\nGenerating Android icons...")
    android_base = r"E:\Development\NightView\lunara_app\android\app\src\main\res"
    for folder, size in android_sizes.items():
        folder_path = os.path.join(android_base, folder)
        os.makedirs(folder_path, exist_ok=True)
        
        icon_path = os.path.join(folder_path, 'ic_launcher.png')
        resized = img.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(icon_path, 'PNG')
        print(f"  ✓ Created {folder}/ic_launcher.png ({size}x{size})")
    
    # Generate iOS icons
    print("\nGenerating iOS icons...")
    ios_base = r"E:\Development\NightView\lunara_app\ios\Runner\Assets.xcassets\AppIcon.appiconset"
    for filename, size in ios_sizes.items():
        icon_path = os.path.join(ios_base, filename)
        resized = img.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(icon_path, 'PNG')
        print(f"  ✓ Created {filename} ({size}x{size})")
    
    print("\n✅ All app icons generated successfully!")
    print("\nNext steps:")
    print("1. Run 'flutter clean' to clear the build cache")
    print("2. Run 'flutter pub get' to refresh assets")
    print("3. Rebuild and run the app to see the new logo")

if __name__ == '__main__':
    generate_icons()
