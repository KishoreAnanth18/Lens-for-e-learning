import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../models/camera_models.dart';
import '../models/scan_models.dart';
import 'auth_service.dart';
import 'scan_service.dart';

class ScanServiceImpl implements IScanService {
  ScanServiceImpl({
    required String baseUrl,
    required IAuthService authService,
  })  : _dio = Dio(BaseOptions(baseUrl: baseUrl)),
        _authService = authService;

  final Dio _dio;
  final IAuthService _authService;
  final _uuid = const Uuid();

  @override
  Stream<ScanProgress> processScan(CompressedImage image) {
    final sessionId = _uuid.v4();
    final controller = StreamController<ScanProgress>.broadcast();
    var latest = ScanProgress(
      sessionId: sessionId,
      stage: ScanStage.upload,
      progress: 0,
      statusMessage: 'Preparing upload...',
      localImagePath: image.path,
    );

    void emit(ScanProgress next) {
      final normalized = next.copyWith(
        progress: next.progress < latest.progress ? latest.progress : next.progress,
      );
      latest = normalized;
      if (!controller.isClosed) {
        controller.add(normalized);
      }
    }

    Future<void>.microtask(() async {
      emit(latest);
      await _runScanWorkflow(image, latest, emit, controller);
    });
    return controller.stream;
  }

  Future<void> _runScanWorkflow(
    CompressedImage image,
    ScanProgress initial,
    void Function(ScanProgress progress) emit,
    StreamController<ScanProgress> controller,
  ) async {
    try {
      final scanId = await _uploadImageWithRetry(image, initial, emit);
      await _pollForCompletion(
        initial.copyWith(scanId: scanId, progress: 0.35),
        emit,
      );
    } catch (error) {
      emit(
        initial.copyWith(
          stage: ScanStage.failed,
          progress: 1,
          statusMessage: 'Scan failed',
          errorMessage: '$error',
        ),
      );
    } finally {
      await controller.close();
    }
  }

  Future<String> _uploadImageWithRetry(
    CompressedImage image,
    ScanProgress initial,
    void Function(ScanProgress progress) emit,
  ) async {
    final base64Image = base64Encode(await image.file.readAsBytes());
    DioException? lastError;

    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final token = await _authService.getValidToken();
        final response = await _dio.post<Map<String, dynamic>>(
          '/api/v1/scans',
          data: {
            'image_data': base64Image,
            'image_format': image.format.name,
          },
          options: Options(
            headers: {'Authorization': 'Bearer $token'},
          ),
          onSendProgress: (sent, total) {
            final fraction = total <= 0 ? 0.1 : sent / total;
            emit(
              initial.copyWith(
                stage: ScanStage.upload,
                progress: 0.05 + (fraction * 0.25),
                statusMessage: 'Uploading image ${(fraction * 100).toStringAsFixed(0)}%',
              ),
            );
          },
        );

        final data = response.data ?? const <String, dynamic>{};
        final scanId = data['scan_id'] as String?;
        if (scanId == null || scanId.isEmpty) {
          throw Exception('Upload completed without a scan ID.');
        }

        emit(
          initial.copyWith(
            scanId: scanId,
            stage: ScanStage.ocr,
            progress: 0.35,
            statusMessage: 'Upload complete. Starting OCR...',
          ),
        );
        return scanId;
      } on DioException catch (error) {
        lastError = error;
        if (attempt >= 3) break;

        final delay = Duration(seconds: 1 << (attempt - 1));
        emit(
          initial.copyWith(
            stage: ScanStage.upload,
            progress: 0.1,
            statusMessage:
                'Upload failed. Retrying in ${delay.inSeconds}s (attempt ${attempt + 1} of 3)...',
          ),
        );
        await Future<void>.delayed(delay);
      }
    }

    throw Exception(_extractError(lastError) ?? 'Upload failed after 3 attempts.');
  }

  Future<void> _pollForCompletion(
    ScanProgress progress,
    void Function(ScanProgress progress) emit,
  ) async {
    final scanId = progress.scanId;
    if (scanId == null) {
      throw Exception('Missing scan ID for polling.');
    }

    final startedAt = DateTime.now();
    String? lastStatus;

    while (true) {
      final result = await getScanResult(scanId);
      final elapsed = DateTime.now().difference(startedAt);
      final status = result.status;

      if (status == 'failed') {
        emit(
          progress.copyWith(
            scanId: scanId,
            stage: ScanStage.failed,
            progress: 1,
            statusMessage: result.errorMessage ?? 'Processing failed.',
            errorMessage: result.errorMessage,
            result: result,
          ),
        );
        return;
      }

      if (status == 'complete') {
        emit(
          progress.copyWith(
            scanId: scanId,
            stage: ScanStage.complete,
            progress: 1,
            statusMessage: 'Scan complete. Results are ready.',
            result: result,
          ),
        );
        return;
      }

      if (status == 'processing') {
        emit(
          progress.copyWith(
            scanId: scanId,
            stage: ScanStage.ocr,
            progress: 0.45,
            statusMessage: 'Running OCR on your page...',
            result: result,
          ),
        );
      } else if (status == 'ocr_complete') {
        emit(
          progress.copyWith(
            scanId: scanId,
            stage: ScanStage.summarization,
            progress: 0.62,
            statusMessage: 'Summarizing extracted text...',
            result: result,
          ),
        );
      } else if (status == 'nlp_complete') {
        if (lastStatus != 'nlp_complete') {
          emit(
            progress.copyWith(
              scanId: scanId,
              stage: ScanStage.keywords,
              progress: 0.76,
              statusMessage: 'Extracting keywords...',
              result: result,
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }

        emit(
          progress.copyWith(
            scanId: scanId,
            stage: ScanStage.search,
            progress: 0.88,
            statusMessage: 'Searching for learning resources...',
            result: result,
          ),
        );
      } else if (elapsed.inSeconds >= 30) {
        emit(
          progress.copyWith(
            scanId: scanId,
            progress: 0.9,
            statusMessage: 'Processing is taking a bit longer than usual...',
            result: result,
          ),
        );
      }

      lastStatus = status;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  @override
  Future<ScanStatusData> getScanResult(String scanId) async {
    final token = await _authService.getValidToken();
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/scans/$scanId',
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
    return ScanStatusData.fromJson(response.data ?? const <String, dynamic>{});
  }

  String? _extractError(DioException? error) {
    if (error == null) return null;
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      return data['detail'] as String? ??
          data['message'] as String? ??
          data['error_message'] as String?;
    }
    return error.message;
  }
}
