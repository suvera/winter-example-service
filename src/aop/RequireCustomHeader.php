<?php
declare(strict_types=1);

namespace dev\example\service\aop;

use Attribute;
use dev\winterframework\reflection\ref\RefMethod;
use dev\winterframework\reflection\support\StereoTypeValidations;
use dev\winterframework\stereotype\StereoTyped;
use dev\winterframework\stereotype\aop\AopStereoType;
use dev\winterframework\stereotype\aop\WinterAspect;
use dev\winterframework\type\TypeAssert;

/**
 * Guards a controller endpoint by requiring an HTTP header with an
 * expected value. Requests carrying any other value (or no value)
 * are denied with a 403 response before the method body runs.
 *
 * The guarded endpoint must declare an HttpRequest argument so the
 * interceptor can read the incoming headers.
 */
#[Attribute(Attribute::TARGET_METHOD)]
#[StereoTyped]
class RequireCustomHeader implements AopStereoType {
    use StereoTypeValidations;

    private ?RequireCustomHeaderInterceptor $interceptor = null;

    public function __construct(
        public string $headerName = 'X-Custom-Foo-Bar',
        public string $expectedValue = 'foo-bar'
    ) {
    }

    public function isPerInstance(): bool {
        return false; // shared stateless interceptor
    }

    public function getAspect(): WinterAspect {
        if (!isset($this->interceptor)) {
            $this->interceptor = new RequireCustomHeaderInterceptor();
        }
        return $this->interceptor;
    }

    public function init(object $ref): void {
        /** @var RefMethod $ref */
        TypeAssert::typeOf($ref, RefMethod::class);
        $this->validateAopMethod($ref, 'RequireCustomHeader');
    }
}
