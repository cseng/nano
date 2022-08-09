import json, nano

var
  exampleName = "example"
  docId = ""

proc example1 =
  # Create a new database and add document
  let connection = newConnection("http://localhost:5984", "admin", "admin")
  # Get list of databases
  echo list(connection)
  # Add new database
  let db = create(connection, exampleName)
  if db == nil:
    raise newException(Exception, "Could not create " & exampleName)
  let doc = $(%*{ "key" : "value" })
  let response = insert(db, doc)
  echo "status: ", response.ok, " id: ", response.id, " rev: ", response.rev
  docId = response.id

proc example2(): JsonNode =
  # Get existing database created in prior run
  let connection = newConnection("http://localhost:5984", "admin", "admin")
  let db = connect(connection, exampleName)
  if db == nil:
    raise newException(Exception, "Could not get " & exampleName)
  let doc1 = get(db, docId)
  if doc1 == nil:
    raise newException(Exception, "Could not get document " & docId)
  else:
    echo "id: ", doc1{"_id"}.getStr(), " key: ", doc1{"key"}.getStr()
    docId = doc1{"_id"}.getStr()
  let info = head(db, docId)
  if info == nil:
    raise newException(Exception, "Could not get " & docId)
  else:
    echo "id: ", info.id, " length: ", info.length, " rev: ", info.rev
  var params = newSeq[(string, string)]()
  add(params, ("revs", $true))
  let doc2 = get(db, docId, params)
  if doc2 == nil:
    raise newException(Exception, "Could not get " & docId)
  else:
    #echo "id: ", doc.id, " rev: ", doc.rev
    echo $doc2
  result = doc2

proc example3(doc: JsonNode) =
  # Removes the document created in example2 and finally removes the database
  let connection = newConnection("http://localhost:5984", "admin", "admin")
  let db = connect(connection, exampleName)
  if db == nil:
    raise newException(Exception, "Could not get " & exampleName)
  destroy(db, doc{"_id"}.getStr(), doc{"_rev"}.getStr())
  destroy(db)
  
example1()
let doc = example2()
example3(doc)
