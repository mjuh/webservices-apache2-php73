
<?php
$link = mysql_connect('127.0.0.1', 'old', 'password123');
if (!$link) {
    die('Error connection: ' . mysql_error());
}
echo 'success connection';
mysql_close($link);
?>

