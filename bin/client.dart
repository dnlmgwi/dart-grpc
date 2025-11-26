import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:grpc/grpc.dart';
import '../lib/src/generated/greeter.pbgrpc.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('host', abbr: 'h', defaultsTo: 'localhost', help: 'Server host')
    ..addOption('port', abbr: 'p', defaultsTo: '50051', help: 'Server port')
    ..addOption('name', abbr: 'n', defaultsTo: 'World', help: 'Your name')
    ..addOption('method',
        abbr: 'm',
        defaultsTo: 'unary',
        allowed: ['unary', 'server-stream', 'client-stream', 'bidirectional', 'all'],
        help: 'RPC method to call')
    ..addFlag('help', negatable: false, help: 'Show help');

  ArgResults results;
  try {
    results = parser.parse(args);
  } catch (e) {
    print('Error: $e\n');
    printUsage(parser);
    exit(1);
  }

  if (results['help'] as bool) {
    printUsage(parser);
    exit(0);
  }

  final host = results['host'] as String;
  final port = int.parse(results['port'] as String);
  final name = results['name'] as String;
  final method = results['method'] as String;

  final channel = ClientChannel(
    host,
    port: port,
    options: ChannelOptions(
      credentials: ChannelCredentials.insecure(),
      codecRegistry: CodecRegistry(codecs: const [GzipCodec(), IdentityCodec()]),
    ),
  );

  final client = GreeterClient(channel);

  try {
    print('Connecting to gRPC server at $host:$port\n');

    if (method == 'all') {
      await testUnary(client, name);
      print('\n${"=" * 60}\n');
      await testServerStream(client, name);
      print('\n${"=" * 60}\n');
      await testClientStream(client, name);
      print('\n${"=" * 60}\n');
      await testBidirectional(client, name);
    } else {
      switch (method) {
        case 'unary':
          await testUnary(client, name);
          break;
        case 'server-stream':
          await testServerStream(client, name);
          break;
        case 'client-stream':
          await testClientStream(client, name);
          break;
        case 'bidirectional':
          await testBidirectional(client, name);
          break;
      }
    }
  } catch (e) {
    print('Error: $e');
    exit(1);
  } finally {
    await channel.shutdown();
  }
}

Future<void> testUnary(GreeterClient client, String name) async {
  print('Testing Unary RPC');
  print('─' * 60);

  final request = HelloRequest()..name = name;
  print('Sending request: name="$name"');

  final response = await client.sayHello(request);
  print('✓ Received response: ${response.message}');
}

Future<void> testServerStream(GreeterClient client, String name) async {
  print('Testing Server Streaming RPC');
  print('─' * 60);

  final request = HelloRequest()..name = name;
  print('Sending request: name="$name"');
  print('Receiving stream of responses:');

  var count = 0;
  await for (var response in client.sayHelloStream(request)) {
    count++;
    print('  [$count] ${response.message}');
  }
  print('✓ Received $count messages from server');
}

Future<void> testClientStream(GreeterClient client, String name) async {
  print('Testing Client Streaming RPC');
  print('─' * 60);

  final names = ['$name', 'Alice', 'Bob', 'Charlie', 'Diana'];

  Stream<HelloRequest> requestStream() async* {
    for (var n in names) {
      print('Sending: name="$n"');
      yield HelloRequest()..name = n;
      await Future.delayed(Duration(milliseconds: 300));
    }
  }

  print('Sending stream of ${names.length} requests...');
  final response = await client.sayHelloClientStream(requestStream());
  print('✓ Received final response: ${response.message}');
}

Future<void> testBidirectional(GreeterClient client, String name) async {
  print('Testing Bidirectional Streaming RPC');
  print('─' * 60);

  final messages = [
    'I am $name',
    'How are you?',
    'Nice weather today',
    'Goodbye!',
  ];

  Stream<HelloRequest> requestStream() async* {
    for (var msg in messages) {
      print('→ Sending: name="$msg"');
      yield HelloRequest()..name = msg;
      await Future.delayed(Duration(milliseconds: 500));
    }
  }

  print('Starting bidirectional conversation...\n');
  var count = 0;
  await for (var response in client.sayHelloBidirectional(requestStream())) {
    count++;
    print('← Received: ${response.message}');
  }
  print('\n✓ Exchanged $count messages');
}

void printUsage(ArgParser parser) {
  print('Dart gRPC Client');
  print('\nUsage: dart run bin/client.dart [options]\n');
  print('Options:');
  print(parser.usage);
  print('\nExamples:');
  print('  dart run bin/client.dart --name Alice');
  print('  dart run bin/client.dart --method server-stream --name Bob');
  print('  dart run bin/client.dart --method all --name Charlie');
  print('  dart run bin/client.dart --host 192.168.1.100 --port 9090');
}
