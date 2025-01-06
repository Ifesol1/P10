import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(RiverhawksApp());
}

class RiverhawksApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Riverhawks',
      theme: ThemeData(
        primaryColor: Colors.blue[800],
        colorScheme: ColorScheme.fromSwatch().copyWith(
          primary: Colors.blue[800],
          secondary: Colors.yellow[700]!,
        ),
        scaffoldBackgroundColor: Colors.blue[50],
        textTheme: TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.blue[800]!),
        ),
      ),
      home: ServerConnectionScreen(),
    );
  }
}

class ServerConnectionScreen extends StatefulWidget {
  @override
  _ServerConnectionScreenState createState() => _ServerConnectionScreenState();
}

class _ServerConnectionScreenState extends State<ServerConnectionScreen>
    with SingleTickerProviderStateMixin {
  String? serverUrl;
  bool isConnected = false;
  bool isConnecting = false;
  String statusMessage = "Disconnected";
  Timer? _pingTimer;
  late AnimationController _animationController;
  late Animation<Color?> _iconColorAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: Duration(milliseconds: 1000),
      vsync: this,
    );

    // Define an animation that transitions between green and grey
    _iconColorAnimation = ColorTween(
      begin: Colors.grey,
      end: Colors.green,
    ).animate(_animationController);
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pingTimer?.cancel();
    super.dispose();
  }

  Future<void> _getServerUrl() async {
    setState(() {
      isConnecting = true;
      statusMessage = "Connecting...";
      _animationController.repeat(reverse: true); // Start blinking animation
    });
    try {
      FirebaseFirestore.instance
          .collection("http_connections")
          .doc("raspberry_pi")
          .snapshots()
          .listen((document) {
        if (document.exists) {
          setState(() {
            serverUrl = document["ip"];
            isConnected = false;
            isConnecting = true;
          });
          _startPingTimer(); // Start the periodic ping check
        } else {
          _showConnectionFailed();
        }
      });
    } catch (e) {
      print(e);
      _showConnectionFailed();
    }
  }

  void _showConnectionFailed() {
    setState(() {
      statusMessage = "Connection failed. Please try again.";
      isConnected = false;
      isConnecting = false;
    });
    _animationController.stop(); // Stop the color animation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Error: Unable to connect to server."),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      _pingServer();
    });
  }

  Future<void> _pingServer() async {
    if (serverUrl == null) return;

    try {
      final response = await http.get(Uri.parse('$serverUrl/ping'));
      if (response.statusCode == 200) {
        setState(() {
          statusMessage = "Connected to server.";
          isConnected = true;
          isConnecting = false;
        });
        _animationController.stop(); // Stop the color animation

      } else {
        _disconnect();
      }
    } catch (e) {
      _disconnect();
    }
  }

  void _disconnect() {
    setState(() {
      statusMessage = "Disconnected.";
      isConnected = false;
      isConnecting = false;
    });
    _animationController.stop();
    _pingTimer?.cancel();
  }
  Future<void> _sendPowerOff() async {
    if (serverUrl != null) {
      try {
        await http.get(Uri.parse('$serverUrl/power_off'));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Power off command sent."),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      } catch (e) {
        print("Error sending power off command: $e");
      }
    }
  }
  Future<void> _sendFile() async {
    if (serverUrl != null) {
      final StreamController<double> progressController = StreamController<double>();

      try {
        FilePickerResult? result = await FilePicker.platform.pickFiles();
        if (result != null && result.files.single.path != null) {
          File file = File(result.files.single.path!);

          var request = http.MultipartRequest('POST', Uri.parse('$serverUrl/upload'));
          int totalBytes = await file.length();
          int bytesSent = 0;

          // Show initial SnackBar with StreamBuilder to update progress
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: StreamBuilder<double>(
                stream: progressController.stream,
                initialData: 0.0,
                builder: (context, snapshot) {
                  double progress = snapshot.data ?? 0.0;
                  return Text("Uploading... ${progress.toStringAsFixed(0)}%");
                },
              ),
              duration: Duration(days: 1),
            ),
          );

          // Open the file as a stream
          var fileStream = file.openRead();

          // Replace the file's byte stream in the request
          var stream = http.ByteStream(
            fileStream.transform(
              StreamTransformer.fromHandlers(
                handleData: (data, sink) {
                  bytesSent += data.length;
                  double progress = (bytesSent / totalBytes) * 100;
                  progressController.add(progress); // Update the Stream with new progress
                  sink.add(data);
                },
                handleError: (error, stackTrace, sink) {
                  sink.addError(error, stackTrace);
                },
                handleDone: (sink) {
                  sink.close();
                },
              ),
            ),
          );

          var multipartFile = http.MultipartFile(
            'file',
            stream,
            totalBytes,
            filename: file.path.split('/').last,
          );

          request.files.clear();
          request.files.add(multipartFile);

          // Send request
          var response = await request.send();
          progressController.close();

          ScaffoldMessenger.of(context).removeCurrentSnackBar(); // Remove progress SnackBar
          if (response.statusCode == 200) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("File uploaded successfully."),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("File upload failed."),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      } catch (e) {
        print("Error uploading file: $e");
        progressController.close();
      }
    }
  }
  void _toggleConnection() {
    if (isConnected) {
      _disconnect();
    } else {
      _getServerUrl();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Riverhawks',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.blue[900],
        elevation: 4,
        actions: [
          AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return IconButton(
                icon: Icon(
                  Icons.wifi,
                  color: isConnected
                      ? Colors.green
                      : isConnecting
                      ? _iconColorAnimation.value // Animate between grey and green
                      : Colors.red, // Red if disconnected
                ),
                onPressed: _toggleConnection,
              );
            },
          ),


          IconButton(
            icon: Icon(Icons.bluetooth, color: Colors.yellow[700]),
            onPressed: () {
              // Add Bluetooth action here
            },
          ),
          IconButton(
            icon: Icon(
              Icons.power_settings_new,
              color: isConnected ? Colors.red : Colors.grey, // Red if connected, grey if disconnected
            ),
            onPressed: isConnected ? _sendPowerOff : null, // Enable only if connected
          ),
        ],
      ),
      body: Row(
        children: [
          Container(
            width: 220,
            color: Colors.blue[800],
            child: LibraryPanel(onSendFile: _sendFile),  // Pass _sendFile as a callback
          ),
          Expanded(
            flex: 2,
            child: Container(
              margin: EdgeInsets.all(12.0),
              padding: EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(
                  color: Colors.yellow[700]!,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: Center(
                child: Text(
                  'Main Content Area',
                  style: TextStyle(
                    color: Colors.blue[900],
                    fontSize: 18.0,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class LibraryPanel extends StatelessWidget {
  final VoidCallback onSendFile;

  LibraryPanel({required this.onSendFile});
  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Library',
                style: TextStyle(
                  color: Colors.yellow[700],
                  fontSize: 22.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 24),
              LibraryButton(
                label: 'Add Text',
                icon: Icons.text_fields,
                onPressed: () {},
              ),
              SizedBox(height: 16),
              LibraryButton(
                label: 'Add Image',
                icon: Icons.image,
                onPressed: onSendFile,
              ),
              SizedBox(height: 16),
              LibraryButton(
                label: 'Add Circle',
                icon: Icons.circle,
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LibraryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  LibraryButton({required this.label, required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.yellow[700], size: 28.0),
      label: Text(
        label,
        style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.w500),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        minimumSize: Size(double.infinity, 56),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
      ),
    );
  }
}
