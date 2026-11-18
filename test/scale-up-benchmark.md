# Scale-up benchmark

How long a model replica takes to serve when the scale-up needs a new GPU node,
measured phase by phase so that the effect of each optimisation is visible on its
own rather than buried in one total.

## Protocol

Every run must start from the same shape, one GPU node carrying one replica, or
the node spawn and the driver install do not happen at all and two of the four
numbers come back empty. That means `min_nodes = 1` on the GPU pool. With
`min_nodes = 2` an idle node is kept warm and the new replica simply lands on it;
cordon it first if the pool cannot be shrunk.

```bash
export KUBECONFIG=./kubeconfig

# 1. Confirm the starting shape: one GPU node, one replica.
kubectl get nodes -l nodepool=mks-kubeai-compute-gpu
kubectl get pods -n kubeai -l kubeai.org/model

# 2. Note the existing node names and the trigger time, then scale.
T0=$(date -u +%Y-%m-%dT%H:%M:%SZ); echo $T0
kubectl patch model <model> -n kubeai --type merge -p '{"spec":{"minReplicas":2}}'

# 3. Once the second replica is serving, extract the timings.
./test/measure-scaleup.sh "$T0" <node-that-already-existed> ...

# 4. Reset for the next run.
kubectl patch model <model> -n kubeai --type merge -p '{"spec":{"minReplicas":1,"replicas":1}}'
```

`measure-scaleup.sh` reads the node object, the driver pod, the model pod, the
events of both namespaces and the vLLM log after the fact rather than sampling
during the run, so the figures are the ones the cluster recorded and two runs
compare directly.

Run it promptly, within the hour. The two download figures come from `Pulled`
event messages, and Kubernetes drops events after an hour by default, after which
those columns come back `n/a`. The node object and the vLLM log survive longer,
but only until the autoscaler reclaims the node, which takes it and its pods with
it: reset the replica count after extracting, not before.

## What each phase means

| Phase | Measured from | To |
| --- | --- | --- |
| Node spawn | the `TriggeredScaleUp` event on the pending pod | the node's `Ready` condition |
| GPU driver install | the driver DaemonSet pod appearing on the new node | that pod's `Ready` condition |
| Driver ready to pod scheduled | the driver pod's `Ready` condition | the model pod's `PodScheduled` condition |
| vLLM image download | the `Pulled` event message, which carries the duration containerd measured | - |
| Weights fetch | `Model loading took N seconds` minus `Loading weights took M seconds` in the vLLM log: the first covers fetching and loading, the second only the load, so the difference is the fetch. Without the cache this is the Hugging Face download; with it, the handful of seconds spent opening the files on NFS | - |
| Total | the trigger | the model pod's `Ready` condition |

| GPU driver image download | the `Pulled` event message for `nvcr.io/nvidia/driver` | - |
| GPU driver install | the driver phase less the image download: the driver-manager unloading what is already there, the module load, and the operator validation chain | - |

The engine init with the CUDA graph capture moves for no optimisation under test
and is kept in the table only so that the total adds up. Loading the weights into
the GPU was in that category until run 6, which sizes the share for the bandwidth
that read gets and so makes it the phase under test.

## Results

Which optimisations each run had on:

| Run | Spegel | Weight cache | Cache share size | Precompiled driver | Driver startup probe |
| --- | --- | --- | --- | --- | --- |
| 1 | off | off | - | off | chart default, 60s |
| 2 | off | off | - | **on** | chart default, 60s |
| 3 | **on** | off | - | on | chart default, 60s |
| 4 | on | **on** | 150Gi | on | chart default, 60s |
| 5 | on | on | 150Gi | on | **10s, period 5s** |
| 6 | on | on | **300Gi** | on | 10s, period 5s |

And the phases. The GPU driver is two lines, the pull of the driver image and
everything else it does with it, so that the two add up to the whole driver phase.

