import httpclient, json, re, strutils, uri

# Port of couchdb-nano

# Database functions
#
# nano.db.get(name, [callback])
# nano.db.destroy(name, [callback])
# nano.db.list([callback])
# nano.db.listAsStream()
# nano.db.compact(name, [designname], [callback])
# nano.db.replicate(source, target, [opts], [callback])
# nano.db.replication.enable(source, target, [opts], [callback])
# nano.db.replication.query(id, [opts], [callback])
# nano.db.replication.disable(id, [opts], [callback])
# nano.db.changes(name, [params], [callback])
# nano.db.changesAsStream(name, [params])
# nano.db.info([callback])
# nano.use(name)
# nano.request(opts, [callback])
# nano.config
# nano.updates([params], [callback])
# nano.info([callback])

# Documents
#
# db.insert(doc, [params], [callback])
# db.destroy(docname, rev, [callback])
# db.get(docname, [params], [callback])
# db.head(docname, [callback])
# db.bulk(docs, [params], [callback])
# db.list([params], [callback])
# db.listAsStream([params])
# db.fetch(docnames, [params], [callback])
# db.fetchRevs(docnames, [params], [callback])
# db.createIndex(indexDef, [callback])
# db.changesReader

type
  Connection                       * = ref object
    location*, username*, password * : string

  Database     * = ref object
    connection * : Connection
    name       * : string

  Cluster * = ref object
    n, q, r, w: int

  Other       * = ref object
    data_size * : int

  Sizes      * = ref object
    active   * : int
    external * : int
    file     * : int

  DatabaseCreateResponse * = ref object
    ok                   * : bool    ## Operation status. Available in case of success.
    error                * : string  ## Error type. Available if response code is 4xx.
    reason               * : string  ## Error description. Available if response code is 4xx.
    
  DatabaseGetResponse    * = ref object
    cluster              * : Cluster
    compact_running      * : bool
    data_size            * : int
    db_name              * : string
    disk_format_version  * : int
    disk_size            * : int
    doc_count            * : int
    doc_del_count        * : int
    instance_start_time  * : string
    other                * : Other
    purge_seq            * : string
    sizes                * : Sizes
    update_seq           * : string
  
  #Document     * = object of RootObj
  #  id         * : string
  #  key        * : string
  #  value      * : JsonNode ## Object structure: { rev : string }

  #DocumentGetResponse * = ref object of RootObj
  #  ##[
  #    Document response: 
  #    http://docs.couchdb.org/en/latest/api/document/common.html#get--db-docid
  #  ]## 
  #  id                * : string        ## Document ID.
  #  rev               * : string        ## Revision MVCC token.
  #  deleted           * : bool          ## Deletion flag. Available if document was removed.
  #  attachments       * : JsonNode      ## Attachment's stubs. Available if document has any attachments.
  #  conflicts         * : seq[JsonNode] ## List of conflicted revisions. Available if requested with conflicts=true query parameter.
  #  deleted_conflicts * : seq[JsonNode] ## List of deleted conflicted revisions. Available if requested with deleted_conflicts=true query parameter.
  #  local_seq         * : string        ## Document's update sequence in current database. Available if requested with local_seq=true query parameter.
  #  revs_info         * : seq[JsonNode] ## List of objects with information about local revisions and their status. Available if requested with open_revs query parameter.
  #  revisions         * : JsonNode      ## List of local revision tokens without. Available if requested with revs=true query parameter.
  
  DocumentListResponse * = ref object
    ##[
      All documents response.
      /{db}/_all_docs
      See: https://docs.couchdb.org/en/latest/api/database/bulk-api.html
    ]##
    offset             * : int
    rows               * : seq[JsonNode] ## Object structure: [{ id : string, key : string, value : { rev : string } }]
    total_rows         * : int

  DocumentInsertResponse * = ref object
    id                   * : string
    ok                   * : bool
    rev                  * : string

  InfoResponse * = ref object
    ## CouchDB status and welcome response.
    couchdb    * : string
    uuid       * : string
    version    * : string
    features   * : seq[string]    ## Contains sequence of strings.
    vendor     * : JsonNode       ## Object structure: { name : string }

