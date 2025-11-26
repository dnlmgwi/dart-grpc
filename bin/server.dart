import 'dart:async';
import 'dart:io';

import 'package:grpc/grpc.dart';
import '../lib/src/generated/greeter.pbgrpc.dart';

class GreeterService extends GreeterServiceBase {
  @override
  Future<HelloReply> sayHello(ServiceCall call, HelloRequest request) async {
    print('Received unary request from: ${request.name}');
    return HelloReply()..message = 'Hello, ${request.name}!';
  }

  @override
  Stream<HelloReply> sayHelloStream(ServiceCall call, HelloRequest request) async* {
    print('Received server streaming request from: ${request.name}');
    final greetings = [
      'Hello',
      'Hi',
      'Hey',
      'Greetings',
      'Welcome',
    ];

    for (var greeting in greetings) {
      yield HelloReply()..message = '$greeting, ${request.name}!';
      await Future.delayed(Duration(milliseconds: 500));
    }
    print('Server streaming completed for: ${request.name}');
  }

  @override
  Future<HelloReply> sayHelloClientStream(
      ServiceCall call, Stream<HelloRequest> request) async {
    print('Received client streaming request');
    final names = <String>[];

    await for (var req in request) {
      print('  Received name: ${req.name}');
      names.add(req.name);
    }

    final allNames = names.join(', ');
    print('Client streaming completed. Received ${names.length} names');
    return HelloReply()..message = 'Hello to all: $allNames!';
  }

  @override
  Stream<HelloReply> sayHelloBidirectional(
      ServiceCall call, Stream<HelloRequest> request) async* {
    print('Received bidirectional streaming request');
    var count = 0;

    await for (var req in request) {
      count++;
      print('  Received message #$count from: ${req.name}');
      yield HelloReply()
        ..message = 'Response #$count: Hello, ${req.name}! Nice to chat with you.';
      await Future.delayed(Duration(milliseconds: 200));
    }
    print('Bidirectional streaming completed. Exchanged $count messages');
  }
}

Future<void> main(List<String> args) async {
  final server = Server.create(
    services: [GreeterService()],
    codecRegistry: CodecRegistry(codecs: const [GzipCodec(), IdentityCodec()]),
  );

  final port = args.isNotEmpty ? int.tryParse(args[0]) ?? 50051 : 50051;

  await server.serve(port: port);
  print('✓ gRPC Server listening on port $port');
  print('Press Ctrl+C to stop the server');

  // Keep the server running
  await ProcessSignal.sigint.watch().first;
  print('\nShutting down server...');
  await server.shutdown();
  print('Server stopped');
}