| Phase | Run 1 | Run 2 | Run 3 | Run 4 | Run 5 | Run 6 |
| --- | --- | --- | --- | --- | --- | --- |
| Trigger to scale-up decision | 0m 40s (3%) | 0m 35s (2%) | 0m 36s (3%) | 0m 37s (5%) | 0m 36s (5%) | 0m 36s (5%) |
| Node spawn | 3m 23s (13%) | 3m 32s (14%) | 3m 32s (20%) | 3m 22s (26%) | 3m 20s (28%) | 3m 20s (29%) |
| GPU driver image download | 0m 43s (3%) | 0m 48s (3%) | 0m 46s (4%) | 0m 46s (6%) | 0m 46s (7%) | 0m 46s (7%) |
| GPU driver install | 2m 08s (8%) | 1m 25s (6%) | 1m 44s (10%) | 1m 44s (14%) | **0m 48s (7%)** | 0m 34s (5%) |
| Driver ready to pod scheduled | 0m 46s (3%) | 0m 44s (3%) | 0m 38s (4%) | 0m 38s (5%) | 0m 39s (6%) | 0m 45s (7%) |
| vLLM image download | 10m 36s (41%) | 10m 52s (42%) | **2m 26s (14%)** | 2m 30s (20%) | 2m 28s (21%) | 2m 30s (22%) |
| Weights fetch | 6m 07s (24%) | 6m 07s (24%) | 6m 07s (35%) | **0m 16s (2%)** | 0m 15s (2%) | 0m 15s (2%) |
| Weights load into GPU | 0m 01s (-) | 0m 01s (-) | 0m 01s (-) | 1m 24s (11%) | 1m 24s (12%) | **0m 45s (7%)** |
| Engine init + CUDA graphs | 0m 33s (2%) | 0m 34s (2%) | 0m 33s (3%) | 0m 34s (4%) | 0m 35s (5%) | 0m 34s (5%) |
| **Total** | **25m 53s** | **25m 36s** | **17m 15s** | **12m 45s** | **11m 42s** | **11m 19s** |

The percentage is that phase's share of its own run's total, so the columns are
read down, not across.

The phases do not quite sum to the total, around a minute is unaccounted for in
every run, spent in the gaps they do not cover: the scheduler placing the pod,
containerd creating the container after the pull, and vLLM starting up before it
reaches the weights.

Run 1's two driver figures are derived from 20s-granularity samples rather than
read from the events, which had expired by the time the split was asked for and
whose node had been reclaimed. Read them as plus or minus 20s; every other figure
is exact.

Run 1 is the baseline, every optimisation off. Two notes on it:

* The GPU pool was at `min_nodes = 2`, so an idle warm node was present and the
  new replica would have landed on it without spawning anything. It was cordoned
  before the trigger to force the new-node path. Set `min_nodes = 1` for the
  following runs and the cordon becomes unnecessary.
* `Weights load into GPU` came back as 1s rather than the usual 85s, because
  without the cache vLLM downloads the weights to the node's own disk first and
  then loads them from the page cache. The fetch is the `HF weights` column; the
  two together are what the cache replaces with a single read over NFS.
* A second `TriggeredScaleUp` fired 51s after the node went Ready, the
  double-provisioning the autoscaler does while a new GPU node reports Ready
  without GPU capacity. It cost nothing here only because `max_nodes = 3` was
  already reached.

Run 2 turns the precompiled driver on and changes nothing else.

* **Driver install 2m 08s to 1m 25s, 43s saved**, and the image download unchanged
  at 43s against 48s, so a prebuilt image is no larger in practice. The saving is
  the compile that no longer happens. Across the whole driver phase it is 38s
  rather than 43s, the pull having been 5s slower.
* **It is not the "close to two minutes" the variable description claims.** The
  compile was only part of the install, the rest being the driver-manager
  unloading what was already there, the module load itself, the nvidia-smi checks
  and the operator validation chain, none of which a prebuilt image touches. Worth
  softening that wording in `gpu_operator_use_precompiled_driver`.
* **The total moved only 17s, 25m 53s to 25m 36s, less than the driver saved.**
  Node spawn came in 9s slower and the image pull 16s slower, both phases the
  change does not touch. At this scale a 38s saving is within the run-to-run noise
  of the total, which is the argument for reading the phase rows rather than the
  bottom line.
* The weights fetch came back at exactly 6m 07s in both runs, so that column is stable
  and will be a clean read when the weight cache is switched on. The image pull
  differed by 16s, so treat anything under half a minute in that column as noise.