template `$`(connection: Connection): string =
  var uri = initUri(false)
  uri = parseUri(connection.location)
  #uri.username = connection.username
  #uri.password = connection.password
  $uri

template `$`*(info: InfoResponse): string = $(%*info)
  ## JSON representation of InfoResponse.

template logDebug(path: string) =
  when not defined(release):
    echo path

template client(token: string = ""): HttpClient =
  let headers = newHttpHeaders()
  headers["accept"] = "application/json"
  headers["content-type"] = "application/json"
  if len(token) > 0:
    headers["cookie"] = token
  newHttpClient(headers = headers)

func newConnection*(location: string; username = ""; password = ""): Connection =
  Connection(
    location: location,
    username: username,
    password: password
  )

func newDatabase(connection: Connection, name: string): Database =
  Database(
    connection : connection,
    name       : name
  )

#func newDocumentGetResponse(node: JsonNode): DocumentGetResponse =
#  DocumentGetResponse(
#    id                : node{"_id" }.getStr(),
#    rev               : node{"_rev" }.getStr(),
#    deleted           : node{"_deleted" }.getBool(),
#    attachments       : node{"_attachments" },
#    conflicts         : node{"_conflicts" }.getElems(),
#    deleted_conflicts : node{"_deleted_conflicts"}.getElems(),
#    local_seq         : node{"_local_seq" }.getStr(),
#    revs_info         : node{"_revs_info" }.getElems(),
#    revisions         : node{"_revisions" }
#  )

proc head(path: string): Response =
  ## Convenience method for HEAD requests. Implement additional behavior elsewhere if needed.
  ## Note that this method does not provide an authenticated client.
  logDebug("HEAD " & path)
  client.head(path)

proc get(path: string): Response =
  ## Convenience method for GET requests. Implement additional behavior elsewhere if needed.
  ## Note that this method does not provide an authenticated client.
  logDebug("GET " & path)
  client.get(path)

proc post(path, data: string): Response =
  ## Convenience method for POST requests. Implement additional behavior elsewhere if needed.
  ## Note that this method does not provide an authenticated client.
  logDebug("POST " & path)
  client.post(path, data)

proc put(path, data: string): Response =
  ## Convenience method for PUT requests. Implement additional behavior elsewhere if needed.
  ## Note that this method does not provide an authenticated client.
  logDebug("PUT " & path)
  if len(data) > 0:
    client.put(path, data)
  else:
    client.put(path)

proc delete(path: string): Response =
  ## Convenience method for DELETE requests. Implement additional behavior elsewhere if needed.
  ## Note that this method does not provide an authenticated client.
  logDebug("DELETE " & path)
  client.delete(path)

proc info*(connection: Connection): InfoResponse =
  let response = get($connection)
  if response.status == $Http200:
    to(parseJson(response.body), InfoResponse)
  else:
    raise newException(Exception, "Failed to get connection information.")

proc authenticate(connection: Connection): string =
  ## Execute `POST /_session`.
  ## Authenticate user and returns session cookie. This method uses the JSON approach.
  let path = $connection.location & "/_session"
  logDebug("POST " & path)
  let response = client.post(path, $(%*{ "name": connection.username, "password": connection.password }))
  case response.status
  of $Http200:
    result = response.headers["Set-Cookie"]
  of $Http302:
    echo "302"
    discard
  of $Http401:
    echo "401"
    discard
  else:
    raise newException(Exception, "Unable to authenticate")
  
proc list*(connection: Connection): seq[string] =
  ## Execute `GET /_all_dbs`.
  ## Returns list of databases in the instance.
  let response = get($connection & "/_all_dbs")
  to(parseJson(response.body), seq[string])

