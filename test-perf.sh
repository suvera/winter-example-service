#!/bin/bash
#
# Performance / memory-leak test for the Example Micro-Service.
#
# Starts the service, sends batches of large JSON payloads to POST /perf/payload
# (concurrently), samples per-worker memory (after a forced GC) and total RSS of
# the server's process tree after every batch, then prints latency/throughput
# and memory stats and flags anomalies.
#
# Tunables (environment variables):
#   BATCHES=10            measured batches (a warm-up batch runs first)
#   REQS_PER_BATCH=60     requests per batch, sizes rotate through SIZES_KB
#   CONCURRENCY=4         parallel requests in flight
#   SIZES_KB="16 256 1024 4096"   payload sizes to send
#   OVERSIZE_KB=10240     probe above server.swoole.package_max_length (0 = skip)
#   LEAK_KB=64            per-worker post-GC growth, rising batch after batch, that is a leak
#   GROWTH_KB=1024        any per-worker post-GC growth that is flagged
#   RSS_GROWTH_MB=32      process-tree RSS growth that is flagged
#   DEGRADE_FACTOR=1.5    last/first batch avg latency ratio that is flagged
#   TAIL_FACTOR=5         p99/p50 ratio that is flagged
#   STRICT=0              1 = warnings also fail the run
#   KEEP_WORK=0           1 = keep the work dir (payloads, raw results, app log)
#   PORT=8080

set -u

BATCHES=${BATCHES:-10}
REQS_PER_BATCH=${REQS_PER_BATCH:-60}
CONCURRENCY=${CONCURRENCY:-4}
SIZES_KB=${SIZES_KB:-"16 256 1024 4096"}
OVERSIZE_KB=${OVERSIZE_KB:-10240}
LEAK_KB=${LEAK_KB:-64}
GROWTH_KB=${GROWTH_KB:-1024}
RSS_GROWTH_MB=${RSS_GROWTH_MB:-32}
DEGRADE_FACTOR=${DEGRADE_FACTOR:-1.5}
TAIL_FACTOR=${TAIL_FACTOR:-5}
STRICT=${STRICT:-0}
KEEP_WORK=${KEEP_WORK:-0}
PORT=${PORT:-8080}
STATS_PROBES=${STATS_PROBES:-32}
# Known, harmless startup log lines that should not be flagged
LOG_IGNORE=${LOG_IGNORE:-"no admin token is configured|Request Entity Too Large"}

BASE_URL="http://localhost:$PORT"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/winter-perf.XXXXXX")
APP_LOG="$WORK/app.log"
APP_PID=""
ORPHANS=""

FAILS=0
WARNS=0
FINDINGS=()

fail() { FAILS=$((FAILS + 1)); FINDINGS+=("FAIL: $*"); echo "FAIL: $*"; }
warn() { WARNS=$((WARNS + 1)); FINDINGS+=("WARN: $*"); echo "WARN: $*"; }

# All descendants of a pid (Swoole: master -> manager -> workers/task workers).
tree_pids() {
    local p
    for p in $(pgrep -P "$1" 2>/dev/null); do
        echo "$p"
        tree_pids "$p"
    done
}

# Total RSS (KB) and process count of the server's process tree.
tree_rss() {
    local total=0 n=0 p rss
    for p in "$APP_PID" $(tree_pids "$APP_PID"); do
        rss=$(awk '/^VmRSS:/ {print $2}' "/proc/$p/status" 2>/dev/null)
        if [ -n "$rss" ]; then
            total=$((total + rss))
            n=$((n + 1))
        fi
    done
    echo "$total $n"
}

stop_app() {
    [ -z "$APP_PID" ] && return
    local pids
    pids="$APP_PID $(tree_pids "$APP_PID")"
    kill "$APP_PID" 2>/dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "$APP_PID" 2>/dev/null || break
        sleep 0.5
    done
    sleep 1
    # Anything still alive after a graceful shutdown of the master is orphaned
    local p left=""
    for p in $pids; do
        kill -0 "$p" 2>/dev/null && left="$left $p($(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | cut -c1-60))"
    done
    [ -n "$left" ] && ORPHANS="$left"
    # shellcheck disable=SC2086
    kill -9 $pids 2>/dev/null
    wait "$APP_PID" 2>/dev/null
    APP_PID=""
    # Verify everything is really gone
    sleep 3
    left=""
    for p in $pids; do
        kill -0 "$p" 2>/dev/null && left="$left $p"
    done
    if [ -n "$left" ]; then
        fail "Processes still running 3s after SIGKILL:$left"
    else
        echo "OK: All service processes stopped"
    fi
}

