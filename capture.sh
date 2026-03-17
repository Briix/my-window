#!/bin/bash

# Capture an image with rpicam-still, rotate 180°, and update a JSON index

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
FILENAME="${TIMESTAMP}.jpg"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_PATH="${SCRIPT_DIR}/${FILENAME}"
JSON_ALL="${SCRIPT_DIR}/images_all.json"
JSON_LATEST="${SCRIPT_DIR}/images_latest.json"

# --- 1. Capture image ---
echo "Capturing image: ${FILENAME}"
rpicam-jpeg --output "${OUTPUT_PATH}" --nopreview

if [ $? -ne 0 ]; then
    echo "Error: rpicam-jpeg failed to capture image." >&2
    exit 1
fi

# --- 2. Rotate 180 degrees in-place ---
echo "Rotating image 180°..."
if ! command -v convert &>/dev/null; then
    echo "Error: ImageMagick 'convert' not found. Install with: sudo apt install imagemagick" >&2
    exit 1
fi

convert "${OUTPUT_PATH}" -rotate 180 "${OUTPUT_PATH}"

if [ $? -ne 0 ]; then
    echo "Error: Image rotation failed." >&2
    exit 1
fi

# --- 3. Build JSON files ---

# Helper function to build a JSON array from an array of image paths
build_json() {
    local -n _images=$1
    local json="["
    local first=true
    for IMG in "${_images[@]}"; do
        BASENAME=$(basename "${IMG}")
        FILESIZE=$(stat -c%s "${IMG}" 2>/dev/null || echo 0)
        MODIFIED=$(stat -c%y "${IMG}" 2>/dev/null | cut -d'.' -f1)
        [ "$first" = true ] && first=false || json+=","
        json+="{\"filename\":\"${BASENAME}\",\"path\":\"${IMG}\",\"size_bytes\":${FILESIZE},\"modified\":\"${MODIFIED}\"}"
    done
    json+="]"
    echo "${json}"
}

# Collect all .jpg files sorted by modification time (newest first)
mapfile -t ALL_IMAGES < <(ls -1t "${SCRIPT_DIR}"/*.jpg 2>/dev/null)

# Slice to latest 10
LATEST_IMAGES=("${ALL_IMAGES[@]:0:10}")

# Write images_all.json
echo "Updating ${JSON_ALL}..."
build_json ALL_IMAGES | python3 -m json.tool > "${JSON_ALL}"
if [ $? -ne 0 ]; then
    echo "Error: Failed to write ${JSON_ALL}." >&2
    exit 1
fi

# Write images_latest.json
echo "Updating ${JSON_LATEST}..."
build_json LATEST_IMAGES | python3 -m json.tool > "${JSON_LATEST}"
if [ $? -ne 0 ]; then
    echo "Error: Failed to write ${JSON_LATEST}." >&2
    exit 1
fi

echo "Done. Image saved to:       ${OUTPUT_PATH}"
echo "All images JSON updated:    ${JSON_ALL}"
echo "Latest 10 JSON updated:     ${JSON_LATEST}"

# --- 4. Commit modified files and push to GitHub ---
echo "Committing and pushing to GitHub..."
cd "${SCRIPT_DIR}"

# Stage only the new image and the two JSON files
git add "${FILENAME}" images_all.json images_latest.json

git commit -m "capture: ${FILENAME}"

if [ $? -ne 0 ]; then
    echo "Error: Git commit failed." >&2
    exit 1
fi

git push

if [ $? -ne 0 ]; then
    echo "Error: Git push failed." >&2
    exit 1
fi

# --- 5. Delete all local .jpg files except the newly captured one ---
echo "Cleaning up old images locally..."
find "${SCRIPT_DIR}" -maxdepth 1 -name "*.jpg" ! -name "${FILENAME}" -delete

echo "All done."
