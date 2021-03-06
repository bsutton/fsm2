import '../types.dart';

class ForkDefinition<E extends Event> {
  ForkDefinition();

  /// List of starts that are the targets of this fork.
  List<Type> stateTargets = <Type>[];

  void addTarget(Type s) {
    stateTargets.add(s);
  }
}
