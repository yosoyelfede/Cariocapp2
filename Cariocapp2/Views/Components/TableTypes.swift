import SwiftUI

// MARK: - Table Row Identifiers
protocol TableRowIdentifiable {
    var id: UUID { get }
}

// MARK: - Table Column Types
struct TableColumn<Value>: Identifiable {
    let id: String
    let title: String
    let value: (Value) -> String
    
    init(_ title: String, value: @escaping (Value) -> String) {
        self.id = UUID().uuidString
        self.title = title
        self.value = value
    }
}

// MARK: - Table Row Content
struct TableRowContent<Value>: View {
    let item: Value
    let columns: [TableColumn<Value>]
    
    var body: some View {
        HStack {
            ForEach(columns) { column in
                Text(column.value(item))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Table Header Content
struct TableHeaderContent<Value>: View {
    let columns: [TableColumn<Value>]
    
    var body: some View {
        HStack {
            ForEach(columns) { column in
                Text(column.title)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Table View
struct TableView<Value: TableRowIdentifiable>: View {
    let items: [Value]
    let columns: [TableColumn<Value>]
    
    var body: some View {
        VStack(spacing: 8) {
            // Header
            TableHeaderContent(columns: columns)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
            
            // Rows
            ForEach(items, id: \.id) { item in
                TableRowContent(item: item, columns: columns)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - Preview
struct TableTypes_Previews: PreviewProvider {
    struct SampleItem: TableRowIdentifiable {
        let id = UUID()
        let name: String
        let value: Int
    }
    
    static var previews: some View {
        let items = [
            SampleItem(name: "Item 1", value: 100),
            SampleItem(name: "Item 2", value: 200),
            SampleItem(name: "Item 3", value: 300)
        ]
        
        let columns = [
            TableColumn("Name") { (item: SampleItem) in item.name },
            TableColumn("Value") { (item: SampleItem) in "\(item.value)" }
        ]
        
        TableView(items: items, columns: columns)
            .padding()
    }
} 