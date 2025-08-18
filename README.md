<!-- @import "[TOC]" {cmd="toc" depthFrom=1 depthTo=6 orderedList=false} -->

<!-- code_chunk_output -->

- [1. Overview](#1-overview)
- [2. Install and Preparation](#2-install-and-preparation)
  - [2.1. Docker](#21-docker)
  - [2.2. Build and Start Docker Containers](#22-build-and-start-docker-containers)
  - [2.3. Build Components](#23-build-components)
  - [2.4. Run Toolchain for Benchmarks](#24-run-toolchain-for-benchmarks)

<!-- /code_chunk_output -->



# 1. Overview

We present a prototype of ***SecSep***, the transformation framework introduced in our accepted paper.
This framework is composed of following components (`$ROOT` is the root directory where this README file is):

|Component|Location|Purpose|
|:-:|:-:|:-|
|Scale|`$ROOT/scale/`|A tiny AST walker to (1) help parse ***SecSep*** annotations and (2) get statistics of the source code.|
|Benchmark|`$ROOT/benchmark/`| (1) Source code of all benchmarks. <br>(2) Parse ***SecSep*** annotations and generate inference inputs. <br>(3) Compile source code into assembly / assembly into binary.|
|Octal|`$ROOT/octal/`| (1) Infer the dependent type, valid-region, and taint type of assembly. <br>(2) Check the inference results using a checker with a small TCB. <br>(3) Transform original assembly using ***SecSep***'s transformations. <br>(4) Run evaluations using transformed binaries and Gem5.|
|Gem5 Simulator|`$ROOT/gem5/`|Implement the hardware-defense on O3 CPU for evaluation.|

# 2. Install and Preparation

## 2.1. Docker

We use Docker to provide stable environments for all components.

You need to install Docker if your OS does not have one.
Installation instructions can be found at [here](https://docs.docker.com/engine/install/).
We recommend following the steps of
1. Click on your platform's link
2. Follow section "Uninstall old versions"
3. Follow section "Install using the apt repository"

Our test platform uses `Docker version 27.5.1`, though most versions of Docker should work.
If you encounter any problem, please consider upgrade or downgrade to this version, or contact us directly for more supports.

## 2.2. Build and Start Docker Containers

In `$ROOT` directory, run:
```bash
docker compose up -d --build

# For older Docker, the command is "docker-compose" instead
```
to build three containers for all four components.
Here are the containers and their directory mappings to the host:

* `secsep-benchmark`: container for Scale and Benchmark.
  * `/root/scale`: mapped to `$ROOT/scale`
  * `/root/benchmark`: mapped to `$ROOT/benchmark`
* `secsep-octal`: container for Octal.
  * `/root/octal`: mapped to `$ROOT/octal`
  * `/root/benchmark`: mapped to `$ROOT/benchmark`
* `secsep-gem5`: container for Gem5.
  * `/root/gem5`: mapped to `$ROOT/gem5`
  * `/root/benchmark`: mapped to `$ROOT/benchmark`

Run `docker ps -a` to make sure all of them are built and started successfully.

To attach a shell to any container, run
```bash
docker exec -it <container name> /bin/zsh

# For example:
# docker exec -it secsep-benchmark /bin/zsh
```

## 2.3. Build Components

In container `secsep-benchmark`, run:
```bash
cd /root/scale
dune build && dune install
```

In container `secsep-octal`, run:
```bash
cd /root/octal
dune build && dune install
```

In container `secsep-gem5`, run:
```bash
cd /root/gem5
scons build/X86_MESI_Two_Level/gem5.opt -j16
# adjust -j at your preference for faster gem5 build
```

## 2.4. Run Toolchain for Benchmarks

Currently there are six supported benchmarks: `salsa20`, `sha512`, `chacha20`, `x25519`, `poly1305`, `ed25519_sign`.
We provide commands to run ***SecSep*** toolchain on one or all benchmarks.

Here are some configurable arguments and their explanation:
* `<name>` specifies the benchmark you choose to work on.
  Commands without `<name>` work on all available benchmarks.
* `<delta>` specifies the delta (in bytes) used by ***SecSep*** transformation.
  Must be specified in hexadecimal format.
  In paper's evaluation, we use `0x800000`, i.e. 8MB.

|Step|Container|Directory|Command|
|:-:|:-|:-|:-|
|1|`secsep-benchmark`|`/root/benchmark`|`make -j`|
|2|`secsep-octal`    |`/root/octal`    |`./scripts/run.py full --delta <delta> --name <name>`|
|3|`secsep-benchmark`|`/root/benchmark`|`./scripts/clang_get_binaries.py`|
|4|`secsep-octal`    |`/root/octal`    |`./scripts/eval.py --gem5-docker secsep-gem5 --delta <delta>` |
|5|`secsep-octal`    |`/root/octal`    |`./scripts/figure.py <eval directory generated in step 4>` |

TODO: connect `secsep-octal` and `secsep-gem5`
