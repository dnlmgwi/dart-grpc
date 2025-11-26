import 'dart:async';
import 'package:test/test.dart';
import 'package:grpc/grpc.dart';
import '../lib/src/greeter_service.dart';
import '../lib/src/generated/greeter.pbgrpc.dart';
import 'test_helpers.dart';

void main() {
  late TestServer testServer;
  late TestClient testClient;

  setUp(() async {
    testServer = TestServer();
    testClient = TestClient();
  });

  tearDown(() async {
    await testClient.close();
    await testServer.stop();
  });

  group('Connection Error Handling', () {
    test('client fails to connect to non-existent server', () async {
      testClient.connect('localhost', 59999);
      final client = GreeterClient(testClient.channel);

      final request = HelloRequest()..name = 'Test';

      expect(
        () => client.sayHello(request),
        throwsA(isA<GrpcError>()),
      );
    });

    test('client handles server shutdown during unary call', () async {
      await testServer.start([GreeterService()]);
      testClient.connect('localhost', testServer.port);
      final client = GreeterClient(testClient.channel);

      // Make first call successfully
      final response1 = await client.sayHello(HelloRequest()..name = 'First');
      expect(response1.message, equals('Hello, First!'));

      // Shutdown server
      await testServer.stop();

      // Next call should fail
      await Future.delayed(Duration(milliseconds: 100));
      expect(
        () => client.sayHello(HelloRequest()..name = 'Second'),
        throwsA(isA<GrpcError>()),
      );
    });

    test('client handles connection timeout', () async {
      testClient.connect('localhost', 59999);
      final client = GreeterClient(testClient.channel);

      final request = HelloRequest()..name = 'Test';
      final callOptions = CallOptions(timeout: Duration(seconds: 1));

      expect(
        () => client.sayHello(request, options: callOptions),
        throwsA(isA<GrpcError>()),
      );
    });

    test('handles invalid host gracefully', () async {
      testClient.connect('invalid.host.nonexistent', 50051);
      final client = GreeterClient(testClient.channel);

      final request = HelloRequest()..name = 'Test';

      expect(
        () => client.sayHello(request),
        throwsA(isA<GrpcError>()),
      );
    });
  });

  group('Stream Error Handling', () {
    test('client handles server shutdown during server streaming', () async {
      await testServer.start([GreeterService()]);
      testClient.connect('localhost', testServer.port);
      final client = GreeterClient(testClient.channel);

      final request = HelloRequest()..name = 'Stream';
      final stream = client.sayHelloStream(request);
      final responses = <HelloReply>[];

      final completer = Completer<void>();
      var hasError = false;

      stream.listen(
        (response) {
          responses.add(response);
          // Shutdown server after first message
          if (responses.length == 1) {
            testServer.stop();
          }
        },
        onError: (error) {
          hasError = true;
          completer.complete();
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
      );

      await completer.future;
      // Should have received at least one message before error
      expect(responses.length, greaterThanOrEqualTo(1));
    });

    test('client handles cancelled client stream', () async {
      await testServer.start([GreeterService()]);
      testClient.connect('localhost', testServer.port);
      final client = GreeterClient(testClient.channel);

      final controller = StreamController<HelloRequest>();

      // Start the call
      final responseFuture = client.sayHelloClientStream(controller.stream);

      // Send one message
      controller.add(HelloRequest()..name = 'First');
      await Future.delayed(Duration(milliseconds: 50));

      // Cancel by closing without completing
      await controller.close();

      // Should complete (possibly with error or partial result)
      try {
        final response = await responseFuture;
        expect(response.message, contains('First'));
      } catch (e) {
        // Cancellation error is also acceptable
        expect(e, isA<GrpcError>());
      }
    });

    test('bidirectional stream handles abrupt client disconnect', () async {
      await testServer.start([GreeterService()]);
      testClient.connect('localhost', testServer.port);
      final client = GreeterClient(testClient.channel);

      final controller = StreamController<HelloRequest>();
      final stream = client.sayHelloBidirectional(controller.stream);

      final responses = <HelloReply>[];
      final subscription = stream.listen((response) {
        responses.add(response);
      });

      // Send messages
      controller.add(HelloRequest()..name = 'First');
      await Future.delayed(Duration(milliseconds: 100));
      controller.add(HelloRequest()..name = 'Second');
      await Future.delayed(Duration(milliseconds: 100));

      // Abruptly cancel
      await subscription.cancel();
      await controller.close();

      expect(responses.length, greaterThanOrEqualTo(1));
    });

    test('handles stream with thrown error', () async {
      await testServer.start([GreeterService()]);
      testClient.connect('localhost', testServer.port);
      final client = GreeterClient(testClient.channel);

      Stream<HelloRequest> errorStream() async* {
        yield HelloRequest()..name = 'First';
        await Future.delayed(Duration(milliseconds: 50));
        throw Exception('Simulated error in stream');
      }

      expect(
        () => client.sayHelloClientStream(errorStream()),
        throwsA(anything),
      );
    });
  });

  group('Timeout Handling', () {
    test('unary call respects timeout', () async {
      await testServer.start([GreeterService()]);
      testClient.connect('localhost', testServer.port);
      final client = GreeterClient(testClient.channel);

      // Set very short timeout
      final callOptions = CallOptions(timeout: Duration(microseconds: 1));
      final request = HelloRequest()..name = 'Test';

      try {
        await client.sayHello(request, options: callOptions);
        fail('Should have thrown timeout error');
      } catch (e) {
        expect(e, isA<GrpcError>());
      }
    });

    test('stream respects timeout', () async {
      await testServer.start([GreeterService()]);
      testClient.connect('localhost', testServer.port);
      final client = GreeterClient(testClient.channel);

      final request = HelloRequest()..name = 'Test';
      // Server stream takes ~500ms, set shorter timeout
      final callOptions = CallOptions(timeout: Duration(milliseconds: 200));

      final stream = client.sayHelloStream(request, options: callOptions);

      var errorOccurred = false;
      try {
        await collectStream(stream);
      } catch (e) {
        errorOccurred = true;
        expect(e, isA<GrpcError>());
      }

      expect(errorOccurred, isTrue);
    });
  });

  group('Resource Cleanup', () {
    test('multiple channel closures are safe', () async {
      testClient.connect('localhost', 50051);

      await testClient.close();
      await testClient.close(); // Should not throw

      expect(testClient.isConnected, isFalse);
    });

    test('server can be stopped multiple times safely', () async {
      await testServer.start([GreeterService()]);
      await testServer.stop();
      await testServer.stop(); // Should not throw

      expect(testServer.isRunning, isFalse);
    });

    test('operations after channel closure fail gracefully', () async {
      await testServer.start([GreeterService()]);
      testClient.connect('localhost', testServer.port);
      final client = GreeterClient(testClient.channel);

      // Make successful call
      final response = await client.sayHello(HelloRequest()..name = 'Before');
      expect(response.message, equals('Hello, Before!'));

      // Close channel
      await testClient.close();

      // Try to make call after closure
      expect(
        () => client.sayHello(HelloRequest()..name = 'After'),
        throwsA(isA<GrpcError>()),
      );
    });
  });

  group('Concurrent Error Scenarios', () {
    test('multiple failed connections do not interfere', () async {
      final clients = <TestClient>[];

      // Create multiple clients connecting to non-existent servers
      for (var i = 0; i < 5; i++) {
        final client = TestClient();
        client.connect('localhost', 59990 + i);
        clients.add(client);
      }

      // All should fail independently
      final futures = clients.map((client) async {
        final greeter = GreeterClient(client.channel);
        try {
          await greeter.sayHello(HelloRequest()..name = 'Test');
          return false;
        } catch (e) {
          return e is GrpcError;
        }
      });

      final results = await Future.wait(futures);
      expect(results.where((r) => r).length, equals(5));

      // Cleanup
      for (var client in clients) {
        await client.close();
      }
    });

    test('server handles multiple simultaneous stream cancellations', () async {
      await testServer.start([GreeterService()]);
      testClient.connect('localhost', testServer.port);

      final controllers = <StreamController<HelloRequest>>[];
      final subscriptions = <StreamSubscription>[];

      // Start multiple bidirectional streams
      for (var i = 0; i < 10; i++) {
        final controller = StreamController<HelloRequest>();
        controllers.add(controller);

        final client = GreeterClient(testClient.channel);
        final stream = client.sayHelloBidirectional(controller.stream);
        subscriptions.add(stream.listen((_) {}));

        controller.add(HelloRequest()..name = 'Start$i');
      }

      await Future.delayed(Duration(milliseconds: 100));

      // Cancel all simultaneously
      final cancelFutures = subscriptions.map((s) => s.cancel());
      await Future.wait(cancelFutures);

      final closeFutures = controllers.map((c) => c.close());
      await Future.wait(closeFutures);

      // Server should still be functional
      final newClient = GreeterClient(testClient.channel);
      final response = await newClient.sayHello(HelloRequest()..name = 'After');
      expect(response.message, equals('Hello, After!'));
    });
  });

  group('Recovery Scenarios', () {
    test('client can recover after connection failure', () async {
      // Start server
      await testServer.start([GreeterService()]);
      testClient.connect('localhost', testServer.port);
      final client = GreeterClient(testClient.channel);

      // Successful call
      final response1 = await client.sayHello(HelloRequest()..name = 'First');
      expect(response1.message, equals('Hello, First!'));

      // Stop server (simulating failure)
      await testServer.stop();
      await Future.delayed(Duration(milliseconds: 100));

      // Failed call
      try {
        await client.sayHello(HelloRequest()..name = 'Failed');
        fail('Should have thrown error');
      } catch (e) {
        expect(e, isA<GrpcError>());
      }

      // Restart server (recovery)
      await testServer.start([GreeterService()]);

      // Close old client and create new one
      await testClient.close();
      testClient = TestClient();
      testClient.connect('localhost', testServer.port);
      final newClient = GreeterClient(testClient.channel);

      // Successful call after recovery
      final response2 = await newClient.sayHello(HelloRequest()..name = 'Recovered');
      expect(response2.message, equals('Hello, Recovered!'));
    });

    test('stream can be retried after failure', () async {
      await testServer.start([GreeterService()]);
      testClient.connect('localhost', testServer.port);
      final client = GreeterClient(testClient.channel);

      // First attempt - let it complete
      final responses1 = await collectStream(
        client.sayHelloStream(HelloRequest()..name = 'Attempt1'),
      );
      expect(responses1.length, equals(5));

      // Second attempt - should work independently
      final responses2 = await collectStream(
        client.sayHelloStream(HelloRequest()..name = 'Attempt2'),
      );
      expect(responses2.length, equals(5));
    });
  });
}
