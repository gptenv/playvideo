#!/usr/bin/env bash
# playvideo - Terminal multi-format file-to-terminal video/image player and converter with audio support
# Usage:
#   playvideo [options] [--video-flags <flags>] [--audio-flags <flags>]
#   Reads input from file argument or stdin if omitted or '-'
#   Outputs to stdout or optionally to file with --output <file>
#   Supports --format {sixel,kitty,ascii,ansi,utf8,caca,gif,mp4}
#   Supports profiles and user custom profiles at ~/.playvideo_profiles
#   Supports --restore-defaults to reset profiles to builtin defaults
#   Audio playback with --audio (uses ffplay by default) and flags passthrough

set -euo pipefail

readonly SCRIPT_NAME=$(basename "$0")

# Location for user profiles
PROFILE_FILE="${HOME}/.playvideo_profiles"

# Globals for options
INPUT_FILE="-"
#INPUT_FILE=""
OUTPUT_FILE=""
FORMAT="sixel"
FPS=24
SHOW_HELP=0
RESTORE_DEFAULTS=0
VERBOSE=0
ENABLE_AUDIO=0
DRY_RUN=0

# Arrays for flags, properly initialized
declare -a VIDEO_EXTRA_FLAGS=()
declare -a AUDIO_EXTRA_FLAGS=()

# Internal command flags, empty by default
FFMPEG_FLAGS=""
CHAFA_FLAGS=""
JP2A_FLAGS=""
IMG2TXT_FLAGS=""
KITTY_FLAGS=""
FFMPEG_OUT=""

