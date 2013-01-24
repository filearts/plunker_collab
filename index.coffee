coffee = require("coffee-script")
express = require("express")
sharejs = require("share")
lactate = require("lactate")
assets = require("connect-assets")
nconf = require("nconf")
request = require("request")

Firebase = require("./firebase-node")
pkginfo = require("./package.json")


# Set defaults in nconf
require "./configure"


host = nconf.get("host")
wwwUrl = nconf.get("url:www")
apiUrl = nconf.get("url:api")


app = module.exports = express()


model = sharejs.server.createModel
  db:
    type: "none"
  reapTime: 1000 * 60 * 60 * 24  * 7 # One week
  forceReaping: true


model.on "disconnect", -> console.log "[DISCONNECT]", arguments...

builder = {}
lactateOptions = 
  "max age": "one week"
  

assets
  src: "#{__dirname}/assets"
  build: true
  minifyBuilds: true
  buildDir: "build"
  buildFilenamer: (filename) -> filename
  helperContext: builder


console.log "Building package"
builder.js("share")
console.log "Package built"


#app.use   (req, res, next) ->
  # Just send the headers all the time. That way we won't miss the right request ;-)
  # Other CORS middleware just wouldn't work for me
  # TODO: Minimize these headers to only those needed at the right time

  #res.set("Access-Control-Allow-Origin", host)
  #res.set("Access-Control-Allow-Methods", "OPTIONS,GET,PUT,POST,DELETE")
  #res.set("Access-Control-Allow-Headers", "Authorization, User-Agent, Referer, X-Requested-With, Proxy-Authorization, Proxy-Connection, Accept-Language, Accept-Encoding, Accept-Charset, Connection, Content-Length, Host, Origin, Pragma, Accept-Charset, Cache-Control, Accept, Content-Type")
  #res.set("Access-Control-Expose-Headers", "Link")
  #res.set("Access-Control-Max-Age", "60")
  
  #if "OPTIONS" == req.method then res.send(200)
  #else next()
  
  
#app.use express.logger()
app.use require("./middleware/vary").middleware()
app.use lactate.static "#{__dirname}/build", lactateOptions


permissions = new Firebase("https://plunker.firebaseio.com/permissions")
permissions.set({})

sharejs.server.attach app,
  browserChannel:
    cors: "*"
  browserchannel:
    cors: "*"
  auth: (agent, action) ->
    if action.name is "connect"
      return action.reject() unless agent.authentication
      
      request.get "#{apiUrl}/sessions/#{agent.authentication}", (err, response, body) ->
        return action.reject() if err
        return action.reject() if response.statusCode >= 400
        
        try
          session = JSON.parse(body)
        catch e
          return action.reject()
        
        agent.name =
          if session.user and session.user.name then "user:#{session.user.name}"
          else "session:#{session.id}"
        
        action.accept()
        
    else if action.name is "create"
      permissions.child(action.docName).child(agent.name).set
        write: true
        admin: true

      action.accept()
      
    else if action.name is "open"
      permRef = permissions.child(action.docName).child(agent.name)
      permRef.once "value", (snapshot) ->
        unless snapshot.val() then permRef.set
          write: false
          admin: false

      action.accept()
      
    else if action.type is "update"
      #return action.accept()
      permissions.child(action.docName).child(agent.name).once "value", (snapshot) ->
        
        perms = snapshot.val()
      
        if perms?.write then action.accept()
        else action.reject()
    
    else
      console.log "[OP]", action.name, action.type, action
      action.accept()
    
    
, model


