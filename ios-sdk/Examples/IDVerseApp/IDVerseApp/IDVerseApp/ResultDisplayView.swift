import SwiftUI
import IDVerseSDK

struct ResultDisplayView: View {
    let result: IDVerseVerificationResult
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Outcome: \(result.outcome.rawValue)").bold()
            Text("Transaction: \(result.transactionId)")
            if let data = result.extractedData {
                ForEach(data.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                    HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v) }
                }
            }
        }
        .padding()
    }
}
