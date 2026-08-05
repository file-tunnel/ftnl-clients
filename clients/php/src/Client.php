<?php
declare(strict_types=1);
namespace ZedPkg\Ftnl;
final readonly class Client {
    public function __construct(public string $baseUrl, public ?string $bearerToken = null) {}
}
