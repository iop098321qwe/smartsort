#!/usr/bin/env bash

smartsort() {
  local mode=""            # Sorting mode (ext, alpha, time, size, type)
  local interactive_mode=0 # Flag for interactive refinements
  local target_dir="."     # Destination directory for sorted folders
  local first_letter=""
  local file=""
  local time_grouping="month"
  local type_granularity="top-level"
  local small_threshold_bytes=1048576   # 1MB default
  local medium_threshold_bytes=10485760 # 10MB default
  local summary_details=""
  local -a selected_extensions=()

  OPTIND=1

  usage() {
    cbc_style_box "$CATPPUCCIN_MAUVE" "Description:" \
      "  Organises files in the current directory according to the mode you choose." \
      "  Available modes:" \
      "    - ext   : Group by file extension (supports multi-selection)." \
      "    - alpha : Group by the first character of the filename." \
      "    - time  : Group by modification time (year, month, or day)." \
      "    - size  : Group by file size buckets (customisable thresholds)." \
      "    - type  : Group by MIME type (top-level or full type)."

    cbc_style_box "$CATPPUCCIN_BLUE" "Usage:" \
      "  smartsort [-h] [-i] [-m mode] [-d directory]"

    cbc_style_box "$CATPPUCCIN_TEAL" "Options:" \
      "  -h            Display this help message." \
      "  -i            Enable interactive prompts for advanced configuration." \
      "  -m mode       Specify the sorting mode directly (ext|alpha|time|size|type)." \
      "  -d directory  Destination root for sorted folders (defaults to current directory)."

    cbc_style_box "$CATPPUCCIN_PEACH" "Examples:" \
      "  smartsort -i" \
      "  smartsort -m type -d ./sorted" \
      "  smartsort -i -m size"
  }

  smartsort_select_mode() {
    local selection=""
    if command -v fzf >/dev/null 2>&1; then
      selection=$(printf "ext\nalpha\ntime\nsize\ntype\n" |
        fzf --prompt="Select sorting mode: " --header="Choose how to organise files")
    elif [ "$CBC_HAS_GUM" -eq 1 ]; then
      selection=$(gum choose --cursor.foreground "$CATPPUCCIN_GREEN" \
        --selected.foreground "$CATPPUCCIN_GREEN" \
        --header "Select how to organise files" ext alpha time size type)
    else
      cbc_style_message "$CATPPUCCIN_SUBTEXT" "Enter sorting mode (ext/alpha/time/size/type):"
      read -r selection
    fi
    printf '%s' "$selection"
  }

  smartsort_prompt_target_dir() {
    local input
    input=$(cbc_input "Destination directory (blank keeps current): " "$(pwd)/sorted")
    if [ -n "$input" ]; then
      target_dir="$input"
    fi
  }

  smartsort_unique_extensions() {
    local -a extensions=()
    while IFS= read -r path; do
      local base ext_label
      base=${path#./}
      if [[ "$base" == *.* && "$base" != .* ]]; then
        ext_label=${base##*.}
      else
        ext_label="no-extension"
      fi
      extensions+=("$ext_label")
    done < <(find . -maxdepth 1 -type f -print)

    if [ "${#extensions[@]}" -eq 0 ]; then
      return 1
    fi

    printf '%s\n' "${extensions[@]}" | sort -u
    return 0
  }

  smartsort_choose_extensions() {
    local -a available=()
    if ! mapfile -t available < <(smartsort_unique_extensions); then
      return 1
    fi

    cbc_style_message "$CATPPUCCIN_SUBTEXT" "Select extensions to include (leave empty to include all)."

    if command -v fzf >/dev/null 2>&1; then
      mapfile -t selected_extensions < <(printf '%s\n' "${available[@]}" |
        fzf --multi --prompt="Extensions: " \
          --header="Tab to toggle multiple extensions. (Esc for all)" \
          --height=12 --border)
    elif [ "$CBC_HAS_GUM" -eq 1 ]; then
      local selection=""
      if selection=$(gum choose --no-limit \
        --cursor.foreground "$CATPPUCCIN_GREEN" \
        --selected.foreground "$CATPPUCCIN_GREEN" \
        --header "Select one or more extensions (Esc for all)" "${available[@]}"); then
        if [ -n "$selection" ]; then
          IFS=$'\n' read -r -a selected_extensions <<<"$selection"
        else
          selected_extensions=()
        fi
      else
        local exit_code=$?
        if [ $exit_code -eq 130 ] || [ -z "$selection" ]; then
          selected_extensions=()
        else
          return $exit_code
        fi
      fi
    else
      local input
      input=$(cbc_input "Extensions (space separated, blank for all): " "${available[*]}")
      if [ -n "$input" ]; then
        read -r -a selected_extensions <<<"$input"
      else
        selected_extensions=()
      fi
    fi

    return 0
  }

  smartsort_get_mod_date() {
    local path="$1"
    local format="$2"
    local mod_date=""

    if mod_date=$(date -r "$path" +"$format" 2>/dev/null); then
      printf '%s' "$mod_date"
      return 0
    fi

    if mod_date=$(stat -f "%Sm" -t "$format" "$path" 2>/dev/null); then
      printf '%s' "$mod_date"
      return 0
    fi

    printf '%s' "unknown"
    return 0
  }

  smartsort_get_file_size() {
    local path="$1"
    local size=""

    if size=$(stat -c%s "$path" 2>/dev/null); then
      printf '%s' "$size"
      return 0
    fi

    if size=$(stat -f%z "$path" 2>/dev/null); then
      printf '%s' "$size"
      return 0
    fi

    return 1
  }

  smartsort_prompt_time_grouping() {
    local selection=""
    if command -v fzf >/dev/null 2>&1; then
      selection=$(printf "month\nyear\nday\n" |
        fzf --prompt="Select time grouping: " --header="Choose modification time grouping granularity")
    elif [ "$CBC_HAS_GUM" -eq 1 ]; then
      selection=$(gum choose --cursor.foreground "$CATPPUCCIN_GREEN" \
        --selected.foreground "$CATPPUCCIN_GREEN" \
        --header "Choose modification time grouping" month year day)
    else
      cbc_style_message "$CATPPUCCIN_SUBTEXT" "Group files by (month/year/day):"
      read -r selection
    fi

    case "$selection" in
    year) time_grouping="year" ;;
    day) time_grouping="day" ;;
    month | "") time_grouping="month" ;;
    *)
      cbc_style_message "$CATPPUCCIN_YELLOW" "Unknown selection '$selection'. Using month grouping."
      time_grouping="month"
      ;;
    esac
  }

  smartsort_prompt_size_thresholds() {
    cbc_style_message "$CATPPUCCIN_SUBTEXT" "Configure size buckets in whole megabytes (press Enter to keep defaults)."
    local input_small
    local input_medium

    input_small=$(cbc_input "Max size for 'small' files (MB): " "$((small_threshold_bytes / 1024 / 1024))")
    input_medium=$(cbc_input "Max size for 'medium' files (MB): " "$((medium_threshold_bytes / 1024 / 1024))")

    if [ -n "$input_small" ]; then
      if echo "$input_small" | grep -Eq '^[0-9]+$'; then
        small_threshold_bytes=$((input_small * 1024 * 1024))
      else
        cbc_style_message "$CATPPUCCIN_RED" "Invalid value '$input_small'. Keeping default small bucket size."
        small_threshold_bytes=1048576
      fi
    fi

    if [ -n "$input_medium" ]; then
      if echo "$input_medium" | grep -Eq '^[0-9]+$'; then
        medium_threshold_bytes=$((input_medium * 1024 * 1024))
      else
        cbc_style_message "$CATPPUCCIN_RED" "Invalid value '$input_medium'. Keeping default medium bucket size."
        medium_threshold_bytes=10485760
      fi
    fi

    if [ "$medium_threshold_bytes" -le "$small_threshold_bytes" ]; then
      cbc_style_message "$CATPPUCCIN_RED" "Medium bucket must be larger than small bucket. Reverting to defaults."
      small_threshold_bytes=1048576
      medium_threshold_bytes=10485760
    fi
  }

  smartsort_prompt_type_granularity() {
    local selection=""
    if command -v fzf >/dev/null 2>&1; then
      selection=$(printf "top-level\nfull\n" |
        fzf --prompt="Select MIME grouping: " --header="Choose MIME granularity")
    elif [ "$CBC_HAS_GUM" -eq 1 ]; then
      selection=$(gum choose --cursor.foreground "$CATPPUCCIN_GREEN" \
        --selected.foreground "$CATPPUCCIN_GREEN" \
        --header "Choose MIME granularity" "top-level" full)
    else
      cbc_style_message "$CATPPUCCIN_SUBTEXT" "Group by MIME (top-level/full):"
      read -r selection
    fi

    case "$selection" in
    full) type_granularity="full" ;;
    top-level | "") type_granularity="top-level" ;;
    *)
      cbc_style_message "$CATPPUCCIN_YELLOW" "Unknown selection '$selection'. Using top-level grouping."
      type_granularity="top-level"
      ;;
    esac
  }

  while getopts ":hm:id:" opt; do
    case $opt in
    h)
      usage
      return 0
      ;;
    i)
      interactive_mode=1
      ;;
    m)
      mode="$OPTARG"
      ;;
    d)
      target_dir="$OPTARG"
      ;;
    \?)
      cbc_style_message "$CATPPUCCIN_RED" "Invalid option: -$OPTARG"
      return 1
      ;;
    :)
      cbc_style_message "$CATPPUCCIN_RED" "Option -$OPTARG requires an argument."
      return 1
      ;;
    esac
  done

  shift $((OPTIND - 1))

  if [ -z "$target_dir" ]; then
    target_dir="."
  fi

  if [ "$interactive_mode" -eq 1 ]; then
    if [ -z "$mode" ]; then
      mode=$(smartsort_select_mode)
      if [ -z "$mode" ]; then
        cbc_style_message "$CATPPUCCIN_RED" "No sorting mode selected. Exiting..."
        return 1
      fi
    else
      cbc_style_message "$CATPPUCCIN_SUBTEXT" "Interactive refinements enabled for mode: $mode"
    fi

    if [ "$target_dir" = "." ]; then
      smartsort_prompt_target_dir
    fi
  fi

  if [ -z "$mode" ]; then
    mode="ext"
  fi

  case "$mode" in
  ext | alpha | time | size | type) ;;
  *)
    cbc_style_message "$CATPPUCCIN_RED" "Invalid sorting mode: $mode"
    return 1
    ;;
  esac

  if [ "$target_dir" != "." ]; then
    if ! mkdir -p "$target_dir"; then
      cbc_style_message "$CATPPUCCIN_RED" "Failed to create destination directory: $target_dir"
      return 1
    fi
  fi

  local absolute_target
  absolute_target=$(cd "$target_dir" 2>/dev/null && pwd)
  if [ -z "$absolute_target" ]; then
    absolute_target="$target_dir"
  fi

  if [ -z "$(find . -maxdepth 1 -type f -print -quit)" ]; then
    cbc_style_message "$CATPPUCCIN_YELLOW" "No files found in the current directory to sort."
    return 0
  fi

  if [ "$mode" = "ext" ] && [ "$interactive_mode" -eq 1 ]; then
    if ! smartsort_choose_extensions; then
      cbc_style_message "$CATPPUCCIN_YELLOW" "No files with extensions found for sorting."
      return 0
    fi
  fi

  if [ "$mode" = "time" ] && [ "$interactive_mode" -eq 1 ]; then
    smartsort_prompt_time_grouping
  fi

  if [ "$mode" = "size" ] && [ "$interactive_mode" -eq 1 ]; then
    smartsort_prompt_size_thresholds
  fi

  if [ "$mode" = "type" ] && [ "$interactive_mode" -eq 1 ]; then
    smartsort_prompt_type_granularity
  fi

  case "$mode" in
  ext)
    if [ "${#selected_extensions[@]}" -gt 0 ]; then
      summary_details="Extensions: ${selected_extensions[*]}"
    else
      summary_details="Extensions: all"
    fi
    ;;
  time)
    summary_details="Time grouping: $time_grouping"
    ;;
  size)
    summary_details="Size buckets (MB): small≤$((small_threshold_bytes / 1024 / 1024)), medium≤$((medium_threshold_bytes / 1024 / 1024)), large>medium"
    ;;
  type)
    summary_details="MIME grouping: $type_granularity"
    ;;
  *)
    summary_details=""
    ;;
  esac

  local -a summary_lines=(
    "  Sorting Mode    : $mode"
    "  Interactive Mode: $([[ "$interactive_mode" -eq 1 ]] && echo Enabled || echo Disabled)"
    "  Target Directory: $absolute_target"
  )

  if [ -n "$summary_details" ]; then
    summary_lines+=("  Details         : $summary_details")
  fi

  cbc_style_box "$CATPPUCCIN_LAVENDER" "Selected Options:" "${summary_lines[@]}"

  if ! cbc_confirm "Proceed with sorting?"; then
    cbc_style_message "$CATPPUCCIN_YELLOW" "Sorting operation canceled."
    return 0
  fi

  sort_by_extension() {
    local include_all=1
    local path=""

    if [ "${#selected_extensions[@]}" -gt 0 ]; then
      include_all=0
    fi

    cbc_style_message "$CATPPUCCIN_BLUE" "Sorting files by extension..."

    while IFS= read -r path; do
      [ -f "$path" ] || continue
      local base ext_label target_subdir matched=0
      base=${path#./}
      if [[ "$base" == *.* && "$base" != .* ]]; then
        ext_label=${base##*.}
      else
        ext_label="no-extension"
      fi

      if [ "$include_all" -eq 0 ]; then
        for selected in "${selected_extensions[@]}"; do
          if [ "$selected" = "$ext_label" ]; then
            matched=1
            break
          fi
        done
        if [ "$matched" -eq 0 ]; then
          continue
        fi
      fi

      target_subdir="$target_dir/$ext_label"
      mkdir -p "$target_subdir"
      mv "$path" "$target_subdir/"
    done < <(find . -maxdepth 1 -type f -print)

    cbc_style_message "$CATPPUCCIN_GREEN" "Files have been sorted into extension-based directories."
  }

  sort_by_alpha() {
    cbc_style_message "$CATPPUCCIN_BLUE" "Sorting files alphabetically by the first letter..."

    while IFS= read -r path; do
      [ -f "$path" ] || continue
      local base letter target_subdir
      base=${path#./}
      letter=$(printf '%s' "$base" | cut -c1 | tr '[:upper:]' '[:lower:]')
      if [ -z "$letter" ]; then
        letter="misc"
      fi
      target_subdir="$target_dir/$letter"
      mkdir -p "$target_subdir"
      mv "$path" "$target_subdir/"
    done < <(find . -maxdepth 1 -type f -print)

    cbc_style_message "$CATPPUCCIN_GREEN" "Files have been sorted into directories based on their first letter."
  }

  sort_by_time() {
    local date_format="%Y-%m"
    case "$time_grouping" in
    year) date_format="%Y" ;;
    day) date_format="%Y-%m-%d" ;;
    *) date_format="%Y-%m" ;;
    esac

    cbc_style_message "$CATPPUCCIN_BLUE" "Sorting files by modification time..."

    while IFS= read -r path; do
      [ -f "$path" ] || continue
      local mod_date target_subdir
      mod_date=$(smartsort_get_mod_date "$path" "$date_format")
      if [ -z "$mod_date" ]; then
        mod_date="unknown"
      fi
      target_subdir="$target_dir/$mod_date"
      mkdir -p "$target_subdir"
      mv "$path" "$target_subdir/"
    done < <(find . -maxdepth 1 -type f -print)

    cbc_style_message "$CATPPUCCIN_GREEN" "Files have been sorted into date-based directories."
  }

  sort_by_size() {
    cbc_style_message "$CATPPUCCIN_BLUE" "Sorting files by size into categories..."

    while IFS= read -r path; do
      [ -f "$path" ] || continue
      local size category="unknown" target_subdir
      if ! size=$(smartsort_get_file_size "$path"); then
        cbc_style_message "$CATPPUCCIN_YELLOW" "Unable to determine size for $path. Skipping."
        continue
      fi

      if [ "$size" -lt "$small_threshold_bytes" ]; then
        category="small"
      elif [ "$size" -lt "$medium_threshold_bytes" ]; then
        category="medium"
      else
        category="large"
      fi

      target_subdir="$target_dir/$category"
      mkdir -p "$target_subdir"
      mv "$path" "$target_subdir/"
    done < <(find . -maxdepth 1 -type f -print)

    cbc_style_message "$CATPPUCCIN_GREEN" "Files have been sorted into size-based directories."
  }

  sort_by_type() {
    if ! command -v file >/dev/null 2>&1; then
      cbc_style_message "$CATPPUCCIN_RED" "The 'file' command is required for type sorting."
      return 1
    fi

    cbc_style_message "$CATPPUCCIN_BLUE" "Sorting files by MIME type..."

    while IFS= read -r path; do
      [ -f "$path" ] || continue
      local mime category target_subdir
      mime=$(file --brief --mime-type "$path")
      if [ "$type_granularity" = "full" ]; then
        category=${mime//\//_}
      else
        category=${mime%%/*}
      fi
      if [ -z "$category" ]; then
        category="unknown"
      fi
      target_subdir="$target_dir/$category"
      mkdir -p "$target_subdir"
      mv "$path" "$target_subdir/"
    done < <(find . -maxdepth 1 -type f -print)

    cbc_style_message "$CATPPUCCIN_GREEN" "Files have been sorted into MIME type directories."
  }

  case "$mode" in
  ext) sort_by_extension || return 1 ;;
  alpha) sort_by_alpha || return 1 ;;
  time) sort_by_time || return 1 ;;
  size) sort_by_size || return 1 ;;
  type) sort_by_type || return 1 ;;
  esac

  cbc_style_message "$CATPPUCCIN_GREEN" "Sorting operation completed successfully."
  cbc_style_message "$CATPPUCCIN_SUBTEXT" "There is no way to undo what you just did. Stay tuned for possible undo in the future."
}

