#!/bin/zsh

# Exit on error
set -e

# Copy iOS icon
echo "Copying iOS icon..."
cp AppIcon.png "../TranslateVideoSubtitles/TranslateVideoSubtitles/Assets.xcassets/AppIcon.appiconset/AppIcon_1024.png"

# Copy background image.
# If ../../social-media-translator-assets/iStock-506763657/iStock-506763657-compressed.jpg exists, use that.
# Otherwise use the placeholder Background.jpg.
BACKGROUND_SRC="../../social-media-translator-assets/iStock-506763657/iStock-506763657-compressed.jpg"
BACKGROUND_DST="../TranslateVideoSubtitles/TranslateVideoSubtitles/Assets.xcassets/Background.imageset/Background.jpg"
if [ -f "$BACKGROUND_SRC" ]; then
    echo "Copying real background image..."
    cp "$BACKGROUND_SRC" "$BACKGROUND_DST"
else
    echo "Copying placeholder background image..."
    cp Background.jpg "$BACKGROUND_DST"
fi
