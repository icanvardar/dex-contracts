#!/bin/bash

# Check if the rpc-url argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <rpc-url>"
    exit 1
fi

# Run the forge script command with the provided rpc-url argument
forge script script/Deploy.s.sol:Deploy --broadcast --rpc-url "$1" -vvvv
 