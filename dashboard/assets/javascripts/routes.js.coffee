Dashboard.Router.map ->
  @route 'history', path: '/histories/*url'

Dashboard.IndexRoute = Ember.Route.extend
  setupController: (controller, model) ->
    # Pass the message processor to the controller.
    controller.set('messageProcessor', model)
    controller.startLogSocket()

    # Bootstrap the processor.
    $.getJSON('logs/recent').then (logs) ->
      model.process(log) for log in logs
      controller.set('dataLoaded', true)

  model: (params) ->
    Dashboard.MessageProcessor.create(jobIndex: {}, jobs: [])

  actions:
    willTransition: (transition) ->
      @controllerFor('index').stopLogSocket()

  gotoHistory: (url) ->
    @transitionTo 'history', url

Dashboard.HistoryRoute = Ember.Route.extend
  model: (params) ->
    url = @requestedUrl(params)

    $.getJSON("/histories?url=#{encodeURIComponent(url)}").then (data) ->
      ret = data['rows'].map (row) -> Dashboard.JobHistoryEntry.create row['doc']
      ret.set 'url', url
      ret

  # If the URL ends with a /, Ember's router will swallow the /.  However,
  # that bit is important to us -- http://www.example.com/foo is not in
  # general the same as http://www.example.com/foo/.
  requestedUrl: (params) ->
    locationHref = window.location.href

    endsWith = (haystack, needle) ->
      haystack.lastIndexOf(needle) == haystack.length - needle.length

    if endsWith(locationHref, '/') && !endsWith(params['url'], '/')
      "#{params['url']}/"
    else
      params['url']

  serialize: (model) ->
    { url: model.get 'url' }

# vim:ts=2:sw=2:et:tw=78
