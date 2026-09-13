<?php
declare(strict_types=1);

namespace dev\example\service\aop;

use dev\winterframework\core\aop\AopExecutionContext;
use dev\winterframework\exception\WinterException;
use dev\winterframework\stereotype\aop\AopContext;
use dev\winterframework\stereotype\aop\WinterAspect;
use dev\winterframework\util\log\Wlf4p;
use dev\winterframework\web\http\HttpRequest;
use dev\winterframework\web\http\HttpStatus;
use dev\winterframework\web\http\ResponseEntity;
use Throwable;

class RequireCustomHeaderInterceptor implements WinterAspect {
    use Wlf4p;

    public function begin(AopContext $ctx, AopExecutionContext $exCtx): void {
        /** @var RequireCustomHeader $stereo */
        $stereo = $ctx->getStereoType();

        self::logInfo(
            'Checking for header "' . $stereo->headerName
            . '" with expected value "' . $stereo->expectedValue
            . '" on method ' . $ctx->getMethod()->getName()
        );

        $request = $ctx->getApplicationContext()->getCurrentHttpRequest();
        if (!isset($request)) {
            throw new WinterException(
                '#[RequireCustomHeader] needs an HttpRequest argument on method '
                . $ctx->getMethod()->getName()
            );
        }

        $actual = $this->readHeader($request, $stereo->headerName);
        if ($actual !== $stereo->expectedValue) {
            self::logWarning(
                'Forbidden call to ' . $ctx->getMethod()->getName()
                . ': header "' . $stereo->headerName . '" must be "'
                . $stereo->expectedValue . '"'
            );
            $exCtx->stopExecution(
                ResponseEntity::status(HttpStatus::$FORBIDDEN)->withJson([
                    'success' => false,
                    'data' => null,
                    'error' => 'Forbidden: header "' . $stereo->headerName
                        . '" must be present with acceptable value'
                ])
            );
        }
    }

    public function beginFailed(
        AopContext $ctx,
        AopExecutionContext $exCtx,
        Throwable $ex
    ): void {
        self::logError(
            'RequireCustomHeader begin failed for ' . $ctx->getMethod()->getName()
            . ': ' . $ex->getMessage()
        );
    }

    public function commit(
        AopContext $ctx,
        AopExecutionContext $exCtx,
        mixed $result
    ): void {
        self::logInfo('RequireCustomHeader check passed for ' . $ctx->getMethod()->getName());
    }

    public function commitFailed(
        AopContext $ctx,
        AopExecutionContext $exCtx,
        mixed $result,
        Throwable $ex
    ): void {
        self::logError(
            'RequireCustomHeader commit failed for ' . $ctx->getMethod()->getName()
            . ': ' . $ex->getMessage()
        );
    }

    public function failed(
        AopContext $ctx,
        AopExecutionContext $exCtx,
        Throwable $ex
    ): void {
        self::logError(
            $ctx->getMethod()->getName() . ' failed: ' . $ex->getMessage()
        );
    }

    private function readHeader(HttpRequest $request, string $name): ?string {
        $value = $request->getFirstHeader($name);
        if (isset($value)) {
            return $value;
        }
        foreach ($request->getHeaders()->getAll() as $headerName => $values) {
            if (strcasecmp($headerName, $name) === 0) {
                return $values[0] ?? null;
            }
        }
        return null;
    }
}
