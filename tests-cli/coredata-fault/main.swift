import CoreData
import Foundation

setbuf(stdout, nil)
guard CommandLine.arguments.count == 3 else {
  fputs("Usage: coredata-fault <prepare|metadata|relationship|payload> <store path>\n", stderr)
  exit(2)
}
let mode = CommandLine.arguments[1]
let url = URL(fileURLWithPath: CommandLine.arguments[2])
let itemCount = Int(ProcessInfo.processInfo.environment["SYNTHETIC_ITEMS"] ?? "20") ?? 20
let payloadMiB = Int(ProcessInfo.processInfo.environment["SYNTHETIC_MIB"] ?? "8") ?? 8

func attribute(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
  let value = NSAttributeDescription()
  value.name = name
  value.attributeType = type
  value.isOptional = false
  return value
}

let itemEntity = NSEntityDescription()
itemEntity.name = "HistoryItem"
itemEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
let contentEntity = NSEntityDescription()
contentEntity.name = "HistoryItemContent"
contentEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
let contents = NSRelationshipDescription()
contents.name = "contents"
contents.destinationEntity = contentEntity
contents.minCount = 0
contents.maxCount = 0
contents.deleteRule = .cascadeDeleteRule
let item = NSRelationshipDescription()
item.name = "item"
item.destinationEntity = itemEntity
item.minCount = 0
item.maxCount = 1
item.deleteRule = .nullifyDeleteRule
contents.inverseRelationship = item
item.inverseRelationship = contents
itemEntity.properties = [attribute("title", .stringAttributeType), contents]
contentEntity.properties = [attribute("type", .stringAttributeType), attribute("value", .binaryDataAttributeType), item]
let model = NSManagedObjectModel()
model.entities = [itemEntity, contentEntity]
let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: nil)
let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
context.persistentStoreCoordinator = coordinator

if mode == "prepare" {
  for index in 0..<itemCount {
    autoreleasepool {
      let history = NSEntityDescription.insertNewObject(forEntityName: "HistoryItem", into: context)
      history.setValue("synthetic-\(index)", forKey: "title")
      let content = NSEntityDescription.insertNewObject(forEntityName: "HistoryItemContent", into: context)
      content.setValue("public.tiff", forKey: "type")
      var data = Data(count: payloadMiB * 1024 * 1024)
      _ = data.withUnsafeMutableBytes { bytes in
        memset(bytes.baseAddress!, Int32(index + 1), bytes.count)
      }
      content.setValue(data, forKey: "value")
      content.setValue(history, forKey: "item")
      try! context.save()
      context.reset()
    }
  }
  print("READY prepared items=\(itemCount) payload=\(itemCount * payloadMiB)MiB")
  exit(0)
}

let request = NSFetchRequest<NSManagedObject>(entityName: "HistoryItem")
let items = try context.fetch(request)
var count = 0
var verifiedPayloads = 0
var retainedPayloads: [Data] = []
for history in items {
  if mode == "metadata" {
    let req = NSFetchRequest<NSDictionary>(entityName: "HistoryItemContent")
    req.resultType = .dictionaryResultType
    req.propertiesToFetch = ["type"]
    req.predicate = NSPredicate(format: "item == %@", history)
    count += try context.fetch(req).count
  } else {
    let children = history.value(forKey: "contents") as! Set<NSManagedObject>
    for child in children {
      if child.value(forKey: "type") as? String == "public.tiff" { count += 1 }
      if mode == "payload", let bytes = child.value(forKey: "value") as? Data {
        let title = history.value(forKey: "title") as! String
        let index = Int(title.split(separator: "-").last!)!
        let expected = UInt8(index + 1)
        guard bytes.count == payloadMiB * 1024 * 1024, bytes.allSatisfy({ $0 == expected }) else {
          fatalError("Synthetic original data did not round-trip")
        }
        verifiedPayloads += 1
        retainedPayloads.append(bytes)
      }
    }
  }
}
print("READY \(mode) items=\(items.count) matched=\(count) verified=\(verifiedPayloads)")
withExtendedLifetime((context, items, retainedPayloads)) { _ = sleep(20) }
