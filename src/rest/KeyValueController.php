<?php
declare(strict_types=1);

namespace dev\example\service\rest;

use dev\winterframework\io\kv\KvTemplate;
use dev\winterframework\stereotype\Autowired;
use dev\winterframework\stereotype\RestController;
use dev\winterframework\stereotype\web\DeleteMapping;
use dev\winterframework\stereotype\web\GetMapping;
use dev\winterframework\stereotype\web\PostMapping;
use dev\winterframework\stereotype\web\RequestMapping;
use dev\winterframework\stereotype\web\RequestParam;

#[RestController]
#[RequestMapping(path: "key-value")]
class KeyValueController {

    #[Autowired]
    protected KvTemplate $kvTemplate;

    #[GetMapping]
    public function get(#[RequestParam] string $key): array {
        return [
            'success' => true,
            'data' => $this->kvTemplate->get('kv-space', $key)
        ];
    }

    #[PostMapping]
    public function put(#[RequestParam] string $key, #[RequestParam] string $value): array {

        $this->kvTemplate->put('kv-space', $key, $value);

        return [
            'success' => true,
            'data' => 'SUCCESS'
        ];
    }

    #[DeleteMapping]
    public function delete(#[RequestParam] string $key): array {

        $this->kvTemplate->del('kv-space', $key);

        return [
            'success' => true,
            'data' => 'SUCCESS'
        ];
    }
}