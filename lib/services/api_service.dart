import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:http_parser/http_parser.dart';

class ApiService {
  // Use different base URLs depending on platform
  // 10.0.2.2 is the special IP for Android emulator to access host machine
  static String get baseUrl {
    if (kIsWeb) {
      return 'http://localhost:8000/api';
    } else if (Platform.isAndroid) {
      return 'http://10.0.2.2:8000/api';
    } else {
      return 'http://localhost:8000/api';
    }
  }

  // Server URL without /api path for accessing media files
  static String get serverBaseUrl {
    if (kIsWeb) {
      return 'http://localhost:8000';
    } else if (Platform.isAndroid) {
      return 'http://10.0.2.2:8000';
    } else {
      return 'http://localhost:8000';
    }
  }

  final logger = Logger();

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  Future<bool> isServerReachable() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/chat-history/'), headers: _headers)
          .timeout(const Duration(seconds: 5));

      return response.statusCode != 502 &&
          response.statusCode != 503 &&
          response.statusCode != 504;
    } catch (e) {
      logger.e('Server not reachable: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> sendMessage(
    String message, {
    File? image,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/chat/');

      // Use MultipartRequest for all platforms
      var request = http.MultipartRequest('POST', uri);
      request.fields['prompt'] = message;

      if (image != null) {
        try {
          String filename = image.path.split('/').last;
          String extension = filename.split('.').last.toLowerCase();

          // Determine content type based on file extension
          String contentType = 'image/jpeg';
          if (extension == 'png') {
            contentType = 'image/png';
          }

          var multipartFile = await http.MultipartFile.fromPath(
            'image',
            image.path,
            contentType: MediaType.parse(contentType),
          );
          request.files.add(multipartFile);

          logger.d('Added image to request: $filename');
        } catch (e) {
          logger.e('Error adding image to request: $e');
          throw Exception('Failed to process image: $e');
        }
      }

      var streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );

      var response = await http.Response.fromStream(streamedResponse);
      logger.d('Message response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to send message: ${response.body}');
      }
    } on TimeoutException {
      logger.e('Request timed out');
      throw Exception('Request timed out. Please try again.');
    } catch (e) {
      logger.e('Error sending message: $e');
      throw Exception('Failed to communicate with server: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getChatHistory() async {
    try {
      final url = '$baseUrl/chat-history/';
      final response = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        // Process image URLs to make them absolute
        for (var item in data) {
          if (item['image'] != null && item['image'].toString().isNotEmpty) {
            // Make sure the image URL is absolute
            if (!item['image'].toString().startsWith('http')) {
              item['image'] = '$serverBaseUrl${item['image']}';
            }
          }
        }
        return data.cast<Map<String, dynamic>>();
      } else {
        String errorMsg = 'Failed to load chat history';
        try {
          final errorData = json.decode(response.body);
          if (errorData.containsKey('error')) {
            errorMsg = errorData['error'];
          }
        } catch (_) {}
        throw Exception('$errorMsg (${response.statusCode})');
      }
    } catch (e) {
      logger.e('Error getting chat history: $e');
      throw Exception('Failed to communicate with server: $e');
    }
  }
}
