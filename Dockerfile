FROM golang:1.26-bookworm AS backend-builder
RUN apt update && apt install -y liblz4-dev
WORKDIR /tmp/src
COPY go.mod .
COPY go.sum .
RUN go mod download
COPY . .
ARG VERSION=unknown
RUN go build -mod=readonly -ldflags "-X main.version=$VERSION" -o coroot .


FROM registry.access.redhat.com/ubi9/ubi AS runtime-deps
RUN mkdir /data && chown 65534:65534 /data


# ubi-micro: only glibc; the runtime bits coroot needs are copied in to keep OS CVE surface minimal
FROM registry.access.redhat.com/ubi9/ubi-micro

ARG VERSION=unknown
LABEL name="coroot" \
      vendor="Coroot, Inc." \
      maintainer="Coroot, Inc." \
      version=${VERSION} \
      release="1" \
      summary="Coroot Community Edition." \
      description="Coroot Community Edition container image."

COPY LICENSE /licenses/LICENSE

COPY --from=runtime-deps /lib64/liblz4.so.1 /lib64/liblz4.so.1.9.3 /lib64/
COPY --from=runtime-deps /etc/pki /etc/pki
COPY --from=runtime-deps /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=runtime-deps --chown=65534:65534 /data /data
COPY --from=backend-builder /tmp/src/coroot /usr/bin/coroot

USER 65534:65534
VOLUME /data
EXPOSE 8080

ENTRYPOINT ["/usr/bin/coroot"]
