# Example micro-service developed using Winter Boot

This is example micro-service, developed using **[winter-boot](https://github.com/suvera/winter-boot)**

## Start Application

Update Library dependencies

```shell
composer update
```

Use one of the way to start application as listed below

### 1. Build **Phar** binary with box, and start service

```shell
./deploy/build.sh

# Start service
php target/example-service.phar -c "$(realpath ./config)"
```

### 2. (OR) Simply run this command

```shell
php bin/example-service.php
```

### 3. (OR) Using Docker Image

```shell
# Build PHAR, then Docker Image
./deploy/build.sh
docker build . -t demoapp/example-service:1.0.0 -f ./Dockerfile

# Start Container, so service starts
docker run -d -p 8080:8080 --name example-service demoapp/example-service:1.0.0
```

## Test API Calls

```shell
# Put a Key Value into store
curl -X POST http://127.0.0.1:8080/key-value -d "key=google&value=Alphabet Inc."

# Get value for key from store
curl http://127.0.0.1:8080/key-value?key=google

# Delete key from store
curl -X DELETE http://127.0.0.1:8080/key-value -d "key=google"
```

### More API calls

```shell
curl http://127.0.0.1:8080/stock/AAPL

# Async execution
curl http://127.0.0.1:8080/crawlAsync

# LOGs shows following line
"Fetched 21897 bytes data from url https://www.php.net/manual/en/intro-whatcando.php"


# Distributed Task execution
curl http://127.0.0.1:8080/distributedJob

```

### Monitoring API's

```shell
curl http://127.0.0.1:8080/monitoring/prometheus

curl http://127.0.0.1:8080/monitoring/health

curl http://127.0.0.1:8080/monitoring/info

curl http://127.0.0.1:8080/monitoring/beans
```

## AOP-Guarded Endpoint

`GET /aop-demo/secure-greeting` is protected by the custom `#[RequireCustomHeader]`
AOP attribute (`src/aop/RequireCustomHeader.php`, interceptor
`src/aop/RequireCustomHeaderInterceptor.php`). The interceptor runs before the
endpoint method and only lets the call through when the request carries the
header `X-Custom-Foo-Bar: foo-bar`; anything else is denied with `403` without
the method body executing:

```shell
# Missing header -> 403 Forbidden
curl -i http://127.0.0.1:8080/aop-demo/secure-greeting

# Wrong value -> 403 Forbidden
curl -i -H "X-Custom-Foo-Bar: wrong" http://127.0.0.1:8080/aop-demo/secure-greeting

# Correct value -> 200 OK
curl -i -H "X-Custom-Foo-Bar: foo-bar" http://127.0.0.1:8080/aop-demo/secure-greeting
```

Expected `403` body:

```json
{"success": false, "data": null, "error": "Forbidden: header \"X-Custom-Foo-Bar\" must be \"foo-bar\""}
```

Expected `200` body:

```json
{"success": true, "data": "Hello from the AOP-guarded endpoint!"}
```

To guard another endpoint, add an `HttpRequest` argument to the method and
annotate it — custom header name/value are optional parameters:

```php
#[GetMapping(path: "my-secure-route")]
#[RequireCustomHeader(headerName: "X-Custom-Foo-Bar", expectedValue: "foo-bar")]
public function myEndpoint(HttpRequest $request): array|ResponseEntity {
    // ...
}
```


## Performance / Memory-Leak Test

`./test-perf.sh` starts the service and sends batches of large JSON payloads
(16 KB to 4 MB by default) concurrently to `POST /perf/payload`, which decodes,
aggregates and re-encodes them, and returns a checksum plus the worker's memory figures.
After every batch it reads each worker's memory after a forced GC
(`GET /perf/stats?gc=1`) and the RSS of the whole server process tree.

It prints throughput and latency (min/avg/p50/p95/p99/max per size), memory for
each worker, and flags anomalies: errors or corrupted payloads, leaks (post-GC memory
rising batch after batch), RSS growth, worker restarts, latency degradation, tail
latency, oversized-request handling, errors in the app log, and processes that
survive a graceful shutdown. It exits non-zero on failures (`STRICT=1` also fails on warnings).

```shell
./test-perf.sh
BATCHES=20 REQS_PER_BATCH=100 CONCURRENCY=8 SIZES_KB="64 2048" ./test-perf.sh
```

All tunables are listed at the top of the script. `server.swoole.package_max_length`
is raised to 8 MB in `config/application.yml` (Swoole's default is 2 MB).

Even more things can be done with **[winter-modules](https://github.com/suvera/winter-modules)**.  Apache Kafka, Redis, S3 etc...
