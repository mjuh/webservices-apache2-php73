<?php
$servername = "127.0.0.1";
$username = "old";
$password = "password123";

try {
    $conn = new PDO("mysql:host=$servername;dbname=oldpasswords", $username, $password);
    // set the PDO error mode to exception
    $conn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    echo "success connection";
    }
catch(PDOException $e)
    {
    echo "Connection failed: " . $e->getMessage();
    }
?> 
