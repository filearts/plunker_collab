coffee = require("coffee-script")
express = require("express")
sharejs = require("share")
lactate = require("lactate")
assets = require("connect-assets")
nconf = require("nconf")
request = require("request")
LRU = require("lru")

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


#permissions = new Firebase("https://plunker.firebaseio.com/participants")
#permissions.set({})

sharejs.server.attach app,
  browserChannel:
    cors: "*"
  browserchannel:
    cors: "*"
  auth: (agent, action) ->
    accept = ->
      console.log "[ACCEPT]", action.name, agent.name, arguments...
      action.accept()
      
    reject = ->
      console.log "[REJECT]", action.name, agent.name, arguments...
      action.reject()
    
    testAction = (agent, action, required) ->
      console.log "[REQUEST]", action.name, agent.name, required
      
      return accept("No docName") unless action.docName
      
      model.getSnapshot action.docName, (err, doc) ->
        unless doc then return reject("No such doc:", action.docName)
        
        # The creator has full admin privileges
        if agent.name is doc.meta.creator then return accept("Creator")

        unless required
          console.log "Unhandled op", arguments...
          return reject("Operation not supported")
          
        console.log "[AUTH]", action.name, required
        console.log "[AUTH]", agent.name, doc.snapshot.permissions[agent.name], doc.snapshot.permissions.$default
        
        perms = doc.snapshot.permissions[agent.name] or doc.snapshot.permissions.$default
        
        if perms[required] then accept() 
        else reject("Insufficient permissions")
            
    if action.name is "connect"
      return reject() unless agent.authentication
      
      request.get "#{apiUrl}/sessions/#{agent.authentication}", (err, response, body) ->
        return reject("Unable to load session") if err
        return reject("Session not found") if response.statusCode >= 400
        
        try
          session = JSON.parse(body)
        catch e
          return reject("Unable to parse session data")
        
        agent.name = session.public_id
        
        accept()
        
    else if action.name is "submit op"
      testAction(agent, action, "write")
    else
      accept()
    
    
, model


