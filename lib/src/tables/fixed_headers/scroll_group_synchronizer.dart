import 'dart:collection';

import 'package:flutter/material.dart';

class ScrollGroupSynchronizer {
  final List<ScrollController> _controllers = [];
  final Map<ScrollController, VoidCallback> _listeners = {};
  bool _isSyncing = false; // Flag to avoid unnecassary updates

  ScrollGroupSynchronizer([List<ScrollController>? controllersToSync]) {
    if (controllersToSync != null) {
      for (var controller in controllersToSync) {
        addController(controller);
      }
    }
  }


  UnmodifiableListView<ScrollController> get controllers => UnmodifiableListView(_controllers);

  void addController(ScrollController controller) {
    if (!_controllers.contains(controller)) {
      _controllers.add(controller);
      listener() => _handleScroll(controller);
      _listeners[controller] = listener;
      controller.addListener(listener);
    }
  }

  /// Usuwa [ScrollController] z grupy synchronizacji.
  /// Usuwa również powiązany listener.
  void removeController(ScrollController controller) {
    if (_controllers.contains(controller)) {
      final listener = _listeners.remove(controller);
      if (listener != null) {
        controller.removeListener(listener);
      }
      _controllers.remove(controller);
    }
  }

  void _handleScroll(ScrollController sourceController) {
    if (_isSyncing || !sourceController.hasClients) return;

    _isSyncing = true;

    final sourceOffset = sourceController.offset;

    for (var targetController in _controllers) {
      if (targetController == sourceController) continue;

      if (targetController.hasClients && targetController.offset != sourceOffset) {
        final targetListener = _listeners[targetController];
        if (targetListener != null) {
          // Temporary delete listener to avoid loop, during jumpTo
          targetController.removeListener(targetListener);
        }

        targetController.jumpTo(sourceOffset);

        if (targetListener != null) {
          // Add listener after set position
          targetController.addListener(targetListener);
        }
      }
    }

    _isSyncing = false;
  }

  
  void dispose() {
    for (var controller in _controllers) {
      final listener = _listeners[controller];
      if (listener != null) {
        controller.removeListener(listener);
      }
      controller.dispose();
    }
    _listeners.clear();
    _controllers.clear();
  }
}