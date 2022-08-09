import httpclient, json, re, std/options, strutils, uri

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
  
  Document     * = object of RootObj
   `"_id"`     * : string
   `"_key"`    * : Option[string]
   value       * : Option[JsonNode] ## Object structure: { rev : string }

  DocumentHeadResponse     * = ref object of RootObj
    ##[
      Document response: 
      http://docs.couchdb.org/en/latest/api/document/common.html#get--db-docid
    ]## 
    id                     * : string
    length                 * : int
    rev                    * : string
    

  DocumentGetResponse      * = ref object of RootObj
    ##[
      Document response: 
      http://docs.couchdb.org/en/latest/api/document/common.html#get--db-docid
    ]## 
    `"_id"`                * : string                ## Document ID.
    `"_rev"`               * : string                ## Revision MVCC token.
    `"_deleted"`           * : Option[bool]          ## Deletion flag. Available if document was removed.
    `"_attachments"`       * : Option[JsonNode]      ## Attachment's stubs. Available if document has any attachments.
    `"_conflicts"`         * : Option[seq[JsonNode]] ## List of conflicted revisions. Available if requested with conflicts=true query parameter.
    `"_deleted_conflicts"` * : Option[seq[JsonNode]] ## List of deleted conflicted revisions. Available if requested with deleted_conflicts=true query parameter.
    `"_local_seq"`         * : Option[string]        ## Document's update sequence in current database. Available if requested with local_seq=true query parameter.
    `"_revs_info"`         * : Option[seq[JsonNode]] ## List of objects with information about local revisions and their status. Available if requested with open_revs query parameter.
    `"_revisions"`         * : Option[JsonNode]      ## List of local revision tokens without. Available if requested with revs=true query parameter.
  
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
    ##[
      Document insert response.
      http://docs.couchdb.org/en/latest/api/document/common.html#insert--db-docid
    ]##
    id                   * : string
    ok                   * : bool
    rev                  * : string

  DocumentDestroyResponse * = ref object
    ##[
      Document delete response.
      http://docs.couchdb.org/en/latest/api/document/common.html#delete--db-docid
    ]##
    id                    * : string ## Document ID
    ok                    * : bool   ## Operation status
    rev                   * : string ## Revision MVCC token
  
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

template `/`(connection: Connection, path: string): string =
  connection.location & "/" & path

template `/`(a, b: string): string =
  a & "/" & b

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

