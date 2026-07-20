import SwiftUI
import LiteWebView

/// Demo native flow: a native form the web page opens via executeNativeFlow("greet", {name}).
struct GreetFlow: ViewControllerNativeFlow {
    struct Args: Decodable { let name: String }
    struct FlowResult: Encodable { let greeting: String }

    @MainActor
    func makeViewController(args: Args,
                            completion: @escaping (Result<FlowResult, NativeFlowError>) -> Void) -> UIViewController {
        UIHostingController(rootView: GreetView(name: args.name) { greeting in
            completion(.success(FlowResult(greeting: greeting)))
        })
    }
}

private struct GreetView: View {
    let name: String
    let onDone: (String) -> Void
    @State private var text = "Hello"

    var body: some View {
        VStack(spacing: 16) {
            Text("Native flow opened by \"\(name)\"").font(.headline)
            TextField("Greeting", text: $text).textFieldStyle(.roundedBorder).padding(.horizontal)
            Button("Return to web page") { onDone(text) }.buttonStyle(.borderedProminent)
            Text("Tip: swipe down instead — the page's promise rejects with code \"cancelled\".")
                .font(.footnote).foregroundColor(.secondary).padding(.horizontal)
        }
        .padding(.top, 32)
    }
}

struct BridgeDemoView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> LiteWebViewController {
        let page = Bundle.main.url(forResource: "bridge-demo", withExtension: "html")!
        let registry = NativeFlowRegistry()
        registry.register("greet", GreetFlow())
        let request = LiteWebViewRequest(
            url: page,
            allowList: OriginAllowList(entries: []),          // no remote content in this demo
            completionRule: RedirectCompletionRule(redirectURL: URL(string: "lite-demo://done")!),
            bundledBridgePage: page,                          // the ONE exact local asset (spec §5a)
            showsOriginHeader: false)
        return LiteWebViewController(request: request, nativeFlows: registry) { _ in }
    }
    func updateUIViewController(_ uiViewController: LiteWebViewController, context: Context) {}
}
