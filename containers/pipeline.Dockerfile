FROM python:3.6-bullseye

RUN apt-get update && apt-get install -y \
    build-essential python3-dev python3-pip sudo \
    libxml2-dev libxslt-dev zlib1g-dev libssl-dev libsqlite3-dev \
    libffi-dev git tmux fontconfig-config fonts-dejavu-core \
    libfontconfig1 libjpeg-turbo-progs libjpeg-progs libjpeg-dev lsof ffmpeg youtube-dl \
    autossh rsync proxychains-ng tini zstd && \
    git clone https://gitea.arpa.li/JustAnotherArchivist/little-things /tmp/JAAs-little-things && \
    cd /tmp/JAAs-little-things && \
    chmod +x /tmp/JAAs-little-things/* && \
    mv /tmp/JAAs-little-things/* /usr/local/bin/ && \
    rm -rf /tmp/JAAs-little-things && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /home/archivebot/ArchiveBot/pipeline
COPY pipeline/requirements.txt /home/archivebot/ArchiveBot/pipeline/requirements.txt
RUN pip install --no-cache-dir -r /home/archivebot/ArchiveBot/pipeline/requirements.txt

COPY . /home/archivebot/ArchiveBot

RUN groupadd -r archivebot && useradd -r -m -g archivebot archivebot && \
    chown -R archivebot:archivebot /home/archivebot/ && \
    chmod -Rv 0755 /home/archivebot/ && \
    mkdir -p /pipeline/completed /pipeline/logs && \
    chown -R archivebot:archivebot /pipeline && \
    chmod -Rv 0755 /pipeline && \
    ln -s /usr/local/bin/wpull /home/archivebot/ArchiveBot/pipeline/wpull && \
    chmod +x /home/archivebot/ArchiveBot/pipeline/wpull
WORKDIR /home/archivebot/ArchiveBot/pipeline
COPY --chown=archivebot:archivebot containers/pipeline.entrypoint.sh /_pipeline_entrypoint.sh
ENTRYPOINT ["/usr/bin/tini", "--", "/_pipeline_entrypoint.sh"]
ENV PYTHONUNBUFFERED=1
