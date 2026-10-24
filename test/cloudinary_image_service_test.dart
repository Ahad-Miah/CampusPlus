import 'dart:convert';
import 'dart:typed_data';

import 'package:campus_plus/services/cloudinary_image_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final imageBytes = Uint8List.fromList(utf8.encode('test image bytes'));

  test('uploads an image using an unsigned preset and returns secure URL', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://api.cloudinary.com/v1_1/campus-demo/image/upload',
      );
      expect(request.headers['content-type'], startsWith('multipart/form-data'));
      expect(request.body, contains('upload_preset'));
      expect(request.body, contains('campusplus_unsigned'));
      expect(request.body, contains('campusplus.jpg'));
      return http.Response(
        jsonEncode({
          'secure_url':
              'https://res.cloudinary.com/campus-demo/image/upload/v1/campusplus.jpg',
        }),
        200,
      );
    });

    final service = CloudinaryImageService(
      client: client,
      cloudName: 'campus-demo',
      uploadPreset: 'campusplus_unsigned',
    );

    await expectLater(
      service.uploadImage(
        bytes: imageBytes,
        fileName: 'report.jpg',
        contentType: 'image/jpeg',
      ),
      completion(
        'https://res.cloudinary.com/campus-demo/image/upload/v1/campusplus.jpg',
      ),
    );
    client.close();
  });

  test('surfaces Cloudinary upload errors', () async {
    final client = MockClient((request) async => http.Response(
          jsonEncode({
            'error': {'message': 'Upload preset is invalid'},
          }),
          400,
        ));
    final service = CloudinaryImageService(
      client: client,
      cloudName: 'campus-demo',
      uploadPreset: 'campusplus_unsigned',
    );

    await expectLater(
      service.uploadImage(
        bytes: imageBytes,
        fileName: 'report.jpg',
        contentType: 'image/jpeg',
      ),
      throwsA(
        isA<CloudinaryUploadException>().having(
          (error) => error.message,
          'message',
          'Upload preset is invalid',
        ),
      ),
    );
    client.close();
  });

  test('rejects images with a mismatched content type before network access', () async {
    final service = CloudinaryImageService(
      client: MockClient(
        (request) async => throw StateError('Unexpected request'),
      ),
      cloudName: 'campus-demo',
      uploadPreset: 'campusplus_unsigned',
    );

    await expectLater(
      service.uploadImage(
        bytes: imageBytes,
        fileName: 'report.jpg',
        contentType: 'image/png',
      ),
      throwsA(isA<CloudinaryUploadException>()),
    );
  });

  test('reports when Cloudinary configuration is missing', () async {
    final service = CloudinaryImageService(
      client: MockClient(
        (request) async => throw StateError('Unexpected request'),
      ),
      cloudName: '',
      uploadPreset: '',
    );

    await expectLater(
      service.uploadImage(
        bytes: imageBytes,
        fileName: 'report.jpg',
        contentType: 'image/jpeg',
      ),
      throwsA(isA<CloudinaryUploadException>()),
    );
  });
}
