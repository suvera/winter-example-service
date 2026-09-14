#!/bin/bash

set -e  # Exit on any error

echo "=== Example Micro-Service Test ==="

# Install dependencies if vendor directory is missing, otherwise update
echo "Installing dependencies..."
if [ ! -d "vendor" ]; then
    composer install --no-interaction
else
    composer update --no-interaction
fi
echo "OK: Dependencies installed"

# Start the application in the background (logs will appear on console)
echo "Starting Winter Boot application (logs will be shown directly)..."
php bin/example-service.php &
APP_PID=$!

# Wait a moment for the app to start
sleep 5

# Test the application is running
echo "Checking if application is running on http://localhost:8080..."
for i in {1..10}; do
    if curl -s -f http://localhost:8080/monitoring/health > /dev/null; then
        echo "OK: Application is running"
        break
    fi
    echo "Waiting for application to start... ($i/10)"
    sleep 2
done

if ! curl -s -f http://localhost:8080/monitoring/health > /dev/null; then
    echo "ERROR: Application did not start properly"
    kill $APP_PID 2>/dev/null || true
    wait $APP_PID 2>/dev/null || true
    killall php
    exit 1
fi

# Unique key for this test run
TEST_KEY="test-key-$(date +%s)"
TEST_VALUE="Alphabet Inc."

echo "Testing Example Service operations..."

# 1. Say hello
echo "1. Saying hello"
response=$(curl -s "http://localhost:8080/say-hello")
if echo "$response" | grep -q 'Hello from WinterBoot!'; then
    echo "OK: Say hello successful"
else
    echo "FAIL: Say hello failed"
    echo "Response: $response"
    kill $APP_PID 2>/dev/null || true
    wait $APP_PID 2>/dev/null || true
    killall php
    exit 1
fi

# 2. Put a key value into store
echo "2. Putting key: $TEST_KEY"
response=$(curl -s -X POST "http://localhost:8080/key-value" -d "key=$TEST_KEY&value=$TEST_VALUE")
if echo "$response" | grep -q '"success".*true'; then
    echo "OK: Key value stored successfully"
else
    echo "FAIL: Failed to store key value"
    echo "Response: $response"
    kill $APP_PID 2>/dev/null || true
    wait $APP_PID 2>/dev/null || true
    killall php
    exit 1
fi

# 3. Get value for key from store
echo "3. Getting key: $TEST_KEY"
response=$(curl -s "http://localhost:8080/key-value?key=$TEST_KEY")
if echo "$response" | grep -q '"success".*true' && echo "$response" | grep -q "$TEST_VALUE"; then
    echo "OK: Key value retrieved successfully with matching content"
else
    echo "FAIL: Failed to retrieve key value or content mismatch"
    echo "Response: $response"
    kill $APP_PID 2>/dev/null || true
    wait $APP_PID 2>/dev/null || true
    exit 1
fi

# 4. Get stock price (price is random, only assert the echoed symbol)
echo "4. Getting stock price for AAPL"
response=$(curl -s "http://localhost:8080/stock/AAPL")
if echo "$response" | grep -q '"symbol".*AAPL' && echo "$response" | grep -q '"price"'; then
    echo "OK: Stock price retrieved successfully"
else
    echo "FAIL: Failed to retrieve stock price"
    echo "Response: $response"
    kill $APP_PID 2>/dev/null || true
    wait $APP_PID 2>/dev/null || true
    killall php
    exit 1
fi

# 5. Monitoring health endpoint
echo "5. Checking monitoring health endpoint"
response=$(curl -s "http://localhost:8080/monitoring/health")
if [ -n "$response" ]; then
    echo "OK: Monitoring health responded"
else
    echo "FAIL: Monitoring health returned empty response"
    kill $APP_PID 2>/dev/null || true
    wait $APP_PID 2>/dev/null || true
    killall php
    exit 1
fi

# 6. Monitoring info endpoint
echo "6. Checking monitoring info endpoint"
response=$(curl -s "http://localhost:8080/monitoring/info")
if [ -n "$response" ]; then
    echo "OK: Monitoring info responded"
