window.Dashboard = Ember.Application.create
  ready: ->
    # setInterval doesn't immediately trigger, so we set currentTime off the
    # bat to make sure that we have a currentTime value.
    Dashboard.set('currentTime', moment())

    setInterval (->
      Dashboard.set('currentTime', moment())
    ), 60000

# vim:ts=2:sw=2:et:tw=78
