#!/usr/bin/env bash

smartsort() {
  local mode=""            # Sorting mode (ext, alpha, time, size)
  local target_dir="."     # Destination directory for sorted folders
  local first_letter=""
  local file=""
  local time_grouping="month"
  local small_threshold_bytes=1048576   # 1MB default
  local medium_threshold_bytes=10485760 # 10MB default
  local summary_details=""
  local source_dir=""
  local run_timestamp=""
  local move_count=0
  local absolute_target=""
  local state_dir=".smartsort"
  local state_manifest="$state_dir/last-run.moves"
  local state_dirs_manifest="$state_dir/last-run.dirs"
  local state_meta="$state_dir/last-run.meta"
  local temp_state_manifest="$state_manifest.tmp"
  local temp_state_dirs_manifest="$state_dirs_manifest.tmp"
  local temp_state_meta="$state_meta.tmp"
  local -a selected_extensions=()

  OPTIND=1

  usage() {
    cbc_style_box "$CATPPUCCIN_MAUVE" "Description:" \
      "  Organises files in the current directory according to the mode you choose." \
      "  Available modes:" \
      "    - ext   : Group by file extension (supports multi-selection)." \
      "    - alpha : Group by the first character of the filename." \
      "    - time  : Group by modification time (year, month, or day)." \
      "    - size  : Group by file size buckets (customisable thresholds)."

    cbc_style_box "$CATPPUCCIN_BLUE" "Usage:" \
      "  smartsort [-h] [-m mode] [-d directory]" \
      "  smartsort undo"

    cbc_style_box "$CATPPUCCIN_TEAL" "Options:" \
      "  -h            Display this help message." \
      "  -m mode       Specify the sorting mode directly (ext|alpha|time|size)." \
      "  -d directory  Destination root for sorted folders (defaults to current directory)." \
      "  undo          Undo the most recent sorting run in this directory."

    cbc_style_box "$CATPPUCCIN_PEACH" "Examples:" \
      "  smartsort" \
      "  smartsort -m ext -d ./sorted" \
      "  smartsort -m size" \
      "  smartsort undo"
  }

  smartsort_select_mode() {
    local selection=""
    if [ "$CBC_HAS_GUM" -eq 1 ]; then
      if selection=$(gum choose --selected=ext \
        --cursor.foreground "$CATPPUCCIN_GREEN" \
        --selected.foreground "$CATPPUCCIN_GREEN" \
        --header "Select how to organise files" ext alpha time size); then
        :
      else
        selection=""
      fi
    elif command -v fzf >/dev/null 2>&1; then
      selection=$(printf "ext\nalpha\ntime\nsize\n" |
        fzf --prompt="Select sorting mode: " --header="Choose how to organise files")
    else
      cbc_style_message "$CATPPUCCIN_SUBTEXT" "Enter sorting mode (ext/alpha/time/size):"
      read -r selection
    fi

    if [ -z "$selection" ]; then
      selection="ext"
    fi

    printf '%s' "$selection"
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

  smartsort_read_meta_value() {
    local key="$1"
    local meta_file="$2"
    local line=""

    while IFS= read -r line; do
      case "$line" in
      "$key="*)
        printf '%s' "${line#*=}"
        return 0
        ;;
      esac
    done < "$meta_file"

    return 1
  }

  smartsort_discard_temp_state() {
    rm -f "$temp_state_manifest" "$temp_state_dirs_manifest" "$temp_state_meta"
  }

  smartsort_prepare_run_state() {
    source_dir=$(pwd -P)
    run_timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%S%z")
    move_count=0

    if ! mkdir -p "$state_dir"; then
      cbc_style_message "$CATPPUCCIN_RED" "Failed to create smartsort state directory: $state_dir"
      return 1
    fi

    if ! : > "$temp_state_manifest"; then
      cbc_style_message "$CATPPUCCIN_RED" "Failed to create undo manifest: $temp_state_manifest"
      return 1
    fi

    if ! : > "$temp_state_dirs_manifest"; then
      cbc_style_message "$CATPPUCCIN_RED" "Failed to create undo directory manifest: $temp_state_dirs_manifest"
      return 1
    fi

    rm -f "$temp_state_meta"
    return 0
  }

  smartsort_record_created_dir() {
    local created_dir="$1"

    if [ -z "$created_dir" ]; then
      return 1
    fi

    if ! printf '%s\0' "$created_dir" >> "$temp_state_dirs_manifest"; then
      cbc_style_message "$CATPPUCCIN_RED" "Failed to write undo directory entry for: $created_dir"
      return 1
    fi

    return 0
  }

  smartsort_ensure_directory() {
    local directory_path="$1"
    local probe_path parent_path
    local -a missing_dirs=()
    local index

    if [ -z "$directory_path" ]; then
      cbc_style_message "$CATPPUCCIN_RED" "Cannot create an empty directory path."
      return 1
    fi

    if [ -d "$directory_path" ]; then
      return 0
    fi

    if [ -e "$directory_path" ] && [ ! -d "$directory_path" ]; then
      cbc_style_message "$CATPPUCCIN_RED" "Path exists but is not a directory: $directory_path"
      return 1
    fi

    probe_path="$directory_path"
    while [ ! -d "$probe_path" ]; do
      missing_dirs+=("$probe_path")
      parent_path=${probe_path%/*}

      if [ -z "$parent_path" ]; then
        if [[ "$probe_path" == /* ]]; then
          parent_path="/"
        else
          parent_path="."
        fi
      fi

      if [ "$parent_path" = "$probe_path" ]; then
        parent_path="."
      fi

      probe_path="$parent_path"
    done

    if ! mkdir -p "$directory_path"; then
      cbc_style_message "$CATPPUCCIN_RED" "Failed to create destination directory: $directory_path"
      return 1
    fi

    for ((index = ${#missing_dirs[@]} - 1; index >= 0; index--)); do
      if ! smartsort_record_created_dir "${missing_dirs[index]}"; then
        return 1
      fi
    done

    return 0
  }

  smartsort_record_move() {
    local original_path="$1"
    local moved_path="$2"

    if ! printf '%s\0%s\0' "$original_path" "$moved_path" >> "$temp_state_manifest"; then
      cbc_style_message "$CATPPUCCIN_RED" "Failed to write undo manifest entry for: $original_path"
      return 1
    fi

    move_count=$((move_count + 1))
    return 0
  }

  smartsort_move_file() {
    local source_path="$1"
    local destination_dir="$2"
    local source_name destination_path

    source_name=${source_path##*/}
    destination_path="$destination_dir/$source_name"

    if ! smartsort_ensure_directory "$destination_dir"; then
      return 1
    fi

    if ! mv "$source_path" "$destination_dir/"; then
      cbc_style_message "$CATPPUCCIN_RED" "Failed to move '$source_path' to '$destination_dir/'"
      return 1
    fi

    if ! smartsort_record_move "$source_path" "$destination_path"; then
      cbc_style_message "$CATPPUCCIN_RED" "Failed to record undo data for: $source_path"
      return 1
    fi

    return 0
  }

  smartsort_finalize_run_state() {
    if ! {
      printf 'version=1\n'
      printf 'source_dir=%s\n' "$source_dir"
      printf 'mode=%s\n' "$mode"
      printf 'target_dir=%s\n' "$absolute_target"
      printf 'timestamp=%s\n' "$run_timestamp"
      printf 'move_count=%s\n' "$move_count"
    } > "$temp_state_meta"; then
      cbc_style_message "$CATPPUCCIN_RED" "Failed to write undo metadata."
      return 1
    fi

    if ! mv "$temp_state_manifest" "$state_manifest"; then
      cbc_style_message "$CATPPUCCIN_RED" "Failed to save undo move manifest."
      return 1
    fi

    if ! mv "$temp_state_dirs_manifest" "$state_dirs_manifest"; then
      cbc_style_message "$CATPPUCCIN_RED" "Failed to save undo directory manifest."
      return 1
    fi

    if ! mv "$temp_state_meta" "$state_meta"; then
      cbc_style_message "$CATPPUCCIN_RED" "Failed to save undo metadata."
      return 1
    fi

    return 0
  }

  smartsort_undo_last_run() {
    local current_dir recorded_source_dir recorded_mode recorded_target_dir recorded_timestamp recorded_move_count
    local -a undo_summary=()
    local -a move_manifest=()
    local -a created_dirs_manifest=()

    if [ ! -f "$state_manifest" ] || [ ! -f "$state_meta" ]; then
      cbc_style_message "$CATPPUCCIN_YELLOW" "No sorting operation is available to undo in this directory."
      return 0
    fi

    current_dir=$(pwd -P)
    recorded_source_dir=$(smartsort_read_meta_value "source_dir" "$state_meta" 2>/dev/null || true)
    recorded_mode=$(smartsort_read_meta_value "mode" "$state_meta" 2>/dev/null || true)
    recorded_target_dir=$(smartsort_read_meta_value "target_dir" "$state_meta" 2>/dev/null || true)
    recorded_timestamp=$(smartsort_read_meta_value "timestamp" "$state_meta" 2>/dev/null || true)
    recorded_move_count=$(smartsort_read_meta_value "move_count" "$state_meta" 2>/dev/null || true)

    if [ -z "$recorded_source_dir" ]; then
      cbc_style_message "$CATPPUCCIN_RED" "Undo metadata is invalid. Remove '$state_meta' to reset undo state."
      return 1
    fi

    if [ "$current_dir" != "$recorded_source_dir" ]; then
      cbc_style_message "$CATPPUCCIN_RED" "Undo must be run from: $recorded_source_dir"
      return 1
    fi

    undo_summary+=("  Source Directory: $recorded_source_dir")
    undo_summary+=("  Sorting Mode    : ${recorded_mode:-unknown}")
    undo_summary+=("  Target Directory: ${recorded_target_dir:-unknown}")
    undo_summary+=("  Timestamp       : ${recorded_timestamp:-unknown}")
    undo_summary+=("  Files to Restore: ${recorded_move_count:-unknown}")

    cbc_style_box "$CATPPUCCIN_LAVENDER" "Undo Preview:" "${undo_summary[@]}"

    if ! cbc_confirm "Proceed with undo?"; then
      cbc_style_message "$CATPPUCCIN_YELLOW" "Undo operation canceled."
      return 0
    fi

    if ! mapfile -d '' -t move_manifest < "$state_manifest"; then
      cbc_style_message "$CATPPUCCIN_RED" "Failed to read undo manifest."
      return 1
    fi

    if [ $(( ${#move_manifest[@]} % 2 )) -ne 0 ]; then
      cbc_style_message "$CATPPUCCIN_RED" "Undo manifest is corrupt. It contains an odd number of path entries."
      return 1
    fi

    local restore_failures=0
    local restore_skips=0
    local restored_count=0
    local index original_path moved_path original_parent

    for ((index = ${#move_manifest[@]} - 2; index >= 0; index -= 2)); do
      original_path="${move_manifest[index]}"
      moved_path="${move_manifest[index + 1]}"

      if [ ! -e "$moved_path" ]; then
        cbc_style_message "$CATPPUCCIN_YELLOW" "Skipping missing file: $moved_path"
        restore_skips=$((restore_skips + 1))
        restore_failures=1
        continue
      fi

      if [ -e "$original_path" ]; then
        cbc_style_message "$CATPPUCCIN_YELLOW" "Skipping restore because destination already exists: $original_path"
        restore_skips=$((restore_skips + 1))
        restore_failures=1
        continue
      fi

      original_parent=${original_path%/*}
      if [ "$original_parent" = "$original_path" ] || [ -z "$original_parent" ]; then
        original_parent="."
      fi

      if ! mkdir -p "$original_parent"; then
        cbc_style_message "$CATPPUCCIN_YELLOW" "Failed to recreate directory: $original_parent"
        restore_skips=$((restore_skips + 1))
        restore_failures=1
        continue
      fi

      if mv "$moved_path" "$original_path"; then
        restored_count=$((restored_count + 1))
      else
        cbc_style_message "$CATPPUCCIN_YELLOW" "Failed to restore file: $moved_path"
        restore_skips=$((restore_skips + 1))
        restore_failures=1
      fi
    done

    local cleanup_failures=0
    local cleaned_dir_count=0
    local cleanup_skips=0
    local cleanup_index cleanup_path

    if [ -f "$state_dirs_manifest" ]; then
      if ! mapfile -d '' -t created_dirs_manifest < "$state_dirs_manifest"; then
        cbc_style_message "$CATPPUCCIN_YELLOW" "Failed to read undo directory manifest."
        cleanup_failures=1
      else
        for ((cleanup_index = ${#created_dirs_manifest[@]} - 1; cleanup_index >= 0; cleanup_index--)); do
          cleanup_path="${created_dirs_manifest[cleanup_index]}"

          if [ -z "$cleanup_path" ] || [ "$cleanup_path" = "." ] || [ "$cleanup_path" = "/" ]; then
            continue
          fi

          if [ ! -e "$cleanup_path" ]; then
            continue
          fi

          if [ ! -d "$cleanup_path" ]; then
            cbc_style_message "$CATPPUCCIN_YELLOW" "Skipping non-directory path during cleanup: $cleanup_path"
            cleanup_skips=$((cleanup_skips + 1))
            cleanup_failures=1
            continue
          fi

          if rmdir "$cleanup_path"; then
            cleaned_dir_count=$((cleaned_dir_count + 1))
          else
            cleanup_skips=$((cleanup_skips + 1))
            cleanup_failures=1
          fi
        done
      fi
    fi

    cbc_style_message "$CATPPUCCIN_GREEN" "Undo restored $restored_count file(s)."
    cbc_style_message "$CATPPUCCIN_GREEN" "Undo removed $cleaned_dir_count directory(s)."

    if [ "$restore_failures" -eq 0 ] && [ "$cleanup_failures" -eq 0 ]; then
      rm -f "$state_manifest" "$state_dirs_manifest" "$state_meta"
      cbc_style_message "$CATPPUCCIN_GREEN" "Undo completed successfully."
      return 0
    fi

    cbc_style_message "$CATPPUCCIN_YELLOW" "Undo completed with issues. Snapshot kept for retry."
    cbc_style_message "$CATPPUCCIN_SUBTEXT" "Files skipped: $restore_skips"
    cbc_style_message "$CATPPUCCIN_SUBTEXT" "Directories skipped: $cleanup_skips"
    return 1
  }

  while getopts ":hm:d:" opt; do
    case $opt in
    h)
      usage
      return 0
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

  if [ "${1:-}" = "undo" ]; then
    if [ "$#" -ne 1 ]; then
      cbc_style_message "$CATPPUCCIN_RED" "The undo command does not accept additional arguments."
      return 1
    fi

    if [ -n "$mode" ] || [ "$target_dir" != "." ]; then
      cbc_style_message "$CATPPUCCIN_RED" "The undo command cannot be combined with -m or -d."
      return 1
    fi

    smartsort_undo_last_run
    return $?
  fi

  if [ "$#" -gt 0 ]; then
    cbc_style_message "$CATPPUCCIN_RED" "Unknown argument: $1"
    return 1
  fi

  if [ "$#" -eq 0 ] && [ -z "$mode" ] && [ "$target_dir" = "." ]; then
    mode=$(smartsort_select_mode)
  fi

  if [ -z "$mode" ]; then
    mode="ext"
  fi

  case "$mode" in
  ext | alpha | time | size) ;;
  *)
    cbc_style_message "$CATPPUCCIN_RED" "Invalid sorting mode: $mode"
    return 1
    ;;
  esac

  if [ "$target_dir" != "." ] && [ -e "$target_dir" ] && [ ! -d "$target_dir" ]; then
    cbc_style_message "$CATPPUCCIN_RED" "Path exists but is not a directory: $target_dir"
    return 1
  fi

  absolute_target=$(cd "$target_dir" 2>/dev/null && pwd)
  if [ -z "$absolute_target" ]; then
    absolute_target="$target_dir"
  fi

  if [ -z "$(find . -maxdepth 1 -type f -print -quit)" ]; then
    cbc_style_message "$CATPPUCCIN_YELLOW" "No files found in the current directory to sort."
    return 0
  fi

  if [ "$mode" = "ext" ]; then
    if ! smartsort_choose_extensions; then
      cbc_style_message "$CATPPUCCIN_YELLOW" "No files with extensions found for sorting."
      return 0
    fi
  fi

  if [ "$mode" = "time" ]; then
    smartsort_prompt_time_grouping
  fi

  if [ "$mode" = "size" ]; then
    smartsort_prompt_size_thresholds
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
  *)
    summary_details=""
    ;;
  esac

  local -a summary_lines=(
    "  Sorting Mode    : $mode"
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

  if ! smartsort_prepare_run_state; then
    return 1
  fi

  if [ "$target_dir" != "." ]; then
    if ! smartsort_ensure_directory "$target_dir"; then
      smartsort_discard_temp_state
      return 1
    fi
  fi

  absolute_target=$(cd "$target_dir" 2>/dev/null && pwd)
  if [ -z "$absolute_target" ]; then
    absolute_target="$target_dir"
  fi

  sort_by_extension() {
    local include_all=1
    local path=""
    local operation_failed=0

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
      if ! smartsort_move_file "$path" "$target_subdir"; then
        operation_failed=1
      fi
    done < <(find . -maxdepth 1 -type f -print)

    if [ "$operation_failed" -ne 0 ]; then
      cbc_style_message "$CATPPUCCIN_RED" "Some files could not be sorted by extension."
      return 1
    fi

    cbc_style_message "$CATPPUCCIN_GREEN" "Files have been sorted into extension-based directories."
  }

  sort_by_alpha() {
    cbc_style_message "$CATPPUCCIN_BLUE" "Sorting files alphabetically by the first letter..."
    local operation_failed=0

    while IFS= read -r path; do
      [ -f "$path" ] || continue
      local base letter target_subdir
      base=${path#./}
      letter=$(printf '%s' "$base" | cut -c1 | tr '[:upper:]' '[:lower:]')
      if [ -z "$letter" ]; then
        letter="misc"
      fi
      target_subdir="$target_dir/$letter"
      if ! smartsort_move_file "$path" "$target_subdir"; then
        operation_failed=1
      fi
    done < <(find . -maxdepth 1 -type f -print)

    if [ "$operation_failed" -ne 0 ]; then
      cbc_style_message "$CATPPUCCIN_RED" "Some files could not be sorted alphabetically."
      return 1
    fi

    cbc_style_message "$CATPPUCCIN_GREEN" "Files have been sorted into directories based on their first letter."
  }

  sort_by_time() {
    local date_format="%Y-%m"
    local operation_failed=0
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
      if ! smartsort_move_file "$path" "$target_subdir"; then
        operation_failed=1
      fi
    done < <(find . -maxdepth 1 -type f -print)

    if [ "$operation_failed" -ne 0 ]; then
      cbc_style_message "$CATPPUCCIN_RED" "Some files could not be sorted by time."
      return 1
    fi

    cbc_style_message "$CATPPUCCIN_GREEN" "Files have been sorted into date-based directories."
  }

  sort_by_size() {
    cbc_style_message "$CATPPUCCIN_BLUE" "Sorting files by size into categories..."
    local operation_failed=0

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
      if ! smartsort_move_file "$path" "$target_subdir"; then
        operation_failed=1
      fi
    done < <(find . -maxdepth 1 -type f -print)

    if [ "$operation_failed" -ne 0 ]; then
      cbc_style_message "$CATPPUCCIN_RED" "Some files could not be sorted by size."
      return 1
    fi

    cbc_style_message "$CATPPUCCIN_GREEN" "Files have been sorted into size-based directories."
  }

  local sorting_status=0
  case "$mode" in
  ext) sort_by_extension || sorting_status=1 ;;
  alpha) sort_by_alpha || sorting_status=1 ;;
  time) sort_by_time || sorting_status=1 ;;
  size) sort_by_size || sorting_status=1 ;;
  esac

  if [ "$sorting_status" -ne 0 ]; then
    smartsort_discard_temp_state
    cbc_style_message "$CATPPUCCIN_RED" "Sorting operation finished with errors."
    return 1
  fi

  if ! smartsort_finalize_run_state; then
    smartsort_discard_temp_state
    cbc_style_message "$CATPPUCCIN_RED" "Sorting completed, but undo data could not be saved."
    return 1
  fi

  cbc_style_message "$CATPPUCCIN_GREEN" "Sorting operation completed successfully."
  cbc_style_message "$CATPPUCCIN_SUBTEXT" "You can revert this run with: smartsort undo"
}
