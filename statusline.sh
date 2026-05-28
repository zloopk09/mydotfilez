#!/bin/bash
# Claude Code Status Line - Three-line display with Dracula theme
# Line 1: Model | Effort | Context Bar | Cost
# Line 2: Dir | Git Branch | Worktree
# Line 3: Token In | Token Out | Cache Hit
# Style: Inspired by webup/skills-cc

# ── Dracula Theme Colors ────────────────────────────────────────────
readonly RST='\033[0m'
readonly C_MODEL='\033[38;2;189;147;249m'      # purple
readonly C_CTX_OK='\033[38;2;80;250;123m'      # green (>50% remaining)
readonly C_CTX_WARN='\033[38;2;241;250;140m'   # yellow (20-50%)
readonly C_CTX_LOW='\033[38;2;255;85;85m'      # red (<20%)
readonly C_BAR_EMPTY='\033[38;2;68;71;90m'     # comment gray
readonly C_DIR='\033[38;2;139;233;253m'         # cyan
readonly C_GIT='\033[38;2;80;250;123m'          # green (clean)
readonly C_GIT_DIRTY='\033[38;2;255;184;108m'  # orange (dirty)
readonly C_WORKTREE='\033[38;2;255;121;198m'   # pink
readonly C_COST='\033[38;2;255;215;0m'         # gold
readonly C_META='\033[38;2;98;114;164m'         # dim gray (meta info)
readonly C_EFFORT_MAX='\033[1;38;2;255;85;85m'    # bold red
readonly C_EFFORT_XHIGH='\033[38;2;255;85;85m'    # red
readonly C_EFFORT_HIGH='\033[1;38;2;80;250;123m'  # bold green
readonly C_EFFORT_MED='\033[38;2;80;250;123m'     # green
readonly C_EFFORT_LOW='\033[38;2;241;250;140m'    # yellow
readonly C_EFFORT_OFF='\033[2;38;2;98;114;164m'   # dim
readonly C_SEP='\033[38;2;98;114;164m'         # comment bright
readonly SEP=' | '

# ── Icons ───────────────────────────────────────────────────────────
readonly I_MODEL='◈'
readonly I_DIR='⌂'
readonly I_GIT='⎇'
readonly I_WORKTREE='⊕'
readonly I_COST='$'
readonly I_EFFORT='↯'
readonly I_IN='⇣'
readonly I_OUT='⇡'
readonly I_HIT='↻'

# Bar characters
readonly BAR_FILLED='█'
readonly BAR_EMPTY='░'
readonly BAR_WIDTH=20

# ── Token formatter ──────────────────────────────────────────────────
# Converts 12345 -> 12.3K, 1234567 -> 1.2M (uppercase like ccstatusline)
format_tokens() {
    local n="$1"
    if [ -z "$n" ] || [ "$n" -eq 0 ]; then
        echo "0"
    elif [ "$n" -ge 1000000 ]; then
        awk -v v="$n" 'BEGIN { printf "%.1fM", v/1000000 }'
    elif [ "$n" -ge 1000 ]; then
        awk -v v="$n" 'BEGIN { printf "%.1fK", v/1000 }'
    else
        echo "$n"
    fi
}

# ── Read JSON from stdin ─────────────────────────────────────────────
input=$(cat)

# Single jq call to extract all needed fields (performance optimization)
# Use TSV format and cut for reliable field extraction (bash read skips empty fields)
tsv=$(echo "$input" | jq -r '[
    .model.display_name // .model.id // "Claude",
    .context_window.used_percentage // "",
    .context_window.total_input_tokens // 0,
    .cost.total_cost_usd // 0,
    .workspace.current_dir // .cwd // "",
    .worktree.name // "",
    .context_window.total_output_tokens // 0,
    .context_window.current_usage.cache_read_input_tokens // 0,
    .context_window.current_usage.input_tokens // 0,
    .context_window.context_window_size // 0,
    .transcript_path // "",
    .effort.level // ""
] | @tsv')

model=$(echo "$tsv" | cut -f1)
used_raw=$(echo "$tsv" | cut -f2)
total_in=$(echo "$tsv" | cut -f3)
cost_usd=$(echo "$tsv" | cut -f4)
cwd=$(echo "$tsv" | cut -f5)
worktree_name=$(echo "$tsv" | cut -f6)
out_tokens=$(echo "$tsv" | cut -f7)
cache_read=$(echo "$tsv" | cut -f8)
current_in=$(echo "$tsv" | cut -f9)
ctx_size=$(echo "$tsv" | cut -f10)
transcript_path=$(echo "$tsv" | cut -f11)
effort_status=$(echo "$tsv" | cut -f12)

