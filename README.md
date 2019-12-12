# Install OpenShift on an OpenStack cluster secured by a self-signed certificate

This script prepares an OpenShift release to accept an additional x.509 CA certificate when interacting with OpenStack.

This script exists for testing purposes only and is not supported in production environments.


## Requirements

  * bash 4.4+
  * grep
  * [jq](https://stedolan.github.io/jq)
  * either podman or docker
  * openshift-installer for automatic image detection (required if "-i" is not used)
  * oc, the OpenShift command-line client

## Usage

```shell
./main.sh [-i release_image] -o dst_image -f cert_file
```

* `-i`: Specify the release image to be used in the build. By default, the image is determined using `openshift-install`, which must be in `$PATH`
* `-o`: Specify the destination registry image. The container runtime must have push privileges, as several images will be pushed there.
* `-f`: Specify the PEM or DER file containing the certificate.
* `-h`: Print this help
