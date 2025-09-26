import 'package:flutter/foundation.dart';
import 'package:docapp/model/customermodel.dart' as model;

class CustomerBus {
  static final ValueNotifier<model.Customer?> changed = ValueNotifier<model.Customer?>(null);

  static void notify(model.Customer c) {
    changed.value = c;
  }
}