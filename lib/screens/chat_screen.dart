import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

class Message {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final File? image;
  final bool isError;
  final bool isSending;
  final bool isTyping;

  Message({
    required this.text,
    required this.isUser,
    this.image,
    this.isError = false,
    this.isSending = false,
    this.isTyping = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory Message.sending(String text, {File? image}) {
    return Message(text: text, isUser: true, image: image, isSending: true);
  }

  factory Message.error(String text) {
    return Message(text: text, isUser: false, isError: true);
  }

  factory Message.typing() {
    return Message(text: '', isUser: false, isTyping: true);
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final List<Message> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final ApiService _apiService = ApiService();
  final ImagePicker _picker = ImagePicker();
  bool _isComposing = false;
  bool _isSending = false;
  File? _selectedImage;
  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeController.forward();
    // Add welcome message
    _messages.add(
      Message(
        text: "👋 Welcome to Eyeconic Chat \nHow can I help you today?",
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );

    _checkServerAndLoadHistory();
  }

  Future<void> _checkServerAndLoadHistory() async {
    try {
      final isReachable = await _apiService.isServerReachable();
      if (!isReachable) {
        _showError(
          'Server is not reachable. Please check your connection and try again.',
        );
        return;
      }
      await _loadChatHistory();
    } catch (e) {
      _showError('Failed to connect to server. Please try again later.');
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadChatHistory() async {
    try {
      final history = await _apiService.getChatHistory();
      setState(() {
        _messages.addAll(
          history
              .map(
                (msg) => Message(
                  text: msg['prompt'],
                  isUser: true,
                  timestamp: DateTime.parse(msg['timestamp']),
                ),
              )
              .followedBy(
                history.map(
                  (msg) => Message(
                    text: msg['response'],
                    isUser: false,
                    timestamp: DateTime.parse(msg['timestamp']),
                  ),
                ),
              ),
        );
      });
      _scrollToBottom();
    } catch (e) {
      _showError('Failed to load chat history');
    }
  }

  Future<void> _pickImage() async {
    try {
      // Show a loading indicator while picking the image
      setState(() {
        _isSending = true; // Reuse the sending state for image picking
      });

      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200, // Limit image size to avoid memory issues
        maxHeight: 1200,
        imageQuality: 85, // Slightly compress to reduce file size
      );

      if (image != null) {
        // Handle possible image processing errors
        try {
          final File imageFile = File(image.path);

          // Verify the file is accessible and valid
          if (await imageFile.exists()) {
            // Check file size and compress if necessary
            final fileSize = await imageFile.length();
            if (fileSize > 4 * 1024 * 1024) {
              // Show warning about large file
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Image is large (${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB). It has been compressed.',
                  ),
                  backgroundColor: Theme.of(context).colorScheme.tertiary,
                  duration: const Duration(seconds: 3),
                ),
              );

              // We could add more compression here if needed
            }

            setState(() {
              _selectedImage = imageFile;
              _isComposing = true; // Enable the send button
            });
          } else {
            _showError(
              'Image file could not be accessed. Please try another image.',
            );
          }
        } catch (e) {
          _showError('Error processing image: ${e.toString()}');
        }
      }
    } catch (e) {
      _showError('Failed to pick image: ${e.toString()}');
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty && _selectedImage == null) {
      return;
    }

    final messageText = _messageController.text;
    final image = _selectedImage;

    setState(() {
      _isSending = true;
      _messages.add(Message.sending(messageText, image: image));
    });

    _messageController.clear();
    setState(() {
      _isComposing = false;
      _selectedImage = null;
    });

    _scrollToBottom();
    try {
      // Add a typing indicator for the AI response
      setState(() {
        _messages.removeLast();
        _messages.add(Message(text: messageText, isUser: true, image: image));
        _messages.add(Message.typing());
      });

      // Log details about the message being sent
      if (image != null) {
        debugPrint('Sending message with image: ${image.path}');
      }

      final response = await _apiService.sendMessage(messageText, image: image);

      // Replace typing indicator with the actual response
      setState(() {
        _messages.removeLast(); // Remove typing indicator
        _messages.add(Message(text: response['response'], isUser: false));
      });
    } catch (e) {
      String errorMessage = 'Failed to get response. Please try again.';

      if (e.toString().contains('API key')) {
        errorMessage =
            'OpenRouter API key issue. Please check your API key in the server .env file.';
      } else if (e.toString().contains('timed out')) {
        errorMessage =
            'Request timed out. The AI model may be taking too long to respond.';
      } else if (e.toString().contains('rate limit')) {
        errorMessage = 'API rate limit reached. Please try again later.';
      } else if (e.toString().contains('image') ||
          e.toString().contains('Image')) {
        errorMessage =
            'Failed to process image. The image may be too large or in an unsupported format.';
      } else if (e.toString().contains('Failed to communicate')) {
        errorMessage =
            'Network error. Please check your connection and try again.';
      }

      setState(() {
        // Make sure to remove any typing indicator if it exists
        if (_messages.isNotEmpty && _messages.last.isTyping) {
          _messages.removeLast();
        }
        // If the user message was removed during error, add it back
        if (_messages.isEmpty || _messages.last.isUser == false) {
          _messages.add(Message(text: messageText, isUser: true, image: image));
        }
        _messages.add(Message.error(errorMessage));
      });
    } finally {
      setState(() {
        _isSending = false;
      });
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 80,
        title: FadeTransition(
          opacity: _fadeController,
          child: Container(
            height: 60,
            constraints: const BoxConstraints(maxWidth: 180),
            child: Image.asset('assets/logo.png', fit: BoxFit.contain),
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          Tooltip(
            message: 'Using Qwen 2.5 AI models',
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Row(
                children: [
                  Text(
                    'EYECONIC',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.auto_awesome,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).scaffoldBackgroundColor,
            ],
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: FadeTransition(
                opacity: _fadeController,
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    final isFirstMessage =
                        index == 0 ||
                        _messages[index - 1].isUser != message.isUser;
                    final isLastMessage =
                        index == _messages.length - 1 ||
                        _messages[index + 1].isUser != message.isUser;

                    return SlideTransition(
                      position: Tween<Offset>(
                        begin: Offset(message.isUser ? 1 : -1, 0),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: _fadeController,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                      child: Align(
                        alignment:
                            message.isUser
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          margin: EdgeInsets.only(
                            top: isFirstMessage ? 8 : 2,
                            bottom: isLastMessage ? 8 : 2,
                            left: message.isUser ? 48 : 0,
                            right: message.isUser ? 0 : 48,
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 16,
                          ),
                          decoration: BoxDecoration(
                            color:
                                message.isUser
                                    ? Theme.of(
                                      context,
                                    ).colorScheme.primary.withOpacity(0.9)
                                    : Theme.of(
                                      context,
                                    ).colorScheme.surface.withOpacity(0.8),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(
                                message.isUser || !isFirstMessage ? 16 : 4,
                              ),
                              topRight: Radius.circular(
                                !message.isUser || !isFirstMessage ? 16 : 4,
                              ),
                              bottomLeft: Radius.circular(
                                message.isUser ? 16 : 4,
                              ),
                              bottomRight: Radius.circular(
                                !message.isUser ? 16 : 4,
                              ),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment:
                                message.isUser
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                            children: [
                              if (!message.isUser &&
                                  !message.isError &&
                                  !message.isSending &&
                                  !message.isTyping)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4.0),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.auto_awesome,
                                        size: 12,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary.withOpacity(0.8),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        message.image != null
                                            ? "Eyeconic "
                                            : "Eyeconic",
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withOpacity(0.8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (message.image != null)
                                Container(
                                  height: 200,
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color:
                                          message.isUser
                                              ? Colors.white.withOpacity(0.2)
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withOpacity(0.3),
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                    image: DecorationImage(
                                      image: FileImage(message.image!),
                                      fit: BoxFit.cover,
                                      opacity: message.isSending ? 0.7 : 1.0,
                                    ),
                                  ),
                                  child:
                                      message.isSending
                                          ? Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                        Color
                                                      >(Colors.white),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  'Uploading image...',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    shadows: [
                                                      Shadow(
                                                        blurRadius: 3,
                                                        color: Colors.black
                                                            .withOpacity(0.5),
                                                        offset: const Offset(
                                                          0,
                                                          1,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                          : null,
                                ),
                              if (message.isSending)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Theme.of(
                                                  context,
                                                ).colorScheme.onPrimary,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Sending...',
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onPrimary
                                              .withOpacity(0.7),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (message.isTyping)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8.0,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      LoadingAnimationWidget.staggeredDotsWave(
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                        size: 30,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Thinking...',
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withOpacity(0.7),
                                          fontSize: 12,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (!message.isTyping)
                                message.isUser || message.isError
                                    ? Text(
                                      message.text,
                                      style: TextStyle(
                                        color:
                                            message.isUser
                                                ? Theme.of(
                                                  context,
                                                ).colorScheme.onPrimary
                                                : message.isError
                                                ? Theme.of(
                                                  context,
                                                ).colorScheme.error
                                                : Theme.of(
                                                  context,
                                                ).colorScheme.onSurface,
                                        fontSize: 16,
                                      ),
                                    )
                                    : AnimatedTextKit(
                                      animatedTexts: [
                                        TypewriterAnimatedText(
                                          message.text,
                                          textStyle: TextStyle(
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.onSurface,
                                            fontSize: 16,
                                          ),
                                          speed: const Duration(
                                            milliseconds: 20,
                                          ),
                                        ),
                                      ],
                                      totalRepeatCount: 1,
                                      displayFullTextOnTap: true,
                                      stopPauseOnTap: true,
                                    ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withOpacity(0.8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    offset: const Offset(0, -1),
                    blurRadius: 8,
                  ),
                ],
              ),
              padding: const EdgeInsets.all(12),
              child: SafeArea(
                child: Row(
                  children: [
                    IconButton(
                      icon:
                          _isSending && _selectedImage == null
                              ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              )
                              : Icon(
                                _selectedImage != null
                                    ? Icons.image
                                    : Icons.image_outlined,
                                color:
                                    _selectedImage != null
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).hintColor,
                              ),
                      onPressed: _isSending ? null : _pickImage,
                      tooltip:
                          _selectedImage != null ? 'Change image' : 'Add image',
                    ),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).scaffoldBackgroundColor.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color:
                                _isComposing || _selectedImage != null
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_selectedImage != null)
                              Stack(
                                children: [
                                  Container(
                                    height: 100,
                                    width: double.infinity,
                                    margin: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary.withOpacity(0.6),
                                        width: 2,
                                      ),
                                      image: DecorationImage(
                                        image: FileImage(_selectedImage!),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: Material(
                                      color: Colors.black.withOpacity(0.5),
                                      shape: const CircleBorder(),
                                      child: IconButton(
                                        icon: const Icon(
                                          Icons.close,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _selectedImage = null;
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 8,
                                    left: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.6),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Image attached',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 8,
                              ),
                              child: TextField(
                                controller: _messageController,
                                onChanged: (text) {
                                  setState(() {
                                    _isComposing = text.isNotEmpty;
                                  });
                                },
                                onSubmitted: (text) {
                                  if (_isComposing || _selectedImage != null) {
                                    _sendMessage();
                                  }
                                },
                                style: TextStyle(
                                  fontSize: 16,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Type a message...',
                                  hintStyle: TextStyle(
                                    color: Theme.of(context).hintColor,
                                  ),
                                  contentPadding: EdgeInsets.zero,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FloatingActionButton(
                      onPressed:
                          _isSending
                              ? null
                              : (_isComposing || _selectedImage != null)
                              ? _sendMessage
                              : null,
                      elevation: _isComposing || _selectedImage != null ? 2 : 0,
                      backgroundColor:
                          _isSending
                              ? Theme.of(context).colorScheme.secondary
                              : (_isComposing || _selectedImage != null)
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(
                                context,
                              ).colorScheme.surface.withOpacity(0.8),
                      mini: true,
                      child:
                          _isSending
                              ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Theme.of(context).colorScheme.onSecondary,
                                  ),
                                ),
                              )
                              : Icon(
                                Icons.send_rounded,
                                color:
                                    _isComposing || _selectedImage != null
                                        ? Theme.of(
                                          context,
                                        ).colorScheme.onPrimary
                                        : Theme.of(context).hintColor,
                              ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
