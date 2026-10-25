#!/usr/bin/env bash
# Claude Code status line command
# Config: $HOME/.claude/statusline-config.json
# Reads JSON from stdin (provided by Claude Code), outputs formatted status lines.
#
# Performance: all values extracted from stdin in a single jq call; config
# elements iterated in pure bash using pre-serialised flat arrays — no jq
# spawned inside the render loop.

CONFIG="$HOME/.claude/statusline-config.json"

if [ ! -f "$CONFIG" ]; then
  echo "[statusline] config not found: $CONFIG" >&2
  exit 1
fi

INPUT=$(cat)
NOW=$(date +%s)

# ---------------------------------------------------------------------------
# 1. Extract all available values from stdin in one jq pass
#    Output: KEY=VALUE lines (tab-separated, empty string when absent)
# ---------------------------------------------------------------------------

declare -A V
while IFS=$'\t' read -r k v; do
  V["$k"]="$v"
done < <(echo "$INPUT" | jq -r '
  def s(p): (p // "") | tostring;
  def pct(p): if (p | type) == "number" then (p | round | tostring) else "" end;
  [
    "session_id",         (s(.session_id)),
    "session_name",       (s(.session_name)),
    "transcript_path",    (s(.transcript_path)),
    "model_display",      (s(.model.display_name)),
    "model_id",           (s(.model.id)),
    "output_style",       (if .output_style.name == "default" then "" else s(.output_style.name) end),
    "version",            (s(.version)),
    "cwd",                (s(.workspace.current_dir)),
    "project_dir",        (s(.workspace.project_dir)),
    "git_worktree",       (s(.workspace.git_worktree)),
    "added_dirs",         ((.workspace.added_dirs // []) | join(":")),
    "context_used_pct",   (pct(.context_window.used_percentage)),
    "context_rem_pct",    (pct(.context_window.remaining_percentage)),
    "context_window_size",(s(.context_window.context_window_size)),
    "tokens_input",       (s(.context_window.total_input_tokens)),
    "tokens_output",      (s(.context_window.total_output_tokens)),
    "cache_creation",     (s(.context_window.current_usage.cache_creation_input_tokens)),
    "cache_read",         (s(.context_window.current_usage.cache_read_input_tokens)),
    "rate_5h_pct",        (pct(.rate_limits.five_hour.used_percentage)),
    "rate_5h_resets",     (if .rate_limits.five_hour.resets_at then (.rate_limits.five_hour.resets_at | tostring) else "" end),
    "rate_7d_pct",        (pct(.rate_limits.seven_day.used_percentage)),
    "rate_7d_resets",     (if .rate_limits.seven_day.resets_at then (.rate_limits.seven_day.resets_at | tostring) else "" end),
    "vim_mode",           (s(.vim.mode)),
    "agent_name",         (s(.agent.name)),
    "agent_type",         (s(.agent.type)),
    "worktree_name",      (s(.worktree.name)),
    "worktree_path",      (s(.worktree.path)),
    "worktree_branch",    (s(.worktree.branch)),
    "worktree_orig_cwd",  (s(.worktree.original_cwd)),
    "worktree_orig_branch",(s(.worktree.original_branch))
  ]
  as $arr
  | range(0; ($arr|length); 2)
  | "\($arr[.])\t\($arr[.+1])"
' | tr -d '\r')

# Map config "key" field to extracted value keys
get_value() {
  local key="$1"
  case "$key" in
    vim_mode)             echo "${V[vim_mode]}" ;;
    agent_name)           echo "${V[agent_name]}" ;;
    agent_type)           echo "${V[agent_type]}" ;;
    worktree_name)        echo "${V[worktree_name]}" ;;
    worktree_path)        echo "${V[worktree_path]}" ;;
    worktree_branch)      echo "${V[worktree_branch]}" ;;
    worktree_orig_cwd)    echo "${V[worktree_orig_cwd]}" ;;
    worktree_orig_branch) echo "${V[worktree_orig_branch]}" ;;
    session_id)           echo "${V[session_id]}" ;;
    session_name)         echo "${V[session_name]}" ;;
    transcript_path)      echo "${V[transcript_path]}" ;;
    model)                echo "${V[model_display]}" ;;
    model_id)             echo "${V[model_id]}" ;;
    output_style)         echo "${V[output_style]}" ;;
    version)              echo "${V[version]}" ;;
    cwd)                  echo "${V[cwd]}" ;;
    project_dir)          echo "${V[project_dir]}" ;;
    git_worktree)         echo "${V[git_worktree]}" ;;
    added_dirs)           echo "${V[added_dirs]}" ;;
    context_used_pct)     echo "${V[context_used_pct]}" ;;
    context_remaining_pct) echo "${V[context_rem_pct]}" ;;
    context_window_size)  echo "${V[context_window_size]}" ;;
    context_tokens_input) echo "${V[tokens_input]}" ;;
    context_tokens_output) echo "${V[tokens_output]}" ;;
    context_cache_creation) echo "${V[cache_creation]}" ;;
    context_cache_read)   echo "${V[cache_read]}" ;;
    rate_limit_5h)        echo "${V[rate_5h_pct]}" ;;
    rate_limit_5h_resets) echo "${V[rate_5h_resets]}" ;;
    rate_limit_7d)        echo "${V[rate_7d_pct]}" ;;
    rate_limit_7d_resets) echo "${V[rate_7d_resets]}" ;;
    *)                    echo "" ;;
  esac
}

