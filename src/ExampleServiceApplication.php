<?php

namespace dev\example\service;

use dev\winterframework\core\app\WinterWebSwooleApplication;
use dev\winterframework\stereotype\cache\EnableCaching;
use dev\winterframework\stereotype\task\EnableAsync;
use dev\winterframework\stereotype\task\EnableScheduling;
use dev\winterframework\stereotype\WinterBootApplication;

#[WinterBootApplication(
    configDirectory: [__DIR__ . "/../config"],
    scanNamespaces: [
        ['dev\\example\\service', __DIR__ . '']
    ]
)]
#[EnableCaching]
#[EnableAsync]
#[EnableScheduling]
class ExampleServiceApplication {

    public static function main(): void {
        $winterApp = new WinterWebSwooleApplication();
        $winterApp->run(self::class);
    }
}