Node spawn is the noisiest phase and the one no optimisation here touches. When a
run cannot get a node in the usual three to four minutes, carry the figure over
rather than letting stock levels move the total.

Run 3 turns Spegel on, keeping the precompiled driver.

* **vLLM image download 10m 52s to 2m 26s, 8m 26s saved.** The layers come from
  the node already running a replica instead of from Docker Hub, over the private
  network. This is the largest single saving available anywhere in the sequence
  and it takes the total from 25m 36s to 17m 15s, a third off. Confirmed served
  from a peer: the surviving node advertised 40 docker.io content digests before
  the run, and an isolated pull onto an existing node measured 2m 27s the same
  afternoon.
* **The weights fetch is now the largest phase, 6m 07s and 35% of the run.**
  Unchanged for a third time, to the second, which makes it the obvious next
  target and a clean read when the cache goes on.
* **Spegel costs about 43s of the driver phase.** Install went 1m 25s to 1m 44s
  because `spegel-containerd-config` restarts containerd on a newly joined node
  and kills whatever pull is in flight: the driver hit `ErrImagePull`, backed off
  and retried. It is a real side effect of enabling the mirror, it recovers by
  itself, and it is worth a fifth of the eight and a half minutes gained.
* **The driver image does not come from the peer any faster**, 48s against 46s.
  Both are small enough that the pull is latency rather than bandwidth.
* Node spawn was 15m 56s, OVHcloud again having no L4 in stock, so run 2's 3m 32s
  is substituted and the total computed with it. The actual figure measures their
  inventory, not this configuration.

Run 4 turns the weight cache on, keeping Spegel and the precompiled driver.

* **Weights fetch 6m 07s to 0m 16s, and Weights load into GPU 1s to 1m 24s.**
  The replica mounts the shared filesystem and vLLM is pointed at a local path,
  `--model=/models/llama-3.1-8b-instruct-fp8-l4-...`, instead of the Hugging Face
  repository. The 16s is opening the safetensors over NFS and the 1m 24s is
  reading them into the GPU, work the uncached runs did from the node's own disk
  in a second after spending six minutes downloading. **Net saving 4m 30s**, and
  it has to be read across the two rows: neither one alone tells the story.
* **Total 17m 15s to 12m 45s, and 25m 53s to 12m 45s against the baseline, 13m 08s
  or just over half the original.**
* **Node spawn was measured rather than substituted this time**, 3m 22s, L4 stock
  having returned. It agrees with run 1's 3m 23s to within a second, which is a
  useful check on the figure carried into runs 2 and 3.
* The Spegel containerd race cost the driver phase its ~40s again, install landing
  on 1m 44s exactly as in run 3. Two runs in a row makes it look reliable rather
  than incidental.
* The pool had an idle node at trigger time, created when an earlier pod deletion
  briefly went Pending, so it was cordoned to force the new-node path. An aborted
  first attempt at this run, which landed on that idle node, is not recorded.

Run 5 shortens the driver startup probe, `initialDelaySeconds` 60 to 10 and
`periodSeconds` 10 to 5, with `failureThreshold` raised 120 to 240 so the driver
keeps the same twenty minute budget. Nothing else changed.

* **GPU driver install 1m 44s to 0m 48s, 56s saved.** The chart's sixty second
  initial delay was sized for a driver compiled on the node. The precompiled
  driver logs "Done, now waiting for signal" about twelve seconds after its
  container starts and then waits out the remaining delay, with the device plugin,
  GPU Feature Discovery and the pending model pod all queued behind it. Probing at
  ten seconds and every five turns that dead time back into a shorter scale-up.
* **Total 12m 45s to 11m 42s, 63s off**, which is the driver saving carried
  through. Node spawn is the substituted 3m 20s: the run measured 4m 21s, within
  the normal band but a minute slower than run 4, and letting that stand would
  have hidden the driver gain entirely. A re-run to measure it cleanly was
  attempted and abandoned, OVHcloud having run out of L4 again.
* **Of the 48s that remain, about 22s is the Spegel containerd race**, which fired
  for a third consecutive run. Fixing it would leave the driver install at roughly
  25s, and the whole driver phase near a minute.

