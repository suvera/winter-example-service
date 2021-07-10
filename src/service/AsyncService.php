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
        $url = 'https://www.php.net/manual/en/intro-whatcando.php';
        $data = file_get_contents($url);

        self::logInfo('Fetched ' . strlen($data) . ' bytes data from url ' . $url);
    }


    public function distributedTask(): string {
        $url = 'https://www.php.net/manual/en/intro-whatcando.php';
        $data = file_get_contents($url);
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
}