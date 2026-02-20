FROM golang:1.24 AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o harvester-csi-driver .

FROM registry.suse.com/bci/bci-base:15.7
# hadolint ignore=DL3034,DL3037
RUN zypper -n install --no-recommends \
    e2fsprogs \
    xfsprogs \
    util-linux \
  && zypper clean -a
COPY --from=builder /src/harvester-csi-driver /usr/local/bin/harvester-csi-driver
ENTRYPOINT ["/usr/local/bin/harvester-csi-driver"]