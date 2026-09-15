import 'dart:io';

final class RecoverableFile {
  RecoverableFile(this.file);

  final File file;

  File get temporary => File('${file.path}.tmp');

  File get backup => File('${file.path}.bak');

  Future<String?> readString() async {
    final candidates = await readCandidates();
    return candidates.isEmpty ? null : candidates.first;
  }

  Future<List<String>> readCandidates() async {
    final contents = <String>[];
    for (final candidate in <File>[file, backup]) {
      if (!await candidate.exists()) continue;
      try {
        contents.add(await candidate.readAsString());
      } on FileSystemException {
        continue;
      }
    }
    return List<String>.unmodifiable(contents);
  }

  Future<void> replaceWithString(String contents) async {
    await file.parent.create(recursive: true);
    await _recoverBackupIfNeeded();

    final temporaryFile = temporary;
    if (await temporaryFile.exists()) await temporaryFile.delete();
    await temporaryFile.writeAsString(contents, flush: true);

    final backupFile = backup;
    if (await backupFile.exists()) await backupFile.delete();
    if (await file.exists()) await file.rename(backupFile.path);

    try {
      await temporaryFile.rename(file.path);
      if (await backupFile.exists()) await backupFile.delete();
    } catch (error, stackTrace) {
      if (!await file.exists() && await backupFile.exists()) {
        await backupFile.rename(file.path);
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      if (await temporaryFile.exists()) await temporaryFile.delete();
    }
  }

  Future<void> clear() async {
    for (final candidate in <File>[backup, temporary, file]) {
      if (await candidate.exists()) await candidate.delete();
    }
  }

  Future<void> _recoverBackupIfNeeded() async {
    final backupFile = backup;
    if (await file.exists() || !await backupFile.exists()) return;
    await backupFile.rename(file.path);
  }
}
