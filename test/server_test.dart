import 'dart:async';
import 'package:test/test.dart';
import 'package:grpc/grpc.dart';
import '../lib/src/greeter_service.dart';
import '../lib/src/generated/greeter.pbgrpc.dart';
import 'test_helpers.dart';

void main() {
  late TestServer testServer;
  late TestClient testClient;
  late GreeterClient client;

  setUp(() async {
    testServer = TestServer();
    testClient = TestClient();
  });

  tearDown(() async {
    await testClient.close();
    await testServer.stop();
  });

  group('GreeterService - Unary RPC', () {
    test('sayHello returns correct greeting for single name', () async {
      await testServer.start([GreeterService()]);
      testClient.connect('localhost', testServer.port);
      client = GreeterClient(testClient.channel);

      final request = HelloRequest()..name = 'Alice';
      final response = await client.sayHello(request);

      expect(response.message, equals('Hello, Alice!'));
    });

    test('sayHello handles empty name', () async {
      await testServer.start([GreeterService()]);
      testClient.connect('localhost', testServer.port);
      client = GreeterClient(testClient.channel);

      final request = HelloRequest()..name = '';
      final response = await client.sayHello(request);

      expect(response.message, equals('Hello, !'));
    });

    test('sayHello handles special characters', () async {
      await testServer.start([GreeterService()]);
      testClient.connect('localhost', testServer.port);
      client = GreeterClient(testClient.channel);

      final request = HelloRequest()..name = 'José-María';
      final response = await client.sayHello(request);

      expect(response.message, equals('Hello, José-María!'));
    });

    test('sayHello handles very long name', () async {
      await testServer.start([GreeterService()]);
      testClient.connect('localhost', testServer.port);
      client = GreeterClient(testClient.channel);

      final longName = 'A' * 1000;
      final request = HelloRequest()..name = longName;
      final response = await client.sayHello(request);

      expect(response.message, equals('Hello, $longName!'));
    });

    test('sayHello handles multiple concurrent requests', () async {
      await testServer.start([GreeterService()]);
      testClient.connect('localhost', testServer.port);
      client = GreeterClient(testClient.channel);

      final names = ['Alice', 'Bob', 'Charlie', 'Diana', 'Eve'];
      final futures = names.map((name) async {
        final request = HelloRequest()..name = name;
        return await client.sayHello(request);
      });

      final responses = await Future.wait(futures);

      expect(responses.length, equals(5));
      for (var i = 0; i < names.length; i++) {
        expect(responses[i].message, equals('Hello, ${names[i]}!'));
      }
    });
  });

  group('GreeterService - Server Streaming RPC', () {
    test('sayHelloStream returns all greetings', () async {
      await testServer.start([GreeterService()]);
      testClient.connect('localhost', testServer.port);
      client = GreeterClient(testClient.channel);

      final request = HelloRequest()..name = 'Bob';
      final responses = await collectStream(client.sayHelloStream(request));

      expect(responses.length, equals(5));
      expect(responses[0].message, equals('Hello, Bob!'));
      expect(responses[1].message, equals('Hi, Bob!'));
      expect(responses[2].message, equals('Hey, Bob!'));
      expect(responses[3].message, equals('Greetings, Bob!'));
      expect(responses[4].message, equals('Welcome, Bob!'));
    });

    test('sayHelloStream handles empty name', () async {
      await testServer.start([GreeterService()]);
      testClient.connect('localhost', testServer.port);
      client = GreeterClient(testClient.channel);

      final request = HelloRequest()..name = '';
      final responses = await collectStream(client.sayHelloStream(request));

      expect(responses.length, equals(5));
      expect(responses[0].message, equals('Hello, !'));
    });

    test('sayHelloStream can be cancelled mid-stream', () async {
      await testServer.start([GreeterService()]);
      testClient.connect('localhost', testServer.port);
      client = GreeterClient(testClient.channel);

      final request = HelloRequest()..name = 'Charlie';
      final stream = client.sayHelloStream(request);
      final responses = <HelloReply>[];

      final subscription = stream.listen((response) {
        responses.add(response);
      });

      // Wait for first two messages
      await Future.delayed(Duration(milliseconds: 250));
      await subscription.cancel();

      expect(responses.length, lessThanOrEqualTo(3));
    });
  });

  group('GreeterService - Client Streaming RPC', () {
    test('sayHelloClientStream aggregates all names', () async {
      await testServer.start([GreeterService()]);
      testClient.connect('localhost', testServer.port);
      client = GreeterClient(testClient.channel);

      Stream<HelloRequest> requestStream() async* {
        for (var name in ['Alice', 'Bob', 'Charlie']) {
          yield HelloRequest()..name = name;
          await Future.delayed(Duration(milliseconds: 50));
        }
      }

      final response = await client.sayHelloClientStream(requestStream());

      expect(response.message, equals('Hello to all: Alice, Bob, Charlie!'));
    });

    test('sayHelloClientStream handles single name', () async {
      await testServer.start([GreeterService()]);
      testClient.connect('localhost', testServer.port);
      client = GreeterClient(testClient.channel);

      Stream<HelloRequest> requestStream() async* {
        yield HelloRequest()..name = 'Diana';
      }

      final response = await client.sayHelloClientStream(requestStream());

      expect(response.message, equals('Hello to all: Diana!'));
    });

    test('sayHelloClientStream handles empty stream', () async {
      await testServer.start([GreeterService()]);
      testClient.connect('localhost', testServer.port);
      client = GreeterClient(testClient.channel);

      Stream<HelloRequest> requestStream() async* {
        // Empty stream
      }

      final response = await client.sayHelloClientStream(requestStream());

      expect(response.message, equals('Hello to all: !'));
    });

    test('sayHelloClientStream handles many names', () async {
      await testServer.start([GreeterService()]);
      testClient.connect('localhost', testServer.port);
      client = GreeterClient(testClient.channel);

      Stream<HelloRequest> requestStream() async* {
        for (var i = 1; i <= 10; i++) {
          yield HelloRequest()..name = 'User$i';
        }
      }

      final response = await client.sayHelloClientStream(requestStream());

      expect(response.message, contains('User1'));
      expect(response.message, contains('User10'));
      expect(response.message.split(',').length, equals(10));
    });
  });

  group('GreeterService - Bidirectional Streaming RPC', () {
    test('sayHelloBidirectional exchanges messages correctly', () async {
      await testServer.start([GreeterService()]);
      testClient.connect('localhost', testServer.port);
      client = GreeterClient(testClient.channel);

      Stream<HelloRequest> requestStream() async* {
        for (var i = 1; i <= 3; i++) {
          yield HelloRequest()..name = 'Message$i';
          await Future.delayed(Duration(milliseconds: 100));
        }
      }

      final responses = await collectStream(
        client.sayHelloBidirectional(requestStream()),
      );

      expect(responses.length, equals(3));
      expect(responses[0].message, contains('Response #1'));
      expect(responses[0].message, contains('Message1'));
      expect(responses[1].message, contains('Response #2'));
      expect(responses[1].message, contains('Message2'));
      expect(responses[2].message, contains('Response #3'));
      expect(responses[2].message, contains('Message3'));
    });

    test('sayHelloBidirectional handles single message', () async {
      await testServer.start([GreeterService()]);
      testClient.connect('localhost', testServer.port);
      client = GreeterClient(testClient.channel);

      Stream<HelloRequest> requestStream() async* {
        yield HelloRequest()..name = 'Solo';
      }

      final responses = await collectStream(
        client.sayHelloBidirectional(requestStream()),
      );

      expect(responses.length, equals(1));
      expect(responses[0].message, contains('Response #1'));
      expect(responses[0].message, contains('Solo'));
    });

    test('sayHelloBidirectional handles rapid messages', () async {
      await testServer.start([GreeterService()]);
      testClient.connect('localhost', testServer.port);
      client = GreeterClient(testClient.channel);

      Stream<HelloRequest> requestStream() async* {
        for (var i = 1; i <= 20; i++) {
          yield HelloRequest()..name = 'Fast$i';
        }
      }

      final responses = await collectStream(
        client.sayHelloBidirectional(requestStream()),
      );

      expect(responses.length, equals(20));
      for (var i = 0; i < responses.length; i++) {
        expect(responses[i].message, contains('Response #${i + 1}'));
      }
    });

    test('sayHelloBidirectional can handle stream cancellation', () async {
      await testServer.start([GreeterService()]);
      testClient.connect('localhost', testServer.port);
      client = GreeterClient(testClient.channel);

      final controller = StreamController<HelloRequest>();
      final stream = client.sayHelloBidirectional(controller.stream);
      final responses = <HelloReply>[];

      final subscription = stream.listen((response) {
        responses.add(response);
      });

      // Send a few messages
      controller.add(HelloRequest()..name = 'First');
      await Future.delayed(Duration(milliseconds: 100));
      controller.add(HelloRequest()..name = 'Second');
      await Future.delayed(Duration(milliseconds: 100));

      // Cancel and close
      await subscription.cancel();
      await controller.close();

      expect(responses.length, greaterThanOrEqualTo(1));
      expect(responses.length, lessThanOrEqualTo(2));
    });
  });

  group('GreeterService - Server Lifecycle', () {
    test('server can start and stop cleanly', () async {
      await testServer.start([GreeterService()]);
      expect(testServer.isRunning, isTrue);
      expect(testServer.port, greaterThan(0));

      await testServer.stop();
      expect(testServer.isRunning, isFalse);
    });

    test('server can be restarted', () async {
      await testServer.start([GreeterService()]);
      final firstPort = testServer.port;
      await testServer.stop();

      await testServer.start([GreeterService()]);
      final secondPort = testServer.port;

      expect(firstPort, greaterThan(0));
      expect(secondPort, greaterThan(0));
      await testServer.stop();
    });

    test('multiple clients can connect to same server', () async {
      await testServer.start([GreeterService()]);

      final client1 = TestClient();
      client1.connect('localhost', testServer.port);
      final greeter1 = GreeterClient(client1.channel);

      final client2 = TestClient();
      client2.connect('localhost', testServer.port);
      final greeter2 = GreeterClient(client2.channel);

      final request1 = HelloRequest()..name = 'Client1';
      final request2 = HelloRequest()..name = 'Client2';

      final response1 = await greeter1.sayHello(request1);
      final response2 = await greeter2.sayHello(request2);

      expect(response1.message, equals('Hello, Client1!'));
      expect(response2.message, equals('Hello, Client2!'));

      await client1.close();
      await client2.close();
    });
  });
}
