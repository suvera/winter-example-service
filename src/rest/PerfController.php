<?php
declare(strict_types=1);

namespace dev\example\service\rest;

use dev\winterframework\stereotype\RestController;
use dev\winterframework\stereotype\web\GetMapping;
use dev\winterframework\stereotype\web\PostMapping;
use dev\winterframework\stereotype\web\RequestMapping;
use dev\winterframework\web\http\HttpRequest;
use dev\winterframework\web\http\ResponseEntity;

/**
 * Endpoints used by test-perf.sh to load the service with large payloads and
 * to watch per-worker memory between batches (leak detection).
 *
 * Every response carries a "worker" block with the Swoole worker's pid and
 * memory figures, so the caller can track each worker independently.
 */
#[RestController]
#[RequestMapping(path: "perf")]
class PerfController {

    /**
     * Requests served by this worker process. Swoole workers are long-lived,
     * so a static survives across requests (one counter per worker).
     */
    private static int $requests = 0;

    /**
     * Accepts a JSON document {"items": [{"id":..,"name":..,"value":..,"tags":[..]}, ...]},
     * does real work on it (decode, aggregate, sort, re-encode) and returns a summary.
     * "sha256" lets the caller verify the body arrived intact.
     */
    #[PostMapping(path: "payload")]
    public function payload(HttpRequest $request): array|ResponseEntity {
        self::$requests++;
        $start = hrtime(true);

        $raw = $request->getRawBody();
        try {
            $doc = json_decode($raw, true, 64, JSON_THROW_ON_ERROR);
        } catch (\JsonException $e) {
            return ResponseEntity::badRequest()->withJson([
                'success' => false,
                'error' => 'Invalid JSON: ' . $e->getMessage(),
                'worker' => self::workerStats(),
            ]);
        }

        $items = is_array($doc['items'] ?? null) ? $doc['items'] : [];
        $sum = 0.0;
        $tags = [];
        foreach ($items as $item) {
            $sum += (float)($item['value'] ?? 0);
            foreach ($item['tags'] ?? [] as $tag) {
                $tags[$tag] = ($tags[$tag] ?? 0) + 1;
            }
        }
        usort($items, fn($a, $b) => ($b['value'] ?? 0) <=> ($a['value'] ?? 0));
        $reEncodedBytes = strlen(json_encode($items));

        return [
            'success' => true,
            'bytes' => strlen($raw),
            'sha256' => hash('sha256', $raw),
            'items' => count($items),
            'valueSum' => round($sum, 4),
            'distinctTags' => count($tags),
            'reEncodedBytes' => $reEncodedBytes,
            'processingMs' => round((hrtime(true) - $start) / 1e6, 3),
            'worker' => self::workerStats(),
        ];
    }

    /**
     * Memory of whichever worker serves this call. With ?gc=1 a cycle
     * collection runs first, so the figure excludes collectable garbage.
     */
    #[GetMapping(path: "stats")]
    public function stats(HttpRequest $request): array {
        $collected = null;
        if ($request->getQueryParam('gc') === '1') {
            $collected = gc_collect_cycles();
        }
        return [
            'success' => true,
            'gcCollected' => $collected,
            'worker' => self::workerStats(),
        ];
    }

    private static function workerStats(): array {
        $gc = gc_status();
        return [
            'pid' => getmypid(),
            'requests' => self::$requests,
            'memUsage' => memory_get_usage(),
            'memReal' => memory_get_usage(true),
            'memPeak' => memory_get_peak_usage(),
            'gcRuns' => $gc['runs'],
            'gcCollected' => $gc['collected'],
            'memLimit' => self::memLimitBytes(),
        ];
    }

    /** memory_limit in bytes, -1 when unlimited. */
    private static function memLimitBytes(): int {
        $limit = trim((string)ini_get('memory_limit'));
        if ($limit === '' || $limit === '-1') {
            return -1;
        }
        $num = (int)$limit;
        return match (strtoupper(substr($limit, -1))) {
            'G' => $num * 1024 ** 3,
            'M' => $num * 1024 ** 2,
            'K' => $num * 1024,
            default => $num,
        };
    }
}
