import 'dart:async';
import 'package:flutter/material.dart';

class RestTimerWidget extends StatefulWidget {
  final Duration initialDuration;
  final VoidCallback? onTimerComplete;
  final VoidCallback? onSkip;
  final VoidCallback? onDismiss;
  final bool autoStart;

  const RestTimerWidget({
    super.key,
    this.initialDuration = const Duration(minutes: 1, seconds: 30),
    this.onTimerComplete,
    this.onSkip,
    this.onDismiss,
    this.autoStart = true,
  });

  @override
  State<RestTimerWidget> createState() => _RestTimerWidgetState();
}

class _RestTimerWidgetState extends State<RestTimerWidget>
    with TickerProviderStateMixin {
  late Duration _remainingTime;
  late AnimationController _animationController;
  Timer? _timer;
  bool _isRunning = false;
  bool _isCompleted = false;

  @override
  void initState() {
    super.initState();
    _remainingTime = widget.initialDuration;
    
    _animationController = AnimationController(
      duration: widget.initialDuration,
      vsync: this,
    );

    if (widget.autoStart) {
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  void _startTimer() {
    if (_isCompleted) return;
    
    setState(() {
      _isRunning = true;
    });

    _animationController.forward();
    
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingTime.inSeconds > 0) {
          _remainingTime = Duration(seconds: _remainingTime.inSeconds - 1);
        } else {
          _completeTimer();
        }
      });
    });
  }

  void _pauseTimer() {
    _timer?.cancel();
    _animationController.stop();
    setState(() {
      _isRunning = false;
    });
  }

  void _resetTimer() {
    _timer?.cancel();
    _animationController.reset();
    setState(() {
      _remainingTime = widget.initialDuration;
      _isRunning = false;
      _isCompleted = false;
    });
  }

  void _completeTimer() {
    _timer?.cancel();
    _animationController.forward();
    setState(() {
      _isRunning = false;
      _isCompleted = true;
      _remainingTime = Duration.zero;
    });
    
    widget.onTimerComplete?.call();
  }

  void _skipRest() {
    _timer?.cancel();
    _animationController.stop();
    widget.onSkip?.call();
  }

  void _dismissTimer() {
    _timer?.cancel();
    _animationController.stop();
    widget.onDismiss?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: _isCompleted 
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  _isCompleted ? Icons.check_circle : Icons.timer,
                  color: _isCompleted 
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isCompleted ? 'Rest Complete!' : 'Rest Timer',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _isCompleted 
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : null,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _dismissTimer,
                  icon: Icon(
                    Icons.close,
                    size: 20,
                  ),
                  tooltip: 'Close',
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Circular Progress Indicator
            SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Background circle
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: CircularProgressIndicator(
                      value: 1.0,
                      strokeWidth: 8,
                      backgroundColor: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.outline.withOpacity(0.1),
                      ),
                    ),
                  ),
                  
                  // Progress circle
                  AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return SizedBox(
                        width: 120,
                        height: 120,
                        child: CircularProgressIndicator(
                          value: _isCompleted 
                              ? 1.0 
                              : 1.0 - (_remainingTime.inSeconds / widget.initialDuration.inSeconds),
                          strokeWidth: 8,
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _isCompleted 
                                ? Colors.green 
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      );
                    },
                  ),
                  
                  // Time display
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatDuration(_remainingTime),
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _isCompleted 
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      if (!_isCompleted)
                        Text(
                          'remaining',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Control Buttons
            if (!_isCompleted) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Reset Button
                  IconButton.outlined(
                    onPressed: _resetTimer,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Reset',
                  ),
                  
                  // Play/Pause Button
                  IconButton.filled(
                    onPressed: _isRunning ? _pauseTimer : _startTimer,
                    icon: Icon(_isRunning ? Icons.pause : Icons.play_arrow),
                    tooltip: _isRunning ? 'Pause' : 'Start',
                  ),
                  
                  // Skip Button
                  IconButton.outlined(
                    onPressed: _skipRest,
                    icon: const Icon(Icons.skip_next),
                    tooltip: 'Skip Rest',
                  ),
                ],
              ),
            ] else ...[
              // Completed state button
              ElevatedButton.icon(
                onPressed: _resetTimer,
                icon: const Icon(Icons.refresh),
                label: const Text('Start New Timer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ],
            
            // Quick time adjustment buttons (only when paused or not started)
            if (!_isRunning && !_isCompleted) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              
              Text(
                'Quick Adjust',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              
              const SizedBox(height: 8),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildTimeAdjustButton('-30s', () => _adjustTime(-30)),
                  _buildTimeAdjustButton('-15s', () => _adjustTime(-15)),
                  _buildTimeAdjustButton('+15s', () => _adjustTime(15)),
                  _buildTimeAdjustButton('+30s', () => _adjustTime(30)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTimeAdjustButton(String label, VoidCallback onPressed) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(50, 35),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  void _adjustTime(int seconds) {
    final newTime = Duration(seconds: _remainingTime.inSeconds + seconds);
    
    if (newTime.inSeconds >= 0) {
      setState(() {
        _remainingTime = newTime;
        
        // Update animation controller duration if needed
        if (_remainingTime.inSeconds > widget.initialDuration.inSeconds) {
          _animationController.duration = _remainingTime;
        }
      });
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}