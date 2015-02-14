'use strict';

app = angular.module('app.user.services', [])

app.factory('blacklistInfo', ['$scope', '$http', ($scope, $http) ->
  $http.get('/api/blacklist')
])