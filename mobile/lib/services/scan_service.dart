import '../models/camera_models.dart';
import '../models/scan_models.dart';

abstract class IScanService {
  Stream<ScanProgress> processScan(CompressedImage image);
  Future<ScanStatusData> getScanResult(String scanId);
}
