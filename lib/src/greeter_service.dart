import 'dart:async';
import 'package:grpc/grpc.dart';
import 'generated/greeter.pbgrpc.dart';

/// Implementation of the Greeter service
class GreeterService extends GreeterServiceBase {
  @override
  Future<HelloReply> sayHello(ServiceCall call, HelloRequest request) async {
    return HelloReply()..message = 'Hello, ${request.name}!';
  }

  @override
  Stream<HelloReply> sayHelloStream(ServiceCall call, HelloRequest request) async* {
    final greetings = [
      'Hello',
      'Hi',
      'Hey',
      'Greetings',
      'Welcome',
    ];

    for (var greeting in greetings) {
      yield HelloReply()..message = '$greeting, ${request.name}!';
      await Future.delayed(Duration(milliseconds: 100));
    }
  }

  @override
  Future<HelloReply> sayHelloClientStream(
      ServiceCall call, Stream<HelloRequest> request) async {
    final names = <String>[];

    await for (var req in request) {
      names.add(req.name);
    }

    final allNames = names.join(', ');
    return HelloReply()..message = 'Hello to all: $allNames!';
  }

  @override
  Stream<HelloReply> sayHelloBidirectional(
      ServiceCall call, Stream<HelloRequest> request) async* {
    var count = 0;

    await for (var req in request) {
      count++;
      yield HelloReply()
        ..message = 'Response #$count: Hello, ${req.name}! Nice to chat with you.';
      await Future.delayed(Duration(milliseconds: 50));
    }
  }
}
