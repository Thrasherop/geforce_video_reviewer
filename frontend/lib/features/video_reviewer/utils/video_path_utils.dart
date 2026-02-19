String extractFileName(String fullPath) {
  final String normalized = fullPath.replaceAll('\\', '/');
  final int index = normalized.lastIndexOf('/');
  if (index < 0 || index + 1 >= normalized.length) {
    return normalized;
  }
  return normalized.substring(index + 1);
}

String extractDirectoryPath(String fullPath) {
  if (fullPath.isEmpty) {
    return '';
  }
  final String normalized = fullPath.replaceAll('/', '\\');
  final int index = normalized.lastIndexOf('\\');
  if (index <= 0) {
    return '';
  }
  return normalized.substring(0, index);
}

String extractTitle(String fullPath) {
  final String fileName = extractFileName(fullPath);
  if (!fileName.toLowerCase().endsWith('.mp4')) {
    return fileName;
  }
  return fileName.substring(0, fileName.length - 4);
}
