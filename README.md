# Dart gRPC Client/Server Demo

A fully functional gRPC client and server command-line application built with Dart. This project demonstrates all four types of gRPC communication patterns:

- **Unary RPC**: Simple request-response
- **Server Streaming RPC**: Single request, multiple responses
- **Client Streaming RPC**: Multiple requests, single response
- **Bidirectional Streaming RPC**: Multiple requests and responses

## Features

- Complete gRPC implementation in Dart
- Command-line interface for both client and server
- Demonstrates all RPC patterns
- Easy to understand and extend
- Production-ready structure

## Prerequisites

- Dart SDK 3.0.0 or later
- Protocol Buffers compiler (`protoc`) - only needed if regenerating proto files

## Installation

1. Clone or download this repository

2. Install dependencies:
```bash
dart pub get
```

3. (Optional) If you modify the `.proto` file, regenerate the code:
```bash
# Activate the protoc plugin
dart pub global activate protoc_plugin

# Add to PATH if needed
export PATH="$PATH:$HOME/.pub-cache/bin"

# Generate Dart code from proto files
./generate_protos.sh
```

## Project Structure

```
dart-grpc/
├── bin/
│   ├── server.dart          # gRPC server implementation
│   └── client.dart          # gRPC client implementation
├── lib/
│   └── src/
│       └── generated/       # Generated protobuf/gRPC code
│           ├── greeter.pb.dart
│           ├── greeter.pbenum.dart
│           ├── greeter.pbgrpc.dart
│           └── greeter.pbjson.dart
├── protos/
│   └── greeter.proto        # Protocol buffer definition
├── pubspec.yaml
└── README.md
```

## Usage

### Starting the Server

Run the server on the default port (50051):
```bash
dart run bin/server.dart
```

Or specify a custom port:
```bash
dart run bin/server.dart 9090
```

The server will display:
```
✓ gRPC Server listening on port 50051
Press Ctrl+C to stop the server
```

### Running the Client

The client supports multiple options and methods:

**Show help:**
```bash
dart run bin/client.dart --help
```

**Basic unary call:**
```bash
dart run bin/client.dart --name Alice
```

**Test server streaming:**
```bash
dart run bin/client.dart --method server-stream --name Bob
```

**Test client streaming:**
```bash
dart run bin/client.dart --method client-stream --name Charlie
```

**Test bidirectional streaming:**
```bash
dart run bin/client.dart --method bidirectional --name Diana
```

**Test all methods:**
```bash
dart run bin/client.dart --method all --name Eve
```

**Connect to a different host/port:**
```bash
dart run bin/client.dart --host 192.168.1.100 --port 9090 --name Frank
```

### Client Options

```
Options:
  -h, --host        Server host (default: localhost)
  -p, --port        Server port (default: 50051)
  -n, --name        Your name (default: World)
  -m, --method      RPC method to call
                    [unary, server-stream, client-stream, bidirectional, all]
                    (default: unary)
      --help        Show help
```

## Examples

### Example 1: Simple Greeting (Unary RPC)

**Terminal 1 (Server):**
```bash
$ dart run bin/server.dart
✓ gRPC Server listening on port 50051
Press Ctrl+C to stop the server
Received unary request from: Alice
```

**Terminal 2 (Client):**
```bash
$ dart run bin/client.dart --name Alice
Connecting to gRPC server at localhost:50051

Testing Unary RPC
────────────────────────────────────────────────────────────
Sending request: name="Alice"
✓ Received response: Hello, Alice!
```

### Example 2: Server Streaming

**Client:**
```bash
$ dart run bin/client.dart --method server-stream --name Bob
Connecting to gRPC server at localhost:50051

Testing Server Streaming RPC
────────────────────────────────────────────────────────────
Sending request: name="Bob"
Receiving stream of responses:
  [1] Hello, Bob!
  [2] Hi, Bob!
  [3] Hey, Bob!
  [4] Greetings, Bob!
  [5] Welcome, Bob!
✓ Received 5 messages from server
```

### Example 3: Client Streaming

**Client:**
```bash
$ dart run bin/client.dart --method client-stream --name Charlie
Connecting to gRPC server at localhost:50051

Testing Client Streaming RPC
────────────────────────────────────────────────────────────
Sending stream of 5 requests...
Sending: name="Charlie"
Sending: name="Alice"
Sending: name="Bob"
Sending: name="Charlie"
Sending: name="Diana"
✓ Received final response: Hello to all: Charlie, Alice, Bob, Charlie, Diana!
```

### Example 4: Bidirectional Streaming

**Client:**
```bash
$ dart run bin/client.dart --method bidirectional --name Diana
Connecting to gRPC server at localhost:50051

Testing Bidirectional Streaming RPC
────────────────────────────────────────────────────────────
Starting bidirectional conversation...

→ Sending: name="I am Diana"
← Received: Response #1: Hello, I am Diana! Nice to chat with you.
→ Sending: name="How are you?"
← Received: Response #2: Hello, How are you?! Nice to chat with you.
→ Sending: name="Nice weather today"
← Received: Response #3: Hello, Nice weather today! Nice to chat with you.
→ Sending: name="Goodbye!"
← Received: Response #4: Hello, Goodbye!! Nice to chat with you.

✓ Exchanged 4 messages
```

## Protocol Buffer Definition

