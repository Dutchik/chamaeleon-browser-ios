#ifndef CHM_MITM_H
#define CHM_MITM_H

// Chamaeleon TLS MITM（OpenSSL）。
// 自前ルートCAを生成し、ホスト毎のリーフ証明書を動的発行してブラウザ⇄オリジン間の
// TLSを終端し、HTTP応答本文を chm_proxy_rewrite_body で書き換える。
// CA証明書は Swift 側が読み込んで WKWebView の ServerTrust で信頼させる。

#ifdef __cplusplus
extern "C" {
#endif

int  chm_mitm_init(const char *ca_dir);       // CA生成/ロード。0成功
const char *chm_mitm_ca_cert_der_path(void);  // CA証明書(DER)のパス（Swiftが信頼設定に使う）
int  chm_mitm_bridge(int client_fd, const char *host, int origin_fd);  // MITM実行。0成功

#ifdef __cplusplus
}
#endif

#endif /* CHM_MITM_H */
