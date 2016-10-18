FROM ruby:latest
MAINTAINER David Yip <yipdw@member.fsf.org>

RUN apt-get -yqq update && apt-get -yqq dist-upgrade

# plumbing needs ZeroMQ
RUN apt-get install -yqq libzmq3-dev

# useful diagnostic tools for when stuff goes wrong
RUN apt-get install -yqq vim git traceroute jq

RUN adduser --home /home/archivebot --shell /bin/bash \
	--uid 1000 archivebot --quiet --disabled-password

VOLUME /home/archivebot/ArchiveBot

USER archivebot
WORKDIR /home/archivebot/ArchiveBot
