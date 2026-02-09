#!/bin/bash

# Get version from GitHub environment variable
version=${VERSION}

# Check if version is provided
if [ -z "$version" ]
then
    echo "No version specified. No kernel or clang will be cloned. Exiting..."
    exit 1
fi

# Convert the YAML file to JSON
json=$(python -c "import sys, yaml, json; json.dump(yaml.safe_load(sys.stdin), sys.stdout)" < sources.yaml)

# Parse the JSON file
kernel_commands=$(echo $json | jq -r --arg version "$version" '.[$version].kernel[]')
clang_commands=$(echo $json | jq -r --arg version "$version" '.[$version].clang[]')

# Print the commands that will be executed
echo -e "\033[31mClone.sh will execute following commands corresponding to ${version}:\033[0m"
echo "$kernel_commands" | while read -r command; do
    echo -e "\033[32m$command\033[0m"
done
echo "$clang_commands" | while read -r command; do
    echo -e "\033[32m$command\033[0m"
done

# Clone the kernel and append clone path to the command
echo "$kernel_commands" | while read -r command; do
    eval "$command kernel"
done

# Setup clang toolchain (skip if restored from cache)
if [ -d "clang-cache/bin" ]; then
    echo -e "\033[32mClang toolchain restored from cache, skipping download.\033[0m"
else
    # Commands run inside the kernel directory so paths are relative to it
    cd kernel
    echo "$clang_commands" | while read -r command; do
        eval "$command"
    done
    cd ..
fi
