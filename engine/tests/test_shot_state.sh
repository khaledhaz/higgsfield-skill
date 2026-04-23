#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SS="$SCRIPT_DIR/../shot_state.py"
FIX_DIR="$SCRIPT_DIR/fixtures"

mkdir -p "$FIX_DIR"
SF="$FIX_DIR/shots.json"
rm -f "$SF"

# init with a 2-shot array
INITIAL='[
  {"id":1,"beat_id":1,"image_prompt":"A","video_prompt":"B","status":{"image":"queued","video":"queued"},"attempts":{"image":0,"video":0},"artifacts":{"image":null,"video":null},"reviews":{"image":[],"video":[]}},
  {"id":2,"beat_id":2,"image_prompt":"C","video_prompt":"D","status":{"image":"queued","video":"queued"},"attempts":{"image":0,"video":0},"artifacts":{"image":null,"video":null},"reviews":{"image":[],"video":[]}}
]'
python3 "$SS" init "$SF" "$INITIAL"
[ -f "$SF" ] || { echo "FAIL: init did not create file"; exit 1; }
echo "PASS test_shot_state init"

# next_queued on image → 1 (lowest id with status.image=queued)
nq=$(python3 "$SS" next_queued "$SF" image)
[ "$nq" = "1" ] || { echo "FAIL: next_queued image got '$nq' (expected 1)"; exit 1; }
echo "PASS test_shot_state next-queued-basic"

# update shot 1 status.image=rendering
python3 "$SS" update "$SF" 1 status.image=rendering
val=$(python3 "$SS" get "$SF" 1 status.image)
[ "$val" = "rendering" ] || { echo "FAIL: update dot-path got '$val' (expected rendering)"; exit 1; }
echo "PASS test_shot_state update-dot-path"

# next_queued on image now → 2 (1 is no longer queued)
nq=$(python3 "$SS" next_queued "$SF" image)
[ "$nq" = "2" ] || { echo "FAIL: next_queued skipped non-queued: got '$nq' (expected 2)"; exit 1; }
echo "PASS test_shot_state next-queued-skips-nonqueued"

# mark_attempt shot 1 image → attempts.image goes 0 → 1
python3 "$SS" mark_attempt "$SF" 1 image
n=$(python3 "$SS" attempts "$SF" 1 image)
[ "$n" = "1" ] || { echo "FAIL: mark_attempt: got '$n' (expected 1)"; exit 1; }
python3 "$SS" mark_attempt "$SF" 1 image
n=$(python3 "$SS" attempts "$SF" 1 image)
[ "$n" = "2" ] || { echo "FAIL: mark_attempt second: got '$n' (expected 2)"; exit 1; }
echo "PASS test_shot_state mark-attempt"

# add_review shot 1 image fail "reason text"
python3 "$SS" add_review "$SF" 1 image fail "only 1 ship visible"
count=$(python3 -c "import json; d=json.load(open('$SF')); print(len(d[0]['reviews']['image']))")
[ "$count" = "1" ] || { echo "FAIL: add_review count: got '$count' (expected 1)"; exit 1; }
verdict=$(python3 -c "import json; d=json.load(open('$SF')); print(d[0]['reviews']['image'][0]['verdict'])")
[ "$verdict" = "fail" ] || { echo "FAIL: add_review verdict: got '$verdict'"; exit 1; }
reason=$(python3 -c "import json; d=json.load(open('$SF')); print(d[0]['reviews']['image'][0]['reason'])")
[ "$reason" = "only 1 ship visible" ] || { echo "FAIL: add_review reason: got '$reason'"; exit 1; }
attempt_num=$(python3 -c "import json; d=json.load(open('$SF')); print(d[0]['reviews']['image'][0]['attempt'])")
[ "$attempt_num" = "2" ] || { echo "FAIL: add_review attempt: got '$attempt_num' (expected 2)"; exit 1; }
echo "PASS test_shot_state add-review"

# get whole shot as JSON
whole=$(python3 "$SS" get "$SF" 1)
echo "$whole" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); assert d['id']==1" || { echo "FAIL: get whole shot"; exit 1; }
echo "PASS test_shot_state get-whole"

# unknown shot_id returns nonzero
if python3 "$SS" get "$SF" 999 2>/dev/null; then echo "FAIL: missing id should exit nonzero"; exit 1; fi
echo "PASS test_shot_state missing-id-errors"

# next_queued when all done returns empty + zero exit
python3 "$SS" update "$SF" 1 status.image=pass
python3 "$SS" update "$SF" 2 status.image=pass
nq=$(python3 "$SS" next_queued "$SF" image)
[ -z "$nq" ] || { echo "FAIL: next_queued when none queued: got '$nq' (expected empty)"; exit 1; }
echo "PASS test_shot_state next-queued-none"

echo "ALL PASSED: shot_state"