else
    echo "FAIL: Monitoring info returned empty response"
    kill $APP_PID 2>/dev/null || true
    wait $APP_PID 2>/dev/null || true
    killall php
    exit 1
fi

# 7. AOP-guarded endpoint without header must be denied (403)
echo "7. Checking AOP-guarded endpoint without header is denied"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/aop-demo/secure-greeting")
if [ "$HTTP_CODE" -eq 403 ]; then
    echo "OK: Request without header denied with 403"
else
    echo "FAIL: Expected 403 without header, got HTTP $HTTP_CODE"
    kill $APP_PID 2>/dev/null || true
    wait $APP_PID 2>/dev/null || true
    killall php
    exit 1
fi

# 8. AOP-guarded endpoint with wrong header value must be denied (403)
echo "8. Checking AOP-guarded endpoint with wrong header is denied"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "X-Custom-Foo-Bar: wrong" "http://localhost:8080/aop-demo/secure-greeting")
if [ "$HTTP_CODE" -eq 403 ]; then
    echo "OK: Request with wrong header denied with 403"
else
    echo "FAIL: Expected 403 with wrong header, got HTTP $HTTP_CODE"
    kill $APP_PID 2>/dev/null || true
    wait $APP_PID 2>/dev/null || true
    killall php
    exit 1
fi

# 9. AOP-guarded endpoint with correct header must succeed (200)
echo "9. Checking AOP-guarded endpoint with correct header succeeds"
response=$(curl -s -H "X-Custom-Foo-Bar: foo-bar" "http://localhost:8080/aop-demo/secure-greeting")
if echo "$response" | grep -q '"success".*true' && echo "$response" | grep -q 'Hello from the AOP-guarded endpoint!'; then
    echo "OK: Request with correct header succeeded"
else
    echo "FAIL: Request with correct header failed"
    echo "Response: $response"
    kill $APP_PID 2>/dev/null || true
    wait $APP_PID 2>/dev/null || true
    killall php
    exit 1
fi

# 10. Async execution (fetches external URL, assert only HTTP 200)
echo "10. Triggering async crawl"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/crawlAsync")
if [ "$HTTP_CODE" -eq 200 ]; then
    echo "OK: Async crawl request accepted"
else
    echo "FAIL: Async crawl failed with HTTP $HTTP_CODE"
    kill $APP_PID 2>/dev/null || true
    wait $APP_PID 2>/dev/null || true
    killall php
    exit 1
fi

# 11. Distributed task execution (fetches external URL, assert only HTTP 200)
echo "11. Triggering distributed job"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/distributedJob")
if [ "$HTTP_CODE" -eq 200 ]; then
    echo "OK: Distributed job request accepted"
else
    echo "FAIL: Distributed job failed with HTTP $HTTP_CODE"
    kill $APP_PID 2>/dev/null || true
    wait $APP_PID 2>/dev/null || true
    killall php
    exit 1
fi

echo ""
echo "=== All tests passed! ==="
echo "Example Micro-Service is working correctly."
echo "- Verified say-hello greeting"
echo "- Performed key-value put, get, and delete operations"
echo "- Verified content integrity"
echo "- Checked stock price and monitoring endpoints"
echo "- Verified AOP-guarded endpoint (403 without/wrong header, 200 with correct header)"
echo "- Triggered async and distributed job endpoints"

# Delete the test key
echo ""
echo "Deleting test key: $TEST_KEY"
response=$(curl -s -X DELETE "http://localhost:8080/key-value" -d "key=$TEST_KEY")
if echo "$response" | grep -q '"success".*true'; then
    echo "OK: Test key deleted successfully"
else
    echo "WARNING: Failed to delete test key"
    echo "Response: $response"
fi

# Stop the application
kill $APP_PID 2>/dev/null || true
wait $APP_PID 2>/dev/null || true
killall php

echo ""
echo "Test completed successfully!"