# Default profiles embedded here
declare -A DEFAULT_PROFILES=(
  [sixel]="FFMPEG_FLAGS='-vf scale=320:-1 -pix_fmt rgb24'
    CHAFA_FLAGS='-f sixels --colors=256 --dither=diffusion --fill=all --symbols=all --clear'
    IMG2TXT_FLAGS='-f ansi --width=80'
    FFMPEG_OUT='-f gif'
    FORMAT='gif'  # Default format, this can be changed via script arguments

    DESC='Sixel terminal output (default)'

    # Attempt to run ffmpeg on the input file
    if ! ffmpeg \$FFMPEG_FLAGS -i \"\$INPUT_FILE\" -f rawvideo -pix_fmt rgb24 pipe:1 2>/dev/null | chafa \$CHAFA_FLAGS; then
      # If ffmpeg fails, fallback to visual representation
      echo 'ffmpeg failed, attempting fallback to visual representation...'
      
      # Check for other transcoding options (like ASCII or GIF)
      if [[ \"\$FORMAT\" == \"gif\" ]]; then
        ffmpeg \$FFMPEG_FLAGS -i \"\$INPUT_FILE\" \$FFMPEG_OUT \"\$OUTPUT_FILE\"
      elif [[ \"\$FORMAT\" == \"ascii\" ]]; then
        jp2a --colors --width=80 \"\$INPUT_FILE\"
      elif [[ \"\$FORMAT\" == \"ansi\" || \"\$FORMAT\" == \"utf8\" || \"\$FORMAT\" == \"caca\" ]]; then
        img2txt \$IMG2TXT_FLAGS \"\$INPUT_FILE\"
      else
        echo \"Unsupported format for fallback: \$FORMAT\"
      fi
    fi"
  [kitty]="FFMPEG_FLAGS='-vf scale=320:-1 -pix_fmt rgb24'
    CHAFA_FLAGS='-f sixels --colors=256 --dither=diffusion --fill=all --symbols=all --clear'
    IMG2TXT_FLAGS='-f ansi --width=80'
    FFMPEG_OUT='-f gif'
    FORMAT='gif'  # Default format, this can be changed via script arguments
    KITTY_FLAGS='--quiet --print-fps' DESC='Kitty graphics protocol output'"
  [ascii]="FFMPEG_FLAGS='-vf scale=80:-1' JP2A_FLAGS='--colors --width=80' DESC='ASCII art output via jp2a'"
  [ansi]="FFMPEG_FLAGS='-vf scale=80:-1' IMG2TXT_FLAGS='-f ansi --width=80' DESC='ANSI colored output via img2txt'"
  [utf8]="FFMPEG_FLAGS='-vf scale=80:-1' IMG2TXT_FLAGS='-f utf8 --width=80' DESC='UTF8 colored output via img2txt'"
  [caca]="FFMPEG_FLAGS='-vf scale=80:-1' IMG2TXT_FLAGS='-f caca --width=80' DESC='Libcaca output'"
  [gif]="FFMPEG_FLAGS='-vf scale=320:-1:flags=lanczos' FFMPEG_OUT='-f gif' DESC='Animated GIF output via ffmpeg'"
  [mp4]="FFMPEG_FLAGS='-vf scale=640:-1' FFMPEG_OUT='-c:v libx264 -preset fast -crf 23' DESC='MP4 output via ffmpeg'"
)

# Helper functions

print_help() {
  cat << EOF
$SCRIPT_NAME - Play any file as terminal video/image or convert to gif/mp4 with audio support

Usage:
  $SCRIPT_NAME [options] [--video-flags <flags>] [--audio-flags <flags>]

Options:
  -i, --input <file>       Input file (default: stdin)
  -o, --output <file>      Output file (default: stdout)
  -f, --format <fmt>       Output format: sixel, kitty, ascii, ansi, utf8, caca, gif, mp4
                           Default: sixel
  --fps <fps>              Set playback framerate (default: 24)
  --audio                  Enable audio playback (via ffplay by default)
  --list-profiles          List available profiles
  --use-profile <name>     Use a profile (sets flags & format accordingly)
  --restore-defaults       Restore default profiles (overwrites ~/.playvideo_profiles)
  --verbose                Show verbose debug output
  --dry-run                Print the commands that would run, then exit
  --video-flags <flags>    Extra flags passed to ffmpeg for video processing
  --audio-flags <flags>    Extra flags passed to audio playback command (ffplay/sox)
  -h, --help               Show this help message

Profiles can be defined/modified in ~/.playvideo_profiles as bash-style variable sets.
Default profiles are:
EOF
  for k in "${!DEFAULT_PROFILES[@]}"; do
    echo "  - $k: ${DEFAULT_PROFILES[$k]%% DESC=*}"
  done
  echo ""
}

load_profiles() {
  # Load user profile overrides if exist
  if [[ -f "$PROFILE_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$PROFILE_FILE"
  fi
}

save_default_profiles() {
  {
    echo "# ~/.playvideo_profiles - user editable playvideo profiles"
    for key in "${!DEFAULT_PROFILES[@]}"; do
      echo "declare -g DEFAULT_PROFILES[$key]=\"${DEFAULT_PROFILES[$key]}\""
    done
    echo "# End of default profiles"
  } > "$PROFILE_FILE"
  echo "Default profiles restored to $PROFILE_FILE"
}

verbose() {
  if [[ "$VERBOSE" -eq 1 ]]; then
    echo "[playvideo]: $*" >&2
  fi
}

# Parse options
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--input)
      INPUT_FILE="$2"
      shift 2
      ;;
    -o|--output)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    -f|--format)
      FORMAT="$2"
      shift 2
      ;;
    --fps)
      FPS="$2"
      shift 2
      ;;
    --audio)
      ENABLE_AUDIO=1
      shift
      ;;
    --list-profiles)
      load_profiles
      echo "Available profiles:"
      for k in "${!DEFAULT_PROFILES[@]}"; do
        echo "  - $k: ${DEFAULT_PROFILES[$k]%% DESC=*}"
      done
      exit 0
      ;;
    --use-profile)
      PROFILE_NAME="$2"
      load_profiles
      if [[ -z "${DEFAULT_PROFILES[$PROFILE_NAME]:-}" ]]; then
        echo "Error: Unknown profile '$PROFILE_NAME'" >&2
        exit 1
      fi
      eval "${DEFAULT_PROFILES[$PROFILE_NAME]}"
      FORMAT="$PROFILE_NAME"
      shift 2
      ;;
    --restore-defaults)
      RESTORE_DEFAULTS=1
      shift
      ;;
    --verbose)
      VERBOSE=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --video-flags)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --video-flags requires an argument" >&2
        exit 1
      fi
      # shellcheck disable=SC2206
      VIDEO_EXTRA_FLAGS+=($2)
      shift 2
      ;;
    --audio-flags)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --audio-flags requires an argument" >&2
        exit 1
      fi
      # shellcheck disable=SC2206
      AUDIO_EXTRA_FLAGS+=($2)
      shift 2
      ;;
    -h|--help)
      SHOW_HELP=1
      shift
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        # Treat all after -- as video flags to keep backward compatibility
        VIDEO_EXTRA_FLAGS+=("$1")
        shift
      done
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