The service is defined in `protos/greeter.proto`:

```protobuf
syntax = "proto3";

package greeter;

service Greeter {
  rpc SayHello (HelloRequest) returns (HelloReply) {}
  rpc SayHelloStream (HelloRequest) returns (stream HelloReply) {}
  rpc SayHelloClientStream (stream HelloRequest) returns (HelloReply) {}
  rpc SayHelloBidirectional (stream HelloRequest) returns (stream HelloReply) {}
}

message HelloRequest {
  string name = 1;
}

message HelloReply {
  string message = 1;
}
```

## Development

### Modifying the Service

1. Edit `protos/greeter.proto` to add new methods or messages
2. Regenerate code: `./generate_protos.sh`
3. Implement new methods in `bin/server.dart`
4. Update client calls in `bin/client.dart`

### Testing

This project includes a comprehensive test suite covering:
- **Unit tests** for individual service methods
- **Integration tests** for end-to-end workflows
- **Error handling tests** for failure scenarios
- **Performance tests** for stress testing
- **Edge case tests** for unusual inputs

#### Running Tests

**Run all tests:**
```bash
dart test
```

**Run tests with verbose output:**
```bash
dart test --reporter=expanded
```

**Run specific test file:**
```bash
dart test test/server_test.dart
dart test test/integration_test.dart
dart test test/error_handling_test.dart
```

**Run tests matching a pattern:**
```bash
dart test --name "unary"
dart test --name "streaming"
```

**Run tests with coverage:**
```bash
dart test --coverage=coverage
dart pub global activate coverage
dart pub global run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib
```

#### Test Structure

```
test/
├── test_helpers.dart         # Shared test utilities and helpers
├── server_test.dart           # Unit tests for server methods
├── integration_test.dart      # End-to-end integration tests
└── error_handling_test.dart   # Error scenarios and recovery tests
```

#### Test Coverage

The test suite includes:

**Server Tests** (test/server_test.dart):
- ✓ Unary RPC with various inputs (empty, special chars, unicode, long strings)
- ✓ Server streaming with cancellation support
- ✓ Client streaming with single/multiple/empty streams
- ✓ Bidirectional streaming with rapid messages
- ✓ Server lifecycle (start, stop, restart)
- ✓ Multiple concurrent clients

**Integration Tests** (test/integration_test.dart):
- ✓ Full workflow testing (all RPC patterns in sequence)
- ✓ Concurrent operations from multiple clients
- ✓ Stress testing (100+ concurrent calls)
- ✓ Mixed workload scenarios
- ✓ Large payload handling (10KB+ messages)
- ✓ Long-running streams (50+ messages)
- ✓ Performance benchmarks
- ✓ Message ordering verification
- ✓ Edge cases (empty strings, unicode, emojis, whitespace)

**Error Handling Tests** (test/error_handling_test.dart):
- ✓ Connection failures (non-existent server, invalid host)
- ✓ Server shutdown during active calls
- ✓ Stream cancellations and interruptions
- ✓ Timeout handling
- ✓ Resource cleanup and leak prevention
- ✓ Recovery scenarios (reconnection after failure)
- ✓ Concurrent error scenarios

#### Example Test Output

```bash
$ dart test --reporter=expanded

00:00 +0: loading test/server_test.dart
00:00 +0: loading test/integration_test.dart
00:00 +0: loading test/error_handling_test.dart

GreeterService - Unary RPC sayHello returns correct greeting for single name
00:01 +1: GreeterService - Unary RPC sayHello handles empty name
00:01 +2: GreeterService - Unary RPC sayHello handles special characters
...

End-to-End Integration Tests full workflow: unary -> server stream -> client stream -> bidirectional
00:05 +25: End-to-End Integration Tests concurrent operations from multiple clients
...

Connection Error Handling client fails to connect to non-existent server
00:08 +45: Connection Error Handling client handles server shutdown during unary call
...

00:15 +89: All tests passed!
```

#### Manual Testing

For manual testing:

1. Start the server in one terminal:
   ```bash
   dart run bin/server.dart
   ```

2. Run the client with `--method all` to test all RPC patterns:
   ```bash
   dart run bin/client.dart --method all --name YourName
   ```

3. Monitor server logs for incoming requests

#### Continuous Integration

To set up CI/CD, add this to your workflow:

```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: dart-lang/setup-dart@v1
      - run: dart pub get
      - run: dart test
```

## Common Issues

**Port already in use:**
- Change the port: `dart run bin/server.dart 9090`
- And connect client: `dart run bin/client.dart --port 9090`

**Connection refused:**
- Ensure the server is running
- Check firewall settings
- Verify the host and port are correct

**Missing dependencies:**
- Run `dart pub get` to install all dependencies

## Learning Resources

- [gRPC Documentation](https://grpc.io/docs/)
- [Protocol Buffers](https://protobuf.dev/)
- [Dart gRPC Package](https://pub.dev/packages/grpc)
- [Dart Language Tour](https://dart.dev/guides/language/language-tour)

## License

This project is provided as-is for educational purposes.

## Contributing

Feel free to extend this project with:
- Authentication/authorization
- TLS/SSL support
- Error handling improvements
- Additional RPC methods
- Interceptors and middleware
- Metrics and monitoring

Happy coding with gRPC and Dart!
