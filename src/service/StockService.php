<?php
declare(strict_types=1);

namespace dev\example\service\service;

use dev\winterframework\cache\stereotype\Cacheable;
use dev\winterframework\stereotype\Service;

#[Service]
class StockService {

    #[Cacheable]
    public function getPrice(string $symbol): string {
        return '$' . mt_rand(1, 1000) . '.' . mt_rand(10, 99);
    }
}