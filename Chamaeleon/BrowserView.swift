import SwiftUI
import WebKit

/// 記録された1操作
struct RecordedStep: Equatable {
    var type: String
    var selector: String?
    var value: String?
}

/// インスペクトした要素の情報
struct InspectedInfo: Equatable {
    var selector: String
    var styles: [String: String]
}

/// WKWebView ラッパー。Site Profile 適用＋記録・インスペクタ・フロー実行のJSブリッジ。
struct BrowserView: UIViewRepresentable {
    @ObservedObject var model: BrowserModel
    @ObservedObject var store: ProfileStore
    var onVisit: ((String, String) -> Void)? = nil

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.userContentController.add(context.coordinator, name: "chm")
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
    func makeCoordinator() -> Coordinator { Coordinator(model: model, store: store, onVisit: onVisit) }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let model: BrowserModel
        let store: ProfileStore
        let onVisit: ((String, String) -> Void)?
        init(model: BrowserModel, store: ProfileStore, onVisit: ((String, String) -> Void)?) {
            self.model = model; self.store = store; self.onVisit = onVisit
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in model.isLoading = true }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in model.isLoading = false; model.finishNav() }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in model.isLoading = false; model.finishNav() }
        }
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            let url = webView.url?.absoluteString ?? ""
            Task { @MainActor in
                model.currentURL = url; model.urlInput = url; model.urlString = url
                PatchEngine.apply(profiles: store.matched(for: url), stage: .documentStart, to: webView)
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let url = webView.url?.absoluteString ?? ""
            Task { @MainActor in
                model.currentURL = url; model.urlInput = url; model.title = webView.title ?? ""
                model.canGoBack = webView.canGoBack; model.canGoForward = webView.canGoForward
                model.isLoading = false
                onVisit?(url, webView.title ?? "")
                let matched = store.matched(for: url)
                model.matchedCount = matched.count
                PatchEngine.apply(profiles: matched, stage: .documentEnd, to: webView)
                if model.recording { model.injectRecorder() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    PatchEngine.apply(profiles: matched, stage: .idle, to: webView)
                }
                model.finishNav()
            }
        }

        // webページ → Swift のメッセージ
        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let kind = body["kind"] as? String else { return }
            Task { @MainActor in
                switch kind {
                case "recorded":
                    model.onRecorded?(RecordedStep(
                        type: body["type"] as? String ?? "click",
                        selector: body["selector"] as? String,
                        value: body["value"] as? String))
                case "inspected":
                    let styles = body["styles"] as? [String: String] ?? [:]
                    model.onInspected?(InspectedInfo(selector: body["selector"] as? String ?? "", styles: styles))
                default: break
                }
            }
        }
    }
}

