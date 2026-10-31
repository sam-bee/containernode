#!/usr/bin/env bash
set -Eeuo pipefail

# Usage: build-and-load.sh /path/to/casefile-checkout
# Requires Docker, kubectl with cluster-admin access, and the containernode context.
SOURCE_DIR="$(realpath "${1:?Pass the Casefile source checkout}")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REVISION="$(git -C "$SOURCE_DIR" rev-parse HEAD)"
IMAGE="localhost/casefile:$REVISION"
EXPECTED_IMAGE="$(sed -n 's/^          image: \(localhost\/casefile:.*\)$/\1/p' "$SCRIPT_DIR/deployment.yaml")"
IMPORT_POD="casefile-image-import-$$"

if [[ "$IMAGE" != "$EXPECTED_IMAGE" ]]; then
  echo "Update deployment.yaml to $IMAGE before building this revision." >&2
  exit 1
fi
if [[ -n "$(git -C "$SOURCE_DIR" status --porcelain)" ]]; then
  echo "Use a clean source checkout so the image tag identifies its contents." >&2
  exit 1
fi
if [[ "$(kubectl get node containernode -o jsonpath='{.status.nodeInfo.architecture}')" != amd64 ]]; then
  echo "This build targets the amd64 containernode." >&2
  exit 1
fi

docker build --platform linux/amd64 --provenance=false --tag "$IMAGE" "$SOURCE_DIR"

cleanup() {
  kubectl delete pod -n kube-system "$IMPORT_POD" --ignore-not-found --wait=false >/dev/null
}
trap cleanup EXIT

# This temporary root pod can administer containerd through its socket. It does
# not need privileged mode, network access, or a service account token.
kubectl create -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $IMPORT_POD
  namespace: kube-system
spec:
  nodeName: containernode
  restartPolicy: Never
  activeDeadlineSeconds: 600
  automountServiceAccountToken: false
  containers:
    - name: import
      image: busybox:1.37.0
      command: ["sleep", "600"]
      securityContext:
        runAsUser: 0
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
      resources:
        requests:
          cpu: 10m
          memory: 32Mi
        limits:
          cpu: "1"
          memory: 128Mi
      volumeMounts:
        - name: k3s-bin
          mountPath: /host-bin
          readOnly: true
        - name: containerd
          mountPath: /run/containerd.sock
  volumes:
    - name: k3s-bin
      hostPath:
        path: /var/lib/rancher/k3s/data/current/bin
        type: Directory
    - name: containerd
      hostPath:
        path: /run/k3s/containerd/containerd.sock
        type: Socket
EOF

kubectl wait -n kube-system --for=condition=Ready "pod/$IMPORT_POD" --timeout=120s
kubectl exec -n kube-system "$IMPORT_POD" -- \
  /host-bin/ctr --address /run/containerd.sock --namespace k8s.io version
docker save "$IMAGE" | kubectl exec -i -n kube-system "$IMPORT_POD" -- \
  /host-bin/ctr --address /run/containerd.sock --namespace k8s.io images import -
echo "Imported $IMAGE on containernode. Commit the manifest change for Flux reconciliation."
