# All Error fields visibble to this file are documented here
# Error Field - HTTP Status Code
# created      - 201
# unauthorized - 401
# nothuman     - 402
# notfound     - 404
# duplicate    - 409
# tryagain     - 500

config = require('./utils/config')

account = require('./features/account')
auth = require('./features/auth')
utils = require('./utils/routines')

module.exports = (app) ->
  # 删除用户
  app.delete('/accounts/users', (req, res) ->
    renderNotImplemented(req, res)
  )

  # 重置密码，供后台管理员使用，不需要任何验证
  app.put('/admin/passwords', (req, res) ->
    uid = req.header('uid')
    body = req.body
    account.setPassword(uid, body.newPassword, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 设置新密码，供用户找回密码使用
  #
  # 1. 该api只被frontend调用。
  # 2. 用户通过点击重置密码邮件执行该操作，必须验证用户身份
  # 3. 不能通过frontend验证cookie方式进行，所以这里由backend验证token
  app.put('/accounts/passwords/reset', (req, res) ->
    body = req.body
    account.resetPassword(body.uid, body.token, body.newPassword, (err, result) ->
      if err?
        if err.unauthorized
          res.send(402)
        else if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 会话校验
  # GET /auth/sessions
  # Header uid: xxxxxxxx
  # Header token: xxxxxxxxxxx # valid session token
  # Response 'xxxxxxxxxxxxx' # renewed session token
  # Sample: curl -H 'uid: 100000' -H 'token: xxxxxxxxxxxx' majun.homeserver.com:16384/auth/sessions
  app.get('/auth/sessions', (req, res) ->
    uid = req.header('uid')
    token = req.header('token')
    auth.validateSession(uid, token, (err, result) ->
      if err?
        res.setHeader('WWW-Authenticate', 'Credentials realm="cunpai.com"')
        res.send(401)
      else
        res.json({
          protocol: 1.0,
          renewedSession: result
        })
    )
  )

  app.post('/auth/tokens', (req, res) ->
    captcha = req.body.captcha ? ''
    if typeof captcha != 'string'
      res.send(400)
      return
    auth.generateCaptchaToken(captcha, req.query.idle, (err, result) ->
      res.json({
        protocol: 1.0,
        token: result
      })
    )
  )

