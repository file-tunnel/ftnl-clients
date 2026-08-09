<?php

declare(strict_types=1);

namespace FileTunnel\Client;

use RuntimeException;

final class ApiException extends RuntimeException
{
    public function __construct(public readonly int $status, public readonly string $responseBody)
    {
        parent::__construct("File Tunnel API returned HTTP {$status}: {$responseBody}");
    }
}

final class Client
{
    public function __construct(private readonly string $baseUrl, private readonly ?string $token = null, private readonly int $timeoutSeconds = 30) {}

    public function request(string $method, string $path, mixed $body = null): mixed
    {
        $handle = curl_init(rtrim($this->baseUrl, '/') . '/' . ltrim($path, '/'));
        if ($handle === false) { throw new RuntimeException('Unable to initialize cURL'); }
        $headers = ['Accept: application/json'];
        if ($this->token !== null && $this->token !== '') { $headers[] = 'Authorization: Bearer ' . $this->token; }
        if ($body !== null) {
            $headers[] = 'Content-Type: application/json';
            curl_setopt($handle, CURLOPT_POSTFIELDS, json_encode($body, JSON_THROW_ON_ERROR));
        }
        curl_setopt_array($handle, [CURLOPT_CUSTOMREQUEST => strtoupper($method), CURLOPT_HTTPHEADER => $headers, CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => $this->timeoutSeconds]);
        $response = curl_exec($handle);
        if ($response === false) {
            $message = curl_error($handle);
            curl_close($handle);
            throw new RuntimeException($message);
        }
        $status = curl_getinfo($handle, CURLINFO_RESPONSE_CODE);
        curl_close($handle);
        if ($status < 200 || $status >= 300) { throw new ApiException($status, $response); }
        return $response === '' ? null : json_decode($response, true, flags: JSON_THROW_ON_ERROR);
    }

    public function health(): mixed
    {
        return $this->request('GET', '/health');
    }
}
