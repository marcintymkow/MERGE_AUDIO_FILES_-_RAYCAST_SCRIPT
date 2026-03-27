#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Merge Audio Files
# @raycast.mode fullOutput

# Optional parameters:
# @raycast.icon 🎵
# @raycast.packageName Audio Tools

# Documentation:
# @raycast.description Merge selected audio files (AAC, MP3, M4A, WAV, FLAC, OGG) into single file
# @raycast.author Marcin
# @raycast.authorURL https://github.com/

# Dependency: ffmpeg (brew install ffmpeg)

set -e

# Check for ffmpeg
if ! command -v ffmpeg &> /dev/null; then
    echo "❌ Error: ffmpeg is not installed"
    echo "Install with: brew install ffmpeg"
    exit 1
fi

# Get selected files from Finder or Path Finder
get_selected_files() {
    local selected=""
    
    # Try Path Finder first
    if pgrep -q "Path Finder"; then
        selected=$(osascript << 'EOF'
tell application "Path Finder"
    set selectedItems to selection
    set output to ""
    repeat with anItem in selectedItems
        set output to output & POSIX path of anItem & linefeed
    end repeat
    return output
end tell
EOF
2>/dev/null)
    fi
    
    # If Path Finder didn't return results, try Finder
    if [ -z "$selected" ]; then
        selected=$(osascript << 'EOF'
tell application "Finder"
    set selectedItems to selection
    set output to ""
    repeat with anItem in selectedItems
        set filePath to POSIX path of (anItem as alias)
        set output to output & filePath & linefeed
    end repeat
    return output
end tell
EOF
2>/dev/null)
    fi
    
    echo "$selected"
}

# Supported audio extensions
SUPPORTED_EXTENSIONS="aac|mp3|m4a|wav|flac|ogg|wma|opus"

# Get selected files
files=$(get_selected_files)

if [ -z "$files" ]; then
    echo "❌ Error: No files selected"
    echo "Select audio files in Finder or Path Finder first"
    exit 1
fi

# Debug: show raw selection
# echo "DEBUG: Raw selection:"
# echo "$files"

# Filter and validate audio files
audio_files=()
while IFS= read -r file; do
    [ -z "$file" ] && continue
    ext="${file##*.}"
    ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    if [[ "$ext_lower" =~ ^($SUPPORTED_EXTENSIONS)$ ]]; then
        if [ -f "$file" ]; then
            audio_files+=("$file")
        fi
    fi
done <<< "$files"

# Check if we have enough files
if [ ${#audio_files[@]} -lt 2 ]; then
    echo "❌ Error: Need at least 2 audio files to merge"
    echo "Selected valid audio files: ${#audio_files[@]}"
    echo "Supported formats: AAC, MP3, M4A, WAV, FLAC, OGG, WMA, OPUS"
    exit 1
fi

echo "🎵 Found ${#audio_files[@]} audio files to merge"

# Sort files naturally (by name)
IFS=$'\n' sorted_files=($(sort -V <<< "${audio_files[*]}")); unset IFS

# Get info from first file to determine output format and quality
first_file="${sorted_files[0]}"
first_ext="${first_file##*.}"
first_ext_lower=$(echo "$first_ext" | tr '[:upper:]' '[:lower:]')
first_dir=$(dirname "$first_file")
first_basename=$(basename "$first_file" ".$first_ext")

# Get audio parameters from first file
echo "📊 Analyzing source audio parameters..."

# Get codec, bitrate, sample rate, channels from first file
audio_info=$(ffprobe -v quiet -select_streams a:0 -show_entries stream=codec_name,bit_rate,sample_rate,channels -of csv=p=0 "$first_file" 2>/dev/null)
IFS=',' read -r codec bitrate sample_rate channels <<< "$audio_info"

echo "   Codec: $codec"
echo "   Bitrate: ${bitrate:-auto}"
echo "   Sample rate: ${sample_rate}Hz"
echo "   Channels: $channels"

# Use the same extension as the first input file
out_ext="$first_ext_lower"

# Determine codec options based on detected codec
case "$codec" in
    aac)
        codec_opts="-c:a aac"
        ;;
    mp3)
        codec_opts="-c:a libmp3lame"
        ;;
    flac)
        codec_opts="-c:a flac"
        ;;
    vorbis)
        codec_opts="-c:a libvorbis"
        ;;
    opus)
        codec_opts="-c:a libopus"
        ;;
    pcm_*)
        codec_opts="-c:a pcm_s16le"
        ;;
    *)
        # Default to AAC for unknown codecs
        codec_opts="-c:a aac"
        ;;