/// タブ1枚分の状態＋自動化ブリッジ
@MainActor
final class BrowserModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published var urlString: String
    @Published var urlInput: String
    @Published var currentURL: String
    @Published var title = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var matchedCount = 0
    @Published var recording = false
    @Published var isHome: Bool
    weak var webView: WKWebView?

    var onRecorded: ((RecordedStep) -> Void)?
    var onInspected: ((InspectedInfo) -> Void)?
    private var navCont: CheckedContinuation<Void, Never>?

    init(home: Bool = true, url: String = "about:blank") {
        urlString = url; urlInput = home ? "" : url; currentURL = home ? "chamaeleon://start" : url; isHome = home
    }

    func navigate(_ raw: String) {
        let n = normalize(raw)
        guard let url = URL(string: n) else { return }
        isHome = false
        webView?.load(URLRequest(url: url))
    }
    func goHome() { isHome = true; currentURL = "chamaeleon://start"; urlInput = "" }
    func normalize(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("http://") || t.hasPrefix("https://") { return t }
        if t.contains("."), !t.contains(" ") { return "https://" + t }
        return "https://duckduckgo.com/?q=" + (t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? t)
    }

    func finishNav() { navCont?.resume(); navCont = nil }
    func navigateAndWait(_ url: String) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            navCont = c
            if let u = URL(string: url) { webView?.load(URLRequest(url: u)) } else { c.resume(); navCont = nil }
        }
    }

    // MARK: - レコーダー

    func startRecording() { recording = true; injectRecorder() }
    func stopRecording() { recording = false; webView?.evaluateJavaScript("window.__chmRec=false") }
    func injectRecorder() {
        webView?.evaluateJavaScript(BrowserJS.recorder)
    }

    // MARK: - インスペクタ / プレビュー

    func startInspect() { webView?.evaluateJavaScript(BrowserJS.inspect) }
    func previewCss(_ css: String) {
        let esc = css.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`")
        webView?.evaluateJavaScript("(function(){var e=document.getElementById('chm-style-preview');if(!e){e=document.createElement('style');e.id='chm-style-preview';document.documentElement.appendChild(e);}e.textContent=`\(esc)`;})();")
    }
    func clearPreview() { webView?.evaluateJavaScript("document.getElementById('chm-style-preview')?.remove();") }

    // MARK: - フローの1ステップ実行（callAsyncJavaScriptでPromiseをawait）

    func runStep(type: String, selector: String?, value: String?, timeoutMs: Int) async -> Bool {
        guard let wv = webView else { return false }
        let args: [String: Any] = [
            "type": type, "selector": selector ?? "", "value": value ?? "", "timeoutMs": timeoutMs,
        ]
        do {
            _ = try await wv.callAsyncJavaScript(BrowserJS.runStep, arguments: args, contentWorld: .page)
            return true
        } catch {
            return false
        }
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

/// webページに注入するJavaScript群
enum BrowserJS {
    // レコーダー: クリック・入力を messageHandler へ送る
    static let recorder = """
    (function(){
      if (window.__chmRecInit) { window.__chmRec = true; return; }
      window.__chmRecInit = true; window.__chmRec = true;
      function sel(el){
        if(el.id) return '#'+CSS.escape(el.id);
        var t=el.getAttribute('data-testid'); if(t) return '[data-testid=\\"'+t+'\\"]';
        var n=el.getAttribute('name'); if(n) return el.tagName.toLowerCase()+'[name=\\"'+n+'\\"]';
        var parts=[],cur=el;
        while(cur&&cur!==document.body&&parts.length<4){
          var p=cur.tagName.toLowerCase();
          var pe=cur.parentElement;
          if(pe){var same=[].slice.call(pe.children).filter(function(c){return c.tagName===cur.tagName;});
            if(same.length>1)p+=':nth-of-type('+(same.indexOf(cur)+1)+')';}
          parts.unshift(p);cur=pe;
        }
        return parts.join(' > ');
      }
      document.addEventListener('click',function(e){ if(!window.__chmRec)return;
        window.webkit.messageHandlers.chm.postMessage({kind:'recorded',type:'click',selector:sel(e.target)});},true);
      document.addEventListener('change',function(e){ if(!window.__chmRec)return; var el=e.target;
        if(!('value' in el))return; var pw=el.type==='password';
        window.webkit.messageHandlers.chm.postMessage({kind:'recorded',type:'input',selector:sel(el),value:pw?'':el.value});},true);
    })();
    """

    // インスペクタ: ホバー＋クリックで要素選択、現在スタイルを返す
    static let inspect = """
    (function(){
      if(window.__chmInspecting)return; window.__chmInspecting=true;
      var ov=document.createElement('div');
      ov.style.cssText='position:fixed;z-index:2147483647;pointer-events:none;border:2px solid #2a7de1;background:rgba(42,125,225,.12);border-radius:3px';
      document.body.appendChild(ov);
      var PROPS=['color','background-color','font-size','font-weight','display','opacity','width','height','max-width','margin','padding','border','border-radius','text-align','box-shadow'];
      function sel(el){ if(el.id)return '#'+CSS.escape(el.id);
        var t=el.getAttribute('data-testid'); if(t)return '[data-testid=\\"'+t+'\\"]';
        var parts=[],cur=el;
        while(cur&&cur!==document.body&&parts.length<4){var p=cur.tagName.toLowerCase();var pe=cur.parentElement;
          if(pe){var same=[].slice.call(pe.children).filter(function(c){return c.tagName===cur.tagName;});
          if(same.length>1)p+=':nth-of-type('+(same.indexOf(cur)+1)+')';}parts.unshift(p);cur=pe;}
        return parts.join(' > ');}
      function move(e){var r=e.target.getBoundingClientRect();ov.style.left=r.left+'px';ov.style.top=r.top+'px';ov.style.width=r.width+'px';ov.style.height=r.height+'px';}
      function click(e){e.preventDefault();e.stopPropagation();var el=e.target;var cs=getComputedStyle(el);var st={};
        PROPS.forEach(function(p){st[p]=cs.getPropertyValue(p).trim();});
        window.webkit.messageHandlers.chm.postMessage({kind:'inspected',selector:sel(el),styles:st});cleanup();}
      function cleanup(){window.__chmInspecting=false;document.removeEventListener('mousemove',move,true);document.removeEventListener('click',click,true);ov.remove();}
      document.addEventListener('mousemove',move,true);
      document.addEventListener('click',click,true);
    })();
    """

    // 単一ステップ実行（Promiseを返す→callAsyncJavaScriptがawait）
    static let runStep = """
    function waitFor(s,t){return new Promise(function(res,rej){var el=document.querySelector(s);if(el)return res(el);
      var to=setTimeout(function(){ob.disconnect();rej('timeout:'+s);},t);
      var ob=new MutationObserver(function(){var e=document.querySelector(s);if(e){clearTimeout(to);ob.disconnect();res(e);}});
      ob.observe(document.documentElement,{childList:true,subtree:true});});}
    return (async function(){
      if(type==='wait'){await new Promise(function(r){setTimeout(r,parseInt(value)||1000);});return;}
      if(type==='runJavaScript'){new Function(value)();return;}
      var el=await waitFor(selector,timeoutMs||12000);
      if(type==='click'){el.scrollIntoView({block:'center'});el.click();}
      else if(type==='input'){el.focus();el.value=value;el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));}
      else if(type==='check'||type==='uncheck'){var w=type==='check';if(el.checked!==w)el.click();}
      else if(type==='select'){el.value=value;el.dispatchEvent(new Event('change',{bubbles:true}));}
      else if(type==='submit'){var f=el.tagName==='FORM'?el:el.closest('form');if(f)f.requestSubmit?f.requestSubmit():f.submit();}
      else if(type==='waitForSelector'){/* 既に待機済み */}
    })();
    """
}
