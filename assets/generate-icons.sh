#!/bin/zsh

# Exit on error
set -e

echo "Generating app icons from AppIcon.png..."

# Create temporary directory for macOS sizes
mkdir -p mac_icons

# Generate macOS sizes
for size in 16 32 128 256 512; do
    sips -s format png -z $size $size AppIcon.png --out mac_icons/icon_${size}x${size}.png
    sips -s format png -z $((size*2)) $((size*2)) AppIcon.png --out mac_icons/icon_${size}x${size}@2x.png
done

# Copy iOS icon
echo "Copying iOS icon..."
cp AppIcon.png "../TranslateVideoSubtitles/TranslateVideoSubtitles/Assets.xcassets/AppIcon.appiconset/AppIcon_1024.png"

# Copy macOS icons
echo "Copying macOS icons..."
for size in 16 32 128 256 512; do
    cp mac_icons/icon_${size}x${size}.png "../TranslateVideoSubtitles/TranslateVideoSubtitles-macOS/Assets.xcassets/AppIcon.appiconset/"
    cp mac_icons/icon_${size}x${size}@2x.png "../TranslateVideoSubtitles/TranslateVideoSubtitles-macOS/Assets.xcassets/AppIcon.appiconset/"
done

# Clean up
rm -rf mac_icons

echo "Done! App icons generated and copied to their destinations." 