# Restore positional parameters
set -- "${POSITIONAL[@]}"

if [[ "$SHOW_HELP" -eq 1 ]]; then
  print_help
  exit 0
fi

if [[ "$RESTORE_DEFAULTS" -eq 1 ]]; then
  save_default_profiles
  exit 0
fi

load_profiles

# Positional input file fallback
if [[ -n "${POSITIONAL[0]:-}" ]] && [[ "$INPUT_FILE" == "-" ]]; then
  INPUT_FILE="${POSITIONAL[0]}"
fi

verbose "Input file: $INPUT_FILE"
verbose "Output file: ${OUTPUT_FILE:-stdout}"
verbose "Format: $FORMAT"
verbose "FPS: $FPS"
verbose "Enable audio: $ENABLE_AUDIO"
verbose "Dry run: $DRY_RUN"
verbose "Video extra flags: ${VIDEO_EXTRA_FLAGS[*]}"
verbose "Audio extra flags: ${AUDIO_EXTRA_FLAGS[*]}"

if [[ "$INPUT_FILE" != "-" && ! -f "$INPUT_FILE" ]]; then
  echo "Error: Input file not found: $INPUT_FILE" >&2
  exit 1
fi

TMPDIR=$(mktemp -d)
cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

# Compose internal commands for video
declare -a video_cmd=()
declare -a audio_cmd=()

case "$FORMAT" in
  sixel)
    verbose "Building sixel output command"
    if [[ "$INPUT_FILE" == "-" ]]; then
      video_cmd=( ffmpeg -loglevel error -i pipe:0 -vf "fps=$FPS,${FFMPEG_FLAGS:-scale=320:-1}" -f rawvideo -pix_fmt rgb24 "${VIDEO_EXTRA_FLAGS[@]}" pipe:1 )
    else
      video_cmd=( ffmpeg -loglevel error -i "$INPUT_FILE" -vf "fps=$FPS,${FFMPEG_FLAGS:-scale=320:-1}" -f rawvideo -pix_fmt rgb24 "${VIDEO_EXTRA_FLAGS[@]}" pipe:1 )
    fi
    # chafa command line flags override from profile or default
    chafa_args=( chafa ${CHAFA_FLAGS:-"-f sixels --colors=256 --dither=diffusion --fill=all --symbols=all --clear"} )
    ;;
  kitty)
    verbose "Building kitty graphics output command"
    if ! command -v kitty +kitten icat >/dev/null 2>&1; then
      echo "Error: kitty +kitten icat not found for kitty graphics output" >&2
      exit 1
    fi
    if [[ "$INPUT_FILE" == "-" ]]; then
      video_cmd=( ffmpeg -loglevel error -i pipe:0 -vf "fps=$FPS,${FFMPEG_FLAGS:-scale=320:-1}" -f rawvideo -pix_fmt rgb24 "${VIDEO_EXTRA_FLAGS[@]}" pipe:1 )
      kitty_args=( kitty +kitten icat --clear --stdin ${KITTY_FLAGS:-} )
    else
      video_cmd=()
      kitty_args=( kitty +kitten icat --clear "$INPUT_FILE" ${KITTY_FLAGS:-} )
    fi
    ;;
  ascii)
    verbose "Building ascii output command"
    if [[ "$INPUT_FILE" == "-" ]]; then
      TMPPNG="$TMPDIR/frame.png"
      video_cmd=( ffmpeg -loglevel error -i pipe:0 -frames:v 1 -vf "${FFMPEG_FLAGS:-scale=80:-1}" "$TMPPNG" "${VIDEO_EXTRA_FLAGS[@]}" )
      jp2a_args=( jp2a ${JP2A_FLAGS:-"--colors --width=80"} )
    else
      jp2a_args=( jp2a ${JP2A_FLAGS:-"--colors --width=80"} "$INPUT_FILE" )
      video_cmd=()
    fi
    ;;
  ansi|utf8|caca)
    verbose "Building img2txt output command"
    declare -A FORMAT_MAP=( [ansi]="-f ansi" [utf8]="-f utf8" [caca]="-f caca" )
    FORMAT_FLAG="${FORMAT_MAP[$FORMAT]}"
    if [[ "$INPUT_FILE" == "-" ]]; then
      TMPPNG="$TMPDIR/frame.png"
      video_cmd=( ffmpeg -loglevel error -i pipe:0 -frames:v 1 -vf "${FFMPEG_FLAGS:-scale=80:-1}" "$TMPPNG" "${VIDEO_EXTRA_FLAGS[@]}" )
      img2txt_args=( img2txt $FORMAT_FLAG --width=80 "$TMPPNG" ${IMG2TXT_FLAGS:-} )
    else
      img2txt_args=( img2txt $FORMAT_FLAG --width=80 "$INPUT_FILE" ${IMG2TXT_FLAGS:-} )
      video_cmd=()
    fi
    ;;
  gif)
    verbose "Building GIF output command"
    if [[ "$INPUT_FILE" == "-" ]]; then
      video_cmd=( ffmpeg -loglevel error -i pipe:0 -vf "fps=$FPS,${FFMPEG_FLAGS:-scale=320:-1:flags=lanczos}" -f gif "${VIDEO_EXTRA_FLAGS[@]}" - )
    else
      video_cmd=( ffmpeg -loglevel error -i "$INPUT_FILE" -vf "fps=$FPS,${FFMPEG_FLAGS:-scale=320:-1:flags=lanczos}" -f gif "${VIDEO_EXTRA_FLAGS[@]}" - )
    fi
    ;;
  mp4)
    verbose "Building MP4 output command"
    if [[ "$INPUT_FILE" == "-" ]]; then
      video_cmd=( ffmpeg -loglevel error -i pipe:0 -vf "fps=$FPS,${FFMPEG_FLAGS:-scale=640:-1}" -c:v libx264 -preset fast -crf 23 "${FFMPEG_OUT:-}" "${VIDEO_EXTRA_FLAGS[@]}" "${OUTPUT_FILE:+"-y"}" "${OUTPUT_FILE:+"$OUTPUT_FILE"}" )
    else
      video_cmd=( ffmpeg -loglevel error -i "$INPUT_FILE" -vf "fps=$FPS,${FFMPEG_FLAGS:-scale=640:-1}" -c:v libx264 -preset fast -crf 23 "${FFMPEG_OUT:-}" "${VIDEO_EXTRA_FLAGS[@]}" "${OUTPUT_FILE:+"-y"}" "${OUTPUT_FILE:+"$OUTPUT_FILE"}" )
    fi
    ;;
  *)
    echo "Error: Unsupported format '$FORMAT'" >&2
    exit 1
    ;;
