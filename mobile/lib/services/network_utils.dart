import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

bool isRetryableNetworkError(Object error) {
  if (error is DioException) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return true;
    }

    if (error.error is SocketException || error.error is TimeoutException) {
      return true;
    }

    final statusCode = error.response?.statusCode;
    return statusCode != null && statusCode >= 500;
  }

  return error is SocketException || error is TimeoutException;
}

bool isOfflineError(Object error) {
  if (error is DioException) {
    return error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.connectionError ||
        error.error is SocketException;
  }

  return error is SocketException || error is TimeoutException;
}

Future<T> retryWithBackoff<T>(
  Future<T> Function() action, {
  int maxAttempts = 3,
  Duration initialDelay = const Duration(seconds: 1),
}) async {
  Object? lastError;

  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await action();
    } catch (error) {
      lastError = error;
      if (attempt >= maxAttempts || !isRetryableNetworkError(error)) {
        rethrow;
      }

      final delay = Duration(
        milliseconds: initialDelay.inMilliseconds * (1 << (attempt - 1)),
      );
      await Future<void>.delayed(delay);
    }
  }

  throw lastError ?? Exception('Request failed');
}

String friendlyNetworkMessage(
  Object error, {
  required String action,
}) {
  if (isOfflineError(error)) {
    return 'You appear to be offline. We will retry $action when the connection returns.';
  }

  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final detail = data['detail'] as String? ??
          data['message'] as String? ??
          data['error'] as String? ??
          data['error_message'] as String?;
      if (detail != null && detail.isNotEmpty) {
        return detail;
      }
    }
  }

  return 'We could not $action right now. Please try again.';
}
