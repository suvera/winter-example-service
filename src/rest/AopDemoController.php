<?php
declare(strict_types=1);

namespace dev\example\service\rest;

use dev\example\service\aop\RequireCustomHeader;
use dev\winterframework\stereotype\RestController;
use dev\winterframework\stereotype\web\GetMapping;
use dev\winterframework\stereotype\web\RequestMapping;
use dev\winterframework\web\http\HttpRequest;
use dev\winterframework\web\http\ResponseEntity;

/**
 * Demo endpoint for the custom #[RequireCustomHeader] AOP guard.
 */
#[RestController]
#[RequestMapping(path: "aop-demo")]
class AopDemoController {

    #[GetMapping(path: "secure-greeting")]
    #[RequireCustomHeader]
    public function secureGreeting(): array|ResponseEntity {
        file_put_contents('/tmp/aop-whoami.log', get_class($this) . "\n", FILE_APPEND);
        return [
            'success' => true,
            'data' => 'Hello from the AOP-guarded endpoint!'
        ];
    }
}
