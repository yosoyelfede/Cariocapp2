import Foundation

@objc(PlayerSnapshot)
public final class PlayerSnapshot: NSObject, NSSecureCoding {
    public let id: UUID
    public let name: String
    public let score: Int
    public let position: Int
    
    public static var supportsSecureCoding: Bool { true }
    
    public init(id: UUID, name: String, score: Int = 0, position: Int = 0) {
        self.id = id
        self.name = name
        self.score = score
        self.position = position
        super.init()
    }
    
    public func encode(with coder: NSCoder) {
        coder.encode(id.uuidString, forKey: "id")
        coder.encode(name, forKey: "name")
        coder.encode(score, forKey: "score")
        coder.encode(position, forKey: "position")
    }
    
    public required init?(coder: NSCoder) {
        guard let idString = coder.decodeObject(of: NSString.self, forKey: "id") as String?,
              let id = UUID(uuidString: idString),
              let name = coder.decodeObject(of: NSString.self, forKey: "name") as String? else {
            return nil
        }
        
        self.id = id
        self.name = name
        self.score = coder.decodeInteger(forKey: "score")
        self.position = coder.decodeInteger(forKey: "position")
        super.init()
    }
}

@objc(PlayerSnapshotsValueTransformer)
final class PlayerSnapshotsValueTransformer: ValueTransformer {
    override class func transformedValueClass() -> AnyClass {
        return NSArray.self
    }
    
    override class func allowsReverseTransformation() -> Bool {
        return true
    }
    
    override func transformedValue(_ value: Any?) -> Any? {
        guard let snapshots = value as? [PlayerSnapshot] else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: snapshots, requiringSecureCoding: true)
    }
    
    override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, PlayerSnapshot.self], from: data) as? [PlayerSnapshot]
    }
    
    static func register() {
        let transformer = PlayerSnapshotsValueTransformer()
        ValueTransformer.setValueTransformer(transformer, forName: NSValueTransformerName("PlayerSnapshotsValueTransformer"))
    }
} 