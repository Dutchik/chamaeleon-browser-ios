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
    @ObservedObject var netRules: NetRuleStore
    var onVisit: ((String, String) -> Void)? = nil

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.userContentController.add(context.coordinator, name: "chm")
        if let list = netRules.compiledList { config.userContentController.add(list) }
        config.userContentController.addUserScript(ChamaeleonAgent.makeUserScript(store.profiles))  // 常駐ルールエンジン
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        if #available(iOS 16.0, *) { webView.isFindInteractionEnabled = true }
        context.coordinator.appliedRuleVersion = netRules.version
        context.coordinator.appliedProfileVersion = store.version
        model.webView = webView
        if let url = URL(string: model.urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.appliedRuleVersion != netRules.version {
            context.coordinator.appliedRuleVersion = netRules.version
            let ucc = webView.configuration.userContentController
            ucc.removeAllContentRuleLists()
            if let list = netRules.compiledList { ucc.add(list) }
        }
        // プロファイル（CSS/DOM/JS）が変わったら Agent を再ビルドして現ページにも即反映
        if context.coordinator.appliedProfileVersion != store.version {
            context.coordinator.appliedProfileVersion = store.version
            let ucc = webView.configuration.userContentController
            ucc.removeAllUserScripts()
            ucc.addUserScript(ChamaeleonAgent.makeUserScript(store.profiles))
            webView.evaluateJavaScript(ChamaeleonAgent.applyNowSource(store.profiles))
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(model: model, store: store, netRules: netRules, onVisit: onVisit) }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
        let model: BrowserModel
        let store: ProfileStore
        let netRules: NetRuleStore
        let onVisit: ((String, String) -> Void)?
        var appliedRuleVersion = -1
        var appliedProfileVersion = -1
        init(model: BrowserModel, store: ProfileStore, netRules: NetRuleStore, onVisit: ((String, String) -> Void)?) {
            self.model = model; self.store = store; self.netRules = netRules; self.onVisit = onVisit
        }

        // target=_blank / window.open を同じWebViewで開く（白画面/リンク無反応の修正）
        // URLが即座に無い(window.open('')後にlocation設定)場合は一時WebViewで受けてメインへ転送
        var popups: [PopupRedirector] = []
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url, !url.absoluteString.isEmpty {
                webView.load(URLRequest(url: url)); return nil
            }
            let redirector = PopupRedirector(main: webView) { [weak self] r in
                self?.popups.removeAll { $0 === r }
            }
            let popup = WKWebView(frame: .zero, configuration: configuration)
            popup.navigationDelegate = redirector
            redirector.popup = popup
            popups.append(redirector)
            return popup
        }

        // JSダイアログ: フロー実行中は自動応答して停止を防ぐ。手動時はネイティブ表示。
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            if model.flowRunning { completionHandler(); return }
            guard let vc = webView.chmTopVC else { completionHandler(); return }
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            vc.present(a, animated: true)
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            if model.flowRunning { completionHandler(true); return }
            guard let vc = webView.chmTopVC else { completionHandler(false); return }
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "キャンセル", style: .cancel) { _ in completionHandler(false) })
            a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
            vc.present(a, animated: true)
        }
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            if model.flowRunning { completionHandler(defaultText); return }
            guard let vc = webView.chmTopVC else { completionHandler(defaultText); return }
            let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            a.addTextField { $0.text = defaultText }
            a.addAction(UIAlertAction(title: "キャンセル", style: .cancel) { _ in completionHandler(nil) })
            a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(a.textFields?.first?.text) })
            vc.present(a, animated: true)
        }

        // TLS MITM 時: 自前CAで署名したリーフ証明書を信頼する
        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            guard netRules.mitmEnabled,
                  challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  let trust = challenge.protectionSpace.serverTrust, let ca = netRules.mitmCA else {
                completionHandler(.performDefaultHandling, nil); return
            }
            SecTrustSetAnchorCertificates(trust, [ca] as CFArray)
            SecTrustSetAnchorCertificatesOnly(trust, false)
            if SecTrustEvaluateWithError(trust, nil) {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }

        // メインフレームのナビゲーションを C エンジンで判定してブロック（http(s)のみ対象）
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if netRules.masterEnabled, navigationAction.targetFrame?.isMainFrame ?? true,
               let u = navigationAction.request.url, let scheme = u.scheme?.lowercased(),
               scheme == "http" || scheme == "https", chm_rules_eval(u.absoluteString) == 1 {
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
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
                // CSS/DOM/JSの適用は documentStart 常駐 Agent（ChamaeleonAgent）が担当。
                model.currentURL = url; model.urlInput = url; model.urlString = url
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let url = webView.url?.absoluteString ?? ""
            Task { @MainActor in
                model.currentURL = url; model.urlInput = url; model.title = webView.title ?? ""
                model.canGoBack = webView.canGoBack; model.canGoForward = webView.canGoForward
                model.isLoading = false
                onVisit?(url, webView.title ?? "")
                model.matchedCount = store.matched(for: url).count
                if model.recording { model.injectRecorder() }
                model.injectVideoOverlay()
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
                case "videoMenu":
                    model.onVideoMenu?(body["src"] as? String ?? "")
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
    var flowRunning = false      // フロー実行中はJSダイアログを自動応答（停止防止）
    weak var webView: WKWebView?

    var onRecorded: ((RecordedStep) -> Void)?
    var onInspected: ((InspectedInfo) -> Void)?
    var onVideoMenu: ((String) -> Void)?     // 動画バッジ押下（src）
    private var navCont: CheckedContinuation<Void, Never>?

    func injectVideoOverlay() { webView?.evaluateJavaScript(BrowserJS.videoOverlay) }

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
    func findOnPage() {
        if #available(iOS 16.0, *) { webView?.findInteraction?.presentFindNavigator(showingReplace: false) }
    }
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
        let b64 = Data(css.utf8).base64EncodedString()
        let decode = "new TextDecoder().decode(Uint8Array.from(atob('\(b64)'),function(c){return c.charCodeAt(0)}))"
        webView?.evaluateJavaScript("(function(){var e=document.getElementById('chm-style-preview');if(!e){e=document.createElement('style');e.id='chm-style-preview';document.documentElement.appendChild(e);}e.textContent=\(decode);})();")
    }
    func clearPreview() { webView?.evaluateJavaScript("document.getElementById('chm-style-preview')?.remove();") }

    /// 現在ページ(レンダリング済みDOM)の全要素からリソースURLを収集
    func collectResources() async -> [String] {
        guard let wv = webView else { return [] }
        let js = """
        JSON.stringify([...document.querySelectorAll('img,video,source,audio,a,link,script,[style]')].flatMap(function(e){
          var o=[]; if(e.currentSrc)o.push(e.currentSrc); if(e.src)o.push(e.src); if(e.href)o.push(e.href);
          if(e.srcset)e.srcset.split(',').forEach(function(s){o.push(s.trim().split(' ')[0]);});
          var bg=(e.style&&e.style.backgroundImage)||''; var m=bg.match(/url\\((['"]?)(.*?)\\1\\)/); if(m)o.push(m[2]);
          return o;
        }).filter(Boolean))
        """
        return await withCheckedContinuation { (c: CheckedContinuation<[String], Never>) in
            wv.evaluateJavaScript(js) { result, _ in
                guard let s = result as? String, let d = s.data(using: .utf8),
                      let arr = try? JSONDecoder().decode([String].self, from: d) else { c.resume(returning: []); return }
                c.resume(returning: arr)
            }
        }
    }

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
        // Base64経由で注入（バッククォート/バックスラッシュ/${}等のエスケープ不具合を回避）
        let b64 = Data(css.code.utf8).base64EncodedString()
        let decode = "new TextDecoder().decode(Uint8Array.from(atob('\(b64)'),function(c){return c.charCodeAt(0)}))"
        let js = "(function(){var s=document.createElement('style');s.dataset.chamaeleon='\(css.id)';s.textContent=\(decode);(document.head||document.documentElement).appendChild(s);})();"
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
    // 動画要素の右上に「⤓」バッジを重ね、押すとネイティブのキャプチャメニューを開く
    static let videoOverlay = """
    (function(){
      if(window.__chmVidInit)return; window.__chmVidInit=true;
      function tag(v){
        if(v.__chmTagged)return; v.__chmTagged=true;
        var b=document.createElement('div'); b.textContent='⤓';
        b.style.cssText='position:absolute;z-index:2147483647;top:8px;right:8px;width:34px;height:34px;line-height:34px;text-align:center;border-radius:17px;background:rgba(53,194,106,.92);color:#fff;font:700 18px -apple-system,sans-serif;cursor:pointer;box-shadow:0 2px 8px rgba(0,0,0,.35)';
        b.addEventListener('click',function(e){e.preventDefault();e.stopPropagation();
          var src=v.currentSrc||v.src||'';
          window.webkit.messageHandlers.chm.postMessage({kind:'videoMenu',src:src});},true);
        var p=v.parentElement||document.body;
        if(getComputedStyle(p).position==='static') p.style.position='relative';
        p.appendChild(b);
      }
      function scan(){document.querySelectorAll('video').forEach(tag);}
      scan();
      try{ new MutationObserver(scan).observe(document.documentElement,{childList:true,subtree:true}); }catch(e){}
    })();
    """

    // 安定セレクタ生成: id / data-* / name / aria-label / 安定クラスを優先し、
    // 必要なときだけ nth-of-type にフォールバック（自動化・スタイル編集の再現性向上）
    static let selJS = """
      function stab(el){ if(!el||el.nodeType!==1)return null;
        if(el.id&&!/^[0-9]/.test(el.id)&&!/[0-9]{4,}/.test(el.id))return '#'+CSS.escape(el.id);
        var A=['data-testid','data-test','data-qa','data-cy','name','aria-label'];
        for(var i=0;i<A.length;i++){var v=el.getAttribute&&el.getAttribute(A[i]);
          if(v){v=v.replace(/["']/g,'');if(v)return el.tagName.toLowerCase()+'['+A[i]+'="'+v+'"]';}}
        return null;}
      function sel(el){ if(!el||el.nodeType!==1)return '';
        var s=stab(el);if(s)return s;
        var parts=[],cur=el,depth=0;
        while(cur&&cur.nodeType===1&&cur!==document.body&&depth<5){
          var d=stab(cur);if(d){parts.unshift(d);break;}
          var tag=cur.tagName.toLowerCase(),cls=null;
          if(cur.classList){for(var i=0;i<cur.classList.length;i++){var c=cur.classList[i];
            if(/^[a-zA-Z][A-Za-z0-9_-]{1,24}$/.test(c)&&!/[0-9]{4,}/.test(c)){cls=c;break;}}}
          var pe=cur.parentElement,seg=cls?tag+'.'+CSS.escape(cls):tag;
          if(pe){var same=[].slice.call(pe.children).filter(function(x){
            if(x.tagName!==cur.tagName)return false;return cls?(x.classList&&x.classList.contains(cls)):true;});
            if(same.length>1)seg=seg+':nth-of-type('+(same.indexOf(cur)+1)+')';}
          parts.unshift(seg);cur=pe;depth++;}
        return parts.join(' > ');}
    """

    // レコーダー: クリック・入力を messageHandler へ送る
    static let recorder = """
    (function(){
      if (window.__chmRecInit) { window.__chmRec = true; return; }
      window.__chmRecInit = true; window.__chmRec = true;
    \(selJS)
      document.addEventListener('click',function(e){ if(!window.__chmRec)return;
        window.webkit.messageHandlers.chm.postMessage({kind:'recorded',type:'click',selector:sel(e.target)});},true);
      document.addEventListener('change',function(e){ if(!window.__chmRec)return; var el=e.target;
        if(!('value' in el))return; var pw=el.type==='password';
        window.webkit.messageHandlers.chm.postMessage({kind:'recorded',type:'input',selector:sel(el),value:pw?'':el.value});},true);
    })();
    """

    // インスペクタ: タッチ(ドラッグで狙って離して選択)＋マウス(Catalyst/desktop)対応。
    // elementFromPoint で指の下の要素を特定するのでタッチ端末でも正確に選べる。
    static let inspect = """
    (function(){
      if(window.__chmInspecting)return; window.__chmInspecting=true;
      var ov=document.createElement('div');
      ov.style.cssText='position:fixed;z-index:2147483647;pointer-events:none;border:2px solid #2a7de1;background:rgba(42,125,225,.14);border-radius:3px;transition:all .03s';
      document.documentElement.appendChild(ov);
      var tip=document.createElement('div');
      tip.textContent='要素をタップ/ドラッグして選択';
      tip.style.cssText='position:fixed;left:50%;bottom:18px;transform:translateX(-50%);z-index:2147483647;pointer-events:none;background:#2a7de1;color:#fff;font:600 12px -apple-system,sans-serif;padding:6px 12px;border-radius:999px';
      document.documentElement.appendChild(tip);
      var PROPS=['color','background-color','font-size','font-weight','display','opacity','width','height','max-width','margin','padding','border','border-radius','text-align','box-shadow'];
    \(selJS)
      function at(x,y){return document.elementFromPoint(x,y);}   // ovは pointer-events:none なので下の要素が返る
      function highlight(el){ if(!el||el===ov||el===tip)return; var r=el.getBoundingClientRect();
        ov.style.left=r.left+'px';ov.style.top=r.top+'px';ov.style.width=r.width+'px';ov.style.height=r.height+'px'; }
      function pick(el){ if(!el||el===ov||el===tip)return; var cs=getComputedStyle(el);var st={};
        PROPS.forEach(function(p){st[p]=cs.getPropertyValue(p).trim();});
        window.webkit.messageHandlers.chm.postMessage({kind:'inspected',selector:sel(el),styles:st});cleanup();}
      function onTouch(e){var t=e.touches&&e.touches[0];if(t){highlight(at(t.clientX,t.clientY));}if(e.cancelable)e.preventDefault();}
      function onEnd(e){if(e.cancelable)e.preventDefault();e.stopPropagation();var t=e.changedTouches&&e.changedTouches[0];if(t){pick(at(t.clientX,t.clientY));}}
      function onMouse(e){highlight(at(e.clientX,e.clientY));}
      function onClick(e){e.preventDefault();e.stopPropagation();pick(at(e.clientX,e.clientY)||e.target);}
      function cleanup(){window.__chmInspecting=false;
        document.removeEventListener('touchstart',onTouch,true);document.removeEventListener('touchmove',onTouch,true);
        document.removeEventListener('touchend',onEnd,true);document.removeEventListener('mousemove',onMouse,true);
        document.removeEventListener('click',onClick,true);ov.remove();tip.remove();}
      document.addEventListener('touchstart',onTouch,{capture:true,passive:false});
      document.addEventListener('touchmove',onTouch,{capture:true,passive:false});
      document.addEventListener('touchend',onEnd,{capture:true,passive:false});
      document.addEventListener('mousemove',onMouse,true);
      document.addEventListener('click',onClick,true);
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
      else if(type==='input'){el.focus();var proto=el instanceof HTMLTextAreaElement?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;var d=Object.getOwnPropertyDescriptor(proto,'value');if(d&&d.set){d.set.call(el,value);}else{el.value=value;}el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));}
      else if(type==='check'||type==='uncheck'){var w=type==='check';if(el.checked!==w)el.click();}
      else if(type==='select'){el.value=value;el.dispatchEvent(new Event('change',{bubbles:true}));}
      else if(type==='submit'){var f=el.tagName==='FORM'?el:el.closest('form');if(f)f.requestSubmit?f.requestSubmit():f.submit();}
      else if(type==='waitForSelector'){/* 既に待機済み */}
    })();
    """
}

/// window.open('')後にlocationが設定されるポップアップを受けてメインWebViewへ転送
final class PopupRedirector: NSObject, WKNavigationDelegate {
    weak var main: WKWebView?
    var popup: WKWebView?
    private let onDone: (PopupRedirector) -> Void
    init(main: WKWebView, onDone: @escaping (PopupRedirector) -> Void) { self.main = main; self.onDone = onDone }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, !url.absoluteString.isEmpty, url.absoluteString != "about:blank" {
            main?.load(URLRequest(url: url))
            decisionHandler(.cancel)
            popup = nil
            onDone(self)
        } else {
            decisionHandler(.allow)
        }
    }
}

extension WKWebView {
    /// 現在表示中の最前面 ViewController（ダイアログ表示用）
    var chmTopVC: UIViewController? {
        var vc = window?.rootViewController
        while let p = vc?.presentedViewController { vc = p }
        return vc
    }
}