cleanup() {
    stop_app
    if [ "$KEEP_WORK" = "1" ] || [ "$FAILS" -gt 0 ]; then
        echo "Work dir kept: $WORK"
    else
        rm -rf "$WORK"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

app_alive() { kill -0 "$APP_PID" 2>/dev/null; }

echo "=== Example Micro-Service Performance Test ==="
echo "batches=$BATCHES reqs/batch=$REQS_PER_BATCH concurrency=$CONCURRENCY sizes(KB)=[$SIZES_KB]"
echo ""

if [ ! -d "vendor" ]; then
    echo "Installing dependencies..."
    composer install --no-interaction || exit 1
fi

KV_PORT=$(awk '/^    kv:/ {f = 1} f && /port:/ {print $2; exit}' config/application.yml)
QUEUE_PORT=$(awk '/^    queue:/ {f = 1} f && /port:/ {print $2; exit}' config/application.yml)
for p in "$PORT" "$KV_PORT" "$QUEUE_PORT"; do
    if [ -n "$p" ] && (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null; then
        echo "ERROR: Port $p is already in use (leftover example-service / kv-server / queue-server?); stop it first."
        exit 1
    fi
done

# ---------------------------------------------------------------- payloads
echo "Generating payloads in $WORK ..."
cat > "$WORK/gen.php" <<'PHP'
<?php
// Usage: gen.php <targetBytes> <outFile>  - deterministic JSON close to target size
[$_, $target, $out] = $argv;
mt_srand((int)$target);
$tags = ['alpha', 'beta', 'gamma', 'delta', 'epsilon', 'zeta', 'eta', 'theta'];
$items = [];
$size = 12;
for ($i = 0; $size < $target; $i++) {
    $item = [
        'id' => $i,
        'name' => 'item-' . $i . '-' . bin2hex(random_bytes(8)),
        'value' => mt_rand(0, 1000000) / 100,
        'tags' => [$tags[$i % 8], $tags[mt_rand(0, 7)]],
        'note' => str_repeat(chr(97 + $i % 26), 40),
    ];
    $items[] = $item;
    $size += strlen(json_encode($item)) + 1;
}
file_put_contents($out, json_encode(['items' => $items]));
echo count($items);
PHP

LABELS=()
for kb in $SIZES_KB; do
    label="${kb}K"
    LABELS+=("$label")
    n=$(php "$WORK/gen.php" $((kb * 1024)) "$WORK/payload-$label.json") || exit 1
    sha256sum "$WORK/payload-$label.json" | cut -d' ' -f1 > "$WORK/payload-$label.sha256"
    echo "$n" > "$WORK/payload-$label.items"
    printf "  %-7s %8d bytes  %6d items\n" "$label" "$(stat -c %s "$WORK/payload-$label.json")" "$n"
done
echo ""

# ---------------------------------------------------------------- start app
echo "Starting application (log: $APP_LOG) ..."
php bin/example-service.php > "$APP_LOG" 2>&1 &
APP_PID=$!

for i in $(seq 1 30); do
    curl -s -f -o /dev/null "$BASE_URL/monitoring/health" && break
    app_alive || break
    sleep 1
done
if ! curl -s -f -o /dev/null "$BASE_URL/monitoring/health"; then
    fail "Application did not start (see $APP_LOG)"
    tail -20 "$APP_LOG"
    exit 1
fi
echo "OK: Application is running (master pid $APP_PID)"
echo ""

# ---------------------------------------------------------------- helpers
# One request; prints: label http_code time_s worker_pid memUsage memPeak memLimit integrity
one_request() {
    local label=$1 file="$WORK/payload-$1.json" expected out body metrics
    local pid=- mem=- peak=- limit=- ok=BAD
    expected=$(<"$WORK/payload-$label.sha256")
    # "Expect:" disables curl's 100-continue handshake for large bodies
    out=$(curl -s -m 60 -X POST -H 'Content-Type: application/json' -H 'Expect:' \
        --data-binary "@$file" -w '\n%{http_code} %{time_total}' "$BASE_URL/perf/payload")
    body=${out%$'\n'*}
    metrics=${out##*$'\n'}
    [[ $body =~ \"pid\":[[:space:]]*([0-9]+) ]] && pid=${BASH_REMATCH[1]}
    [[ $body =~ \"memUsage\":[[:space:]]*([0-9]+) ]] && mem=${BASH_REMATCH[1]}
    [[ $body =~ \"memPeak\":[[:space:]]*([0-9]+) ]] && peak=${BASH_REMATCH[1]}
    [[ $body =~ \"memLimit\":[[:space:]]*(-?[0-9]+) ]] && limit=${BASH_REMATCH[1]}
    if [[ $body =~ \"sha256\":[[:space:]]*\"([0-9a-f]+)\" ]] && [ "${BASH_REMATCH[1]}" = "$expected" ] \
        && [[ $body =~ \"items\":[[:space:]]*([0-9]+) ]] && [ "${BASH_REMATCH[1]}" = "$(<"$WORK/payload-$label.items")" ]; then
        ok=OK
    fi
    printf '%s %s %s %s %s %s %s\n' "$label" "$metrics" "$pid" "$mem" "$peak" "$limit" "$ok"
}
export -f one_request
export WORK BASE_URL

# Runs one batch; results in $WORK/batch-<n>.txt, wall time (ms) in batch-<n>.wall
run_batch() {
    local b=$1 i t0 t1
    for ((i = 0; i < REQS_PER_BATCH; i++)); do
        echo "${LABELS[i % ${#LABELS[@]}]}"
    done > "$WORK/jobs.txt"
    t0=$(date +%s%N)
    xargs -P "$CONCURRENCY" -I{} bash -c 'one_request "$1"' _ {} < "$WORK/jobs.txt" > "$WORK/batch-$b.txt"
    t1=$(date +%s%N)
    echo $(((t1 - t0) / 1000000)) > "$WORK/batch-$b.wall"
}

# Post-GC memory of each worker (round-robin dispatch reaches all of them)
# and the tree RSS; appended to mem.txt / rss.txt for batch <n>.
sample_memory() {
    local b=$1 i body rss
    for ((i = 0; i < STATS_PROBES; i++)); do
        body=$(curl -s -m 10 "$BASE_URL/perf/stats?gc=1")
        if [[ $body =~ \"pid\":[[:space:]]*([0-9]+) ]]; then
            local pid=${BASH_REMATCH[1]}
            [[ $body =~ \"memUsage\":[[:space:]]*([0-9]+) ]] && local mem=${BASH_REMATCH[1]}
            [[ $body =~ \"memReal\":[[:space:]]*([0-9]+) ]] && local real=${BASH_REMATCH[1]}
            [[ $body =~ \"requests\":[[:space:]]*([0-9]+) ]] && local reqs=${BASH_REMATCH[1]}
            echo "$b $pid $mem $real $reqs" >> "$WORK/mem.txt"
        fi
    done
    rss=$(tree_rss)
    echo "$b $rss" >> "$WORK/rss.txt"
    tree_pids "$APP_PID" | sort -n > "$WORK/pids-$b.txt"
}

# ---------------------------------------------------------------- sanity
echo "1. Sanity check: one request per payload size"
for label in "${LABELS[@]}"; do
    read -r _ code t _ _ _ _ ok <<< "$(one_request "$label")"
    if [ "$code" = "200" ] && [ "$ok" = "OK" ]; then
        printf "   OK: %-7s HTTP %s in %6.1f ms, checksum matches\n" "$label" "$code" "$(echo "$t * 1000" | bc -l)"
    else
        fail "$label payload: HTTP $code, integrity=$ok"
    fi
done
[ "$FAILS" -gt 0 ] && exit 1
echo ""

# ---------------------------------------------------------------- warm-up
echo "2. Warm-up batch (not measured), then baseline memory sample"
run_batch 0
sample_memory 0
read -r _ base_rss base_procs <<< "$(tail -1 "$WORK/rss.txt")"
echo "   Baseline RSS: $((base_rss / 1024)) MB across $base_procs processes"
echo ""

# ---------------------------------------------------------------- batches
echo "3. Running $BATCHES measured batches"
printf "   %-6s %5s %6s %9s %9s %9s %9s %10s %9s\n" \
    "batch" "reqs" "errors" "wall(ms)" "req/s" "MB/s" "avg(ms)" "maxW-mem" "RSS(MB)"
for ((b = 1; b <= BATCHES; b++)); do
    run_batch "$b"
    if ! app_alive; then
        fail "Application died during batch $b (see $APP_LOG)"
        break
    fi
    sample_memory "$b"
    wall=$(<"$WORK/batch-$b.wall")
    rss=$(tail -1 "$WORK/rss.txt" | cut -d' ' -f2)
    maxw=$(awk -v b="$b" '$1 == b {m[$2] = $3} END {x = 0; for (p in m) if (m[p] > x) x = m[p]; printf "%.1fMB", x / 1048576}' "$WORK/mem.txt")
    awk -v wall="$wall" -v sizes="$SIZES_KB" -v b="$b" -v rss="$rss" -v maxw="$maxw" '
        BEGIN { split(sizes, s, " "); for (i in s) kb[s[i] "K"] = s[i] }
        { n++; t += $3; if ($2 != 200 || $8 != "OK") e++; bytes += kb[$1] * 1024 }
        END {
            ws = (wall > 0 ? wall : 1) / 1000
            printf "   %-6s %5d %6d %9d %9.1f %9.1f %9.1f %10s %9.1f\n",
                b, n, e, wall, n / ws, bytes / 1048576 / ws, n ? t / n * 1000 : 0, maxw, rss / 1024
        }' "$WORK/batch-$b.txt"
done
echo ""

# ---------------------------------------------------------------- latency per size
echo "4. Latency by payload size (all measured batches)"
cat "$WORK"/batch-[1-9]*.txt > "$WORK/all.txt" 2>/dev/null
printf "   %-7s %6s %6s %9s %9s %9s %9s %9s %9s\n" "size" "count" "errors" "min" "avg" "p50" "p95" "p99" "max"
for label in "${LABELS[@]}"; do
    stats=$(awk -v l="$label" '$1 == l { print $3 * 1000 }' "$WORK/all.txt" | sort -n | awk '
        { v[NR] = $1; s += $1 }
        END {
            if (NR == 0) { print "0 0 0 0 0 0 0"; exit }
            p50 = v[int(NR * 0.50 + 0.999)]; p95 = v[int(NR * 0.95 + 0.999)]; p99 = v[int(NR * 0.99 + 0.999)]
            printf "%d %.1f %.1f %.1f %.1f %.1f %.1f\n", NR, v[1], s / NR, p50, p95, p99, v[NR]
        }')
    errors=$(awk -v l="$label" '$1 == l && ($2 != 200 || $8 != "OK")' "$WORK/all.txt" | wc -l)
    read -r cnt mn avg p50 p95 p99 mx <<< "$stats"
    printf "   %-7s %6d %6d %9s %9s %9s %9s %9s %9s  (ms)\n" "$label" "$cnt" "$errors" "$mn" "$avg" "$p50" "$p95" "$p99" "$mx"
    echo "$label $cnt $errors $avg $p50 $p99 $mx" >> "$WORK/latency.txt"
done
echo ""

# ---------------------------------------------------------------- memory per worker
echo "5. Worker memory after forced GC (baseline = after warm-up)"
printf "   %-8s %9s %11s %11s %11s %9s %11s\n" "pid" "requests" "baseline" "final" "delta" "rising" "peak"
awk -v last="$BATCHES" '
    { m[$2, $1] = $3; r[$2, $1] = $5; pids[$2] = 1; if ($1 > maxb) maxb = $1 }
    END {
        for (p in pids) {
            first = ""; prev = ""; rising = 0; steps = 0
            for (b = 0; b <= maxb; b++) {
                if (!((p, b) in m)) continue
                if (first == "") { first = m[p, b]; fb = b }
                else { steps++; if (m[p, b] > prev) rising++ }
                prev = m[p, b]; lb = b
            }
            print p, r[p, lb], first, prev, prev - first, rising, steps, r[p, lb] - r[p, fb]
        }
    }' "$WORK/mem.txt" | sort -n > "$WORK/workers.txt"

while read -r pid reqs first final delta rising steps served; do
    peak=$(awk -v p="$pid" '$4 == p && $6 != "-" { if ($6 > x) x = $6 } END { printf "%.1fMB", x / 1048576 }' "$WORK/all.txt")
    printf "   %-8s %9s %10.2fM %10.2fM %+10.1fK %4s/%-4s %11s\n" "$pid" "$reqs" \
        "$(echo "$first / 1048576" | bc -l)" "$(echo "$final / 1048576" | bc -l)" \
        "$(echo "$delta / 1024" | bc -l)" "$rising" "$steps" "$peak"
done < "$WORK/workers.txt"

read -r _ final_rss final_procs <<< "$(tail -1 "$WORK/rss.txt")"
rss_delta=$((final_rss - base_rss))
echo ""
echo "   Process tree RSS: baseline $((base_rss / 1024)) MB -> final $((final_rss / 1024)) MB" \
     "($((rss_delta / 1024)) MB), processes $base_procs -> $final_procs"
echo ""

# ---------------------------------------------------------------- anomalies
echo "6. Anomaly checks"

total=$(wc -l < "$WORK/all.txt")
errs=$(awk '$2 != 200' "$WORK/all.txt" | wc -l)
corrupt=$(awk '$2 == 200 && $8 != "OK"' "$WORK/all.txt" | wc -l)
[ "$errs" -gt 0 ] && fail "$errs of $total requests did not return HTTP 200 (codes: $(awk '$2 != 200 {print $2}' "$WORK/all.txt" | sort | uniq -c | tr -s ' ' | tr '\n' ','))"
[ "$corrupt" -gt 0 ] && fail "$corrupt responses had a checksum/item-count mismatch (payload corrupted or truncated)"

# Leak: post-GC usage keeps rising batch after batch, or grew a lot overall.
# A healthy worker returns to the same post-GC figure (delta ~0).
while read -r pid reqs first final delta rising steps served; do
    [ "$steps" -lt 2 ] && continue
    per_req=$((delta / (served > 0 ? served : 1)))
    if [ "$delta" -gt $((LEAK_KB * 1024)) ] && [ $((rising * 10)) -ge $((steps * 7)) ]; then
        fail "Memory leak in worker $pid: +$((delta / 1024)) KB after GC, rising in $rising/$steps batches (~$per_req bytes retained per request)"
    elif [ "$delta" -gt $((GROWTH_KB * 1024)) ]; then
        warn "Worker $pid memory grew +$((delta / 1024)) KB after GC (rising in $rising/$steps batches, ~$per_req bytes/request)"
    fi
done < "$WORK/workers.txt"

# Child processes that were replaced after warm-up => restarts (crash, OOM, max_request)
gone=$(cat "$WORK"/pids-[1-9]*.txt 2>/dev/null | sort -nu | comm -23 "$WORK/pids-0.txt" - | tr '\n' ' ')
new=$(cat "$WORK"/pids-[1-9]*.txt 2>/dev/null | sort -nu | comm -13 "$WORK/pids-0.txt" - | tr '\n' ' ')
[ -n "${gone// /}" ] && warn "Server process(es) disappeared during the run: $gone- worker crash/OOM/restart?"
[ -n "${new// /}" ] && warn "New server process(es) appeared during the run: $new- worker restarted?"

if [ "$rss_delta" -gt $((RSS_GROWTH_MB * 1024)) ]; then
    rising_rss=$(awk 'NR > 1 && $2 > prev {r++} {prev = $2} END {print r + 0}' "$WORK/rss.txt")
    warn "Process tree RSS grew $((rss_delta / 1024)) MB (rose in $rising_rss/$BATCHES batches); allocator may hold freed memory, but check if it keeps climbing with more BATCHES"
fi

# Peak memory vs memory_limit
read -r peak limit <<< "$(awk '$6 != "-" { if ($6 > p) p = $6; l = $7 } END { print p + 0, l + 0 }' "$WORK/all.txt")"
if [ "$limit" -gt 0 ] && [ $((peak * 2)) -gt "$limit" ]; then
    warn "Worker peak memory $((peak / 1048576)) MB is over 50% of memory_limit ($((limit / 1048576)) MB); larger payloads/concurrency risk OOM"
fi

# Latency degradation over the run
read -r first_avg last_avg <<< "$(awk -v last="$BATCHES" '
    FILENAME ~ /batch-1\.txt$/ { a += $3; na++ }
    FILENAME ~ ("batch-" last "\\.txt$") { b += $3; nb++ }
    END { printf "%.1f %.1f\n", na ? a / na * 1000 : 0, nb ? b / nb * 1000 : 0 }' "$WORK/batch-1.txt" "$WORK/batch-$BATCHES.txt" 2>/dev/null)"
if awk -v f="$first_avg" -v l="$last_avg" -v k="$DEGRADE_FACTOR" 'BEGIN { exit !(f > 0 && l > f * k && l - f > 5) }'; then
    warn "Latency degraded over the run: batch 1 avg ${first_avg} ms -> batch $BATCHES avg ${last_avg} ms"
fi

# Tail latency and suspicious ~1s stalls (e.g. 100-continue / Nagle delays)
while read -r label cnt e avg p50 p99 mx; do
    if awk -v a="$p50" -v b="$p99" -v k="$TAIL_FACTOR" 'BEGIN { exit !(a > 0 && b > a * k && b > 50) }'; then
        warn "$label: tail latency p99 ${p99} ms is >${TAIL_FACTOR}x p50 ${p50} ms"
    fi
done < "$WORK/latency.txt"
stalls=$(awk '$3 >= 1.0 && $3 < 1.2' "$WORK/all.txt" | wc -l)
[ "$stalls" -gt 0 ] && warn "$stalls requests took ~1s (typical of a 100-continue or connection stall)"

# Oversized payload must be rejected without hurting the server
if [ "$OVERSIZE_KB" -gt 0 ] && app_alive; then
    head -c $((OVERSIZE_KB * 1024)) /dev/zero | tr '\0' 'x' > "$WORK/oversize.bin"
    code=$(curl -s -o /dev/null -m 30 -X POST -H 'Content-Type: application/json' -H 'Expect:' \
        --data-binary "@$WORK/oversize.bin" -w '%{http_code}' "$BASE_URL/perf/payload")
    if ! curl -s -f -o /dev/null "$BASE_URL/monitoring/health"; then
        fail "Server unhealthy after ${OVERSIZE_KB}K oversized request (got HTTP $code)"
    elif [ "$code" = "200" ]; then
        warn "${OVERSIZE_KB}K invalid payload was accepted with HTTP 200"
    else
        echo "   OK: ${OVERSIZE_KB}K oversized payload rejected (HTTP $code), server still healthy"
    fi
fi

# Errors in the application log
grep -iE 'fatal|allowed memory size|segmentation|exception|\bERROR\b|CRITICAL|WARNING|worker.*(exit|abnormal)' "$APP_LOG" \
    | grep -vE "$LOG_IGNORE" > "$WORK/log-issues.txt"
log_issues=$(wc -l < "$WORK/log-issues.txt")
if [ "$log_issues" -gt 0 ]; then
    warn "$log_issues suspicious line(s) in application log ($APP_LOG)"
    head -5 "$WORK/log-issues.txt" | cut -c1-200 | sed 's/^/        /'
    KEEP_WORK=1
fi

if app_alive; then
    # Graceful shutdown must take every child process down with the master
    ORPHANS=""
    stop_app
    [ -n "$ORPHANS" ] && warn "Processes survived graceful shutdown (SIGTERM to master), would hold ports on restart:$ORPHANS"
else
    fail "Application is no longer running"
fi
[ "$FAILS" -eq 0 ] && [ "$WARNS" -eq 0 ] && echo "   OK: No anomalies detected"
echo ""

# ---------------------------------------------------------------- summary
echo "=== Summary ==="
echo "Requests: $total measured ($errs errors, $corrupt corrupted) across $BATCHES batches"
if [ ${#FINDINGS[@]} -gt 0 ]; then
    printf '  %s\n' "${FINDINGS[@]}"
fi
if [ "$FAILS" -gt 0 ] || { [ "$STRICT" = "1" ] && [ "$WARNS" -gt 0 ]; }; then
    echo "RESULT: FAILED ($FAILS failures, $WARNS warnings)"
    exit 1
fi
echo "RESULT: PASSED ($WARNS warnings)"
