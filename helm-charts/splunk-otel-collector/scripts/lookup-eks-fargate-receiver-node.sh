#! /usr/bin/bash
set -ex

# exit successfully if we aren't the second replica
if [[ "${K8S_POD_NAME}" != *-1 ]]; then
  echo "EKS kubelet stats receiver node lookup not applicable for $K8S_POD_NAME. Ensuring it won't monitor itself to avoid Fargate network limitation."
  echo "export CR_KUBELET_STATS_NODE_FILTER=\"&& not ( name contains \"\'${K8S_NODE_NAME}\'\" )\"" > /splunk-messages/environ

  echo "Disabling k8s_cluster receiver for this instance"

  curl -L -o yq https://github.com/mikefarah/yq/releases/download/v4.16.2/yq_linux_amd64
  ACTUAL=$( sha256sum yq | awk '{print $1}' )
  if [ "${ACTUAL}" != "5c911c4da418ae64af5527b7ee36e77effb85de20c2ce732ed14c7f72743084d" ]; then
    echo "will not attempt to use yq with unexpected sha256 (${ACTUAL} != 5c911c4da418ae64af5527b7ee36e77effb85de20c2ce732ed14c7f72743084d)";
    exit 1
  fi
  chmod a+x yq
  ./yq e 'del(.service.pipelines.metrics.receivers[0])' /conf/relay.yaml > /splunk-messages/config.yaml
  exit 0
fi

FIRST_REPLICA_POD="${K8S_POD_NAME::-1}0"

# download kubectl (verifying checksum)
curl -o kubectl https://amazon-eks.s3.us-west-2.amazonaws.com/1.16.15/2020-11-02/bin/linux/amd64/kubectl
curl -o kubectl.sha256 https://amazon-eks.s3.us-west-2.amazonaws.com/1.16.15/2020-11-02/bin/linux/amd64/kubectl.sha256
ACTUAL=$( sha256sum kubectl | awk '{print $1}' )
EXPECTED=$( cat kubectl.sha256 | awk '{print $1}' )
if [ "${ACTUAL}" != "${EXPECTED}" ]; then
  echo "will not attempt to use kubectl with unexpected sha256 (${ACTUAL} != ${EXPECTED})";
  exit 1
fi
chmod a+x kubectl

# lookup cluster receiver pod 0's node name
echo "looking up node for $FIRST_REPLICA_POD"

FIRST_CR_REPLICA_NODE_NAME=$(./kubectl get pods $FIRST_REPLICA_POD -o=jsonpath='{.spec.nodeName}')

if [ -n "${FIRST_CR_REPLICA_NODE_NAME}" ]; then
  echo "will configure kubelet stats receiver to follow node ${FIRST_CR_REPLICA_NODE_NAME}, as well as use cluster receiver."
  echo "export CR_KUBELET_STATS_NODE_FILTER=\"&& name == \"\'${FIRST_CR_REPLICA_NODE_NAME}\'\"\"" > /splunk-messages/environ
  cat /splunk-messages/environ
fi


cp /conf/relay.yaml /splunk-messages/config.yaml
