messageProcessor = Dashboard.MessageProcessor.create
  jobIndex: {}
  jobs: []

Dashboard.set 'messageProcessor', messageProcessor

# Open a WebSocket to the log broadcaster.  Whenever we receive a log event,
# process it.
ws = new WebSocket('ws://' + window.location.host + '/stream')

ws.onmessage = (msg) ->
  messageProcessor.process(msg.data)

# Prime ourselves with the latest log entries.
$.getJSON('logs/recent').then (logs) ->
  logs.forEach (log) ->
    messageProcessor.process(log)

# vim:ts=2:sw=2:et:tw=78
