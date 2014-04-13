window.Dashboard = Ember.Application.create
  ready: ->
    # Some dashboard processes need to run periodically.  We use a clock for
    # that.
    #
    # The clock is set to fire off around once every second, subject to the
    # usual Javascript clock wonkiness.  Fortunatly, we can deal with that.
    Dashboard.set('currentTime', moment())

    setInterval (->
      Dashboard.set('currentTime', moment())
    ), 1000

# vim:ts=2:sw=2:et:tw=78