esac

# Compose audio command (only if enabled)
if [[ "$ENABLE_AUDIO" -eq 1 ]]; then
  # For audio playback we use ffplay by default
  if [[ "$INPUT_FILE" == "-" ]]; then
    audio_cmd=( ffplay -nodisp -autoexit -loglevel error "${AUDIO_EXTRA_FLAGS[@]}" pipe:0 )
  else
    audio_cmd=( ffplay -nodisp -autoexit -loglevel error "${AUDIO_EXTRA_FLAGS[@]}" "$INPUT_FILE" )
  fi
fi

# Handle dry-run: output all internal commands as a shell script snippet and exit
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "#!/bin/bash"
  echo "# Dry run generated script from $SCRIPT_NAME"
  echo ""
  if [[ "${#video_cmd[@]}" -gt 0 ]]; then
    echo "echo 'Running video command:'"
    printf 'echo "  %s"\n' "${video_cmd[@]}"
    echo "${video_cmd[@]}"
  fi
  if [[ -v chafa_args && "${#chafa_args[@]}" -gt 0 ]]; then
    echo ""
    echo "echo 'Running chafa command:'"
    printf 'echo "  %s"\n' "${chafa_args[@]}"
    echo "${chafa_args[@]}"
  fi
  if [[ -v kitty_args && "${#kitty_args[@]}" -gt 0 ]]; then
    echo ""
    echo "echo 'Running kitty command:'"
    printf 'echo "  %s"\n' "${kitty_args[@]}"
    echo "${kitty_args[@]}"
  fi
  if [[ -v jp2a_args && "${#jp2a_args[@]}" -gt 0 ]]; then
    echo ""
    echo "echo 'Running jp2a command:'"
    printf 'echo "  %s"\n' "${jp2a_args[@]}"
    echo "${jp2a_args[@]}"
  fi
  if [[ -v img2txt_args && "${#img2txt_args[@]}" -gt 0 ]]; then
    echo ""
    echo "echo 'Running img2txt command:'"
    printf 'echo "  %s"\n' "${img2txt_args[@]}"
    echo "${img2txt_args[@]}"
  fi
  if [[ -v audio_cmd && "${#audio_cmd[@]}" -gt 0 ]]; then
    echo ""
    echo "echo 'Running audio playback command:'"
    printf 'echo "  %s"\n' "${audio_cmd[@]}"
    echo "${audio_cmd[@]}"
  fi
  exit 0
