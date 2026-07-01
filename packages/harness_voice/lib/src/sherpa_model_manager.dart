import 'dart:io';

/// The four files a streaming Zipformer transducer recognizer needs.
class SherpaModelPaths {
  const SherpaModelPaths({
    required this.encoder,
    required this.decoder,
    required this.joiner,
    required this.tokens,
    this.modelType = '',
  });

  final String encoder;
  final String decoder;
  final String joiner;
  final String tokens;

  /// sherpa `modelType` hint (empty = auto-detect; 'zipformer2' for v2 models).
  final String modelType;
}

/// Describes a downloadable streaming model: a base URL + the four filenames.
class SherpaModelSpec {
  const SherpaModelSpec({
    required this.baseUrl,
    required this.encoder,
    required this.decoder,
    required this.joiner,
    this.tokens = 'tokens.txt',
    this.modelType = '',
  });

  final String baseUrl;
  final String encoder;
  final String decoder;
  final String joiner;
  final String tokens;
  final String modelType;

  /// Default: the small (~20M-param) int8 English streaming Zipformer — the
  /// app-size sweet spot from the reference pattern. URLs point at the
  /// HuggingFace mirror; confirm they resolve for your model before relying on
  /// them (a 404 surfaces as a download error → the engine falls back).
  static const SherpaModelSpec defaultEnStreaming20M = SherpaModelSpec(
    baseUrl:
        'https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-en-20M-2023-02-17/resolve/main',
    encoder: 'encoder-epoch-99-avg-1.int8.onnx',
    decoder: 'decoder-epoch-99-avg-1.int8.onnx',
    joiner: 'joiner-epoch-99-avg-1.int8.onnx',
    tokens: 'tokens.txt',
  );

  List<String> get _files => <String>[encoder, decoder, joiner, tokens];
}

/// Downloads + caches a streaming model under a target directory on first use,
/// so recognition is fully on-device/offline afterwards.
///
/// Uses `dart:io` [HttpClient] (built-in — NO `http`/`dio` package, which could
/// reintroduce a `web` dependency that clashes with Firebase). The app passes
/// the target [Directory] (it owns `path_provider`), so this package stays
/// dependency-free beyond sherpa itself.
class SherpaModelManager {
  SherpaModelManager(
    this.targetDir, {
    this.spec = SherpaModelSpec.defaultEnStreaming20M,
  });

  /// Directory the model files are stored in (the app supplies it, e.g. a
  /// `voice_model/` subdir of the app support directory).
  final Directory targetDir;
  final SherpaModelSpec spec;

  /// True once all four files are present locally.
  Future<bool> isReady() async {
    for (final String name in spec._files) {
      if (!await File('${targetDir.path}/$name').exists()) return false;
    }
    return true;
  }

  /// Ensure all model files are present (download the missing ones), returning
  /// the local paths. [onProgress] reports 0..1 across the file set.
  Future<SherpaModelPaths> ensureModel({
    void Function(double progress)? onProgress,
  }) async {
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final List<String> files = spec._files;
    for (int i = 0; i < files.length; i++) {
      final String name = files[i];
      final File dest = File('${targetDir.path}/$name');
      if (!await dest.exists()) {
        await _download('${spec.baseUrl}/$name', dest);
      }
      onProgress?.call((i + 1) / files.length);
    }

    return SherpaModelPaths(
      encoder: '${targetDir.path}/${spec.encoder}',
      decoder: '${targetDir.path}/${spec.decoder}',
      joiner: '${targetDir.path}/${spec.joiner}',
      tokens: '${targetDir.path}/${spec.tokens}',
      modelType: spec.modelType,
    );
  }

  Future<void> _download(String url, File dest) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest req = await client.getUrl(Uri.parse(url));
      final HttpClientResponse res = await req.close(); // follows redirects
      if (res.statusCode != HttpStatus.ok) {
        throw HttpException('GET $url failed: HTTP ${res.statusCode}');
      }
      // Write to a temp file first, rename on success → no half-file is ever
      // mistaken for a complete model.
      final File tmp = File('${dest.path}.part');
      final IOSink sink = tmp.openWrite();
      try {
        await res.forEach(sink.add);
        await sink.flush();
      } finally {
        await sink.close();
      }
      await tmp.rename(dest.path);
    } finally {
      client.close(force: true);
    }
  }
}
