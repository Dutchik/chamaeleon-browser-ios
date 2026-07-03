#ifndef CHM_PROXY_H
#define CHM_PROXY_H

// Chamaeleon ローカルプロキシ（C）。
// WKWebView の proxyConfigurations から 127.0.0.1:port の CONNECT プロキシとして使う。
// 全トラフィックを自前C層に通し、chm_rules でホスト単位のブロックを行う。
// ・HTTPS(:443) は現状ブラインドトンネル（本文書換=TLS MITMは次段）。
// ・接続確立/ブロック/転送バイト数を扱う土台。

#ifdef __cplusplus
extern "C" {
#endif

int  chm_proxy_start(int port);   // 127.0.0.1:port で待受（0=自動割当）。実ポートを返す。失敗は0
void chm_proxy_stop(void);
int  chm_proxy_running(void);
long chm_proxy_bytes(void);       // 累計転送バイト数（統計用）

// 本文書換ルール（平文HTTP／MITM後のHTTPSに適用）
void chm_proxy_clear_rewrites(void);
void chm_proxy_add_rewrite(const char *find, const char *replace);
long chm_proxy_rewrites_applied(void);   // 実際に置換した回数（検証用）

// body(len) に全書換ルールを適用した新バッファを返す（malloc、呼び出し側free）。*outlen更新。
char *chm_proxy_rewrite_body(const char *body, long len, long *outlen);

// MITM(HTTPS本文書換) の有効/無効。ONのとき:443も終端して書換する。
void chm_proxy_set_mitm(int on);
int  chm_proxy_mitm_enabled(void);
int  chm_proxy_rewrite_count(void);      // 有効な書換ルール数

// パケット/ネットワーク層キャプチャ: プロキシを通過するメディア応答本文を dir に保存。
// アプリ層で再取得せず、実際に流れたバイトをそのまま書き出す。
void chm_proxy_set_capture(const char *dir, int on);
int  chm_proxy_capture_enabled(void);
int  chm_proxy_capture_count(void);      // 保存したメディア数（検証・進捗用）
// 応答(ヘッダ+ボディ)がメディアならキャプチャ保存する内部ヘルパの公開版（MITMからも使用）
void chm_proxy_capture_if_media(const char *header, long headerlen,
                                const char *body, long bodylen, const char *url_hint);

#ifdef __cplusplus
}
#endif

#endif /* CHM_PROXY_H */
