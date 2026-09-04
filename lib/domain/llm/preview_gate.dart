import 'package:kelola/domain/llm/provider.dart';

/// Cloud providers need an explicit preview approve once per app session.
class AssistPreviewGate {
  AssistPreviewGate();

  bool _cloudApproved = false;

  bool needsPreview(LlmProvider provider) {
    if (!provider.needsCloudPreview) {
      return false;
    }
    return !_cloudApproved;
  }

  void markCloudApproved() {
    _cloudApproved = true;
  }
}
