'use strict';

#Angular module dependencies
appDependencies = [
  # Angular modules
  'ngRoute'
  'ngAnimate'

  # 3rd Party Modules
  'ui.bootstrap'
  'easypiechart'
  'mgo-angular-wizard'
  'textAngular'

  # Custom modules
  'app.ui.ctrls'
  'app.ui.directives'
  'app.ui.services'
  'app.controllers'
  'app.directives'
  'app.form.validation'
  'app.ui.form.ctrls'
  'app.ui.form.directives'
  'app.tables'
  'app.task'
  'app.localization'
  'app.chart.ctrls'
  'app.chart.directives'
]

#TODO fix icon
tabControllers = [
  {
    name: 'Dashboard'
    path: '/dashboard'
    templateUrl: 'views/dashboard.html'
    icon: 'fa-dashboard'
  }
  {
    name: 'UI'
    icon: 'fa-graduation-cap'
    subTabs:[
      {
        name: 'UI Typography'
        path: '/ui/typography'
        templateUrl: 'views/ui/typography.html'
      }
      {
        name: 'UI Buttons'
        path: '/ui/typography'
        templateUrl: 'views/ui/typography.html'
      }
    ]
  }
]

app = angular.module('app', appDependencies)

#Global reference for debugging only (!)
lmClient = window.lmClient = {}
lmClient.app = app
lmClient.types = types



app.config(['$routeProvider', '$injector', ($routeProvider, $injector) ->
  angular.forEach(tabControllers, (route) ->
    if not route.subTabs?
      $routeProvider.when(route.path, {
        templateUrl: route.templateUrl
        controller: route.controller
      })
    angular.forEach(route.subTabs, (route) ->
      $routeProvider.when(route.path, {
        templateUrl: route.templateUrl
        controller: route.controller
      })
    )
  )

  #add non-sidebar routes here
# $routeProvider
#  .when('path', {
#    templateUrl : ''
#    controller  : ''
#  })
#  .otherwise({
#    redirectTo : '/dashboard'
#  })
])

