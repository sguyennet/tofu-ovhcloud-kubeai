#!/bin/bash
# Extracts the phase timings of a model scale-up that needed a new GPU node.
#
# Run it after the new replica is serving. It reads the Kubernetes objects, the
# events and the vLLM log rather than sampling while the scale-up runs, so the
# numbers are the ones the cluster recorded and two runs are comparable.
#
#   ./test/measure-scaleup.sh <trigger-time-RFC3339> [known-node ...]
#
# The known nodes are the GPU nodes that already existed before the run; the
# newest node that is not one of them is the one measured.
set -u
TRIGGER="${1:?usage: measure-scaleup.sh <trigger-time-RFC3339> [known-node ...]}"
shift
KNOWN="$*"

NS=kubeai
POOL=mks-kubeai-compute-gpu

node=$(kubectl get nodes -l nodepool=$POOL -o json | python3 -c "
import json,sys
known=set('''$KNOWN'''.split())
ns=[n for n in json.load(sys.stdin)['items'] if n['metadata']['name'] not in known]
ns.sort(key=lambda n: n['metadata']['creationTimestamp'])
print(ns[-1]['metadata']['name'] if ns else '')")
[ -z "$node" ] && { echo "no new GPU node found (all nodes were already known)"; exit 1; }

pod=$(kubectl get pods -n $NS -l kubeai.org/model --field-selector spec.nodeName=$node \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
[ -z "$pod" ] && { echo "no model pod on $node"; exit 1; }

drv=$(kubectl get pods -n gpu-operator --field-selector spec.nodeName=$node --no-headers 2>/dev/null \
        | grep driver-daemonset | awk '{print $1}' | head -1)

kubectl get node $node -o json                                  > /tmp/ms-node.json
kubectl get pod  -n $NS $pod -o json                            > /tmp/ms-pod.json
[ -n "$drv" ] && kubectl get pod -n gpu-operator $drv -o json   > /tmp/ms-drv.json || echo '{}' > /tmp/ms-drv.json
kubectl get events -n $NS -o json                               > /tmp/ms-ev.json
kubectl get events -n gpu-operator -o json                      > /tmp/ms-drvev.json
kubectl logs -n $NS $pod 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' > /tmp/ms-log.txt

python3 - "$TRIGGER" "$node" "$pod" "$drv" <<'PYEOF'
import json, re, sys
from datetime import datetime

trigger, node_name, pod_name, drv_name = sys.argv[1:5]
T = lambda s: datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ") if s else None
def cond(o, t):
    for c in o.get("status", {}).get("conditions", []):
        if c["type"] == t and c["status"] == "True":
            return T(c["lastTransitionTime"])
def secs(a, b):
    return None if not a or not b else (b - a).total_seconds()
def fmt(s):
    return "n/a" if s is None else ("%dm %02ds" % (int(s)//60, int(s)%60))

node = json.load(open("/tmp/ms-node.json"))
pod  = json.load(open("/tmp/ms-pod.json"))
drv  = json.load(open("/tmp/ms-drv.json"))
ev   = json.load(open("/tmp/ms-ev.json"))["items"]
drvev= json.load(open("/tmp/ms-drvev.json"))["items"]
log  = open("/tmp/ms-log.txt").read()

t0          = T(trigger)
node_create = T(node["metadata"]["creationTimestamp"])
node_ready  = cond(node, "Ready")
drv_sched   = T(drv.get("metadata", {}).get("creationTimestamp")) if drv else None
drv_ready   = cond(drv, "Ready") if drv else None
pod_sched   = cond(pod, "PodScheduled")
pod_ready   = cond(pod, "Ready")
cstart      = T(pod["status"].get("containerStatuses", [{}])[0].get("state", {}).get("running", {}).get("startedAt"))

def event(name, reason):
    for e in ev:
        if e["involvedObject"].get("name") == name and e.get("reason") == reason:
            return e
    return None
su = event(pod_name, "TriggeredScaleUp") or {}
decision = T(su.get("firstTimestamp")) if su else None
pulled   = event(pod_name, "Pulled") or {}
m = re.search(r"in (?:(\d+)m)?([\d.]+)s", pulled.get("message", ""))
pull = (int(m.group(1) or 0) * 60 + float(m.group(2))) if m else None

def logval(pat):
    m = re.search(pat, log)
    return float(m.group(1)) if m else None
w_load  = logval(r"Loading weights took ([\d.]+) seconds")
m_load  = logval(r"Model loading took [\d.]+ GiB memory and ([\d.]+) seconds")
engine  = logval(r"init engine \(profile, create kv cache, warmup model\) took ([\d.]+) seconds")
hf      = (m_load - w_load) if (m_load is not None and w_load is not None) else None

# Driver install split three ways: the driver-manager init container, which
# unloads whatever is already there, the pull of the driver image itself, and the
# load of the module plus the operator validation chain. Only the last one is
# shorter with a precompiled image, and only by the compile it skips.
drv_init = cond(drv, "Initialized") if drv else None
drv_cstart = None
if drv:
    cs = drv.get("status", {}).get("containerStatuses", [])
    if cs:
        drv_cstart = T(cs[0].get("state", {}).get("running", {}).get("startedAt"))
drv_pull = None
for e in drvev:
    if e["involvedObject"].get("name") == drv_name and e.get("reason") == "Pulled" \
       and "nvidia/driver:" in e.get("message", ""):
        mm = re.search(r"in (?:(\d+)m)?([\d.]+)s", e["message"])
        if mm:
            drv_pull = int(mm.group(1) or 0) * 60 + float(mm.group(2))

rows = [
    ("Trigger to scale-up decision", secs(t0, decision)),
    ("Node spawn (decision to Ready)", secs(decision or t0, node_ready)),
    ("GPU driver image download", drv_pull),
    ("GPU driver install", (
        None if (drv_pull is None or secs(drv_sched, drv_ready) is None)
        else secs(drv_sched, drv_ready) - drv_pull)),
    ("Driver ready to pod scheduled", secs(drv_ready, pod_sched)),
    ("vLLM image download", pull),
    ("Weights fetch", hf),
    ("Weights load into GPU", w_load),
    ("Engine init + CUDA graphs", engine),
    ("TOTAL trigger to serving", secs(t0, pod_ready)),
]
print()
print("  node : %s" % node_name)
print("  pod  : %s" % pod_name)
print("  driver pod: %s" % (drv_name or "n/a"))
print()
for k, v in rows:
    print("  %-36s %s" % (k, fmt(v)))
print()
print("TABLE COLUMN for scale-up-benchmark.md, paste as a new run column:")
pick = dict(rows)
for label in ("Trigger to scale-up decision", "Node spawn (decision to Ready)",
              "GPU driver image download", "GPU driver install",
              "Driver ready to pod scheduled", "vLLM image download",
              "Weights fetch", "Weights load into GPU",
              "Engine init + CUDA graphs", "TOTAL trigger to serving"):
    print("| %s" % fmt(pick[label]))
PYEOF
