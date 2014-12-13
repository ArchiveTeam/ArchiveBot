#!/bin/bash

export REDIS_URL=redis://localhost:6379/0
export UPDATES_CHANNEL=updates
plumbing/updates-listener | plumbing/log-firehose | bundle exec ruby dashboard/app.rb
