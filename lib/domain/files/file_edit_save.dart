import 'dart:convert';
import 'dart:io';

import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/files/binary_detect.dart';
import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/files/text_diff.dart';
import 'package:kelola/domain/probes/sftp_probe.dart';

const editorMaxBytes = 512 * 1024;

Future<void> saveEditedFile({
  required SftpPort sftp,
  required String remotePath,
  required File originalFile,
  required String editedText,
  required Future<bool> Function(String diff) confirmDiff,
}) async {
  final original = await originalFile.readAsString();
  final diff = unifiedDiff(original, editedText, path: remotePath);
  if (!await confirmDiff(diff)) {
    throw SaveAbortedException();
  }
  final editedFile = File('${originalFile.path}.edit');
  await editedFile.writeAsBytes(utf8.encode(editedText), flush: true);
  await SftpSaveProbe(
    remotePath: remotePath,
    originalLocalPath: originalFile.path,
    editedLocalPath: editedFile.path,
  ).run(sftp);
}

void guardTextEdit({required List<int> peek, required int size}) {
  prepareTextEdit(peek);
  if (size > editorMaxBytes) {
    throw FileTooLargeToEditException();
  }
}
