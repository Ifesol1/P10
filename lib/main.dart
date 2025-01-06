import 'dart:convert';
import 'package:rxdart/rxdart.dart';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'animation.dart';
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
  List<Map<String, dynamic>> mediaSections = [];

  final GlobalKey<AnimationPanelState> animationPanelKey = GlobalKey<AnimationPanelState>();

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
          // Run button as the first item
          IconButton(
            icon: Icon(
              Icons.play_arrow,
              color: isConnected ? Colors.green : Colors.grey, // Change color based on isConnected
            ),
            onPressed: isConnected ? _onRunPressed : null, // Disable button if isConnected is false
          ),
          AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return IconButton(
                icon: Icon(
                  Icons.wifi,
                  color: isConnected
                      ? Colors.green
                      : isConnecting
                      ? _iconColorAnimation
                      .value // Animate between grey and green
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
              color: isConnected ? Colors.red : Colors
                  .grey, // Red if connected, grey if disconnected
            ),
            onPressed: isConnected
                ? _sendPowerOff
                : null, // Enable only if connected
          ),
        ],
      ),
      body: Row(
        children: [
          Container(
            width: 220,
            color: Colors.blue[800],
            child: LibraryPanel(
            ), //
          ),
          AnimationPanel(
            key: animationPanelKey,
            onMediaSectionsRetrieved: (sections) {
             mediaSections = sections;
            },
          ),
        ],
      ),
    );
  }

