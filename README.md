# Install OpenShift on an OpenStack cluster secured by a self-signed certificate

1. ask for a quay or dockerHub account
1. call the openstack endpoint and get the CA cert
1. download the release image
1. for each image listed as needing Openstack TLS, buildah a new layer with the cert added
1. build the release image
1. print the fully-qualified URL of the image for it to be used as OVERRIDE_IMAGE