# ── Line 1: Model, Effort, Context Bar ────────────────────────────────

# Model (already extracted above)

# Effort level - multi-source fallback (like ccstatusline):
# 1. statusJSON.effort.level (most reliable)
# 2. Transcript (last effort command)
# 3. Settings file (fallback)
effort=""
if [ -n "$effort_status" ]; then
    effort="$effort_status"
elif [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    # Search transcript for effort setting (reverse order, last match wins)
    effort=$(tail -r "$transcript_path" 2>/dev/null | grep -m1 -oE 'Set effort level to [a-zA-Z0-9-]+' | sed 's/Set effort level to //' 2>/dev/null)
fi
# Fallback to settings if still empty
if [ -z "$effort" ]; then
    for f in "$HOME/.claude/settings.local.json" "$HOME/.claude/settings.json"; do
        if [ -z "$effort" ] && [ -f "$f" ]; then
            effort=$(jq -r '.effortLevel // empty' "$f" 2>/dev/null)
        fi
    done
fi

# Context - use used_percentage directly from API (real-time)
bar=""

if [ -n "$used_raw" ] && [ "$used_raw" != "0" -o "$total_in" != "0" ]; then
    used_int=$(printf "%.0f" "$used_raw")
    used="$used_int"
elif [ "$total_in" -eq 0 ] && [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    # stdin shows zero but transcript exists - post-/compact glitch fallback
    compact_info=$(tail -r "$transcript_path" 2>/dev/null | grep -m1 '"type":"system".*"subtype":"compact_boundary"' | jq -c '{post: .compactMetadata.postTokens, size: .compactMetadata.contextWindowSize}' 2>/dev/null)
    if [ -n "$compact_info" ]; then
        post_tokens=$(echo "$compact_info" | jq -r '.post // empty')
        compact_ctx_size=$(echo "$compact_info" | jq -r '.size // empty')
        if [ -n "$post_tokens" ] && [ "$post_tokens" -gt 0 ]; then
            if [ -n "$compact_ctx_size" ] && [ "$compact_ctx_size" -gt 0 ]; then
                used=$((post_tokens * 100 / compact_ctx_size))
            elif [ "$ctx_size" -gt 0 ]; then
                used=$((post_tokens * 100 / ctx_size))
            else
                used=$((post_tokens * 100 / 200000))
            fi
        fi
    fi
fi

if [ -n "$used" ] && [ "$used" != "0" ]; then
    # Ensure integer (jq may return float like 7.5)
    used=$(printf "%.0f" "$used")
    remaining=$((100 - used))
    filled=$((used * BAR_WIDTH / 100))
    empty=$((BAR_WIDTH - filled))

    # Color based on remaining capacity
    if [ "$remaining" -lt 15 ]; then
        ctx_color="$C_CTX_LOW"
    elif [ "$remaining" -lt 40 ]; then
        ctx_color="$C_CTX_WARN"
    else
        ctx_color="$C_CTX_OK"
    fi

    # Build bar: ████████████████░░░░░░░░░░░░░░ 62%
    for ((i=0; i<filled; i++)); do bar+="${ctx_color}${BAR_FILLED}${RST}"; done
    for ((i=0; i<empty; i++)); do bar+="${C_BAR_EMPTY}${BAR_EMPTY}${RST}"; done
    bar+=" ${ctx_color}${used}%${RST}"
fi

# Assemble Line 1
line1="${C_MODEL}${I_MODEL} ${model}${RST}"

if [ -n "$effort" ]; then
    case "$effort" in
        max|MAX|Max)                                  effort_color="$C_EFFORT_MAX" ;;
        xhigh|XHIGH|XHigh)                            effort_color="$C_EFFORT_XHIGH" ;;
        high|High|HIGH)                               effort_color="$C_EFFORT_HIGH" ;;
        medium|Medium|MEDIUM)                         effort_color="$C_EFFORT_MED" ;;
        low|Low|LOW|xlow|XLow|XLOW|minimal|Minimal)   effort_color="$C_EFFORT_LOW" ;;
        *)                                            effort_color="$C_EFFORT_OFF" ;;
    esac
    line1="${line1}${C_SEP}${SEP}${RST}${effort_color}${I_EFFORT} ${effort}${RST}"
fi

[ -n "$bar" ] && line1="${line1}${C_SEP}${SEP}${RST}${bar}"

# Cost on line 1 (already extracted above)
cost_formatted=$(awk -v v="$cost_usd" 'BEGIN { printf "%.2f", v+0 }')
line1="${line1}${C_SEP}${SEP}${RST}${C_COST}${I_COST}${cost_formatted}${RST}"

