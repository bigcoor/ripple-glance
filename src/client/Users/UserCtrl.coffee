'use strict'
querystring = require 'querystring'

app = angular.module('app.user.ctrls', [])

app.controller('BlacklistCtrl', ["$scope", "$http", ($scope, $http) ->
  $scope.loadBlacklistInfo = (count, offset)->
    if count? and offset?
      _uri = "api/user/blacklist?" + querystring.stringify({count: count, offset: offset})
    else
      _uri =  "api/user/blacklist"

    $http
    .get(_uri)
    .success (data) ->
      console.log(data, ">>>>>>>>")
      $scope.userTimeLine = data.result.userTimeLine
      console.log($scope)

      $scope.totalItems = data.result.blacklistCommentsCount

  $scope.deleteReply = (postId, replyId, ownerId, uid, callback) ->
    if postId? and replyId? and ownerId
      _uri = "/api/posts/#{postId}/replies/#{replyId}?" + querystring.stringify({owner: ownerId})
    else
      _uri =  "api/user/blacklist"

    $http(
      method: 'DELETE'
      url: _uri
      headers:
        uid: uid
    )
    .success (data) ->
      console.log(data, ">>>>>>>>")
      console.log($scope)
      callback(null, data)
    .error (err) ->
      callback(err)


  $scope.loadBlacklistInfo()

  #pagination for comment table
  #

  $scope.currentPage = 1
  $scope.itemsPerPage = 20

  $scope.setPage = (pageNo) ->
    $scope.currentPage = pageNo
    _count = $scope.itemsPerPage
    _offset = (pageNo - 1) * _count

    $scope.loadBlacklistInfo(_count, _offset)

  $scope.deleteComment = (comment) ->
    [postId, replyId, ownerId, uid] = [comment.pid, comment.key, comment.puid, comment.uid]
    $scope.deleteReply(postId, replyId, ownerId, uid, (err, data) ->
      reloadUserTimeLine = []
      if err?
        console.log(err)
      else
        for comment in $scope.userTimeLine
          continue if replyId == comment.key
          reloadUserTimeLine.push(comment)

      $scope.userTimeLine = reloadUserTimeLine
    )

])