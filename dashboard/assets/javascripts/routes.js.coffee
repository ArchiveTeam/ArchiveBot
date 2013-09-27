Dashboard.Router.map ->
  @route 'history', path: '/histories/*url'

Dashboard.IndexRoute = Ember.Route.extend
  setupController: (controller) ->
    controller.set('controllers.jobs.model', Dashboard.get('messageProcessor.jobs'))

  gotoHistory: (url) ->
    @transitionTo 'history', url

Dashboard.HistoryRoute = Ember.Route.extend
  model: (params) ->
    $.getJSON("/histories/#{params['url']}").then (data) ->
      data['rows'].map (row) ->
        Dashboard.JobHistoryEntry.create row['doc']

  serialize: (model) ->
    { url: model.get 'url' }

# vim:ts=2:sw=2:et:tw=78
