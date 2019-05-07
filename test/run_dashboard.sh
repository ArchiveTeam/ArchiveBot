#!/bin/bash

export REDIS_URL=redis://localhost:6379/0
bundle exec ruby dashboard/app.rb
