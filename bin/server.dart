import 'dart:async';
import 'dart:io';

import 'package:grpc/grpc.dart';
import '../lib/src/greeter_service.dart';

Future<void> main(List<String> args) async {
  final server = Server.create(
    services: [GreeterService()],
    codecRegistry: CodecRegistry(codecs: const [GzipCodec(), IdentityCodec()]),
  );

  final port = args.isNotEmpty ? int.tryParse(args[0]) ?? 50051 : 50051;

  await server.serve(port: port);
  print('✓ gRPC Server listening on port $port');
  print('Press Ctrl+C to stop the server');
  print('');
  print('Server logs:');
  print('─' * 60);

  // Keep the server running
  await ProcessSignal.sigint.watch().first;
  print('\n${"─" * 60}');
  print('Shutting down server...');
  await server.shutdown();
  print('Server stopped');
}
