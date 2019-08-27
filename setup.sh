#!/bin/bash

if [ -z "${GRAALVM_HOME}" ]; then
	echo "GRAALVM_HOME is not set"
	exit
fi

if [ -z "${JAVA_HOME}" ]; then
	echo "JAVA_HOME is not set"
	exit
fi

pushd "${GRAALVM_HOME}"/bin &>/dev/null
./gu install native-image
popd &>/dev/null

./mvnw package

./mvnw package -Pnative
