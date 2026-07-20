import SwiftUI
import IDVerseSDK

struct StartView: View {
    /// Prefill for local runs: set the IDVERSE_TX_URL env var in the run scheme
    /// (or edit the default below — do not commit a real transaction URL).
    /// IDVERSE_REDIRECT overrides the completion redirect.
    @State private var transactionURLText = ProcessInfo.processInfo.environment["IDVERSE_TX_URL"]
        ?? ""
    private let redirectURL = URL(string: ProcessInfo.processInfo.environment["IDVERSE_REDIRECT"]
                                  ?? "idverse-sdk://complete") ?? URL(string: "idverse-sdk://complete")!
    @State private var showVerification = false
    @State private var result: IDVerseVerificationResult?
    @State private var errorText: String?

    /// A valid http(s) URL from the text field, or nil.
    private var transactionURL: URL? {
        let trimmed = transactionURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }

    /// Canned result so the result UI can be demonstrated without a live backend.
    private var cannedResult: IDVerseVerificationResult {
        IDVerseVerificationResult(
            transactionId: "tx_demo", outcome: .passed,
            extractedData: ["full_name": "Jane Demo", "document_number": "X1234567"])
    }

    /// For the real flow: a mock service whose transaction loads the pasted URL.
    /// (Result is still canned — fetching real results needs the live IDVerse API.)
    private func flowService(url: URL) -> IDVerseTransactionService {
        let tx = IDVerseTransaction(id: "tx_demo", url: url, redirectURL: redirectURL)
        return MockTransactionService(transaction: tx, result: cannedResult)
    }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("IDVerse SDK Test App").font(.title2).bold()

                TextField("Paste a real IDVerse transaction URL", text: $transactionURLText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)

                Button("Run verification flow") { showVerification = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(transactionURL == nil)
                Text("Loads the transaction URL in the IDVerse WKWebView. Needs a real transaction URL (a placeholder will just time out).")
                    .font(.caption).foregroundStyle(.secondary)

                Divider()

                Button("Preview result screen (mock)") {
                    result = cannedResult; errorText = nil
                }
                Text("Shows the result UI with canned data — no webview, no network.")
                    .font(.caption).foregroundStyle(.secondary)

                Divider()

                NavigationLink("Bridge demo") { BridgeDemoView() }
                Text("LiteWebView core loading a bundled page that calls a native flow via the JS bridge.")
                    .font(.caption).foregroundStyle(.secondary)

                if let result {
                    ResultDisplayView(result: result)
                }
                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(.red)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("IDVerse")
        }
        .fullScreenCover(isPresented: $showVerification) {
            if let url = transactionURL {
                IDVerseVerificationFlow(
                    config: TransactionConfig(redirectURL: redirectURL),
                    service: flowService(url: url)
                ) { outcome in
                    showVerification = false
                    switch outcome {
                    case .success(let r): result = r; errorText = nil
                    case .failure(let e): errorText = "Error: \(e)"
                    }
                }
                .ignoresSafeArea()
            }
        }
    }
}
