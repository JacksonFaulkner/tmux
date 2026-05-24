#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/git-branch.sh"

TARGET=$(strip_git_branch_info "$1")
session_name=$(echo "$TARGET" | cut -d: -f1)
window_index=$(echo "$TARGET" | cut -d: -f2 | cut -d' ' -f1)

[[ -z "$session_name" || -z "$window_index" ]] && { echo "No window selected."; exit 0; }

window_target="${session_name}:${window_index}"
history_file="$HOME/.claude/history.jsonl"
[[ ! -f "$history_file" ]] && { echo "No claude history found."; exit 0; }

pane_path=$(tmux display-message -t "$window_target" -p "#{pane_current_path}" 2>/dev/null)
[[ -z "$pane_path" ]] && { echo "Cannot determine path for ${window_target}."; exit 0; }

export CLAUDE_PANE_PATH="$pane_path"
export CLAUDE_HISTORY_FILE="$history_file"
export CLAUDE_PROJECTS_DIR="$HOME/.claude/projects"
export CLAUDE_SESSIONS_DIR="$HOME/.claude/sessions"
export CLAUDE_TODOS_DIR="$HOME/.claude/todos"

uvx python << 'EOF'
import json, os, time, textwrap, glob

RESET  = "\033[0m"
BOLD   = "\033[1m"
DIM    = "\033[2m"
BLUE   = "\033[38;5;33m"
ACOLOR = "\033[38;5;252m"
GRAY   = "\033[38;5;240m"
GREEN  = "\033[38;5;71m"
YELLOW = "\033[38;5;221m"
BORDER = "\033[38;5;238m"
BRED   = "\033[38;5;203m"

WIDTH      = 62
BOX_W_A    = 54
BOX_W_U    = 44
INNER_A    = BOX_W_A - 4
INNER_U    = BOX_W_U - 4
ASST_LINES = 5
MSG_COUNT  = 8

pane_path    = os.environ["CLAUDE_PANE_PATH"]
history_file = os.environ["CLAUDE_HISTORY_FILE"]
projects_dir = os.environ["CLAUDE_PROJECTS_DIR"]
sessions_dir = os.environ["CLAUDE_SESSIONS_DIR"]
todos_dir    = os.environ["CLAUDE_TODOS_DIR"]
recaps_dir   = os.path.expanduser("~/.claude/recaps")
now          = time.time()
home         = os.path.expanduser("~")

def rel_time(ts_ms):
    age = now - ts_ms / 1000
    if age < 60:      return "just now"
    if age < 3600:    return f"{int(age//60)}m ago"
    if age < 86400:   return f"{int(age//3600)}h ago"
    if age < 604800:  return f"{int(age//86400)}d ago"
    return time.strftime("%b %d", time.localtime(ts_ms / 1000))

def short_path(p):
    p = p.replace(home, "~")
    parts = p.split("/")
    return "/".join(parts[-2:]) if len(parts) > 2 else p

def render_divider(label, vis_len):
    pad = (WIDTH - vis_len) // 2
    right = WIDTH - pad - vis_len
    print(f"{GRAY}{'─'*pad}{label}{'─'*max(0,right)}{RESET}")

def render_box_assistant(text):
    label = "─ Claude "
    lines = textwrap.wrap(text.strip(), INNER_A)[:ASST_LINES]
    trunc = len(textwrap.wrap(text.strip(), INNER_A)) > ASST_LINES
    if trunc and lines: lines[-1] = lines[-1][:INNER_A-1] + "…"
    print(f"{BORDER}╭{label}{'─'*(BOX_W_A-len(label)-2)}╮{RESET}")
    for ln in lines:
        print(f"{BORDER}│{RESET} {ACOLOR}{ln:<{INNER_A}}{RESET} {BORDER}│{RESET}")
    print(f"{BORDER}╰{'─'*(BOX_W_A-2)}╯{RESET}")

def render_box_user(text):
    label = " You ─"
    lines = textwrap.wrap(text.strip(), INNER_U) or [text.strip()[:INNER_U]]
    pad   = WIDTH - BOX_W_U
    print(f"{' '*pad}{BORDER}╭{'─'*(BOX_W_U-len(label)-2)}{label}╮{RESET}")
    for ln in lines:
        print(f"{' '*pad}{BORDER}│{RESET} {BLUE}{ln:<{INNER_U}}{RESET} {BORDER}│{RESET}")
    print(f"{' '*pad}{BORDER}╰{'─'*(BOX_W_U-2)}╯{RESET}")

def render_todos(todos):
    if not todos: return
    icons = {'completed': f"{GREEN}✓{RESET}", 'in_progress': f"{YELLOW}●{RESET}", 'pending': f"{GRAY}○{RESET}"}
    for status, content in todos:
        icon = icons.get(status, f"{GRAY}○{RESET}")
        t = content if len(content) <= WIDTH-5 else content[:WIDTH-6]+"…"
        dim = DIM if status == 'completed' else ''
        print(f"  {icon} {dim}{GRAY}{t}{RESET}")