fi

# Now run the actual commands, depending on format

run_video_audio() {
  verbose "FORMAT=\"$FORMAT\""
  case "$FORMAT" in
    sixel)
      if [[ "${#video_cmd[@]}" -eq 0 ]]; then echo "No video command for sixel"; exit 1; fi
      if [[ "${#chafa_args[@]}" -eq 0 ]]; then echo "No chafa command for sixel"; exit 1; fi
      # Connect video pipeline to chafa
      verbose "Starting sixel video pipeline"
      if [[ "$ENABLE_AUDIO" -eq 1 ]]; then
        # Run audio asynchronously
        "${audio_cmd[@]}" < "$INPUT_FILE" >/dev/null 2>&1 &
        AUDIO_PID=$!
      fi
      "${video_cmd[@]}" | "${chafa_args[@]}"
      if [[ "$ENABLE_AUDIO" -eq 1 ]]; then
        wait $AUDIO_PID
      fi
      ;;
    kitty)
      if [[ "$INPUT_FILE" == "-" ]]; then
        if [[ "${#video_cmd[@]}" -eq 0 || "${#kitty_args[@]}" -eq 0 ]]; then
          echo "Missing kitty commands" >&2
          exit 1
        fi
        if [[ "$ENABLE_AUDIO" -eq 1 ]]; then
          "${audio_cmd[@]}" < "$INPUT_FILE" >/dev/null 2>&1 &
          AUDIO_PID=$!
        fi
        "${video_cmd[@]}" | "${kitty_args[@]}"
        if [[ "$ENABLE_AUDIO" -eq 1 ]]; then
          wait $AUDIO_PID
        fi
      else
        if [[ "$ENABLE_AUDIO" -eq 1 ]]; then
          "${audio_cmd[@]}" >/dev/null 2>&1 &
          AUDIO_PID=$!
        fi
        "${kitty_args[@]}"
        if [[ "$ENABLE_AUDIO" -eq 1 ]]; then
          wait $AUDIO_PID
        fi
      fi
      ;;
    ascii)
      if [[ "${#jp2a_args[@]}" -eq 0 ]]; then
        echo "No jp2a command for ascii" >&2
        exit 1
      fi
      if [[ "$INPUT_FILE" == "-" ]]; then
        "${video_cmd[@]}"
        "${jp2a_args[@]}" "$TMPDIR/frame.png"
      else
        if [[ "$ENABLE_AUDIO" -eq 1 ]]; then
          "${audio_cmd[@]}" >/dev/null 2>&1 &
          AUDIO_PID=$!
        fi
        "${jp2a_args[@]}"
        if [[ "$ENABLE_AUDIO" -eq 1 ]]; then
          wait $AUDIO_PID
        fi
      fi
      ;;
    ansi|utf8|caca)
      if [[ "${#img2txt_args[@]}" -eq 0 ]]; then
        echo "No img2txt command for $FORMAT" >&2
        exit 1
      fi
      if [[ "$INPUT_FILE" == "-" ]]; then
        "${video_cmd[@]}"
        "${img2txt_args[@]}" "$TMPDIR/frame.png"
      else
        if [[ "$ENABLE_AUDIO" -eq 1 ]]; then
          "${audio_cmd[@]}" >/dev/null 2>&1 &
          AUDIO_PID=$!
        fi
        "${img2txt_args[@]}"
        if [[ "$ENABLE_AUDIO" -eq 1 ]]; then
          wait $AUDIO_PID
        fi
      fi
      ;;
    gif|mp4)
      if [[ "${#video_cmd[@]}" -eq 0 ]]; then
        echo "No video command for $FORMAT" >&2
        exit 1
      fi
      if [[ "$ENABLE_AUDIO" -eq 1 ]]; then
        # Run audio playback async alongside video conversion if possible
        "${video_cmd[@]}" &
        VID_PID=$!
        "${audio_cmd[@]}" >/dev/null 2>&1 &
        AUDIO_PID=$!
        wait $VID_PID
        wait $AUDIO_PID
      else
        "${video_cmd[@]}"
      fi
      ;;
    *)
      echo "Unsupported format for run_video_audio: $FORMAT" >&2
      exit 1
      ;;
  esac
}

run_video_audio

exit 0

