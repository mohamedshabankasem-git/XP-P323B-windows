import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// One monochrome raster image, packed MSB-first as required by ESC/POS.
class ThermalRaster {
  const ThermalRaster({
    required this.widthBytes,
    required this.height,
    required this.data,
  });

  final int widthBytes;
  final int height;
  final List<int> data;
}

/// Image-to-ESC/POS Raster conversion shared by preview and physical printing.
///
/// Paper widths are expressed in print-head dots: 384, 400, or 576.
/// Alignment is applied to the raster bytes in software; ESC/POS justification
/// remains left so that the printer does not apply a second alignment offset.
class RasterPrint {
  static const int maxWidthDots = 576;
  static const int maxHeightDots = 4096;

  static ThermalRaster imageToRaster(
    List<int> encodedImage, {
    int maxWidth = maxWidthDots,
    int maxHeight = maxHeightDots,
    int threshold = 160,
    String mode = 'floydSteinberg',
  }) {
    if (maxWidth < 8 || maxWidth > maxWidthDots || maxHeight < 1) {
      throw ArgumentError('Invalid raster dimensions.');
    }
    final decoded = img.decodeImage(Uint8List.fromList(encodedImage));
    if (decoded == null) {
      throw const FormatException('Unsupported or damaged image.');
    }
    return _decodedToRaster(
      decoded,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      threshold: threshold,
      mode: mode,
    );
  }

  static ThermalRaster _decodedToRaster(
    img.Image decoded, {
    required int maxWidth,
    required int maxHeight,
    required int threshold,
    required String mode,
  }) {
    if (threshold < 0 || threshold > 255) {
      throw ArgumentError.value(threshold, 'threshold');
    }
    final scale = math.min(
      1.0,
      math.min(maxWidth / decoded.width, maxHeight / decoded.height),
    );
    final width = math.max(1, (decoded.width * scale).floor()).toInt();
    final height = math.max(1, (decoded.height * scale).floor()).toInt();
    final raster = (width == decoded.width && height == decoded.height)
        ? decoded
        : img.copyResize(
            decoded,
            width: width,
            height: height,
            interpolation: img.Interpolation.average,
          );

    final bytesPerRow = (raster.width + 7) ~/ 8;
    final packed = List<int>.filled(bytesPerRow * raster.height, 0);
    final luminance = List<double>.filled(raster.width * raster.height, 255);
    for (var y = 0; y < raster.height; y++) {
      for (var x = 0; x < raster.width; x++) {
        final pixel = raster.getPixel(x, y);
        final alpha = pixel.a.toDouble() / 255.0;
        final red = pixel.r.toDouble() * alpha + 255 * (1 - alpha);
        final green = pixel.g.toDouble() * alpha + 255 * (1 - alpha);
        final blue = pixel.b.toDouble() * alpha + 255 * (1 - alpha);
        luminance[y * raster.width + x] =
            0.299 * red + 0.587 * green + 0.114 * blue;
      }
    }

    const ordered = [
      [0, 8, 2, 10],
      [12, 4, 14, 6],
      [3, 11, 1, 9],
      [15, 7, 13, 5],
    ];

    void setBlack(int x, int y) {
      packed[y * bytesPerRow + (x ~/ 8)] |= 0x80 >> (x % 8);
    }

    if (mode == 'floydSteinberg' || mode == 'atkinson') {
      for (var y = 0; y < raster.height; y++) {
        for (var x = 0; x < raster.width; x++) {
          final index = y * raster.width + x;
          final old = luminance[index].clamp(0.0, 255.0).toDouble();
          final next = old < threshold ? 0.0 : 255.0;
          if (next == 0) setBlack(x, y);
          final error = old - next;

          void add(int dx, int dy, double factor) {
            final nx = x + dx;
            final ny = y + dy;
            if (nx >= 0 && nx < raster.width &&
                ny >= 0 && ny < raster.height) {
              luminance[ny * raster.width + nx] += error * factor;
            }
          }

          if (mode == 'floydSteinberg') {
            add(1, 0, 7 / 16);
            add(-1, 1, 3 / 16);
            add(0, 1, 5 / 16);
            add(1, 1, 1 / 16);
          } else {
            add(1, 0, 1 / 8);
            add(2, 0, 1 / 8);
            add(-1, 1, 1 / 8);
            add(0, 1, 1 / 8);
            add(1, 1, 1 / 8);
            add(0, 2, 1 / 8);
          }
        }
      }
    } else {
      for (var y = 0; y < raster.height; y++) {
        for (var x = 0; x < raster.width; x++) {
          final value = luminance[y * raster.width + x];
          final cutoff = mode == 'ordered'
              ? (ordered[y % 4][x % 4] * 16 + 8).toDouble()
              : threshold.toDouble();
          if (value < cutoff) setBlack(x, y);
        }
      }
    }

    return ThermalRaster(
      widthBytes: bytesPerRow,
      height: raster.height,
      data: packed,
    );
  }