def render_recap(sid):
    path = f"{recaps_dir}/{sid}.txt"
    if not os.path.exists(path): return
    text = open(path).read().strip()
    if not text: return
    lines = textwrap.wrap(text, WIDTH - 4)
    print(f"{GRAY}╌╌ recap {'╌'*(WIDTH-9)}{RESET}")
    for ln in lines:
        print(f"  {ACOLOR}{ln}{RESET}")
    print()

def render_files(written, read):
    if not written and not read: return
    seen = set()
    for path in written:
        sp = short_path(path)
        if sp not in seen:
            seen.add(sp)
            print(f"  {YELLOW}∆{RESET} {GRAY}{sp}{RESET}")
    extra_read = [p for p in read if short_path(p) not in seen]
    if extra_read:
        for path in list(dict.fromkeys(extra_read))[:3]:
            sp = short_path(path)
            print(f"  {GRAY}· {sp}{RESET}")

# ── live sessions ──────────────────────────────────────────
live_sessions = set()
if os.path.isdir(sessions_dir):
    for f in glob.glob(f"{sessions_dir}/*.json"):
        try:
            d = json.loads(open(f).read())
            cwd = d.get('cwd', '')
            if cwd == pane_path or cwd.startswith(pane_path) or pane_path.startswith(cwd):
                live_sessions.add(d['sessionId'])
        except Exception: pass

# ── user messages from history.jsonl ──────────────────────
sessions_user = {}
with open(history_file) as f:
    for line in f:
        try: obj = json.loads(line)
        except: continue
        proj = obj.get('project', '')
        if not (proj == pane_path or proj.startswith(pane_path) or pane_path.startswith(proj)):
            continue
        sid  = obj.get('sessionId')
        text = obj.get('display', '').strip()
        ts   = obj.get('timestamp', 0)
        if not sid or not text: continue
        sessions_user.setdefault(sid, []).append((ts, text))

if not sessions_user:
    print(f"{GRAY}No conversation history for this project.{RESET}")
    raise SystemExit(0)

# ── find session transcript files ──────────────────────────
candidate_dirs = [projects_dir+'/'+d for d in os.listdir(projects_dir)
                  if os.path.isdir(projects_dir+'/'+d)]
session_files = {}
for sid in sessions_user:
    for d in candidate_dirs:
        path = f"{d}/{sid}.jsonl"
        if os.path.exists(path): session_files[sid] = path; break

sorted_sessions = sorted(sessions_user.keys(),
                         key=lambda s: max(ts for ts,_ in sessions_user[s]),
                         reverse=True)[:3]

for sid in sorted_sessions:
    user_msgs = sorted(sessions_user[sid], key=lambda x: x[0])
    last_ts   = max(ts for ts,_ in user_msgs)
    is_live   = sid in live_sessions

    # session header
    live_tag = f" {GREEN}● live{RESET}{GRAY}" if is_live else ""
    label    = f" {rel_time(last_ts)}{live_tag} "
    vis_len  = len(f" {rel_time(last_ts)}  ") + (6 if is_live else 0)
    print()
    render_divider(label, vis_len)
    print()

    # ── parse transcript ───────────────────────────────────
    asst_msgs    = []   # (ts, text)
    files_written = []
    files_read    = []
    todos_raw     = []

    if sid in session_files:
        with open(session_files[sid]) as f:
            for line in f:
                try: d = json.loads(line)
                except: continue

                if d['type'] == 'assistant':
                    ts = d.get('timestamp', 0)
                    if isinstance(ts, str):
                        try: ts = int(ts)
                        except: ts = 0
                    for block in d.get('message', {}).get('content', []):
                        if not isinstance(block, dict): continue
                        if block.get('type') == 'text':
                            t = block['text'].strip()
                            if t: asst_msgs.append((ts, t))
                            break
                        if block.get('type') == 'tool_use':
                            name = block.get('name', '')
                            inp  = block.get('input', {})
                            path = inp.get('file_path') or inp.get('path', '')
                            if path:
                                if name in ('Write', 'Edit'): files_written.append(path)
                                elif name == 'Read':           files_read.append(path)

    # ── todos ──────────────────────────────────────────────
    if os.path.isdir(todos_dir):
        for f in glob.glob(f"{todos_dir}/{sid}-agent-*.json"):
            try:
                for item in json.loads(open(f).read()):
                    todos_raw.append((item.get('status','pending'), item.get('content','')))
            except: pass

    render_recap(sid)

    render_todos(todos_raw)
    if todos_raw: print()

    render_files(list(dict.fromkeys(files_written)), list(dict.fromkeys(files_read)))
    if files_written or files_read: print()

    # ── conversation ───────────────────────────────────────
    all_msgs = [(ts, 'user', t) for ts,t in user_msgs] + \
               [(ts, 'assistant', t) for ts,t in asst_msgs]
    all_msgs.sort(key=lambda x: x[0])
    all_msgs = all_msgs[-MSG_COUNT:]

    for _, role, text in all_msgs:
        if role == 'user': render_box_user(text)
        else:              render_box_assistant(text)
        print()

EOF
