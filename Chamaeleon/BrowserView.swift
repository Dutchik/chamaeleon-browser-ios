import SwiftUI
import WebKit

/// WKWebView ラッパー。Site Profile にマッチした CSS/JS/DOMルールを注入する。
struct BrowserView: UIViewRepresentable {
    @ObservedObject var model: BrowserModel
    @ObservedObject var store: ProfileStore

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        model.webView = webView
        if let url = URL(string: model.urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(model: model, store: store) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let model: BrowserModel
        let store: ProfileStore
        init(model: BrowserModel, store: ProfileStore) {
            self.model = model
            self.store = store
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            let url = webView.url?.absoluteString ?? ""
            Task { @MainActor in
                model.currentURL = url
                model.urlInput = url
                // document_start 相当: コミット直後に注入
                PatchEngine.apply(profiles: store.matched(for: url), stage: .documentStart, to: webView)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let url = webView.url?.absoluteString ?? ""
            Task { @MainActor in
                model.currentURL = url
                model.urlInput = url
                model.title = webView.title ?? ""
                model.canGoBack = webView.canGoBack
                model.canGoForward = webView.canGoForward
                let matched = store.matched(for: url)
                model.matchedCount = matched.count
                PatchEngine.apply(profiles: matched, stage: .documentEnd, to: webView)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    PatchEngine.apply(profiles: matched, stage: .idle, to: webView)
                }
            }
        }
    }
}

/// タブ1枚分の状態
@MainActor
final class BrowserModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published var urlString: String
    @Published var urlInput: String
    @Published var currentURL: String
    @Published var title = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var matchedCount = 0
    weak var webView: WKWebView?

    init(url: String = "https://duckduckgo.com") {
        urlString = url
        urlInput = url
        currentURL = url
    }

    func navigate(_ raw: String) {
        let t = raw.trimmingCharacters(in: .whitespaces)
        let urlStr: String
        if t.hasPrefix("http://") || t.hasPrefix("https://") {
            urlStr = t
        } else if t.contains("."), !t.contains(" ") {
            urlStr = "https://" + t
        } else {
            urlStr = "https://duckduckgo.com/?q=" + (t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? t)
        }
        guard let url = URL(string: urlStr) else { return }
        webView?.load(URLRequest(url: url))
    }
}

/// パッチ適用エンジン（仕様§10.1の順序: CSS → DOM → JS）
enum PatchEngine {
    static func apply(profiles: [SiteProfile], stage: RunAt, to webView: WKWebView) {
        for profile in profiles {
            for css in profile.cssPatches where css.enabled && css.runAt == stage {
                inject(css: css, to: webView)
            }
            for rule in profile.domRules where rule.enabled && rule.runAt == stage {
                webView.evaluateJavaScript(js(for: rule), completionHandler: nil)
            }
            for jsPatch in profile.jsPatches.sorted(by: { $0.priority < $1.priority })
            where jsPatch.enabled && jsPatch.runAt == stage {
                webView.evaluateJavaScript(jsPatch.code, completionHandler: nil)
            }
        }
    }

    private static func inject(css: CssPatch, to webView: WKWebView) {
        let escaped = css.code
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
        let js = """
        (function(){
          var s = document.createElement('style');
          s.dataset.chamaeleon = '\(css.id)';
          s.textContent = `\(escaped)`;
          (document.head || document.documentElement).appendChild(s);
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    /// DOM Rule を実行するJSを生成（waitForSelector対応・MutationObserver使用）
    static func js(for rule: DomRule) -> String {
        let value = (rule.value ?? "")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let selector = rule.selector
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let action: String
        switch rule.action {
        case .hide: action = "el.style.setProperty('display','none','important');"
        case .remove: action = "el.remove();"
        case .highlight: action = "el.style.setProperty('outline','3px solid #ff5a4e','important');"
        case .replaceText: action = "el.textContent = '\(value)';"
        case .addClass: action = "el.classList.add(...'\(value)'.split(/\\s+/));"
        case .setStyle: action = "el.setAttribute('style', (el.getAttribute('style')||'') + ';' + '\(value)');"
        case .move: action = "var t=document.querySelector('\(value)'); if(t) t.appendChild(el);"
        case .click: action = "el.click();"
        case .input: action = "el.value='\(value)'; el.dispatchEvent(new Event('input',{bubbles:true})); el.dispatchEvent(new Event('change',{bubbles:true}));"
        }
        return """
        (function(){
          function run(){
            var els = document.querySelectorAll('\(selector)');
            if (els.length === 0) return false;
            els.forEach(function(el){ \(action) });
            return true;
          }
          if (run()) return;
          \(rule.waitForSelector ? """
          var obs = new MutationObserver(function(){ if (run()) obs.disconnect(); });
          obs.observe(document.documentElement, {childList:true, subtree:true});
          setTimeout(function(){ obs.disconnect(); }, \(rule.timeoutMs));
          """ : "")
        })();
        """
    }
}