  static ThermalRaster alignRaster(
    ThermalRaster source, {
    required int paperWidth,
    required String alignment,
  }) {
    if (paperWidth < 8 || paperWidth > maxWidthDots) {
      throw ArgumentError.value(paperWidth, 'paperWidth');
    }
    final widthBytes = (paperWidth + 7) ~/ 8;
    final sourceWidth = source.widthBytes * 8;
    final contentWidth = math.min(sourceWidth, paperWidth);
    final offset = switch (alignment) {
      'right' => paperWidth - contentWidth,
      'center' => (paperWidth - contentWidth) ~/ 2,
      _ => 0,
    };
    final data = List<int>.filled(widthBytes * source.height, 0);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < contentWidth; x++) {
        final byte = source.data[y * source.widthBytes + (x ~/ 8)];
        if ((byte & (0x80 >> (x % 8))) != 0) {
          final targetX = x + offset;
          data[y * widthBytes + (targetX ~/ 8)] |= 0x80 >> (targetX % 8);
        }
      }
    }
    return ThermalRaster(widthBytes: widthBytes, height: source.height, data: data);
  }

  static Uint8List imageToPreviewPng(
    List<int> encodedImage, {
    required int maxWidth,
    required String alignment,
    String mode = 'floydSteinberg',
  }) {
    final source = imageToRaster(
      encodedImage,
      maxWidth: maxWidth,
      mode: mode,
    );
    final raster = alignRaster(
      source,
      paperWidth: maxWidth,
      alignment: alignment,
    );
    final paper = img.Image(width: maxWidth, height: raster.height);
    img.fill(paper, color: img.ColorRgb8(255, 255, 255));
    for (var y = 0; y < raster.height; y++) {
      for (var x = 0; x < maxWidth; x++) {
        final byte = raster.data[y * raster.widthBytes + (x ~/ 8)];
        if ((byte & (0x80 >> (x % 8))) != 0) {
          paper.setPixelRgb(x, y, 0, 0, 0);
        }
      }
    }
    return Uint8List.fromList(img.encodePng(paper));
  }

  static List<int> imageToEscPos(
    List<int> encodedImage, {
    int threshold = 160,
    int maxWidth = maxWidthDots,
    String alignment = 'left',
    String mode = 'floydSteinberg',
    bool feedAfterPrint = true,
  }) {
    final source = imageToRaster(
      encodedImage,
      maxWidth: maxWidth,
      threshold: threshold,
      mode: mode,
    );
    final raster = alignRaster(
      source,
      paperWidth: maxWidth,
      alignment: alignment,
    );
    return <int>[
      0x1B, 0x40, // Initialize printer.
      0x1B, 0x61, 0x00, // Software alignment: keep printer justification left.
      0x1D, 0x76, 0x30, 0x00, // GS v 0: raster bit image.
      raster.widthBytes & 0xFF,
      (raster.widthBytes >> 8) & 0xFF,
      raster.height & 0xFF,
      (raster.height >> 8) & 0xFF,
      ...raster.data,
      if (feedAfterPrint) ...<int>[0x0A, 0x0A],
      0x1B, 0x61, 0x00, // Reset justification.
    ];
  }

  static Future<List<int>> imageToEscPosAsync(
    List<int> encodedImage, {
    int threshold = 160,
    int maxWidth = maxWidthDots,
    String alignment = 'left',
    String mode = 'floydSteinberg',
  }) {
    return compute(_imageToEscPosWorker, <String, Object>{
      'bytes': Uint8List.fromList(encodedImage),
      'threshold': threshold,
      'maxWidth': maxWidth,
      'alignment': alignment,
      'mode': mode,
    });
  }
}

List<int> _imageToEscPosWorker(Map<String, Object> args) {
  return RasterPrint.imageToEscPos(
    args['bytes']! as Uint8List,
    threshold: args['threshold']! as int,
    maxWidth: args['maxWidth']! as int,
    alignment: args['alignment']! as String,
    mode: args['mode']! as String,
  );
}
