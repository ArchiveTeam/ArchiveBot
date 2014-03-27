messageProcessor = Dashboard.MessageProcessor.create
  jobIndex: {}
  jobs: []

Dashboard.set 'messageProcessor', messageProcessor

# Open a WebSocket to the log broadcaster.  Whenever we receive a log event,
# process it.
ws = new WebSocket('ws://' + window.location.host + '/stream')

ws.onmessage = (msg) ->
  messageProcessor.process(msg.data)

# vim:ts=2:sw=2:et:tw=78
