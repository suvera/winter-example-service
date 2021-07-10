<?php
declare(strict_types=1);

namespace dev\example\service\rest;

use dev\example\service\service\AsyncService;
use dev\winterframework\stereotype\Autowired;
use dev\winterframework\stereotype\RestController;
use dev\winterframework\stereotype\web\GetMapping;

#[RestController]
class AsyncTaskController {

    #[Autowired]
    protected AsyncService $asyncService;

    #[GetMapping(path: "crawlAsync")]
    public function doAsync(): string {

        $this->asyncService->crawlAsync();

        return 'Your Request has been Accepted' . "\n";
    }


    #[GetMapping(path: "distributedJob")]
    public function doDistributed(): string {

        return $this->asyncService->distributedTask();
    }
}