<?php
declare(strict_types=1);

namespace dev\example\service\service;

use dev\winterframework\dtce\task\service\TaskExecutionServiceFactory;
use dev\winterframework\stereotype\Autowired;
use dev\winterframework\stereotype\Service;
use dev\winterframework\task\async\stereotype\Async;
use dev\winterframework\util\log\Wlf4p;

#[Service]
class AsyncService {
    use Wlf4p;

    #[Autowired]
    private TaskExecutionServiceFactory $factory;

    #[Async]
    public function crawlAsync(): void {
        $url = 'https://go.dev/doc/tutorial/getting-started';
        $data = $this->fetchUrl($url);
        if ($data === null) {
            self::logError("Failed to fetch data from {$url}");
            return;
        }

        self::logInfo('Fetched ' . strlen($data) . ' bytes data from url ' . $url);
    }

    public function distributedTask(): string {
        $url = 'https://go.dev/doc/modules/managing-dependencies';
        $data = $this->fetchUrl($url);
        if ($data === null) {
            self::logError("Failed to fetch data for distributedTask from {$url}");
            return '';
        }
        $data = strip_tags($data);

        $executor = $this->factory->executionService('wordCount');
        $job = $executor->newJob();

        $tasks = [];
        for ($i = 0; $i < strlen($data);) {
            $tasks[] = substr($data, $i, 300);
            $i += 300;
        }

        $job->addTasks(...$tasks);
        $res = $executor->executeJob($job);

        $str = '';
        foreach ($res->getResults() as $index => $result) {
            if ($result->isSuccess()) {
                $tres = $result->getResult();
                $str .= "Distributed Task - $index SUCCESS:  WordCount=" . print_r($tres->get(), true) . "\n";
            } else {
                $str .= "Distributed Task - $index FAILED\n";
            }
        }
        return $str . "\n";
    }

    /**
     * Safely fetch a URL.
     * Returns the response body as string or null on failure.
     */
    private function fetchUrl(string $url): ?string {
        // Prefer cURL if available for better error handling.
        if (function_exists('curl_init')) {
            $ch = curl_init($url);
            curl_setopt_array($ch, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_FOLLOWLOCATION => true,
                CURLOPT_TIMEOUT => 10,
                CURLOPT_FAILONERROR => true,
            ]);
            $data = curl_exec($ch);
            $err = curl_error($ch);
            curl_close($ch);
            if ($err !== '' || $data === false) {
                return null;
            }
            return $data;
        }
        // Fallback to file_get_contents with suppressed warnings.
        $data = @file_get_contents($url);
        return $data !== false ? $data : null;
    }
}
