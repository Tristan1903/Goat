extension StringCasingExtension on String {
  String toTitleCase() {
    if (isEmpty) return this;
    return replaceAll(RegExp(' +'), ' ')
        .split(' ')
        .map((word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}'
            : '')
        .join(' ');
  }
}