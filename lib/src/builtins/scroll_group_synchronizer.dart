import 'dart:collection';

import 'package:flutter/material.dart';

class ScrollGroupSynchronizer {
  final List<ScrollController> _controllers = [];
  final Map<ScrollController, VoidCallback> _listeners = {};
  bool _isSyncing = false; // Flaga zapobiegająca pętlom i zbędnym aktualizacjom

  /// Tworzy synchronizator dla podanej listy kontrolerów.
  /// Kontrolery można również dodawać później za pomocą metody [addController].
  ScrollGroupSynchronizer([List<ScrollController>? controllersToSync]) {
    if (controllersToSync != null) {
      for (var controller in controllersToSync) {
        addController(controller);
      }
    }
  }

  /// Zwraca niemodyfikowalną listę zsynchronizowanych kontrolerów.
  UnmodifiableListView<ScrollController> get controllers => UnmodifiableListView(_controllers);

  /// Dodaje [ScrollController] do grupy synchronizacji.
  /// Jeśli kontroler jest już w grupie, nic się nie dzieje.
  void addController(ScrollController controller) {
    if (!_controllers.contains(controller)) {
      _controllers.add(controller);
      // Tworzymy unikalny listener dla każdego kontrolera,
      // aby wiedzieć, który z nich był źródłem zmiany.
      VoidCallback listener = () => _handleScroll(controller);
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
    // Jeśli już jesteśmy w trakcie synchronizacji z innego źródła,
    // lub jeśli źródłowy kontroler nie ma klientów (nie jest przyłączony), nie rób nic.
    if (_isSyncing || !sourceController.hasClients) return;

    _isSyncing = true; // Ustaw flagę, aby zasygnalizować początek procesu synchronizacji

    final sourceOffset = sourceController.offset;

    for (var targetController in _controllers) {
      // Nie synchronizuj kontrolera ze samym sobą
      if (targetController == sourceController) continue;

      // Synchronizuj tylko jeśli target jest przyłączony i jego offset jest inny
      if (targetController.hasClients && targetController.offset != sourceOffset) {
        final targetListener = _listeners[targetController];
        if (targetListener != null) {
          // Tymczasowo usuń listener, aby uniknąć pętli, gdy wywołamy jumpTo
          targetController.removeListener(targetListener);
        }

        targetController.jumpTo(sourceOffset);

        if (targetListener != null) {
          // Dodaj listener z powrotem po ustawieniu pozycji
          targetController.addListener(targetListener);
        }
      }
    }

    _isSyncing = false; // Zresetuj flagę po zakończeniu synchronizacji
  }

  /// Usuwa wszystkie listenery z zarządzanych kontrolerów.
  /// Ta metoda powinna być wywołana, gdy synchronizator nie jest już potrzebny,
  /// np. w metodzie `dispose` widgetu State.
  /// Wywołuje też `dispose()` na samych kontrolerach, więc nie powinny być zarządzane przez inny kod
  void dispose() {
    for (var controller in _controllers) {
      final listener = _listeners[controller];
      if (listener != null) {
        controller.removeListener(listener);
      }
      controller.dispose();
    }
    _listeners.clear();
    _controllers.clear(); // Czyści listę, ale nie dispose'uje kontrolerów
  }
}