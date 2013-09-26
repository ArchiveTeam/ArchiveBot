messageProcessor = Dashboard.MessageProcessor.create
  jobIndex: {}
  jobs: []

Dashboard.set 'messageProcessor', messageProcessor

ws = new WebSocket('ws://' + window.location.host + '/stream')

ws.onmessage = (msg) ->
  messageProcessor.process(msg.data)

# vim:ts=2:sw=2:et:tw=78
