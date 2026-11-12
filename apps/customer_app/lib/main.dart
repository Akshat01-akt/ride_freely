import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ride_core/ride_core.dart';

import 'app.dart';

const _baseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2/api/v1');

void main() {
  final client = ApiClient(baseUrl: _baseUrl, storage: SecureTokenStorage(namespace: 'customer'));
  Get.put(AuthController(AuthRepository(client, UserRole.customer)), permanent: true);
  runApp(const CustomerApp());
}