// Define the _onRunPressed function
  void _onRunPressed() async {
    print(mediaSections);

    // Endpoint URL for checking files on the server
    final url = Uri.parse("$serverUrl/check-files");

    // Prepare the request payload by including only entries that have a non-empty path
    final requestPayload = {
      "mediaSections": mediaSections
          .where((section) =>
      section['path'] != null && section['path'].isNotEmpty)
          .map((section) => {
        "type": section['type'],
        "path": section['path'],
      })
          .toList()
    };

    try {
      // Send the request to the server to check for missing files
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode(requestPayload),
      );

      // Check the response status
      if (response.statusCode == 200) {
        // Parse the response JSON
        final responseData = json.decode(response.body);
        List<String> missingFiles = List<String>.from(responseData['missingFiles']);
        print("Missing files: $missingFiles");

        if (missingFiles.isNotEmpty) {
          // If there are missing files, upload each one
          await _sendFiles(missingFiles);
        } else {
          print("All files are already on the server.");
          sendFullData();
        }
      } else {
        print("Error: ${response.statusCode}");
      }
    } catch (e) {
      print("Failed to check files: $e");
    }
  }
  Future<void> sendFullData() async {
    final url = Uri.parse("$serverUrl/send-full-data");

    // Prepare the payload
    final requestPayload = {
      "mediaSections": mediaSections,
    };

    try {
      // Send the full data to the server
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode(requestPayload),
      );

      // Check the response status
      if (response.statusCode == 200) {
        print("Full data sent successfully.");
        animationPanelKey.currentState?.startPlayhead();

      } else {
        print("Error sending full data: ${response.statusCode}");
      }
    } catch (e) {
      print("Failed to send full data: $e");
    }
  }

  Future<void> _sendFiles(List<String> missingFiles) async {
    if (serverUrl != null) {
      final BehaviorSubject<double> progressController = BehaviorSubject<double>();
      bool allUploadsSuccessful = true;

      try {
        for (String filePath in missingFiles) {
          File file = File(filePath);

          if (!file.existsSync()) {
            print("File not found: $filePath");
            allUploadsSuccessful = false;
            continue;
          }

          var request = http.MultipartRequest('POST', Uri.parse('$serverUrl/upload'));
          int totalBytes = await file.length();
          int bytesSent = 0;

          // Display SnackBar with progress for each file
          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          final snackBar = SnackBar(
            content: StatefulBuilder(
              builder: (context, setState) {
                return StreamBuilder<double>(
                  stream: progressController.stream,
                  initialData: 0.0,
                  builder: (context, snapshot) {
                    double progress = snapshot.data ?? 0.0;
                    return Text("Uploading ${file.path.split('/').last}... ${progress.toStringAsFixed(0)}%");
                  },
                );
              },
            ),
            duration: Duration(days: 1),
          );
          ScaffoldMessenger.of(context).showSnackBar(snackBar);

          // Open the file as a stream
          var fileStream = file.openRead();

          // Replace the file's byte stream in the request
          var stream = http.ByteStream(
            fileStream.transform(
              StreamTransformer.fromHandlers(
                handleData: (data, sink) {
                  bytesSent += data.length;
                  double progress = (bytesSent / totalBytes) * 100;
                  progressController.add(progress); // Update progress
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
          progressController.add(0); // Reset progress for the next file

          if (response.statusCode == 200) {
            print("File uploaded successfully: ${file.path}");
          } else {
            print("Failed to upload: ${file.path}");
            allUploadsSuccessful = false;
          }
        }

        // Close progress controller after all files are processed
        progressController.close();

        // Show final success or failure message
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              allUploadsSuccessful
                  ? "All files uploaded successfully."
                  : "Some files failed to upload. Check logs.",
            ),
            backgroundColor: allUploadsSuccessful ? Colors.green : Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      } catch (e) {
        print("Error uploading files: $e");
        progressController.close();
      }
    }
  }

}



class LibraryPanel extends StatefulWidget {
  @override
  _LibraryPanelState createState() => _LibraryPanelState();

  // Expose the library items through a method

}

class _LibraryPanelState extends State<LibraryPanel> {
  final List<Widget> _libraryItems = [];

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(10.0),
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
              SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  LibraryIconButton(
                    icon: Icons.text_fields,
                    onPressed: () => _showTextInputDialog(context),
                  ),
                  SizedBox(width: 16),
                  LibraryIconButton(
                    icon: Icons.perm_media,
                    onPressed: _pickMediaFile,
                  ),
                  SizedBox(width: 16),
                  LibraryIconButton(
                    icon: Icons.category,
                    onPressed: () {}, // Add functionality for shapes as needed
                  ),
                ],
              ),
              SizedBox(height: 24),
              ..._libraryItems,
            ],
          ),
        ),
      ),
    );
  }

  void _showTextInputDialog(BuildContext context) {

    TextEditingController textController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: 200),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 100,
                    child: TextFormField(
                      controller: textController,
                      decoration: InputDecoration(
                        hintText: 'Type your text here',
                        hintStyle: TextStyle(color: Colors.grey),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                      ),
                      style: TextStyle(color: Colors.black),
                      autofocus: true,
                      maxLines: null,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actionsAlignment: MainAxisAlignment.spaceAround,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                String enteredText = textController.text;
                _addTextComponent(enteredText);
                Navigator.of(context).pop();
              },
              child: Text('Add Text'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickMediaFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'mp3', 'wav', 'aac', 'flac', 'mp4', 'mov', 'avi', 'mkv'],
    );

    if (result != null) {
      String filePath = result.files.single.path!;
      String fileType = classifyMedia(filePath);
      _addMediaComponent(filePath, fileType);
    }
  }

  void _addTextComponent(String text) {
    setState(() {
      _libraryItems.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Draggable<String>(
            data: "text|$text",
            feedback: Material(
              color: Colors.transparent,
              child: SizedBox(
                width: 60.0, // Set small width for draggable feedback
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.text_fields, // Use an icon to represent text
                      color: Colors.blueAccent, // Choose color for the icon
                      size: 20.0,
                    ),
                    Text(
                      text,
                      style: TextStyle(fontSize: 12, color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.5, child: _buildTextTile(text)),
            child: _buildTextTile(text),
          ),
        ),
      );
    });
  }


  void _addMediaComponent(String filePath, String fileType) {
    setState(() {
      _libraryItems.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Draggable<String>(
            data: '$fileType|$filePath',
            feedback: Material(
              color: Colors.transparent,
              child: SizedBox(
                width: 60.0, // Set small width for draggable feedback
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getIconForFileType(fileType),
                      color: Colors.yellow[700],
                      size: 20.0,
                    ),
                    Text(
                      filePath.split('/').last,
                      style: TextStyle(fontSize: 10, color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.5, child: _buildMediaTile(filePath, fileType)),
            child: _buildMediaTile(filePath, fileType),
          ),
        ),
      );
    });
  }

  Widget _buildTextTile(String text) {
    return ListTile(
      leading: Icon(Icons.text_fields, color: Colors.yellow[700]),
      title: Text(
        text,
        style: TextStyle(color: Colors.white),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildMediaTile(String filePath, String fileType) {
    return ListTile(
      leading: Icon(
        _getIconForFileType(fileType),
        color: Colors.yellow[700],
      ),
      title: Text(
        filePath.split('/').last,
        style: TextStyle(color: Colors.white),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  IconData _getIconForFileType(String fileType) {
    switch (fileType) {
      case 'image':
        return Icons.image;
      case 'audio':
        return Icons.audiotrack;
      case 'video':
        return Icons.videocam;
      default:
        return Icons.insert_drive_file;
    }
  }

  String classifyMedia(String fileName) {
    final imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp'];
    final audioExtensions = ['mp3', 'wav', 'aac', 'flac'];
    final videoExtensions = ['mp4', 'mov', 'avi', 'mkv'];

    String extension = fileName.split('.').last.toLowerCase();

    if (imageExtensions.contains(extension)) {
      return 'image';
    } else if (audioExtensions.contains(extension)) {
      return 'audio';
    } else if (videoExtensions.contains(extension)) {
      return 'video';
    } else {
      return 'unknown';
    }
  }
}

class LibraryIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  LibraryIconButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: Colors.yellow[700], size: 28.0),
      onPressed: onPressed,
    );
  }
}
