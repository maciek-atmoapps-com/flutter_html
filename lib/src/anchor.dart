import 'package:flutter/widgets.dart';
import 'package:flutter_html/src/tree/styled_element.dart';

class AnchorKey extends GlobalKey {
  static final Set<AnchorKey> _registry = <AnchorKey>{};

  final Key parentKey;
  final String id;

  const AnchorKey._(this.parentKey, this.id) : super.constructor();

  /// Clears all registered anchor keys for a given [parentKey].
  /// Must be called before each build to allow keys to be re-registered.
  static void resetRegistryForParent(Key parentKey) {
    _registry.removeWhere((key) => key.parentKey == parentKey);
  }

  static AnchorKey? of(Key? parentKey, StyledElement? id) {
    final key = forId(parentKey, id?.elementId);
    if (key == null || _registry.contains(key)) {
      // Invalid id or already created a key with this id: silently ignore
      return null;
    }
    _registry.add(key);
    return key;
  }

  /// Finds the registered AnchorKey for the given [parentKey] and [id]
  /// and returns its current BuildContext (if the widget is still mounted).
  static BuildContext? findContext(Key? parentKey, String? id) {
    if (parentKey == null || id == null || id.isEmpty || id == "[[No ID]]") {
      return null;
    }
    // Look up the EXACT registered instance that was assigned to a widget,
    // so that GlobalKey.currentContext can find it in the framework's registry.
    final registeredKey = _registry.lookup(AnchorKey._(parentKey, id));
    return registeredKey?.currentContext;
  }

  static AnchorKey? forId(Key? parentKey, String? id) {
    if (parentKey == null || id == null || id.isEmpty || id == "[[No ID]]") {
      return null;
    }

    return AnchorKey._(parentKey, id);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnchorKey &&
          runtimeType == other.runtimeType &&
          parentKey == other.parentKey &&
          id == other.id;

  @override
  int get hashCode => parentKey.hashCode ^ id.hashCode;

  @override
  String toString() {
    return 'AnchorKey{parentKey: $parentKey, id: #$id}';
  }
}
