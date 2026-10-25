<?php
$root = '/config';
$result = [];
$iter = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS), RecursiveIteratorIterator::SELF_FIRST);
foreach ($iter as $file) {
    $path = substr($file->getPathname(), strlen($root) + 1);
    $row = ['mode' => $file->getPerms() & 07777, 'uid' => $file->getOwner(), 'gid' => $file->getGroup()];
    if ($file->isLink()) { $row['link'] = readlink($file->getPathname()); }
    elseif ($file->isFile()) { $row['sha256'] = hash_file('sha256', $file->getPathname()); }
    elseif ($file->isDir()) { $row['directory'] = true; }
    else { throw new RuntimeException('Unsupported special file'); }
    $result[$path] = $row;
}
ksort($result);
echo json_encode($result, JSON_PRETTY_PRINT), "\n";
