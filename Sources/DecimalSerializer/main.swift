import Foundation

let jsonData = """
{
    "amount": 12.68,
    "memo": "Payment",
    "cleared": true
}
""".data(using: .utf8)!

struct Transaction: Decodable {
    let amount: Decimal
    let memo: String
    let cleared: Bool
}

let transaction = try DecimalJSONDecoder().decode(Transaction.self, from: jsonData)
print(transaction)

