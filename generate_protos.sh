#!/bin/bash

# Generate Dart code from proto files

# Install protoc_plugin if not already installed
dart pub global activate protoc_plugin

# Add dart pub global bin to PATH
export PATH="$PATH":"$HOME/.pub-cache/bin"

# Create output directory if it doesn't exist
mkdir -p lib/src/generated

# Generate Dart code
protoc --dart_out=grpc:lib/src/generated -Iprotos protos/*.proto

echo "Proto files generated successfully!"
