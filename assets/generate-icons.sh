#!/bin/zsh

# Exit on error
set -e

echo "Generating app icons from AppIcon.png..."

# Copy iOS icon
echo "Copying iOS icon..."
cp AppIcon.png "../TranslateVideoSubtitles/TranslateVideoSubtitles/Assets.xcassets/AppIcon.appiconset/AppIcon_1024.png"

echo "Done! App icons generated and copied to their destinations." 
