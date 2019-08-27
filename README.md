# quarkus-test

Environment variables to be set:
JAVA_HOME
GRAALVM_HOME
CRIU_HOME

Get OpenJ9 from https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u222-b10_openj9-0.15.1/OpenJDK8U-jdk_x64_linux_openj9_8u222b10_openj9-0.15.1.tar.gz

Get GraalVM from https://github.com/oracle/graal/releases/tag/vm-19.1.1

Install CRIU by following https://criu.org/Installation

Now run `./setup.sh`. This would generate a jar file and a native executable (using GraalVM).

Now run `./host_test.sh | tee logs`. This would trigger the tests and the results are captured in `logs` file.
Total 10 iterations are done for each test.