proc create*(connection: Connection; name: string): Database =
  ## Execute `PUT /{db}`.
  ## Create new database using provided name.
  if re.match(name, re"^[a-z][a-z0-9_$()+/-]*$"):
    let token = authenticate(connection)
    let temp = connection.location & "/" & name
    let response = client(token).put(temp, "")
    case response.status
    of $Http200, $Http201, $Http202:
      result = newDatabase(connection, name)
    of $Http400:
      echo "400"
      discard
    of $Http401:
      echo "401"
      discard
    of $Http404:
      echo "404"
      discard
    of $Http412:
      echo "412"
      discard
    else:
      raise newException(Exception, "Unable to create database: " & name)
  else:
    raise newException(Exception, "Name wrong")

proc connect*(connection: Connection, name: string): Database =
  ## Execute `HEAD {db}`.
  ## Checks for existence of database and returns it if it exists.
  let response = head($connection & "/" & name)
  case response.status
  of $Http200:
    result = newDatabase(connection, name)
  of $Http404:
    result = nil
  else:
    result = nil

proc get*(db: Database): DatabaseGetResponse =
  ## Execute `GET {db}`
  let response = get($db.connection & "/" & db.name)
  case response.status
  of $Http200:
    result = to(parseJson(response.body), DatabaseGetResponse) 
  else:
    result = nil

proc destroy*(db: Database) =
  ## Execute `DELETE /{db}`
  let token = authenticate(db.connection)
  let response = client(token).delete($db.connection & "/" & db.name)
  case response.status
  of $Http200, $Http202:
    echo "200, 202"
    discard
  of $Http400:
    echo "400"
    discard
  of $Http401:
    echo "401"
    discard
  of $Http404:
    echo "404"
    discard
  else:
    raise newException(Exception, "Unable to delete database: " & db.name)

proc list*(db: Database): DocumentListResponse =
  ## Execute `GET {db}/_all_docs`
  # TODO: parameters
  let response = get($db.connection & "/" & db.name & "/_all_docs")
  case response.status
  of $Http200:
    result = to(parseJson(response.body), DocumentListResponse)
  else:
    result = nil

proc get*(db: Database, id: string): JsonNode =
  ## Execute `GET {db}/{docid}`.
  # TODO: parameters
  let response = get($db.connection & "/" & db.name & "/" & id)
  case response.status
  of $Http200:
    result = parseJson(response.body)
  else:
    result = nil

proc insert*(db: Database, doc: string): DocumentInsertResponse =
  # TODO: parameters
  let response = post($db.connection & "/" & db.name, doc)
  case response.status
  of $Http200, $Http201, $Http202:
    result = to(parseJson(response.body), DocumentInsertResponse)
  of $Http400:
    logDebug "400 - Bad Request" # Invalid database name
    discard
  of $Http401:
    logDebug "401 - Unauthorized" # Write permissions needed
    discard
  of $Http404:
    logDebug "404 - Not Found" # Database doesn't exist
    discard
  of $Http409:
    logDebug "409 - Conflict" # Document with same Id found
    discard
  else:
    discard

proc destroy*(db: Database, id, rev: string) =
  ## Remove document from database.
  let path = $db.connection & "/" & db.name & "/" & id & "?rev=" & rev
  logDebug("DELETE " & path)
  let response = client.delete(path)
  case response.status
  of $Http200:
    echo "200"
    discard
  of $Http202:
    echo "202"
    discard
  of $Http302:
    echo "302"
    discard
  of $Http400:
    echo "400"
    discard
  of $Http401:
    echo "401"
    discard
  of $Http404:
    echo "404"
    discard
  of $Http409:
    echo "409"
    discard
  else:
    raise newException(Exception, "Unable to delete document.")

proc head(db: Database, id: string) =
  discard

proc bulk(db: Database, id: string) =
  # TODO: parameters
  discard

proc fetch(db: Database, ids: seq[string]) =
  # TODO: parameters
  discard

proc fetchRevs(db: Database, ids: seq[string]) =
  # TODO: parameters
  discard

proc createIndex(db: Database) =
  # TODO: parameters
  discard
