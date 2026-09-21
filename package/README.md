# PHP 8.5 for Wasmer

The PHP 8.5 command line runtime, compiled for **WASIX** (WASI preview 1 plus the
POSIX extensions PHP needs) and packaged for the [Wasmer runtime](https://wasmer.io).

The registry only ships PHP 8.3 today; this package provides the 8.5 series so
applications, CI jobs and Wasmer Edge deployments can use the features and
security fixes of the newer branch.

## Usage

```bash
# REPL-less one liners
wasmer run shira/php -- -r 'echo PHP_VERSION, PHP_EOL;'

# run a script from the host directory
wasmer run shira/php --volume .:/app -- -f /app/index.php

# built-in web server
wasmer run shira/php --net --volume .:/app -- -t /app -S localhost:8080

# as a dependency of your own package
```

```toml
[dependencies]
"shira/php" = "8.5.7"

[[command]]
name = "web"
module = "shira/php:php"
runner = "wasi"

[command.annotations.wasi]
main-args = ["-t", "/app", "-S", "localhost:8080"]
```

## What is inside

| Path | Description |
| ---- | ----------- |
| `/modules/php` | `php.wasm`, the PHP 8.5 CLI compiled for `wasm32-wasi`/WASIX |
| `/etc/ssl` | CA bundle used by `openssl` and stream wrappers |
| `/icu` | ICU data used by the `intl` extension |

Compiled extensions include `bcmath`, `curl`, `exif`, `gd`, `iconv`, `igbinary`,
`imagick`, `intl`, `mbstring`, `mysqli`, `opcache`, `openssl`, `pdo_mysql`,
`pdo_pgsql`, `pdo_sqlite`, `pgsql`, `soap`, `sodium`, `tidy` and `zip`.

## Custom configuration

PHP reads `PHPRC`; mount your own configuration and point PHP at it:

```toml
[fs]
"/config" = "config"

[[command]]
name = "php"
module = "shira/php:php"
runner = "wasi"

[command.annotations.wasi]
env = ["PHPRC=/config/"]
```

## License

PHP is distributed under the [PHP License v3.01](https://www.php.net/license/3_01.txt).