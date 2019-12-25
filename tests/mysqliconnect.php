
<?php
$link = mysqli_connect('127.0.0.1', 'old', 'password123');
if (!$link) {
    die('Error connection: ' . mysqli_connect_errno());
}
echo 'success connection';
mysqli_close($link);
?>

