Dashboard.Router.map ->
  @route 'history', path: '/histories/*url'

Dashboard.IndexRoute = Ember.Route.extend
  setupController: (controller) ->
    controller.set('controllers.jobs.model', Dashboard.get('messageProcessor.jobs'))

  gotoHistory: (url) ->
    @transitionTo 'history', url

Dashboard.HistoryRoute = Ember.Route.extend
  model: (params) ->
    Dashboard.JobHistory.create(url: params['url']).fetch()

  serialize: (model) ->
    { url: model.get 'url' }

# vim:ts=2:sw=2:et:tw=78
