#!/bin/bash

services=("cluster-api-provider-openstack" "cloud-provider-openstack" "image-registry" "cluster-image-registry-operator" "kubernetes-apiserver" "cloud-credential-operator")
cert_dir=$CA_BUNDLE

for service in $services; do
    git clone https://github.com/openshift/$service
    if [ "$service" -ne "cloud-provider-openstack" ] || [ "$service" -ne "kubernetes-apiserver" ]; then
        cd $service
        echo "COPY $cert_dir /etc/pki/ca-trust/source/anchors/" >> Dockerfile
        echo "RUN update-ca-trust" >> Dockerfile ## This might need sudo. This may be a problem.

        ## Alternative strategies:
        #### https://www.happyassassin.net/2015/01/14/trusting-additional-cas-in-fedora-rhel-centos-dont-append-to-etcpkitlscertsca-bundle-crt-or-etcpkitlscert-pem/
        #### https://github.com/openshift/cluster-image-registry-operator/blob/8b59dceb5a690d93f592cb83a3d0fc6359437103/images/bin/entrypoint.sh
    
    else

done
