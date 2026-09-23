FROM debian:bullseye-slim
ENV LC_ALL=C
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt-get -qqy --no-install-recommends -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-unsafe-io install \
    tini curl sudo gnupg ca-certificates apt-utils build-essential ruby ruby-dev bundler python3 python3-websockets git libzmq5 libzmq3-dev libssl-dev && \
    echo 'deb http://deb.debian.org/debian bullseye-backports main' >/etc/apt/sources.list.d/backports.list && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt-get -qqy --no-install-recommends -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-unsafe-io -t bullseye-backports install zstd && \
    git clone https://gitea.arpa.li/JustAnotherArchivist/little-things /tmp/JAAs-little-things && \
    cd /tmp/JAAs-little-things && \
    chmod +x /tmp/JAAs-little-things/* && \
    mv /tmp/JAAs-little-things/* /usr/local/bin/ && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /home/archivebot/ArchiveBot

COPY Gemfile /home/archivebot/ArchiveBot/Gemfile
COPY plumbing/Gemfile /home/archivebot/ArchiveBot/plumbing/Gemfile
ENV GEM_HOME=/home/archivebot/.gems
RUN bundle install && \
    cd plumbing && \
    bundle install && \
    gem install bundler -v 1.15.1
COPY . /home/archivebot/ArchiveBot
RUN rm /home/archivebot/ArchiveBot/Gemfile.lock && \
    rm /home/archivebot/ArchiveBot/plumbing/Gemfile.lock
RUN cd /home/archivebot/ArchiveBot/ && \
    bundle install --path /home/archivebot/.gems

RUN groupadd -r archivebot && useradd -r -m -g archivebot archivebot && \
    chown -R archivebot:archivebot /home/archivebot/ &\
    chmod -R 0755 /home/archivebot/ &\
    wait
# USER archivebot
WORKDIR /home/archivebot/ArchiveBot
ENV PATH="/home/archivebot/.gems/ruby/2.7.0/bin:${PATH}" \
    PYTHONUNBUFFERED=1
ENTRYPOINT ["/usr/bin/tini", "--", "/home/archivebot/ArchiveBot/entrypoint.sh"]
CMD ["help"]
