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


Even more things can be done with **[winter-modules](https://github.com/suvera/winter-modules)**.  Apache Kafka, Redis, S3 etc...
