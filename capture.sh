#!/bin/bash

# Capture an image with rpicam-jpeg, rotate 180°, and update a JSON index

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
echo "Updating JSON files..."
python3 - "${JSON_ALL}" "${JSON_LATEST}" "${OUTPUT_PATH}" "${FILENAME}" <<'EOF'
import json, os, sys, datetime

json_all_path    = sys.argv[1]
json_latest_path = sys.argv[2]
output_path      = sys.argv[3]
filename         = sys.argv[4]

# Build new entry — parse date from filename so it works even if file is deleted later
size = os.path.getsize(output_path) if os.path.exists(output_path) else 0
try:
    stem = os.path.splitext(filename)[0]
    modified = datetime.datetime.strptime(stem, "%Y%m%d_%H%M%S").strftime("%Y-%m-%d %H:%M:%S")
except ValueError:
    modified = ""

new_entry = {
    "filename": filename,
    "path": output_path,
    "size_bytes": size,
    "modified": modified
}

# Load existing entries or start fresh
if os.path.exists(json_all_path):
    with open(json_all_path) as f:
        existing = json.load(f)
else:
    existing = []

merged = [new_entry] + existing

with open(json_all_path, "w") as f:
    json.dump(merged, f, indent=2)

with open(json_latest_path, "w") as f:
    json.dump(merged[:10], f, indent=2)

print(f"images_all.json    → {len(merged)} images")
print(f"images_latest.json → {min(len(merged), 10)} images")
EOF

if [ $? -ne 0 ]; then
    echo "Error: Failed to write JSON files." >&2
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
