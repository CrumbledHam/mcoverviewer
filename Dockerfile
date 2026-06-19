FROM python:3.9-slim

ENV DEBIAN_FRONTEND=noninteractive

# wget/xz-utils: fetch and unpack the Overviewer release tarball
# unzip: inspect and extract texture jars/zips at runtime
RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
	   ca-certificates wget xz-utils unzip \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Pull the pre-built Overviewer binary (no C build toolchain needed) and
# the official Mojang 1.21 client jar for textures. The jar is used as the
# default texture source when no TEXTURE_PATH is supplied at runtime.
RUN wget https://github.com/GregoryAM-SP/The-Minecraft-Overviewer/releases/download/1.21.0/overviewer-v1.21.0-LINUX.tar.xz \
	&& tar -xf overviewer-v1.21.0-LINUX.tar.xz \
	&& mv overviewer/* /usr/local/bin/ \
	&& rm -rf overviewer overviewer-v1.21.0-LINUX.tar.xz \
	&& mkdir -p /opt/minecraft-textures \
	&& wget https://overviewer.org/textures/1.21 -O /opt/minecraft-textures/1.21.jar

# Render loop + HTTP server; installed as a named command for clarity
COPY entrypoint.sh /usr/local/bin/overviewer-render
RUN chmod +x /usr/local/bin/overviewer-render

# /world  — Minecraft world directory (mount read-only)
# /output — rendered map tiles and HTML
VOLUME ["/world", "/output"]

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/overviewer-render"]
