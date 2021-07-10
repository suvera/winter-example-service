<?php
declare(strict_types=1);

namespace dev\example\service\rest;

use dev\example\service\service\StockService;
use dev\winterframework\stereotype\Autowired;
use dev\winterframework\stereotype\RestController;
use dev\winterframework\stereotype\web\GetMapping;
use dev\winterframework\stereotype\web\PathVariable;

#[RestController]
class StockController {

    #[Autowired]
    protected StockService $stockService;

    #[GetMapping(path: "stock/{symbol}")]
    public function get(#[PathVariable] string $symbol): array {
        return [
            'symbol' => $symbol,
            'price' => $this->stockService->getPrice($symbol)
        ];
    }
}