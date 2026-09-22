# PHP 8.5 for Wasmer

[![Build and publish the PHP runtime](https://github.com/shirakun/wasmer-php/actions/workflows/php-runtime.yml/badge.svg)](https://github.com/shirakun/wasmer-php/actions/workflows/php-runtime.yml)

[![Wasmer package](https://img.shields.io/badge/wasmer-shira%2Fphp%408.5.10-654ff0)](https://wasmer.io/shira/php)

Build and publish a **PHP 8.5 runtime as a Wasmer package**, so `wasmer run` and
Wasmer Edge can execute PHP 8.5 code — the official registry only ships PHP 8.3.

Published: [`shira/php@8.5.10`](https://wasmer.io/shira/php)

The package bundles `php.wasm` (PHP 8.5 CLI compiled for
[WASIX](https://wasix.org): WASI preview 1 plus the POSIX extensions PHP needs)
together with the ICU data and CA bundle the `intl` and `openssl` extensions
load at runtime.

```bash
wasmer run shira/php -- -r 'echo PHP_VERSION, PHP_EOL;'
# 8.5.10
```

## What is in the package

| Path in the package | Contents |
| ------------------- | -------- |
| `modules/php` | `php.wasm`, the PHP 8.5 CLI built for `wasm32-wasi` / WASIX (~55 MB) |
| `php-wasix-deps/icu` | ICU 75 data required by `intl` |
| `php-wasix-deps/openssl/ssl` | CA bundle + `openssl.cnf` mounted at `/etc/ssl` |

Compiled extensions: `bcmath`, `curl`, `exif`, `ftp`, `gd`, `iconv`, `igbinary`,
`imagick`, `intl`, `mbstring`, `mysqli`, `opcache`, `openssl`, `pdo_mysql`,
`pdo_pgsql`, `pdo_sqlite`, `pgsql`, `soap`, `sodium`, `tidy`, `zip`.

## Requirements

* [Docker](https://docs.docker.com/get-docker/) (the PHP WASIX build runs in a container).
  Building the image resolves the WASIX sysroot and LLVM through `api.github.com`; if that
  is rate limited (shared CI runners), pass a token:
  `docker build --secret id=github_token,env=GITHUB_TOKEN -t wasmer-php-builder:8.5 docker`
  (CI does this automatically with the runner token, `build.ps1` picks up `GITHUB_TOKEN`/`GH_TOKEN`)
* [Wasmer CLI](https://docs.wasmer.io/install) `>= 4` — `wasmer whoami` must show your account
* On Windows: PowerShell 7 (the wrapper) — no local C toolchain is needed

## Quick start

```powershell
# Windows / PowerShell: build the runtime, then publish it
.\build.ps1 -Publish

# Validate the publish flow without uploading anything
.\build.ps1 -SkipBuild -Publish -DryRun
```

```bash
# Linux / macOS
docker compose run --rm builder bash scripts/build-runtime.sh   # compile PHP 8.5 -> dist/
bash scripts/build-package.sh                                  # dist/ -> build/php-8.5.10.webc
wasmer publish dist                                            # push to the registry

wasmer run dist -- -r 'echo PHP_VERSION, PHP_EOL;'              # smoke test the local package
```

The first build takes a while (it downloads LLVM, the WASIX sysroot and the
prebuilt dependency libraries, then compiles PHP, ~30-45 min on 12 cores).

> `build.ps1 -DryRun` / `scripts/publish.sh --dry-run` validate the package with
> `wasmer package build --check` instead of `wasmer publish --dry-run`: the CLI
> cannot tag a version that is not on the registry yet.

### Release status

`PHP 8.5.10` is published as `shira/php@8.5.10`
([package page](https://wasmer.io/shira/php)), verified on Linux with
Wasmer 7.4.2:

```console
$ wasmer run shira/php -- -r 'printf("PHP %s INT_SIZE=%d\n", PHP_VERSION, PHP_INT_SIZE);'
PHP 8.5.10 INT_SIZE=8
```

It is built by porting the WASIX overlay from `8.5.7-wasix` onto upstream
`php-8.5.10` (`scripts/port-wasix-version.sh`), because `wasix-org/php` has not
branched 8.5.10 yet. The earlier `shira/php@8.5.7` release stays on the registry
(versions are immutable) but is no longer the latest.

`curl`, `gd`, `imagick`, `intl`, `mbstring`, `openssl`, `pdo_sqlite`, `sodium`
and `zip` are loaded; HTTPS requests and `php -S` (built-in web server) work.
On Windows hosts the Wasmer runtime itself panics (see troubleshooting).

## Using the published package

```bash
# one-liner
wasmer run shira/php -- -r 'var_dump(PHP_VERSION_ID);'

# run a script from the host directory
wasmer run shira/php --volume .:/app -- -f /app/index.php

# built-in web server (needs networking)
wasmer run shira/php --net --volume .:/app -- -t /app -S localhost:8080

# any PHP CLI flag works, e.g. install packages with Composer
wasmer run shira/php --volume .:/app --net -- /app/composer.phar install
```

`examples/hello.php` in this repository prints the version, the integer width and
the state of the compiled extensions:

```bash
wasmer run shira/php --volume .:/app -- -f /app/examples/hello.php
```

Use it as a dependency from your own package:

```toml
[package]
name = "your-user/your-app"
version = "0.1.0"
entrypoint = "web"

[dependencies]
"shira/php" = "8.5.10"

[[command]]
name = "web"
module = "shira/php:php"
runner = "wasi"

[command.annotations.wasi]
main-args = ["-t", "/app", "-S", "localhost:8080"]
```

## Configuration

PHP reads `PHPRC`, so a custom `php.ini` is mounted and pointed at:

```toml
[fs]
"/config" = "config"

[command.annotations.wasi]
env = ["PHPRC=/config/"]
```

## How the build works

`scripts/build-runtime.sh` runs inside the image defined in `docker/Dockerfile`
and replays the upstream PHP WASIX recipe:

1. clone [`wasix-org/php`](https://github.com/wasix-org/php) at the `8.5.7-wasix`
   branch and [`wasix-org/php-wasix-deps`](https://github.com/wasix-org/php-wasix-deps)
   (prebuilt WASIX libraries: openssl, icu, curl, gd/ImageMagick, pgsql, ...);
2. `wasix-configure-eh-64.sh` — configure `wasm32-wasi` with the WASIX clang
   wrapper, 64-bit longs, LTO and the exception-handling variant of the deps;
3. `wasix-build-eh.sh` — `make` and then `wasm-opt -O3 --all-features --asyncify`
   to produce `sapi/cli/php.wasm`;
4. stage `dist/modules/php` plus the ICU/SSL runtime data.

Toolchain versions are pinned in `docker/Dockerfile`, but not to the versions the
upstream CI file names — that file is stale:

| Component | Upstream CI | Here | Why |
| --------- | ----------- | ---- | --- |
| wasixcc | v0.3.0 | **v0.4.7** | `wasix-configure-eh.sh` sets `WASM_EXCEPTIONS=legacy`, which v0.3.0 rejects (`Invalid value legacy`) |
| WASIX sysroot | v2026-02-16.1 | **v2026-07-03.1** | the older tag has no `sysroot-exnref-eh`/`sysroot-eh` variants that wasixcc v0.4.x links against |
| LLVM / binaryen | latest / 123 | 21.1.206 / 123 | reproducible builds |

`scripts/build-runtime.sh` also exports `WASIXCC_WASM_EXCEPTIONS=legacy` for the
`make` step: the upstream helper script only exports it inside its own subshell,
and without it wasixcc links the exnref sysroot and fails on `libc++.a`
(`undefined symbol: _Znwm`, `__cxa_allocate_exception`, ...).

### Building another PHP version

**A `*-wasix` branch exists** (the Wasmer team released that version) — build it directly:

```powershell
.\build.ps1 -PhpVersion 8.4.22 -PhpBranch 8.4.22-wasix -Publish
```

```bash
PHP_BRANCH=8.4.22-wasix PHP_VERSION=8.4.22 docker compose run --rm builder bash scripts/build-runtime.sh
```

**Only upstream php-src has the release** — the usual case for a fresh patch release,
because `wasix-org/php` lags behind. Port the WASIX overlay onto it first:

```powershell
.\build.ps1 -PhpVersion 8.5.10 -PhpBranch 8.5.7-wasix -Publish   # ports automatically
```

```bash
docker compose run --rm -e PHP_VERSION=8.5.10 -e PHP_BASE_BRANCH=8.5.7-wasix -e FORCE=1 \
  builder bash scripts/port-wasix-version.sh

docker compose run --rm -e PHP_VERSION=8.5.10 -e PHP_SOURCE_DIR=/work/.work/php-8.5.10 \
  builder bash scripts/build-runtime.sh
```

`build.ps1` ports automatically whenever `-PhpBranch` does not match `-PhpVersion`
(force it with `-Port`).

`scripts/port-wasix-version.sh` expresses the WASIX port as
`diff(php-<branch version> -> <wasix branch>)` — about 65 core files, plus the vendored
`ext/igbinary` and `ext/imagick` — and applies it onto the requested `php-src` tag in
`.work/php-<version>`. The resulting runtime reports the upstream version:

```console
$ wasmer run build/php-8.5.10.webc -- -r 'echo PHP_VERSION;'
8.5.10
```

## Layout

```
build.ps1                  Windows entry point (build / package / publish)
docker/Dockerfile          build image: wasixcc + sysroot + binaryen + host tools
docker-compose.yml         compose wrapper for the same image
package/wasmer.toml        package manifest template (name/version placeholders)
package/README.md          README shipped inside the published package
scripts/build-runtime.sh   compile PHP for WASIX, stage dist/
scripts/build-package.sh   dist/ -> build/<name>-<version>.webc
scripts/publish.sh         build + `wasmer publish`
.github/workflows/         CI: build, smoke test, upload artefact, optional publish
```

## CI

`.github/workflows/php-runtime.yml` builds the package on demand
(`workflow_dispatch`) and on `php-*` tags, uploads the `.webc` artefact and
publishes when `publish` is selected. It needs:

* `secrets.WASMER_TOKEN` — a Wasmer registry access token (`wasmer.io/settings/access-tokens`);
* `vars.WASMER_NAMESPACE` — the namespace to publish into (optional, defaults to `shira`).

Publishing is guarded: `scripts/publish.sh` refuses to upload a version that already
exists on the registry (versions are immutable), so every release needs a new
`php_version` — e.g. `php_version: 8.5.10` with `wasix_branch: 8.5.7-wasix` (the patched
overlay is ported onto that PHP release during the run).

## Troubleshooting

* **`missing import "wasix_32v1..."`** — the module and the runtime disagree on
  the ABI. Use a Wasmer release that ships the matching WASIX version
  (`wasmer --version`, must be `>= 7`).
* **`wasm-opt: command not found`** — build inside the container
  (`docker compose run --rm builder ...`); binaryen is installed there.
* **Build killed (exit 137)** — the compile ran out of memory. Give Docker more
  memory or lower the parallelism in `wasix-build-eh.sh`.
* **`intl`/`openssl` errors at runtime** — the package must be run including its
  filesystem (`wasmer run <namespace>/php`), not the bare `modules/php` file.
* **Panic on Windows hosts** — `wasmer` 7.4.x panics with
  `not implemented: wasi::platform_clock_time_get(Clockid::ProcessCputimeId)`
  when running PHP WASIX modules on Windows. This is a Wasmer-on-Windows gap
  (the same happens with the official `php/php` package): run the package on
  Linux, in WSL, in a container, or on Wasmer Edge.
* **`Invalid value legacy for WASM_EXCEPTIONS`** — an old wasixcc is on the
  path; rebuild the image so it contains v0.4.7.

## License

The build scripts in this repository are MIT licensed (see `LICENSE`).
The PHP runtime they produce is distributed under the
[PHP License v3.01](https://www.php.net/license/3_01.txt).

The compile recipe and the prebuilt WASIX libraries come from
[`wasix-org/php`](https://github.com/wasix-org/php) and
[`wasix-org/php-wasix-deps`](https://github.com/wasix-org/php-wasix-deps).

---

## 中文快速开始

本仓库用于把 **PHP 8.5 运行时**发布成 Wasmer package（官方 registry 目前只有 PHP 8.3）。

```powershell
# 1. 构建 PHP 8.5 的 wasm 运行时（Docker 内编译）
.\build.ps1

# 2. 打包成本地 .webc 并试跑
wasmer run .\build\php-8.5.10.webc -- -r 'echo PHP_VERSION;'

# 3. 校验发布流程（不真正上传）
.\build.ps1 -SkipBuild -Publish -DryRun

# 4. 正式发布到 registry（命名空间默认取 `wasmer whoami`）
.\build.ps1 -SkipBuild -Publish
```

发布后使用：

```bash
wasmer run <你的命名空间>/php -- -r 'echo PHP_VERSION;'
wasmer run <你的命名空间>/php --volume .:/app -- -f /app/index.php
```