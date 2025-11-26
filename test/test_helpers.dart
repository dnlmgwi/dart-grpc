import 'dart:async';
import 'package:grpc/grpc.dart';

/// Helper class to start and manage a test gRPC server
class TestServer {
  Server? _server;
  int? _port;

  int get port => _port ?? 0;
  bool get isRunning => _server != null;

  /// Start the server on a random available port
  Future<void> start(List<Service> services) async {
    if (_server != null) {
      throw StateError('Server is already running');
    }

    _server = Server.create(
      services: services,
      codecRegistry: CodecRegistry(codecs: const [GzipCodec(), IdentityCodec()]),
    );

    // Use port 0 to let the OS assign an available port
    await _server!.serve(port: 0);
    _port = _server!.port;
  }

  /// Stop the server
  Future<void> stop() async {
    if (_server != null) {
      await _server!.shutdown();
      _server = null;
      _port = null;
    }
  }
}

/// Helper class to create and manage a test gRPC client
class TestClient {
  ClientChannel? _channel;
  String? _host;
  int? _port;

  bool get isConnected => _channel != null;

  /// Create a client channel
  void connect(String host, int port) {
    if (_channel != null) {
      throw StateError('Client is already connected');
    }

    _host = host;
    _port = port;
    _channel = ClientChannel(
      host,
      port: port,
      options: ChannelOptions(
        credentials: ChannelCredentials.insecure(),
        codecRegistry: CodecRegistry(codecs: const [GzipCodec(), IdentityCodec()]),
      ),
    );
  }

  /// Get the client channel
  ClientChannel get channel {
    if (_channel == null) {
      throw StateError('Client is not connected');
    }
    return _channel!;
  }

  /// Close the client channel
  Future<void> close() async {
    if (_channel != null) {
      await _channel!.shutdown();
      _channel = null;
      _host = null;
      _port = null;
    }
  }
}

/// Collect all items from a stream into a list
Future<List<T>> collectStream<T>(Stream<T> stream) async {
  final items = <T>[];
  await for (var item in stream) {
    items.add(item);
  }
  return items;
}

/// Collect items from a stream with a timeout
Future<List<T>> collectStreamWithTimeout<T>(
  Stream<T> stream,
  Duration timeout,
) async {
  final items = <T>[];
  try {
    await for (var item in stream.timeout(timeout)) {
      items.add(item);
    }
  } on TimeoutException {
    // Expected for some tests
  }
  return items;
}

/// Create a stream from a list of items with delays
Stream<T> createDelayedStream<T>(
  List<T> items,
  Duration delay,
) async* {
  for (var item in items) {
    await Future.delayed(delay);
    yield item;
  }
}

/// Wait for a condition to be true with timeout
Future<void> waitForCondition(
  bool Function() condition,
  Duration timeout, {
  Duration checkInterval = const Duration(milliseconds: 100),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > timeout) {
      throw TimeoutException('Condition not met within timeout', timeout);
    }
    await Future.delayed(checkInterval);
  }
}
