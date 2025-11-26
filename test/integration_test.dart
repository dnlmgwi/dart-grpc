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
    await testServer.start([GreeterService()]);
    testClient = TestClient();
    testClient.connect('localhost', testServer.port);
    client = GreeterClient(testClient.channel);
  });

  tearDown(() async {
    await testClient.close();
    await testServer.stop();
  });

  group('End-to-End Integration Tests', () {
    test('full workflow: unary -> server stream -> client stream -> bidirectional', () async {
      // 1. Unary call
      final unaryRequest = HelloRequest()..name = 'Integration';
      final unaryResponse = await client.sayHello(unaryRequest);
      expect(unaryResponse.message, equals('Hello, Integration!'));

      // 2. Server streaming
      final serverStreamRequest = HelloRequest()..name = 'Stream';
      final serverStreamResponses = await collectStream(
        client.sayHelloStream(serverStreamRequest),
      );
      expect(serverStreamResponses.length, equals(5));

      // 3. Client streaming
      Stream<HelloRequest> clientRequestStream() async* {
        yield HelloRequest()..name = 'User1';
        yield HelloRequest()..name = 'User2';
      }
      final clientStreamResponse = await client.sayHelloClientStream(
        clientRequestStream(),
      );
      expect(clientStreamResponse.message, contains('User1'));
      expect(clientStreamResponse.message, contains('User2'));

      // 4. Bidirectional streaming
      Stream<HelloRequest> bidirectionalStream() async* {
        yield HelloRequest()..name = 'Msg1';
        yield HelloRequest()..name = 'Msg2';
      }
      final bidirectionalResponses = await collectStream(
        client.sayHelloBidirectional(bidirectionalStream()),
      );
      expect(bidirectionalResponses.length, equals(2));
    });

    test('concurrent operations from multiple clients', () async {
      // Create additional clients
      final client2 = TestClient();
      client2.connect('localhost', testServer.port);
      final greeter2 = GreeterClient(client2.channel);

      final client3 = TestClient();
      client3.connect('localhost', testServer.port);
      final greeter3 = GreeterClient(client3.channel);

      // Execute operations concurrently
      final futures = [
        // Client 1: Unary
        client.sayHello(HelloRequest()..name = 'Client1'),

        // Client 2: Server streaming
        collectStream(
          greeter2.sayHelloStream(HelloRequest()..name = 'Client2'),
        ),

        // Client 3: Client streaming
        greeter3.sayHelloClientStream(
          Stream.fromIterable([
            HelloRequest()..name = 'C3-1',
            HelloRequest()..name = 'C3-2',
          ]),
        ),
      ];

      final results = await Future.wait(futures);

      expect((results[0] as HelloReply).message, equals('Hello, Client1!'));
      expect((results[1] as List).length, equals(5));
      expect((results[2] as HelloReply).message, contains('C3-1'));

      await client2.close();
      await client3.close();
    });

    test('stress test: 100 concurrent unary calls', () async {
      final futures = <Future<HelloReply>>[];
      for (var i = 0; i < 100; i++) {
        final request = HelloRequest()..name = 'User$i';
        futures.add(client.sayHello(request));
      }

      final responses = await Future.wait(futures);

      expect(responses.length, equals(100));
      for (var i = 0; i < 100; i++) {
        expect(responses[i].message, equals('Hello, User$i!'));
      }
    });

    test('stress test: multiple concurrent streams', () async {
      final futures = <Future>[];

      // Start 10 concurrent server streaming calls
      for (var i = 0; i < 10; i++) {
        final request = HelloRequest()..name = 'Streamer$i';
        futures.add(collectStream(client.sayHelloStream(request)));
      }

      final results = await Future.wait(futures);

      expect(results.length, equals(10));
      for (var result in results) {
        expect((result as List).length, equals(5));
      }
    });

    test('mixed workload: interleaved RPC types', () async {
      final results = <dynamic>[];

      // Unary
      results.add(await client.sayHello(HelloRequest()..name = 'A'));

      // Start server stream
      final serverStreamFuture = collectStream(
        client.sayHelloStream(HelloRequest()..name = 'B'),
      );

      // Unary
      results.add(await client.sayHello(HelloRequest()..name = 'C'));

      // Client stream
      results.add(await client.sayHelloClientStream(
        Stream.fromIterable([
          HelloRequest()..name = 'D1',
          HelloRequest()..name = 'D2',
        ]),
      ));

      // Wait for server stream
      results.add(await serverStreamFuture);

      // Bidirectional
      results.add(await collectStream(
        client.sayHelloBidirectional(
          Stream.fromIterable([HelloRequest()..name = 'E']),
        ),
      ));

      expect(results.length, equals(5));
      expect((results[0] as HelloReply).message, equals('Hello, A!'));
      expect((results[1] as HelloReply).message, equals('Hello, C!'));
      expect((results[2] as HelloReply).message, contains('D1'));
      expect((results[3] as List).length, equals(5));
      expect((results[4] as List).length, equals(1));
    });

    test('large payload: 10KB name in unary call', () async {
      final largeName = 'A' * 10240; // 10KB
      final request = HelloRequest()..name = largeName;
      final response = await client.sayHello(request);

      expect(response.message, equals('Hello, $largeName!'));
      expect(response.message.length, greaterThan(10240));
    });

    test('long-running stream: 50 messages', () async {
      Stream<HelloRequest> longStream() async* {
        for (var i = 0; i < 50; i++) {
          yield HelloRequest()..name = 'Msg$i';
        }
      }

      final responses = await collectStream(
        client.sayHelloBidirectional(longStream()),
      );

      expect(responses.length, equals(50));
      expect(responses.first.message, contains('Response #1'));
      expect(responses.last.message, contains('Response #50'));
    });

    test('rapid reconnection: client disconnect and reconnect', () async {
      // Make initial call
      final response1 = await client.sayHello(HelloRequest()..name = 'First');
      expect(response1.message, equals('Hello, First!'));

      // Disconnect
      await testClient.close();

      // Reconnect
      testClient = TestClient();
      testClient.connect('localhost', testServer.port);
      client = GreeterClient(testClient.channel);

      // Make another call
      final response2 = await client.sayHello(HelloRequest()..name = 'Second');
      expect(response2.message, equals('Hello, Second!'));
    });

    test('sequential operations maintain state independence', () async {
      // Client stream 1
      final response1 = await client.sayHelloClientStream(
        Stream.fromIterable([
          HelloRequest()..name = 'A',
          HelloRequest()..name = 'B',
        ]),
      );

      // Client stream 2 should not be affected by stream 1
      final response2 = await client.sayHelloClientStream(
        Stream.fromIterable([
          HelloRequest()..name = 'C',
          HelloRequest()..name = 'D',
        ]),
      );

      expect(response1.message, equals('Hello to all: A, B!'));
      expect(response2.message, equals('Hello to all: C, D!'));
      expect(response1.message, isNot(equals(response2.message)));
    });

    test('bidirectional stream maintains message ordering', () async {
      final names = <String>[];
      for (var i = 1; i <= 20; i++) {
        names.add('Order$i');
      }

      Stream<HelloRequest> orderedStream() async* {
        for (var name in names) {
          yield HelloRequest()..name = name;
        }
      }

      final responses = await collectStream(
        client.sayHelloBidirectional(orderedStream()),
      );

      expect(responses.length, equals(20));
      for (var i = 0; i < 20; i++) {
        expect(responses[i].message, contains('Response #${i + 1}'));
        expect(responses[i].message, contains('Order${i + 1}'));
      }
    });
  });

  group('Performance Tests', () {
    test('measure unary RPC latency', () async {
      final stopwatch = Stopwatch()..start();

      for (var i = 0; i < 50; i++) {
        await client.sayHello(HelloRequest()..name = 'Perf');
      }

      stopwatch.stop();
      final avgLatency = stopwatch.elapsedMilliseconds / 50;

      // Should complete 50 calls in reasonable time (less than 20ms per call on average)
      expect(avgLatency, lessThan(20));
    });

    test('measure streaming throughput', () async {
      final stopwatch = Stopwatch()..start();

      Stream<HelloRequest> throughputStream() async* {
        for (var i = 0; i < 100; i++) {
          yield HelloRequest()..name = 'Throughput$i';
        }
      }

      final responses = await collectStream(
        client.sayHelloBidirectional(throughputStream()),
      );

      stopwatch.stop();

      expect(responses.length, equals(100));
      // Should handle 100 messages in reasonable time
      expect(stopwatch.elapsedMilliseconds, lessThan(10000));
    });
  });

  group('Edge Cases', () {
    test('empty string name in all RPC types', () async {
      final emptyName = HelloRequest()..name = '';

      // Unary
      final unaryResp = await client.sayHello(emptyName);
      expect(unaryResp.message, equals('Hello, !'));

      // Server stream
      final serverStream = await collectStream(
        client.sayHelloStream(emptyName),
      );
      expect(serverStream.length, equals(5));

      // Client stream
      final clientStream = await client.sayHelloClientStream(
        Stream.fromIterable([emptyName]),
      );
      expect(clientStream.message, contains('Hello to all'));

      // Bidirectional
      final bidi = await collectStream(
        client.sayHelloBidirectional(Stream.fromIterable([emptyName])),
      );
      expect(bidi.length, equals(1));
    });

    test('unicode and emoji names', () async {
      final unicodeNames = [
        '你好',
        '🎉',
        'José',
        'Москва',
        '😀👍',
        'مرحبا',
      ];

      for (var name in unicodeNames) {
        final response = await client.sayHello(HelloRequest()..name = name);
        expect(response.message, equals('Hello, $name!'));
      }
    });

    test('whitespace-only names', () async {
      final whitespaceNames = [' ', '  ', '\t', '\n', '   \t\n   '];

      for (var name in whitespaceNames) {
        final response = await client.sayHello(HelloRequest()..name = name);
        expect(response.message, equals('Hello, $name!'));
      }
    });
  });
}
