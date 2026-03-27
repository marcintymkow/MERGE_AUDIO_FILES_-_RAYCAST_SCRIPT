# Merge Audio Files

Raycast Script Command that merges multiple selected audio files into one, matching quality settings from the first file when re-encoding is needed.

## Overview

Select two or more audio files in **Finder** or **Path Finder**, run the command from Raycast, and get a single file in the same folder. The script reads codec, bitrate, sample rate, and channel layout from the first file (after sorting) and uses **ffmpeg** to concatenate.

## Features

- **Codec-aware workflow** – probes the first track and aligns output settings
- **Fast path for AAC/MP3** – if every file uses the same codec as the first, uses **stream copy** (`-c copy`) so there is no generation loss and merging is quick
- **Re-encode when needed** – mixed codecs or non–AAC/MP3 same-codec cases are re-encoded using the detected parameters
- **Natural sort order** – files are ordered with version-style sorting (`sort -V`) so `2.mp3` comes before `10.mp3`
- **Finder and Path Finder** – selection is read from Path Finder when it is running, otherwise from Finder
- **Output naming** – `MERGED - {name}.{ext}` with common leading track numbers stripped (e.g. `01. `, `1 - `)

## Supported formats

Extensions (case-insensitive): **aac**, **mp3**, **m4a**, **wav**, **flac**, **ogg**, **wma**, **opus**

## Requirements

- macOS
- [Raycast](https://www.raycast.com/)
- **ffmpeg** (includes **ffprobe**), e.g.:

  ```bash
  brew install ffmpeg
  ```

## Installation

1. Copy the script into Raycast’s Script Commands folder:

   ```bash
   cp merge-audio-files.sh ~/Library/Application\ Support/Raycast/Script\ Commands/
   ```

2. Make it executable:

   ```bash
   chmod +x ~/Library/Application\ Support/Raycast/Script\ Commands/merge-audio-files.sh
   ```

3. Reload Raycast. The command title is **Merge Audio Files** (package **Audio Tools**).

## Usage

1. In Finder or Path Finder, select **at least two** supported audio files.
2. Open Raycast and run **Merge Audio Files**.
3. When finished, the merged file appears in the **same directory as the first file** in the sorted list, and Finder is asked to reveal it.

## Output

| Item | Behavior |
|------|----------|
| **Filename** | `MERGED - {clean_name}.{ext}` — leading numeric prefixes like `1. `, `01 - `, `1-` are removed from the first file’s basename |
| **Extension** | Same as the first sorted input (e.g. `.m4a` stays `.m4a`) |
| **Collision** | If that path exists, a timestamp suffix is added |
| **Location** | Directory of the first file after sorting |

## How it works (short)

1. Collect paths from Path Finder or Finder.
2. Keep only existing files with supported extensions.
3. Sort paths with natural/version order.
4. Probe the first file for audio stream parameters.
5. If all files share the **same** codec **and** that codec is **aac** or **mp3**, concatenate with **copy**; otherwise concatenate with **re-encode** using the chosen encoder options, sample rate, and channel count from the first file.

## Troubleshooting

| Message | What to do |
|---------|------------|
| `ffmpeg is not installed` | Install ffmpeg (e.g. `brew install ffmpeg`). |
| `No files selected` | Select files in Finder or Path Finder before running the command. |
| `Need at least 2 audio files` | Ensure at least two selections are valid audio files (see supported extensions). |
| Wrong merge order | Use consistent numeric prefixes in filenames so version sort orders them as you want. |

## Author

Marcin — Tymków

## License

MIT License — free for personal and commercial use.
