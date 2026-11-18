# vLLM image for one NVIDIA L4

`Dockerfile.l4` builds the vLLM engine image for the L4 GPUs of this
deployment. It is upstream's `docker/Dockerfile` at tag `v0.11.2`, the version
the cluster serves, with only what an L4 never uses removed. Every change is
marked `# L4:` in the file and says what it removes and on what evidence:

| Removed | Why |
| --- | --- |
| The CUDA `devel` base, for `base` | Only kept upstream for FlashInfer's AOT wheel, which is not installed |
| Six of the seven compiled GPU architectures | An L4 is `sm_89` and nothing else runs here |
| FlashInfer's precompiled kernels and JIT build dependencies | vLLM uses the FLASH_ATTN backend on this GPU; the kernels weigh about 5 GB |
| DeepGEMM, gdrcopy, pplx-kernels, DeepEP | Built for Hopper and Blackwell, multi-node or MoE serving |
| bitsandbytes, modelscope, timm, runai-model-streamer | Not used by an FP8 text model read from a shared filesystem |
| ccache, wget, vim | Development tools with no runtime use |

`VLLM_ATTENTION_BACKEND=FLASH_ATTN` is set so that the engine cannot select
FlashInfer, whose kernels are no longer in the image.

## Build

The build context is a vLLM checkout at the same tag. From this directory
(`image/vllm/` is ignored by Git):

```sh
git clone --depth 1 -b v0.11.2 https://github.com/vllm-project/vllm image/vllm

docker build -f image/Dockerfile.l4 --target vllm-openai \
  --build-arg max_jobs=16 --build-arg nvcc_threads=8 \
  --build-arg RUN_WHEEL_CHECK=false \
  -t <registry>/<project>/vllm-openai:v0.11.2-l4 image/vllm

docker push <registry>/<project>/vllm-openai:v0.11.2-l4
```

`RUN_WHEEL_CHECK=false` skips upstream's PyPI size check: the wheel is about
605 MB against a 500 MB limit, and nothing here uploads it to PyPI.

To compare against upstream when vLLM moves:

```sh
curl -sO https://raw.githubusercontent.com/vllm-project/vllm/v0.11.2/docker/Dockerfile
diff -u Dockerfile image/Dockerfile.l4
```

## Use it

Point the deployment at the pushed image in `terraform.tfvars`:

```hcl
vllm_image_registry = "<registry>"
vllm_image          = "<project>/vllm-openai:v0.11.2-l4"

# Only for a private repository
vllm_image_registry_username = "<username>"
vllm_image_registry_password = "<password>"
```
