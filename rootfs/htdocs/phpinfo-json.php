<?php
function recode(&$item, $key) {
	$item = iconv('UTF-8','UTF-8//IGNORE', $item);
}
$extensions = get_loaded_extensions();
$data = array(
	"version" => phpversion(),
	"constants" => get_defined_constants(true),
	"ini" => ini_get_all(),
	"extensions" => $extensions,
	"extensionFuncs" => array(),
	"includedFiles" => get_included_files(),
);
foreach($extensions as $e) {
	$data['extensionFuncs'][$e] = get_extension_funcs($e);
}
array_walk_recursive($data, 'recode');
header("Content-Type: application/json");
echo json_encode($data);
