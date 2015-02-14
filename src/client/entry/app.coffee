'use strict'

require '../Users/UserCtrl.coffee'
require '../Users/UserServices.coffee'
require '../Chart/ChartCtrl.coffee'
require '../Chart/ChartDirective.coffee'
require '../Form/FormCtrl.coffee'
require '../Form/FormDirective.coffee'
require '../Form/FormValidation.coffee'
require '../Table/TableCtrl.coffee'
require '../Task/Task.coffee'
require '../UI/UICtrl.coffee'
require '../UI/UIDirective.coffee'
require '../UI/UIService.coffee'


#services
require '../Services/blob.coffee'

#directives
require '../shared/directives.coffee'
require '../shared/localize.coffee'
require '../shared/main.coffee'

#Global config
require '../utils/config.coffee'

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
  'app.user.ctrls'
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
    name: 'User'
    icon: 'fa-users'
    subTabs: [
      {
        name: 'User Blacklist'
        path: '/users/blacklist'
        templateUrl: 'views/users/blacklist.html'
      }
    ]
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

app.config(['$routeProvider', '$httpProvider', '$injector', ($routeProvider, $httpProvider, $injector) ->
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
  $httpProvider.interceptors.push(($q, $rootScope, logger) ->
    return {
      request: (config) ->
        return config
      response: (response) ->
        if (response.success && response.success == false)
          logger.logError(response.success)
          $rootScope.logout()
        return response
    }
  )
])

