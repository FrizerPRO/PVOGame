#!/bin/bash
# Restart each running sprites/web_ui.py instance on its original --port.
# No-op if none are running. Invoked by the Stop hook when
# /tmp/pvogame-webui-dirty is present — meaning a file under sprites/*.py was
# edited and the in-memory Python module in the server is stale.
#
# Output goes to stderr so the hook machinery surfaces it in the UI without
# polluting the model's context.
set -u

PROJECT_DIR="/Users/frizer/Documents/Study/IOS/PVOGame"
DEFAULT_PORT=8765
LOG="/tmp/pvogame-webui.log"

cd "$PROJECT_DIR" || { echo "❌ cannot cd to $PROJECT_DIR" >&2; exit 0; }

PIDS=$(pgrep -f 'sprites/web_ui.py' || true)
if [ -z "$PIDS" ]; then
    echo "  web_ui not running — nothing to restart" >&2
    exit 0
fi

# Snapshot (pid, port) pairs BEFORE killing — we need the ports for each
# instance so every restarted server comes back on the same URL.
INSTANCES=()
for pid in $PIDS; do
    port=$(ps -p "$pid" -o command= 2>/dev/null \
            | /usr/bin/grep -oE -- '--port[= ][0-9]+' \
            | /usr/bin/head -n1 \
            | /usr/bin/awk -F'[= ]' '{print $NF}')
    port=${port:-$DEFAULT_PORT}
    INSTANCES+=("$pid:$port")
done

echo "  🔁 restarting ${#INSTANCES[@]} web_ui instance(s): ${INSTANCES[*]}" >&2

# Kill all old PIDs (SIGTERM first, then SIGKILL after a grace period)
for inst in "${INSTANCES[@]}"; do
    pid="${inst%%:*}"
    kill "$pid" 2>/dev/null || true
done
sleep 1
for inst in "${INSTANCES[@]}"; do
    pid="${inst%%:*}"
    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null || true
    fi
done
sleep 1

# Launch fresh instances on their original ports. Detached + logs redirected.
NEW_PIDS=()
for inst in "${INSTANCES[@]}"; do
    port="${inst#*:}"
    nohup python3 "$PROJECT_DIR/sprites/web_ui.py" --port "$port" --no-browser \
        >>"$LOG" 2>&1 &
    new_pid=$!
    disown "$new_pid" 2>/dev/null || true
    NEW_PIDS+=("$new_pid:$port")
done

# Poll health for each instance, up to ~6 seconds total
sleep 1
ok=0
for entry in "${NEW_PIDS[@]}"; do
    pid="${entry%%:*}"
    port="${entry#*:}"
    for i in 1 2 3 4 5; do
        if curl -fs -o /dev/null "http://127.0.0.1:$port/api/status" 2>/dev/null; then
            echo "  ✅ PID $pid on port $port — healthy" >&2
            ok=$((ok+1))
            break
        fi
        sleep 1
    done
    if ! curl -fs -o /dev/null "http://127.0.0.1:$port/api/status" 2>/dev/null; then
        echo "  ⚠️  PID $pid on port $port — health check timed out (see $LOG)" >&2
    fi
done

echo "  restart summary: ${ok}/${#NEW_PIDS[@]} healthy" >&2
exit 0
