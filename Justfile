kind-create:
  envsubst < kind.yaml \
  | kind create cluster \
    --name sigstore \
    --config - \
  && kubectl --context=kind-sigstore wait \
    --for=condition=Ready \
    --timeout=2m \
    node/sigstore-control-plane

kind-delete:
  kind delete cluster --name sigstore

registry:
  #!/usr/bin/env bash
  set -x

  reg_name="kind-registry"
  reg_port="5001"
  if [ "$(docker inspect -f "{{"{{"}}.State.Running{{"}}"}}" "${reg_name}" 2>/dev/null || true)" != "true" ]; then
    docker run \
      -d --restart=always \
      -p "127.0.0.1:${reg_port}:5000" \
      --network bridge \
      --name "${reg_name}" \
      registry:2
  fi

  reg_dir="${HOME}/.docker/certs.d/localhost:${reg_port}"
  if [ ! -d $reg_dir ]; then
    mkdir -p $reg_dir
    echo "[host.\"http://${reg_name}:5000\"]" > $reg_dir/hosts.toml
  fi

  if [ "$(docker inspect -f="{{"{{"}}json .NetworkSettings.Networks.kind{{"}}"}}" "${reg_name}")" = "null" ]; then
    docker network connect "kind" "${reg_name}"
  fi

  cat <<EOF | kubectl --context=kind-sigstore apply -f -
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: local-registry-hosting
    namespace: kube-public
  data:
    localRegistryHosting.v1: |
      host: "localhost:${reg_port}"
      help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
  EOF

flux:
  #!/usr/bin/env bash

  kubectl --context=kind-sigstore \
  apply -k github.com/fluxcd/flux2/manifests/crds

  helm --kube-context=kind-sigstore \
    upgrade --install flux \
    --create-namespace \
    --namespace flux-system \
    --values flux-values.yaml \
    oci://ghcr.io/fluxcd-community/charts/flux2

push:
  #!/usr/bin/env bash
  set +e

  tar zcvf data.tar.gz kubernetes
  oras push localhost:5001/sigstore:latest data.tar.gz
  rm -f data.tar.gz

find-recent-tag image:
  #!/usr/bin/env bash

  TAG=$(skopeo list-tags docker://{{image}} \
  | jq -r '.Tags[]' \
  | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
  | sort -V | tail -n 1)

  SHA=$(oras discover {{image}}:${TAG} \
  | tail -n +2 | cut -d' ' -f2)

  echo "{{image}}:${TAG}@${SHA}"