# ---------------------------------------------------------------------------
# 2. Read config in one jq pass — produce flat tab-delimited element records
#    Format per line: LINE_IDX\tELEM_IDX\tENABLED\tKEY\tICON\tLABEL\tFORMAT\tCOLOR_OR_THRESHOLDS\tRESET
#    color_thresholds serialised as JSON on a single line
# ---------------------------------------------------------------------------

GLOBAL_ICONS_ENABLED=""
GLOBAL_COLORS_ENABLED=""
GLOBAL_SEPARATOR=""
GLOBAL_LINE_SEP=""

{
  read -r GLOBAL_ICONS_ENABLED
  read -r GLOBAL_COLORS_ENABLED
  IFS= read -r GLOBAL_SEPARATOR
  IFS= read -r _LINE_SEP_B64
} < <(jq -r '
  (.global.icons_enabled | tostring),
  (.global.colors_enabled | tostring),
  .global.separator,
  (.global.line_separator | @base64)
' "$CONFIG" | tr -d '\r')
_LINE_SEP_WITH_X=$(printf '%s' "$_LINE_SEP_B64" | base64 -d 2>/dev/null; printf 'X')
GLOBAL_LINE_SEP="${_LINE_SEP_WITH_X%X}"

# Read all element records.
# For color_thresholds, we pre-expand into 4 fields:
#   THRESH_C0|THRESH_B0|THRESH_C1|THRESH_B1|... (pipe-delimited pairs, max 8 thresholds)
# Static color is stored as-is. The bash render loop resolves thresholds with no jq.
mapfile -t ELEM_RECORDS < <(
  jq -r '
    def encode_color(elem):
      if elem | has("color_thresholds") then
        # Encode as "THRESH:<c0>|<b0>|<c1>|<b1>|..."
        "THRESH:" + (
          elem.color_thresholds
          | map("\(.color)|\(.below)")
          | join("|")
        )
      else
        (elem.color // "")
      end;
    .lines | to_entries[] |
    .key as $li |
    .value |
    if .enabled then
      .elements | to_entries[] |
      .key as $ei |
      .value |
      if .enabled then
        [
          ($li | tostring),
          ($ei | tostring),
          "true",
          .key,
          (.icon // ""),
          (.label // ""),
          (.format // "value"),
          encode_color(.),
          (.reset // "")
        ] | join("\u0001")
      else
        empty
      end
    else
      empty
    end
  ' "$CONFIG" | tr -d '\r'
)

# ---------------------------------------------------------------------------
# 3. Resolve color — pure bash, no jq
#    For static: returns the color as-is.
#    For thresholds (prefix "THRESH:"): iterates pairs to find the right color.
# ---------------------------------------------------------------------------

resolve_color() {
  local color_field="$1"
  local val="$2"

  if [[ "$color_field" == THRESH:* ]]; then
    local thresholds="${color_field#THRESH:}"
    local num_val
    num_val=$(printf "%.0f" "$val" 2>/dev/null) || num_val="0"
    # Parse pipe-delimited pairs: color|below|color|below|...
    IFS='|' read -ra parts <<< "$thresholds"
    local i=0
    while (( i + 1 < ${#parts[@]} )); do
      local t_color="${parts[$i]}"
      local t_below="${parts[$((i+1))]}"
      if (( num_val < t_below )); then
        echo "$t_color"
        return
      fi
      (( i += 2 ))
    done
    # Exceeded all thresholds: use last color
    echo "${parts[$((${#parts[@]} - 2))]}"
    return
  fi

  echo "$color_field"
}

# ---------------------------------------------------------------------------
# 4. Render loop — pure bash, no jq per element
# ---------------------------------------------------------------------------

declare -A LINE_PARTS
declare -a LINE_ORDER

prev_li=-1

for record in "${ELEM_RECORDS[@]}"; do
  IFS=$'\x01' read -r li ei enabled key icon label format color_field reset <<< "$record"

  val=$(get_value "$key")
  [[ -z "$val" ]] && continue

  # Format value
  display_val="$val"
  if [[ "$format" == "percent" ]]; then
    display_val="${val}%"
  elif [[ "$format" == "compact_number" ]]; then
    num_val=$(printf "%.0f" "$val" 2>/dev/null) || num_val="$val"
    if (( num_val >= 1000 )); then
      display_val=$(awk "BEGIN { printf \"%.1fk\", $num_val / 1000 }")
    else
      display_val="$num_val"
    fi
  elif [[ "$format" == "progress_bar" ]]; then
    num_val=$(printf "%.0f" "$val" 2>/dev/null) || num_val="0"
    bar_len=10
    filled=$(( num_val * bar_len / 100 ))
    (( filled > bar_len )) && filled=$bar_len
    (( filled < 0 )) && filled=0
    empty=$(( bar_len - filled ))
    display_val=""
    for (( i=0; i<filled; i++ )); do display_val+="█"; done
    for (( i=0; i<empty; i++ )); do display_val+="░"; done
  elif [[ "$format" == "countdown" ]]; then
    diff=$(( val - NOW ))
    if (( diff <= 0 )); then
      display_val="0m"
    else
      days=$(( diff / 86400 ))
      hours=$(( (diff % 86400) / 3600 ))
      mins=$(( (diff % 3600) / 60 ))
      if (( days > 0 )); then
        display_val="${days}j${hours}h"
      elif (( hours > 0 )); then
        display_val="${hours}h$(printf '%02d' $mins)"
      else
        display_val="${mins}m"
      fi
    fi
  fi

  # Resolve color
  color=""
  if [[ "$GLOBAL_COLORS_ENABLED" == "true" && -n "$color_field" ]]; then
    color=$(resolve_color "$color_field" "$val")
  fi

  # Build rendered part
  part=""
  [[ -n "$color" ]] && part="${color}"
  if [[ "$GLOBAL_ICONS_ENABLED" == "true" && -n "$icon" ]]; then
    part="${part}${icon} "
  fi
  [[ -n "$label" ]] && part="${part}${label}:"
  part="${part}${display_val}"
  [[ -n "$color" ]] && part="${part}${reset}"

  # Accumulate per line
  if [[ -z "${LINE_PARTS[$li]+x}" ]]; then
    LINE_ORDER+=("$li")
    LINE_PARTS[$li]="$part"
  else
    LINE_PARTS[$li]="${LINE_PARTS[$li]}${GLOBAL_SEPARATOR}${part}"
  fi
done

# ---------------------------------------------------------------------------
# 5. Assemble final output
# ---------------------------------------------------------------------------

output=""
for li in "${LINE_ORDER[@]}"; do
  line_str="${LINE_PARTS[$li]}"
  [[ -z "$line_str" ]] && continue
  if [[ -z "$output" ]]; then
    output="$line_str"
  else
    output="${output}${GLOBAL_LINE_SEP}${line_str}"
  fi
done

# Strip trailing $ or >
output=$(printf "%s" "$output" | sed 's/[>$][[:space:]]*$//')

printf "%s" "$output"
