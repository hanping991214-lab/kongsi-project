import 'package:flutter/material.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();

  // Mock messages
  final List<Map<String, dynamic>> _messages = [
    {'text': 'Hello!', 'isMe': true, 'time': '09:31 AM'},
    {'text': 'Hi, how can I help you?', 'isMe': false, 'time': '09:32 AM'},
    {'text': 'I wanted to ask about the item.', 'isMe': true, 'time': '09:33 AM'},
    {'text': 'Sure, what would you like to know?', 'isMe': false, 'time': '09:34 AM'},
  ];

  // List of bad words (expand as needed)
  final List<String> _badWords = [
    'badword1', 'badword2', 'damn', 'shit', 'fuck', 'bitch', 'asshole', 'bastard', 'crap', 'dick', 'piss', 'bloody', 'bugger', 'bollocks', 'arse', 'wanker', 'prick', 'slut', 'whore', 'twat', 'cunt'
  ];

  // List of financial warning words
  final List<String> _financialWarningWords = [
    'payment', 'transfer', 'bank', 'account', 'cash', 'duit', 'bayar', 'paypal'
  ];

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    // Check for bad words (case insensitive)
    final lowerText = text.toLowerCase();
    final containsBadWord = _badWords.any((word) => lowerText.contains(word));
    if (containsBadWord) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Inappropriate Language'),
          content: const Text('Your message contains inappropriate language. Please revise your message.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final containsFinancialWord = _financialWarningWords.any((word) => lowerText.contains(word));
    if (containsFinancialWord) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Safety Warning'),
          content: const Text('For your safety, keep all financial transactions inside the app to avoid scams.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      // Optionally, you can still allow the message to be sent, or block it if you want.
    }

    setState(() {
      _messages.add({
        'text': text,
        'isMe': true,
        'time': TimeOfDay.now().format(context),
      });
    });
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final chatName = args != null && args['name'] != null ? args['name'] as String : 'Chat';

    return Scaffold(
      appBar: AppBar(
        title: Text(chatName),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? Colors.white,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor ?? Colors.black,
        elevation: Theme.of(context).appBarTheme.elevation ?? 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isMe = message['isMe'] as bool;
                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.blue[700] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        Text(
                          message['text'],
                          style: TextStyle(
                            color: isMe ? Colors.white : Colors.black,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          message['time'],
                          style: TextStyle(
                            color: isMe ? Colors.white70 : Colors.grey[600],
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blue),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
