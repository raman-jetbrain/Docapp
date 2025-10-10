import 'package:docapp/model/customer.dart' as model;
import 'package:flutter/foundation.dart';

class CustomerBus {
  static final ValueNotifier<model.Customer?> changed = ValueNotifier<model.Customer?>(null);

  static void notify(model.Customer c) {
    changed.value = c;
  }
}