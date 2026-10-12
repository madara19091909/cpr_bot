class LevelDbException implements Exception {
  LevelDbException(this.message, {this.file, this.offset});
  final String message;
  final String? file;
  final int? offset;
  @override
  String toString() =>
      'LevelDbException: $message${file != null ? ' [$file' '${offset != null ? ' @$offset' : ''}]' : ''}';
}
