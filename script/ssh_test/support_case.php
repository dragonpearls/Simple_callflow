<?php

echo "Start:";
$serv = new Swoole\Server("0.0.0.0", 9501);
$serv->on('connect', function ($serv, $fd) {
    echo "Client: Connect.\n";
});

$serv->on('Receive', function ($serv, $fd, $from_id, $data) {
    var_dump($data);
    if (strpos($data, "ssh") === 0) {
       echo "ssh\n";
    }
    $serv->send($fd, "Server");
    $serv->close($fd);
});

$serv->on('Close', function ($serv, $fd) {
    echo "close\n";
});

$serv->start();
