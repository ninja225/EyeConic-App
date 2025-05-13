import 'package:flutter/material.dart';

class Message {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  Message({required this.text, required this.isUser, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({Key? key}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final List<Message> _messages = [];
  final ScrollController _scrollController = ScrollController();
  bool _isComposing = false;
  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;

    setState(() {
      _messages.add(Message(text: _messageController.text, isUser: true));
      // Here you will add the API call later
      // For now, we'll just add a dummy response
      _messages.add(
        Message(
          text: "This is a placeholder response. API integration coming soon!",
          isUser: false,
        ),
      );
    });

    _messageController.clear();
    setState(() {
      _isComposing = false;
    });

    // Scroll to the bottom after sending message
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
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
                          child: Text(
                            message.text,
                            style: TextStyle(
                              color:
                                  message.isUser
                                      ? Theme.of(context).colorScheme.onPrimary
                                      : Theme.of(context).colorScheme.onSurface,
                              fontSize: 16,
                            ),
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
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).scaffoldBackgroundColor.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color:
                                _isComposing
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: TextField(
                          controller: _messageController,
                          onChanged: (text) {
                            setState(() {
                              _isComposing = text.isNotEmpty;
                            });
                          },
                          onSubmitted:
                              (_) => _isComposing ? _sendMessage() : null,
                          style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Type a message...',
                            hintStyle: TextStyle(
                              color: Theme.of(context).hintColor,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      child: FloatingActionButton(
                        onPressed: _isComposing ? _sendMessage : null,
                        elevation: _isComposing ? 2 : 0,
                        backgroundColor:
                            _isComposing
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(
                                  context,
                                ).colorScheme.surface.withOpacity(0.8),
                        child: Icon(
                          Icons.send_rounded,
                          color:
                              _isComposing
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : Theme.of(context).hintColor,
                        ),
                        mini: true,
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