esac

# Add bitrate if available and codec supports it
if [ -n "$bitrate" ] && [ "$bitrate" != "N/A" ] && [[ ! "$codec" =~ ^(flac|pcm_) ]]; then
    codec_opts="$codec_opts -b:a $bitrate"
fi

# Generate output filename
timestamp=$(date +%Y%m%d_%H%M%S)

# Extract clean name from first file (remove numbering prefix like "1. ", "01. ", "1 - ", "01 - ", etc.)
first_basename=$(basename "$first_file" ".$first_ext")
# Remove common numbering patterns at the start:
# - "1. " or "01. " or "001. " (number + dot + space)
# - "1 - " or "01 - " (number + space + dash + space)
# - "1-" or "01-" (number + dash)
# - "1 " or "01 " (number + space)
clean_name=$(echo "$first_basename" | sed -E 's/^[0-9]+[.\-]?[[:space:]]*[-]?[[:space:]]*//')

# If clean_name is empty (unlikely), fall back to timestamp
if [ -z "$clean_name" ]; then
    clean_name="audio_${timestamp}"
fi

output_file="${first_dir}/MERGED - ${clean_name}.${out_ext}"

# If file already exists, add timestamp to avoid overwriting
if [ -f "$output_file" ]; then
    output_file="${first_dir}/MERGED - ${clean_name}_${timestamp}.${out_ext}"
fi

# Create temporary file list for ffmpeg concat
temp_list=$(mktemp /tmp/audio_merge_XXXXXX.txt)
trap "rm -f '$temp_list'" EXIT

echo "📝 Preparing files for merge:"
for file in "${sorted_files[@]}"; do
    echo "   → $(basename "$file")"
    # Escape special characters for ffmpeg concat
    escaped_file=$(printf '%s\n' "$file" | sed "s/'/'\\\\''/g")
    echo "file '$escaped_file'" >> "$temp_list"
done

echo ""
echo "🔄 Merging audio files..."

# Check if all files have the same codec - if so, use stream copy (fastest, lossless)
all_same_codec=true
for file in "${sorted_files[@]}"; do
    file_codec=$(ffprobe -v quiet -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$file" 2>/dev/null)
    if [ "$file_codec" != "$codec" ]; then
        all_same_codec=false
        break
    fi
done

if $all_same_codec && [[ "$codec" =~ ^(aac|mp3)$ ]]; then
    echo "   Using stream copy (lossless, fast)..."
    # For AAC/MP3 with same codec, use concat demuxer with stream copy
    ffmpeg -y -f concat -safe 0 -i "$temp_list" -c copy "$output_file" 2>/dev/null
else
    echo "   Re-encoding to match quality..."
    # Re-encode when codecs differ
    ffmpeg -y -f concat -safe 0 -i "$temp_list" \
        $codec_opts \
        -ar "$sample_rate" \
        -ac "$channels" \
        "$output_file" 2>/dev/null
fi

if [ -f "$output_file" ]; then
    # Get output file size
    output_size=$(du -h "$output_file" | cut -f1)
    output_duration=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$output_file" 2>/dev/null)
    duration_formatted=$(printf '%02d:%02d:%02d' $(echo "$output_duration/3600" | bc) $(echo "($output_duration%3600)/60" | bc) $(echo "$output_duration%60" | bc) 2>/dev/null || echo "N/A")
    
    echo ""
    echo "✅ Successfully merged ${#sorted_files[@]} files!"
    echo "📁 Output: $(basename "$output_file")"
    echo "📏 Size: $output_size"
    echo "⏱️  Duration: $duration_formatted"
    echo "📂 Location: $first_dir"
    
    # Reveal in Finder/Path Finder
    osascript -e "tell application \"Finder\" to reveal POSIX file \"$output_file\"" 2>/dev/null || true
else
    echo "❌ Error: Failed to create merged file"
    exit 1
fi
