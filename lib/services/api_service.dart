import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

class ApiService {
  // Change this to your Django backend URL (adjust for your setup)
  static const String baseUrl = 'http://localhost:8000/api';
  final logger = Logger();
  // Headers for regular JSON requests
  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    // Do not manually add CORS headers in client code
    // These are handled by the server
  };
  Future<bool> isServerReachable() async {
    try {
      // Check chat-history endpoint as it's simpler (GET request)
      final response = await http
          .get(Uri.parse('$baseUrl/chat-history/'), headers: _headers)
          .timeout(const Duration(seconds: 5));

      // Even if we get a 500 error, the server is technically reachable
      // We'll handle the specific error elsewhere
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

      // Handle differently for web vs mobile
      if (kIsWeb) {
        // For web, we need a simpler approach since File won't work the same way
        // For now, we'll just send the text (image upload requires a different approach in web)
        final response = await http
            .post(
              uri,
              headers: _headers,
              body: jsonEncode({
                'prompt': message,
                // Image handling for web would require a different approach
                // like base64 encoding or using FormData
              }),
            )
            .timeout(
              const Duration(seconds: 30),
              onTimeout: () {
                throw TimeoutException('Request timed out');
              },
            );

        logger.d(
          'Web send message response: ${response.statusCode} - ${response.body}',
        );

        if (response.statusCode == 200) {
          return json.decode(response.body);
        } else {
          logger.e('Error: ${response.statusCode} - ${response.body}');
          throw Exception('Failed to send message: ${response.body}');
        }
      } else {
        // Mobile implementation using MultipartRequest
        var request = http.MultipartRequest('POST', uri);

        // Add headers for multipart request
        request.headers.addAll({'Accept': 'application/json'});

        // Add text message - ensure field name matches backend
        request.fields['prompt'] = message;

        // Add image if provided - ensure field name matches backend
        if (image != null) {
          var imageStream = http.ByteStream(image.openRead());
          var length = await image.length();
          var multipartFile = http.MultipartFile(
            'image',
            imageStream,
            length,
            filename: image.path.split('/').last,
          );
          request.files.add(multipartFile);
        }

        logger.d(
          'Mobile sending request to $uri with prompt: $message and image: ${image != null}',
        );

        var streamedResponse = await request.send().timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw TimeoutException('Request timed out');
          },
        );

        var response = await http.Response.fromStream(streamedResponse);
        logger.d(
          'Mobile send message response: ${response.statusCode} - ${response.body}',
        );

        if (response.statusCode == 200) {
          return json.decode(response.body);
        } else {
          logger.e('Error: ${response.statusCode} - ${response.body}');
          throw Exception('Failed to send message: ${response.body}');
        }
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
      logger.d('Getting chat history from: $url');

      final response = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException('Request timed out');
            },
          );

      logger.d(
        'Chat history response: ${response.statusCode} - ${response.body}',
      );

      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        // Try to decode error message if possible
        String errorMsg = 'Failed to load chat history';
        try {
          final errorData = json.decode(response.body);
          if (errorData.containsKey('error')) {
            errorMsg = errorData['error'];
          }
        } catch (e) {
          // Ignore json decode errors
        }

        logger.e('Error: ${response.statusCode} - $errorMsg');
        throw Exception('$errorMsg (${response.statusCode})');
      }
    } on TimeoutException {
      logger.e('Request timed out');
      throw Exception('Request timed out. Server might be overloaded.');
    } catch (e) {
      logger.e('Error getting chat history: $e');
      throw Exception('Failed to communicate with server: $e');
    }
  }
}
