<?php

declare(strict_types=1);

printf("PHP %s (PHP_INT_SIZE=%d)\n", PHP_VERSION, PHP_INT_SIZE);

$extensions = ['curl', 'gd', 'intl', 'mbstring', 'openssl', 'pdo_sqlite', 'sodium', 'zip', 'imagick'];

foreach ($extensions as $extension) {
    printf("%-12s %s\n", $extension, extension_loaded($extension) ? 'loaded' : 'MISSING');
}

echo json_encode(['ok' => true, 'php' => PHP_VERSION]), "\n";