func newDocumentHeadResponse(id: string, length: int, rev: string): DocumentHeadResponse =
  DocumentHeadResponse(
    id     : id,
    length : if length < 0: 0 else: length,
    rev    : rev
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
  let path = connection / "_session"
  logDebug("POST " & path)
  let response = client.post(path, $(%*{ "name": connection.username, "password": connection.password }))
  case response.status
  of $Http200:
    result = response.headers["Set-Cookie"]
  of $Http302:
    logDebug "302"
    discard
  of $Http401:
    logDebug "401"
    discard
  else:
    raise newException(Exception, "Unable to authenticate")
  
proc list*(connection: Connection): seq[string] =
  ## Execute `GET /_all_dbs`.
  ## Returns list of databases in the instance.
  let response = get(connection / "_all_dbs")
  to(parseJson(response.body), seq[string])

proc create*(connection: Connection; name: string): Database =
  ## Execute `PUT /{db}`.
  ## Create new database using provided name.
  if re.match(name, re"^[a-z][a-z0-9_$()+/-]*$"):
    let token = authenticate(connection)
    let path = connection / name
    let response = client(token).put(path, "")
    case response.status
    of $Http200, $Http201, $Http202:
      result = newDatabase(connection, name)
    of $Http400:
      logDebug "400"
      discard
    of $Http401:
      logDebug "401"
      discard
    of $Http404:
      logDebug "404"
      discard
    of $Http412:
      logDebug "412"
      discard
    else:
      raise newException(Exception, "Unable to create database: " & name)
  else:
    raise newException(Exception, "Name wrong")

proc connect*(connection: Connection, name: string): Database =
  ## Execute `HEAD {db}`.
  ## Checks for existence of database and returns it if it exists.
  let path = connection / name
  let response = head(path)
  case response.status
  of $Http200:
    logDebug "200 - OK"
    result = newDatabase(connection, name)
  of $Http404:
    logDebug "404 - Not Found"
    result = nil
  else:
    result = nil

proc get*(db: Database): DatabaseGetResponse =
  ## Execute `GET {db}`
  let response = get(db.connection / db.name)
  case response.status
  of $Http200:
    result = to(parseJson(response.body), DatabaseGetResponse) 
  else:
    result = nil

proc destroy*(db: Database) =
  ## Execute `DELETE /{db}`
  let token = authenticate(db.connection)
  let path = db.connection / db.name
  let response = client(token).delete(path)
  case response.status
  of $Http200, $Http202:
    logDebug "200, 202"
    discard
  of $Http400:
    logDebug "400"
    discard
  of $Http401:
    logDebug "401"
    discard
  of $Http404:
    logDebug "404"
    discard
  else:
    raise newException(Exception, "Unable to delete database: " & db.name)

proc list*(db: Database): DocumentListResponse =
  ## Execute `GET {db}/_all_docs`
  # TODO: parameters
  let path = db.connection / db.name / "_all_docs"
  let response = get(path)
  case response.status
  of $Http200:
    logDebug "200 OK"        # Requested completed successfully
    result = to(parseJson(response.body), DocumentListResponse)
  of $Http404:
    logDebug "404 Not Found" # Requested database not found
  else:
    result = nil

proc get*(db: Database, id: string, parameters: seq[(string, string)] = newSeq[(string, string)]()): JsonNode =
  ##[
    Execute `GET {db}/{docid}`.
  
    http://docs.couchdb.org/en/latest/api/document/common.html#get--db-docid
  
    Parameters are implemented as a list of tuples; no special type provided.
  
    - **attachments**       - Includes attachments bodies in response. Default is false
    - **att_encoding_info** - Includes encoding information in attachment stubs if the particular attachment is compressed. Default is false.
    - **atts_since**        - Includes attachments only since specified revisions. Doesn't includes attachments for specified revisions. Optional
    - **conflicts**         - Includes information about conflicts in document. Default is false
    - **deleted_conflicts** - Includes information about deleted conflicted revisions. Default is false
    - **latest**            - Forces retrieving latest 'leaf' revision, no matter what rev was requested. Default is false
    - **local_seq**         - Includes last update sequence for the document. Default is false
    - **meta**              - Acts same as specifying all conflicts, deleted_conflicts and revs_info query parameters. Default is false
    - **open_revs**         - Retrieves documents of specified leaf revisions. Additionally, it accepts value as all to return all leaf revisions. Optional
    - **rev**               - Retrieves document of specified revision. Optional
    - **revs**              - Includes list of all known document revisions. Default is false
    - **revs_info**         - Includes detailed information for all known document revisions. Default is false
  ]##
  let token = authenticate(db.connection)
  var path = ""
  if len(parameters) > 0:
    let query = encodeQuery(parameters)
    path = db.connection / db.name / id & "?" & query
  else:
    path = db.connection / db.name / id
  logDebug(path)
  let response = client(token).get(path)
  case response.status
  of $Http200:
    logDebug "200 OK"           # Request completed successfully
    result = parseJson(response.body)
  of $Http304:
    logDebug "304 Not Modified" # Document wasn�t modified since specified revision
  of $Http400:
    logDebug "400 Bad Request"  # The format of the request or revision was invalid
  of $Http401:
    logDebug "401 Unauthorized" # Read privilege required
  of $Http404:
    logDebug "404 Not Found"    # Document not found
  else:
    logDebug response.status
    result = nil

proc insert*(db: Database, doc: string): DocumentInsertResponse =
  # TODO: parameters
  let path = db.connection / db.name
  let response = post(path, doc)
  case response.status
  of $Http200, $Http201, $Http202:
    result = to(parseJson(response.body), DocumentInsertResponse)
  of $Http400:
    logDebug "400 Bad Request"  # Invalid database name
  of $Http401:
    logDebug "401 Unauthorized" # Write permissions needed
  of $Http404:
    logDebug "404 Not Found"    # Database doesn't exist
  of $Http409:
    logDebug "409 Conflict"     # Document with same Id found
  else:
    discard

proc destroy*(db: Database, id, rev: string) =
  ## Remove document from database.
  let path = db.connection / db.name / id / "?rev=" & rev
  logDebug("DELETE " & path)
  let response = client.delete(path)
  case response.status
  of $Http200:
    logDebug "200 OK"           # Document successfully removed
  of $Http202:
    logDebug "202 Accepted"     # Request was accepted, but changes are not yet stored on disk
  of $Http400:
    logDebug "400 Bad Request"  # Invalid request body or parameters
  of $Http401:
    logDebug "401 Unauthorized" # Write privileges required
  of $Http404:
    logDebug "404 Not Found"    # Specified database or document ID doesn�t exists
  of $Http409:
    logDebug "409 Conflict"     # Specified revision is not the latest for target document
  else:
    raise newException(Exception, "Unable to delete document.")

proc head*(db: Database, id: string): DocumentHeadResponse =
  ##[
    Document retrieve info
    http://docs.couchdb.org/en/latest/api/document/common.html#get--db-docid
  ]##
  let path = db.connection / db.name / id
  let response = client.head(path)
  let headers = response.headers
  case response.status
  of $Http200:
    logDebug "200 OK"           # Document exists
    result = newDocumentHeadResponse(id, parseInt(headers["Content-Length"]), headers["ETag"])
  of $Http304:
    logDebug "304 Not Modified" # Document wasn�t modified since specified revision"
    discard
  of $Http401:
    logDebug "401 Unauthorized" # Read privilege required
  of $Http404:
    logDebug "404 Not Found"    # Document not found
    discard
  else:
    raise newException(Exception, "Unable to get document.")

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
