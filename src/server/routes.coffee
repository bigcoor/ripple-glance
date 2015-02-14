profile = require './controllers/profile'

module.exports = (app) ->
  # 注册新用户
  app.post('/accounts/users', (req, res) ->
    body = req.body
    captcha = req.body.captcha ? ''
    captchaToken = req.body.token

    async.waterfall([
        async.apply(auth.validateCaptchaToken, captcha, captchaToken),
        async.apply(account.register, body.email, body.nick, body.password)
      ], (err, result) ->
      if err?
        if err.nothuman
          res.send(402) # Payment Required, like YouTube
        else if err.duplicate
          res.send(409)
        else if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )