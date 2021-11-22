# Example micro-service developed using Winter Boot

This is example micro-service, developed using **[winter-boot](https://github.com/suvera/winter-boot)**

## Start Application

Update Library dependencies

```shell
composer update
```

Use one of the way to start application as listed below

### 1. Build **Phar** binary with phing, and start service

```shell
./vendor/bin/phing clean phar

# Start service
php target/phar/example-service-1.0.0-dev.phar -c "$(realpath ./config)"
```

### 2. (OR) Simply run this command

```shell
php bin/example-service.php
```

### 3. (OR) Using Docker Image

```shell
# Build Docker Image
./vendor/bin/phing clean docker

# Start Container, so service starts
docker run -d -p 8080:8080 --name example-service demoapp/example-service:1.0.0-dev
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


Even more things can be done with **[winter-modules](https://github.com/suvera/winter-modules)**.  Apache Kafka, Redis, S3 etc...
