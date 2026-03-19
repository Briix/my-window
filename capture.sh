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
FILESIZE=$(stat -c%s "${OUTPUT_PATH}" 2>/dev/null || echo 0)
MODIFIED=$(stat -c%y "${OUTPUT_PATH}" 2>/dev/null | cut -d'.' -f1)
NEW_ENTRY="{\"filename\":\"${FILENAME}\",\"path\":\"${OUTPUT_PATH}\",\"size_bytes\":${FILESIZE},\"modified\":\"${MODIFIED}\"}"

# Prepend new entry to images_all.json (create if it doesn't exist)
echo "Updating ${JSON_ALL}..."
if [ -f "${JSON_ALL}" ]; then
    EXISTING=$(python3 -c "import json,sys; data=json.load(open('${JSON_ALL}')); print(json.dumps(data))")
    python3 -c "
import json, sys
existing = json.loads(sys.argv[1])
new_entry = json.loads(sys.argv[2])
merged = [new_entry] + existing
print(json.dumps(merged, indent=2))
" "${EXISTING}" "${NEW_ENTRY}" > "${JSON_ALL}"
else
    echo "[${NEW_ENTRY}]" | python3 -m json.tool > "${JSON_ALL}"
fi

if [ $? -ne 0 ]; then
    echo "Error: Failed to write ${JSON_ALL}." >&2
    exit 1
fi

# Derive images_latest.json as the first 12 entries from images_all.json
echo "Updating ${JSON_LATEST}..."
python3 -c "
import json
with open('${JSON_ALL}') as f:
    data = json.load(f)
print(json.dumps(data[:12], indent=2))
" > "${JSON_LATEST}"

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
