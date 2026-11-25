import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

class LoadedPrintDocument {
  const LoadedPrintDocument({
    required this.name,
    required this.pages,
    required this.kind,
  });

  final String name;
  final List<Uint8List> pages;
  final String kind;
}

class PrintDocumentLoader {
  static Future<LoadedPrintDocument> fromPath(
    String path, {
    required int paperWidth,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', path);
    }
    final bytes = await file.readAsBytes();
    final extension = path.split('.').last.toLowerCase();

    if (['png', 'jpg', 'jpeg', 'bmp', 'gif', 'webp', 'tif', 'tiff']
        .contains(extension)) {
      return LoadedPrintDocument(
        name: _fileName(path),
        pages: [Uint8List.fromList(bytes)],
        kind: 'image',
      );
    }

    if (extension == 'pdf') {
      return _loadPdf(path, paperWidth);
    }

    if (['txt', 'csv', 'log'].contains(extension)) {
      final text = utf8.decode(bytes, allowMalformed: true);
      return LoadedPrintDocument(
        name: _fileName(path),
        pages: [await _renderText(text, paperWidth)],
        kind: 'text',
      );
    }

    throw FormatException('Unsupported file type: .$extension');
  }

  static Future<LoadedPrintDocument> _loadPdf(
    String path,
    int paperWidth,
  ) async {
    final document = await PdfDocument.openFile(path);
    final pages = <Uint8List>[];
    try {
      if (document.pagesCount < 1) {
        throw const FormatException('The PDF has no pages.');
      }
      if (document.pagesCount > 100) {
        throw const FormatException(
          'PDF files are limited to 100 pages per print job.',
        );
      }
      for (var number = 1; number <= document.pagesCount; number++) {
        final page = await document.getPage(number);
        try {
          final scale = paperWidth / page.width;
          final height = (page.height * scale).round().clamp(1, 4096);
          final rendered = await page.render(
            width: paperWidth,
            height: height,
            format: PdfPageImageFormat.png,
            backgroundColor: '#FFFFFF',
          );
          if (rendered == null) {
            throw FormatException('Could not render PDF page $number.');
          }
          pages.add(Uint8List.fromList(rendered.bytes));
        } finally {
          await page.close();
        }
      }
    } finally {
      await document.close();
    }
    return LoadedPrintDocument(
      name: _fileName(path),
      pages: pages,
      kind: 'pdf',
    );
  }

  static Future<Uint8List> _renderText(String value, int paperWidth) async {
    final rtl = RegExp(r'[\u0600-\u06FF]').hasMatch(value);
    final painter = TextPainter(
      text: TextSpan(
        text: value.isEmpty ? ' ' : value,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 18,
          height: 1.35,
          fontFamily: 'Segoe UI',
        ),
      ),
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
    )..layout(maxWidth: paperWidth - 32);

    final height = (painter.height.ceil() + 32).clamp(64, 4096);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    painter.paint(canvas, const Offset(16, 16));
    final picture = recorder.endRecording();
    final image = await picture.toImage(paperWidth, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final result = data!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
    painter.dispose();
    return Uint8List.fromList(result);
  }

  static String _fileName(String path) =>
      path.split(RegExp(r'[/\\]')).last;
}