# ── Line 2: Dir, Git, Worktree ───────────────────────────────────────

# cwd already extracted above
if [ -n "$cwd" ]; then
    cwd="${cwd/#$HOME/~}"
fi

# Git branch with dirty/conflict detection
git_branch=""
git_status="clean"  # clean | dirty | conflict
if [ -n "$cwd" ]; then
    resolved_cwd="${cwd/#\~/$HOME}"
    if git -C "$resolved_cwd" --no-optional-locks rev-parse --git-dir >/dev/null 2>&1; then
        git_branch=$(git -C "$resolved_cwd" --no-optional-locks branch --show-current 2>/dev/null)
        [ -z "$git_branch" ] && git_branch=$(git -C "$resolved_cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
        if [ -n "$git_branch" ]; then
            # Check for conflicts first (highest priority)
            if git -C "$resolved_cwd" --no-optional-locks diff --name-only --diff-filter=U 2>/dev/null | grep -q .; then
                git_status="conflict"
            elif ! git -C "$resolved_cwd" --no-optional-locks diff --quiet 2>/dev/null || \
               ! git -C "$resolved_cwd" --no-optional-locks diff --cached --quiet 2>/dev/null; then
                git_status="dirty"
            fi
        fi
    fi
fi

# Worktree detection (worktree_name already extracted above)
is_worktree=0
if [ -n "$worktree_name" ]; then
    is_worktree=1
elif [ -n "$resolved_cwd" ] && git -C "$resolved_cwd" --no-optional-locks rev-parse --git-dir >/dev/null 2>&1; then
    _gd=$(git -C "$resolved_cwd" --no-optional-locks rev-parse --git-dir 2>/dev/null)
    _gcd=$(git -C "$resolved_cwd" --no-optional-locks rev-parse --git-common-dir 2>/dev/null)
    # Resolve to absolute paths for comparison (git-common-dir may return relative path)
    if [ -n "$_gd" ]; then
        _gd=$(cd "$resolved_cwd" 2>/dev/null && cd "$_gd" 2>/dev/null && pwd)
    fi
    if [ -n "$_gcd" ]; then
        _gcd=$(cd "$resolved_cwd" 2>/dev/null && cd "$_gcd" 2>/dev/null && pwd)
    fi
    if [ -n "$_gd" ] && [ -n "$_gcd" ] && [ "$_gd" != "$_gcd" ]; then
        is_worktree=1
        if [ -z "$worktree_name" ]; then
            _parent=$(dirname "$resolved_cwd")
            worktree_name=$(basename "$_parent")
        fi
    fi
fi

# Assemble Line 2
line2="${C_DIR}${I_DIR} ${cwd}${RST}"
if [ -n "$git_branch" ]; then
    case "$git_status" in
        conflict) line2="${line2}${C_SEP}${SEP}${RST}${C_EFFORT_XHIGH}${I_GIT} ${git_branch}${RST}" ;;
        dirty)    line2="${line2}${C_SEP}${SEP}${RST}${C_GIT_DIRTY}${I_GIT} ${git_branch}${RST}" ;;
        *)        line2="${line2}${C_SEP}${SEP}${RST}${C_GIT}${I_GIT} ${git_branch}${RST}" ;;
    esac
fi
if [ "$is_worktree" -eq 1 ] && [ -n "$worktree_name" ]; then
    line2="${line2}${C_SEP}${SEP}${RST}\033[1m${C_WORKTREE}${I_WORKTREE} worktree:${worktree_name}${RST}"
fi

# ── Line 3: Token In | Token Out | Cache Hit ─────────────────────────

# Tokens already extracted above

# Cache hit % = cache_read / (cache_read + current_in) * 100
hit_pct="0"
total_for_hit=$((cache_read + current_in))
if [ "$total_for_hit" -gt 0 ]; then
    hit_pct=$(awk -v read="$cache_read" -v total="$total_for_hit" 'BEGIN { printf "%.1f", (read/total)*100 }')
fi

in_fmt=$(format_tokens "$total_in")
out_fmt=$(format_tokens "$out_tokens")

line3="${C_META}${I_IN} ${in_fmt}${RST}"
line3="${line3}${C_SEP}${SEP}${RST}${C_META}${I_OUT} ${out_fmt}${RST}"
line3="${line3}${C_SEP}${SEP}${RST}${C_META}${I_HIT} ${hit_pct}%${RST}"

# ── Output ───────────────────────────────────────────────────────────
printf "%b\n%b\n%b" "$line1" "$line2" "$line3"
