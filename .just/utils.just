find-recent-tag image:
  #!/usr/bin/env bash

  TAG=$(skopeo list-tags docker://{{image}} \
  | jq -r '.Tags[]' \
  | grep -E 'v[0-9]+\.[0-9]+\.[0-9]+' \
  | sed -nE 's/.*(v[0-9]+\.[0-9]+\.[0-9]+).*/\1/p' \
  | sort -V | tail -n 1)

  SHA=$(oras discover {{image}}:${TAG} \
  | tail -n +2 | cut -d' ' -f2)

  echo "{{image}}:${TAG}@${SHA}"

image-size image:
  echo "scale=2; $(\
    skopeo inspect docker://{{image}} \
    | jq '.LayersData[0].Size' \
    | xargs | tr ' ' '+' | bc \
  ) / (1024 * 1024)" | bc