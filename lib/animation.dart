import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'dart:io'; // Add this line for the File class

class AnimationPanel extends StatefulWidget {
  final Function(List<Map<String, dynamic>>) onMediaSectionsRetrieved;

  AnimationPanel({required Key key, required this.onMediaSectionsRetrieved}) : super(key: key);

  @override
  AnimationPanelState createState() => AnimationPanelState();

  List<Map<String, dynamic>> getLibraryItems() {

    return AnimationPanelState().mediaSections;
  }
}

class AnimationPanelState extends State<AnimationPanel> {
  Tool selectedTool = Tool.drag;
  double playheadPosition = 45.0;
  double timelineWidth = 2000.0; // Increase width for horizontal scrolling
  Timer? playheadTimer;
  final ScrollController _scrollController = ScrollController();
  final ScrollController _headerScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onMediaSectionsRetrieved(mediaSections);
    });
    // Synchronize scroll between timeline header and body
    _scrollController.addListener(() {
      _headerScrollController.jumpTo(_scrollController.position.pixels);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _headerScrollController.dispose();
    super.dispose();
  }

  // List to store media sections with their type, start, and duration in pixels
  List<Map<String, dynamic>> mediaSections = [];

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          _buildToolbar(), // Toolbar for tool selection
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _buildTimelineHeader(),
                      // Timeline header with time markers
                      Expanded(child: _buildTimeline()),
                      // Main timeline with tracks and playhead
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Toolbar for selecting tools
  Widget _buildToolbar() {
    return Container(
      color: Colors.yellow[700],
      height: 50.0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          _buildToolButton(Tool.drag, Icons.open_with, "Drag"),
          _buildToolButton(Tool.expand, Icons.unfold_more, "Expand"),
        ],
      ),
    );
  }
  void startPlayhead() {
    // Stop any existing timer before starting a new one
    playheadTimer?.cancel();

    // Create a timer to update the playhead position periodically
    playheadTimer = Timer.periodic(Duration(milliseconds: 16), (timer) {
      setState(() {
        // Move the playhead by a small amount for each tick
        playheadPosition += 1.0;

        // Check if the playhead has reached the end of the timeline
        if (playheadPosition >= timelineWidth) {
          // Stop the timer if it reaches the end
          playheadPosition = 45.0;
          timer.cancel();
        }
      });
      // Scroll the view to follow the playhead
      if (playheadPosition <= timelineWidth-550) {

        _scrollController.jumpTo(
          playheadPosition - 45,
        );
      }

    });
  }

  // Tool button widget
  Widget _buildToolButton(Tool tool, IconData icon, String label) {
    bool isSelected = selectedTool == tool;
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedTool = tool;
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        color: isSelected ? Colors.yellow[800] : Colors.yellow[600],
        child: Row(
          children: [
            Icon(icon, color: Colors.white),
            SizedBox(width: 8.0),
            Text(label, style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }


  // Timeline header with synchronized scroll and time markers
  Widget _buildTimelineHeader() {
    return SingleChildScrollView(
      controller: _headerScrollController, // Separate controller for header
      scrollDirection: Axis.horizontal,
      child: Container(
        width: timelineWidth,
        height: 30.0,
        color: Colors.yellow[700],
        child: Row(
          children: List.generate(
            (timelineWidth / 100).floor(),
                (index) =>
                Container(
                  width: 100.0,
                  alignment: Alignment.center,
                  child: Text(
                    '${index * 5}s', // Time marker in seconds
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
          ),
        ),
      ),
    );
  }

  // Horizontal Timeline with droppable media sections and playhead
  Widget _buildTimeline() {
    return SingleChildScrollView(
      controller: _scrollController, // Synchronized scroll controller
      scrollDirection: Axis.horizontal,
      child: Container(
        width: timelineWidth,
        color: Colors.yellow[50],
        child: Stack(
          children: [
            _buildDroppableTrack('video', 20.0),
            _buildDroppableTrack('image', 80.0),
            _buildDroppableTrack('audio', 140.0),
            _buildDroppableTrack('text', 200.0),
            Positioned(
              left: playheadPosition,
              top: 0.0,
              child: Container(
                width: 2.0,
                height: 300.0,
                color: Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }
  IconData getIconForType(String type) {
    switch (type) {
      case 'image':
        return Icons.image;
      case 'text':
        return Icons.text_fields;
      case 'video':
        return Icons.videocam;
      case 'audio':
        return Icons.audiotrack;
      default:
        return Icons.insert_drive_file; // Default icon for unknown types
    }
  }

  // Droppable track for a specific media type
  Widget _buildDroppableTrack(String type, double topPosition) {
    return Positioned(
      top: topPosition,
      left: 0.0,
      child: DragTarget<String>(
        onAcceptWithDetails: (details) {
          final splitData = details.data.contains('|')
              ? details.data.split('|')
              : [details.data];
          final datatype = splitData[0];
          final path = splitData.length > 1 ? splitData[1] : '';

          if (datatype == type) {
            // Calculate drop position on the timeline
            double dropX = details.offset.dx - 150; // Adjust for sidebar width
            dropX = dropX.clamp(0.0, timelineWidth - 40.0); // Limit within bounds

            _addMediaSection(type, path, dropX);
          }
        },
        builder: (context, candidateData, rejectedData) {
          return Container(
            width: timelineWidth,
            height: 40.0,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.yellow[900]!, width: 0.5),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Row(
                    children: [
                      Icon(
                        getIconForType(type),
                        color: Colors.yellow[900],
                        size: 24.0,
                      ),
                      SizedBox(width: 8.0),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: mediaSections
                        .where((section) => section['type'] == type)
                        .map((section) => _buildMediaRectangle(section))
                        .toList(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

// Helper method to display media rectangles with media names
  Widget _buildMediaRectangle(Map<String, dynamic> section) {
    print(section['path']);
    return Positioned(
      left: section['start'] as double,
      child: GestureDetector(
        onHorizontalDragUpdate: (details) {
          setState(() {
            if (selectedTool == Tool.drag) {
              // Dragging the entire rectangle
              section['start'] += details.delta.dx;
              if (section['start'] < 0.0) section['start'] = 0.0;
            } else if (selectedTool == Tool.expand &&
                (section['type'] == 'image' || section['type'] == 'text')) {
              // Expanding rectangle duration
              section['duration'] = (section['duration'] as double) + details.delta.dx;
              if (section['duration'] < 50.0) section['duration'] = 50.0;
            }
          });
        },
        onLongPress: () {
          showMenu(
            context: context,
            position: RelativeRect.fromLTRB(
              section['start'], // Position right beside the rectangle
              0.0, // Adjust for vertical position if necessary
              0.0,
              0.0,
            ),
            items: [
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Delete',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'panelView',
                child: Row(
                  children: [
                    Icon(Icons.visibility, color: Colors.blue, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Panel View',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ).then((value) {
            if (value == 'delete') {
              setState(() {
                // Code to delete the section from your data structure
                mediaSections.remove(section); // Assuming `sections` is your data list
              });
            } else if (value == 'panelView') {
              showDialog(
                context: context,
                builder: (context) => Center(
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.8,
                    height: MediaQuery.of(context).size.width * 0.4,
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.blue, width: 2),
                    ),
                    child: Center(
                      child: Text(
                        'Panel View Content',
                        style: TextStyle(
                          color: Colors.blue[900],
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }
          });
        },
        child: Container(
          width: section['duration'] as double,
          height: 50.0,
          decoration: BoxDecoration(
            color: Colors.yellow[700]!.withOpacity(0.3),
            borderRadius: BorderRadius.circular(4.0),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                section['path'].split('/').last.toUpperCase(),
                style: TextStyle(
                  color: Colors.yellow[900],
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }


  Future<void> _addMediaSection(String type, String path, double start) async {
    const double pixelsPerSecond = 20.0; // 20 pixels per second
    double durationPixels = 100.0; // Default duration in pixels (equivalent to 5 seconds)

    if (type == 'video' || type == 'audio') {
      VideoPlayerController controller = VideoPlayerController.file(File(path));

      try {
        await controller.initialize();
        double mediaDurationInSeconds = controller.value.duration.inSeconds
            .toDouble();

        // Set duration in pixels, capping at 95 seconds
        double cappedDurationInSeconds = mediaDurationInSeconds > 95
            ? 95
            : mediaDurationInSeconds;
        durationPixels = cappedDurationInSeconds * pixelsPerSecond;
      } catch (e) {
        print('Failed to load media duration: $e');
      } finally {
        controller.dispose();
      }
    }

    setState(() {
      mediaSections.add({
        'type': type,
        'start': start,
        'duration': durationPixels,
        'path': path,
      });
    });
  }

}

enum Tool { drag, expand }
