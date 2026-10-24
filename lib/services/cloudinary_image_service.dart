import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class CloudinaryImageService {
  static final http.Client _sharedClient = http.Client();

  CloudinaryImageService({
    http.Client? client,
    String cloudName = const String.fromEnvironment(
      'CLOUDINARY_CLOUD_NAME',
      defaultValue: 'be4i3h7e',
    ),
    String uploadPreset = const String.fromEnvironment(
      'CLOUDINARY_UPLOAD_PRESET',
      defaultValue: 'campusplus_preset',
    ),
  })  : _client = client ?? _sharedClient,
        _cloudName = cloudName,
        _uploadPreset = uploadPreset;

  final http.Client _client;
  final String _cloudName;
  final String _uploadPreset;

  String get cloudName => _cloudName;

  Future<String> uploadImage({
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    _validateConfiguration();
    final extension = _validateImage(bytes, fileName, contentType);
    final endpoint = Uri.https(
      'api.cloudinary.com',
      '/v1_1/$_cloudName/image/upload',
    );
    final request = http.MultipartRequest('POST', endpoint)
      ..fields['upload_preset'] = _uploadPreset
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: 'campusplus.$extension',
        ),
      );

    final streamedResponse =
        await _client.send(request).timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(
      streamedResponse,
    ).timeout(const Duration(seconds: 30));
    final decoded = _decodeResponse(response.body);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded is Map ? decoded['error'] : null;
      final message = error is Map ? error['message'] : null;
      throw CloudinaryUploadException(
        message is String && message.isNotEmpty
            ? message
            : 'Cloudinary upload failed (HTTP ${response.statusCode}).',
      );
    }

    if (decoded is! Map || decoded['secure_url'] is! String) {
      throw const CloudinaryUploadException(
        'Cloudinary returned an invalid upload response.',
      );
    }
    final secureUrl = Uri.tryParse(decoded['secure_url'] as String);
    if (secureUrl == null ||
        secureUrl.scheme != 'https' ||
        secureUrl.host != 'res.cloudinary.com' ||
        !secureUrl.path.startsWith('/$_cloudName/image/upload/')) {
      throw const CloudinaryUploadException(
        'Cloudinary returned an unexpected image URL.',
      );
    }
    return secureUrl.toString();
  }

  void _validateConfiguration() {
    final validCloudName = RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(_cloudName);
    final validPreset = RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(_uploadPreset);
    if (!validCloudName || !validPreset) {
      throw const CloudinaryUploadException(
        'Photo uploads are not configured. Set CLOUDINARY_CLOUD_NAME and CLOUDINARY_UPLOAD_PRESET.',
      );
    }
  }

  String _validateImage(
    Uint8List bytes,
    String fileName,
    String contentType,
  ) {
    if (bytes.isEmpty || bytes.lengthInBytes > 5 * 1024 * 1024) {
      throw const CloudinaryUploadException(
        'Choose an image smaller than 5 MB.',
      );
    }
    final extension = fileName.split('.').last.toLowerCase();
    const allowedTypes = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
    };
    if (allowedTypes[extension] != contentType) {
      throw const CloudinaryUploadException(
        'Choose a JPG, PNG, or WebP image.',
      );
    }
    return extension;
  }

  Object? _decodeResponse(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
}

class CloudinaryUploadException implements Exception {
  const CloudinaryUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}