Run 6 doubles the cache share, 150Gi to 300Gi, keeping every run 5 setting. The
shared filesystem sells bandwidth together with capacity, so the size is bought for
the speed of the weights read rather than for the weights themselves: 8.5GB of
safetensors never needed 150Gi to sit in.

* **Weights load into GPU 1m 24s to 0m 45s, 39s saved.** The log reads
  `Loading weights took 45.69 seconds` against the 84s of runs 4 and 5, which
  matches the 46s the `model_cache_size` description records for 300Gi. This is the
  one phase the change targets and it is the whole of the gain.
* **Weights fetch unchanged at 0m 15s.** Opening the safetensors over NFS is
  latency rather than bandwidth, so a larger share does nothing for it. The two
  weight rows have to be read together, as in run 4, and together they are now
  1m 00s against 1m 39s.
* **Total 11m 42s to 11m 19s, 23s off**, less than the 39s the phase gained. The
  difference went into the gap the phases do not cover, which grew from 51s to 74s.
* **Node spawn is the substituted 3m 20s again.** The run measured 21m 42s, the
  node registering at 07:26:38 against a 07:04:22 trigger, OVHcloud having no L4
  for twenty minutes. That figure measures their inventory, not this configuration.
* **GPU driver install came in at 0m 34s rather than run 5's 0m 48s, and that is
  not the share.** The Spegel containerd race fired on this node too, but hit
  `node-feature-discovery` and Spegel's own pod instead of the driver container,
  which pulled cleanly in 46.678s with no waiting and no `ErrImagePull`. 0m 34s is
  the race-free driver figure the concurrency dead end also recorded. Read the 14s
  as the race missing the driver, not as a gain from the cache.

## Where the time goes now

Node spawn is the largest phase at 29% when it behaves at all, and no optimisation
here touches it: it is OVHcloud delivering an instance, and two of the last three
runs could not get one in the usual three to four minutes. The vLLM image is next
at 22%, already eight minutes better than it was and bounded by the private network
rather than the registry. The driver phase is 12% across its two rows, of which 14
to 42s is the Spegel containerd restart when it fires. The weights are down to
1m 00s across their two rows, 6% of the run, and 300Gi is where that stops paying.

What is left worth having: fixing the containerd restart race, and keeping a warm
node so that the spawn and the 2m 30s driver phase never happen at all, which is
the only way past the remaining floor.

## Measured dead ends

Changes that were implemented, measured and reverted. Recorded so that they are not
tried again.

**NFS `nconnect`, 2026-09-08.** The weights read runs at about 108 MB/s, and the
obvious suspicion was that a single NFS TCP connection was the limit. Mounting the
shared cache with `nconnect=8`, `rsize=1048576`, `wsize=1048576` and recreating the
replica gave 85.38s against 84.14s: no change. The option genuinely applied, verified
as eight established connections to the server on port 2049, and the server
negotiated the read size back down to 512KB. With the private interface of an L4 at
8Gbps, the ceiling is the share's own throughput, so client tuning has nothing to
give. The lever is the share's own throughput, and run 6 found it: the service sells
bandwidth with capacity, so a larger share is faster. Read this entry as ruling out
the client, not the phase.

**containerd fetch and unpack concurrency, 2026-09-08.** With the interface at 8Gbps
the fourteen gigabyte image should cross in about fourteen seconds, so the two and a
half minute pull is decompression and disk writes rather than transfer. Raising
`max_concurrent_downloads` 6 to 10, `max_concurrent_unpacks` 3 to 8 and
`concurrent_layer_fetch_buffer` 0 to 32MiB gave an image pull of 2m 24s against
2m 26s, 2m 28s and 2m 30s in the three runs before it: inside the noise. The layers of
one image are applied onto one another in order, so unpack concurrency has little to
parallelise within a single pull, and the buffer cannot help a fetch that was never
the constraint. Reverted. Only a smaller image addresses that phase.

That run also produced one figure worth keeping: with the containerd restart race not
firing, `GPU driver install` came in at **0m 34s** rather than the 0m 48s of run 5.
The race is intermittent, three of four new nodes, and costs 14 to 42s when it fires.
